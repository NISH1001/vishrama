import Foundation

/// What survives a relaunch or a settings-driven engine rebuild: where you
/// are in the work interval, the long-break cycle, and layer-1 adaptivity.
public struct ScheduleSnapshot: Codable, Equatable, Sendable {
    public var remainingWork: TimeInterval
    public var completedShortBreaks: Int
    public var backoffLevel: Int
    public var quietUntil: Date?
    public var savedAt: Date
}

/// Pure schedule state machine, driven at 1 Hz by the shell.
/// All time comes in through parameters — fully deterministic and testable.
public final class ScheduleEngine {
    public let config: BreakConfiguration
    private(set) var state: ScheduleState

    /// Pattern-learning multiplier applied to the work interval when
    /// scheduling the NEXT break (1.0 = no change). Set by the shell.
    public var intervalScale: Double = 1.0

    /// Consecutive skips since the last completed break (drives backoff + logs).
    public private(set) var backoffLevel = 0
    /// Recent skip/postpone weights for flow detection.
    private var skipWeights: [(at: Date, weight: Double)] = []
    /// While set (and in the future), due breaks notify instead of taking the screen.
    private var quietUntil: Date?
    /// The breakDue we already sent a heads-up for (one warning per break).
    private var preBreakWarnedFor: Date?
    /// When a meeting signal first became continuously active (nil = not in one).
    private var meetingSince: Date?
    /// The upcoming meeting we already offered an early break for — so dismissing
    /// it doesn't re-fire seconds later for the same meeting.
    private var meetingGapOfferedFor: Date?
    /// Last in-meeting eye reminder (anchors the repeat cadence).
    private var lastMicroNudge: Date?
    /// When the current work period began. Idle time is clamped to this so
    /// hands-off time DURING a break can't leak into the fresh interval as
    /// phantom "away" time (which double-credited natural breaks).
    private var workStartedAt: Date

    public init(config: BreakConfiguration = BreakConfiguration(), startAt now: Date, restoring snapshot: ScheduleSnapshot? = nil) {
        self.config = config
        self.workStartedAt = now
        guard let snapshot else {
            self.workStartedAt = now
        state = .working(breakDue: now.addingTimeInterval(config.shortInterval), completedShortBreaks: 0)
            return
        }
        // Carry the cycle and adaptivity over; expired flow-quiet stays expired.
        backoffLevel = snapshot.backoffLevel
        quietUntil = snapshot.quietUntil.flatMap { $0 > now ? $0 : nil }
        let gap = max(0, now.timeIntervalSince(snapshot.savedAt))
        let remaining: TimeInterval
        if gap > 10 * 60 {
            // Long downtime: a fresh interval, but the cycle position survives.
            remaining = config.shortInterval
        } else {
            // Brief relaunch: the countdown continues, downtime counted as worked.
            remaining = min(max(30, snapshot.remainingWork - gap), config.shortInterval)
        }
        self.workStartedAt = now
        state = .working(breakDue: now.addingTimeInterval(remaining), completedShortBreaks: snapshot.completedShortBreaks)
    }

    /// Capture what should survive a rebuild/relaunch. A snapshot taken
    /// mid-break restores as fresh work — overlays are never resurrected.
    public func snapshot(now: Date) -> ScheduleSnapshot {
        let remaining: TimeInterval
        let completed: Int
        switch state {
        case .working(let breakDue, let c):
            remaining = max(0, breakDue.timeIntervalSince(now))
            completed = c
        case .idlePaused(let r, let c, _):
            remaining = r
            completed = c
        case .manuallyPaused(let r, let c):
            remaining = r
            completed = c
        case .breakActive(_, _, let c):
            remaining = scaledInterval
            completed = c
        case .pendingSuppressed(_, _, let c):
            remaining = 0
            completed = c
        }
        return ScheduleSnapshot(
            remainingWork: remaining,
            completedShortBreaks: completed,
            backoffLevel: backoffLevel,
            quietUntil: quietUntil,
            savedAt: now
        )
    }

    public func tick(now: Date, context: ContextSnapshot) -> [Effect] {
        // Eye nudges are keyed to time-in-meeting (read state before it mutates).
        let nudge = microNudgeEffects(now: now, context: context)
        return tickState(now: now, context: context) + nudge
    }

    /// 20-20-20 eye reminder during a long meeting — driven by how long a
    /// meeting signal (camera/mic or busy calendar) has been continuously
    /// active, independent of the break cycle. Silent while screen-sharing and
    /// when the meeting is about to end.
    private func microNudgeEffects(now: Date, context: ContextSnapshot) -> [Effect] {
        let inMeeting = context.activeSignals.contains(.cameraMic)
            || context.activeSignals.contains(.calendarBusy)
        guard inMeeting else {
            meetingSince = nil
            lastMicroNudge = nil
            return []
        }
        if meetingSince == nil {
            meetingSince = now
            lastMicroNudge = nil
        }
        // Only while at the screen (working / a held break) — not mid-break or paused.
        let nudgeable: Bool
        switch state {
        case .working, .pendingSuppressed: nudgeable = true
        default: nudgeable = false
        }
        guard config.microNudgeInterval > 0,
              nudgeable,
              !context.activeSignals.contains(.screenShare)
        else { return [] }

        let endsSoon = context.currentBusyEnd.map { $0 > now && $0.timeIntervalSince(now) < 5 * 60 } ?? false
        let anchor = lastMicroNudge ?? meetingSince ?? now
        if now.timeIntervalSince(anchor) >= config.microNudgeInterval, !endsSoon {
            lastMicroNudge = now
            return [.notifyMicroBreak, .log(.microNudge, nil)]
        }
        return []
    }

    private func tickState(now: Date, context: ContextSnapshot) -> [Effect] {
        switch state {
        case .working(let breakDue, let completed):
            // Idle can't predate this work period (amnesty for the break itself).
            let effectiveIdle = min(context.idleSeconds, now.timeIntervalSince(workStartedAt))
            // Sitting quietly in a meeting is not "away": only idle-pause when no signals.
            if effectiveIdle >= config.idlePauseThreshold, context.activeSignals.isEmpty {
                // Freeze the countdown at the moment activity stopped.
                let idleStart = now.addingTimeInterval(-effectiveIdle)
                let remaining = max(0, breakDue.timeIntervalSince(idleStart))
                state = .idlePaused(remainingWork: remaining, completedShortBreaks: completed, idleStart: idleStart)
                return [.updateStatus(.idlePaused(remaining: remaining))]
            }
            if now >= breakDue {
                let kind = pendingBreakKind(completedShortBreaks: completed)
                if !context.activeSignals.isEmpty {
                    state = .pendingSuppressed(dueSince: breakDue, clearSince: nil, completedShortBreaks: completed)
                    return [.updateStatus(.suppressed(overdue: now.timeIntervalSince(breakDue))), .log(.suppressedStart, kind)]
                }
                if let quiet = quietUntil {
                    if now < quiet {
                        // Flow mode: whisper, don't take over; try again next interval.
                        workStartedAt = now
        state = .working(breakDue: now.addingTimeInterval(scaledInterval), completedShortBreaks: completed)
                        return [
                            .notifyBreak(kind),
                            .updateStatus(.working(remaining: scaledInterval)),
                            .log(.notified, kind),
                        ]
                    }
                    quietUntil = nil
                }
                let duration = config.duration(of: kind)
                state = .breakActive(kind: kind, endsAt: now.addingTimeInterval(duration), completedShortBreaks: completed)
                return [.showOverlay(kind), .updateStatus(.onBreak(kind: kind, remaining: duration)), .log(.fired, kind)]
            }
            // Meeting-gap: most of the interval is done and a busy event starts
            // soon — take the break NOW so it fits before the meeting, instead
            // of it landing mid-meeting and being suppressed for an hour.
            if let nextBusy = context.nextBusyStart,
               context.activeSignals.isEmpty,
               meetingGapOfferedFor != nextBusy,   // once per upcoming meeting
               quietUntil == nil || now >= quietUntil! {
                let kind = pendingBreakKind(completedShortBreaks: completed)
                let remaining = breakDue.timeIntervalSince(now)
                let untilMeeting = nextBusy.timeIntervalSince(now)
                if remaining <= 0.4 * config.shortInterval,
                   untilMeeting > 0,
                   untilMeeting <= config.duration(of: kind) + 5 * 60 {
                    meetingGapOfferedFor = nextBusy
                    let duration = config.duration(of: kind)
                    state = .breakActive(kind: kind, endsAt: now.addingTimeInterval(duration), completedShortBreaks: completed)
                    return [
                        .showOverlayForMeetingGap(kind),
                        .updateStatus(.onBreak(kind: kind, remaining: duration)),
                        .log(.fired, kind),
                    ]
                }
            }

            // Gentle heads-up shortly before the break — skipped in meetings
            // (the break would be suppressed) and in flow quiet (it notifies anyway).
            if config.preBreakWarning > 0,
               now >= breakDue.addingTimeInterval(-config.preBreakWarning),
               context.activeSignals.isEmpty,
               preBreakWarnedFor != breakDue,
               quietUntil == nil || now >= quietUntil! {
                preBreakWarnedFor = breakDue
                let kind = pendingBreakKind(completedShortBreaks: completed)
                return [
                    .updateStatus(.working(remaining: breakDue.timeIntervalSince(now))),
                    .notifyPreBreak(kind, config.preBreakWarning),
                ]
            }
            return [.updateStatus(.working(remaining: breakDue.timeIntervalSince(now)))]

        case .pendingSuppressed(let dueSince, let clearSince, let completed):
            let kind = pendingBreakKind(completedShortBreaks: completed)
            let overdue = now.timeIntervalSince(dueSince)
            if !context.activeSignals.isEmpty {
                // (Re)entered a busy context: any grace countdown restarts.
                if clearSince != nil {
                    state = .pendingSuppressed(dueSince: dueSince, clearSince: nil, completedShortBreaks: completed)
                }
                // The 20-20-20 eye nudge is handled by microNudgeEffects (keyed
                // to meeting time, not break-suppression time).
                return [.updateStatus(.suppressed(overdue: overdue))]
            }
            guard let clearedAt = clearSince else {
                state = .pendingSuppressed(dueSince: dueSince, clearSince: now, completedShortBreaks: completed)
                return [.updateStatus(.suppressed(overdue: overdue))]
            }
            if now.timeIntervalSince(clearedAt) >= config.suppressionGrace {
                let duration = config.duration(of: kind)
                state = .breakActive(kind: kind, endsAt: now.addingTimeInterval(duration), completedShortBreaks: completed)
                return [
                    .log(.suppressedEnd, kind),
                    .showOverlay(kind),
                    .updateStatus(.onBreak(kind: kind, remaining: duration)),
                    .log(.fired, kind),
                ]
            }
            return [.updateStatus(.suppressed(overdue: overdue))]

        case .breakActive(let kind, let endsAt, let completed):
            if now >= endsAt {
                return [.hideOverlay] + completeBreak(of: kind, completedShortBreaks: completed, now: now) + [.log(.completed, kind)]
            }
            return [.updateStatus(.onBreak(kind: kind, remaining: endsAt.timeIntervalSince(now)))]

        case .idlePaused(let remainingWork, let completed, let idleStart):
            if context.idleSeconds >= config.idlePauseThreshold {
                return [.updateStatus(.idlePaused(remaining: remainingWork))]
            }
            // User is back. Idle span ran from idleStart until activity resumed.
            let totalIdle = now.timeIntervalSince(idleStart) - context.idleSeconds
            let pending = pendingBreakKind(completedShortBreaks: completed)
            if totalIdle >= config.duration(of: pending) {
                // The absence was long enough to count as the pending break itself.
                return completeBreak(of: pending, completedShortBreaks: completed, now: now) + [.log(.naturalBreak, pending)]
            }
            if totalIdle >= config.shortDuration {
                // A real rest, even if shorter than the pending long break: restart the interval.
                workStartedAt = now
        state = .working(breakDue: now.addingTimeInterval(scaledInterval), completedShortBreaks: completed)
                return [.updateStatus(.working(remaining: scaledInterval))]
            }
            // Brief absence: resume the frozen countdown.
            workStartedAt = now
        state = .working(breakDue: now.addingTimeInterval(remainingWork), completedShortBreaks: completed)
            return [.updateStatus(.working(remaining: remainingWork))]

        case .manuallyPaused(let remainingWork, _):
            // Paused means paused — idle and due times are irrelevant until resume.
            return [.updateStatus(.manualPaused(remaining: remainingWork))]
        }
    }

    /// System slept (lid closed) while we were in `working` — the idle
    /// machinery never saw it coming, so account for the absence here:
    /// long sleep = the break happened naturally; a nap defers the due time
    /// so waking is never ambushed by an instantly-overdue overlay.
    public func systemSlept(for duration: TimeInterval, now: Date) -> [Effect] {
        guard case .working(let breakDue, let completed) = state else { return [] }
        let pending = pendingBreakKind(completedShortBreaks: completed)
        if duration >= config.duration(of: pending) {
            return completeBreak(of: pending, completedShortBreaks: completed, now: now) + [.log(.naturalBreak, pending)]
        }
        if duration >= config.shortDuration {
            workStartedAt = now
        state = .working(breakDue: now.addingTimeInterval(scaledInterval), completedShortBreaks: completed)
            return [.updateStatus(.working(remaining: scaledInterval))]
        }
        // Brief nap: resume with whatever work time was left when the lid closed.
        let remaining = max(0, breakDue.timeIntervalSince(now.addingTimeInterval(-duration)))
        workStartedAt = now
        state = .working(breakDue: now.addingTimeInterval(remaining), completedShortBreaks: completed)
        return [.updateStatus(.working(remaining: remaining))]
    }

    /// Menu action: start over — full interval, clean backoff/flow slate.
    public func reset(now: Date) -> [Effect] {
        let completed: Int
        var effects: [Effect] = []
        switch state {
        case .working(_, let c), .idlePaused(_, let c, _), .manuallyPaused(_, let c),
             .pendingSuppressed(_, _, let c):
            completed = c
        case .breakActive(_, _, let c):
            completed = c
            effects.append(.hideOverlay)
        }
        backoffLevel = 0
        skipWeights.removeAll()
        quietUntil = nil
        workStartedAt = now
        state = .working(breakDue: now.addingTimeInterval(config.shortInterval), completedShortBreaks: completed)
        effects.append(.updateStatus(.working(remaining: config.shortInterval)))
        return effects
    }

    /// Menu-bar pause button: freeze everything until pressed again.
    public func togglePause(now: Date) -> [Effect] {
        switch state {
        case .working(let breakDue, let completed):
            let remaining = max(0, breakDue.timeIntervalSince(now))
            state = .manuallyPaused(remainingWork: remaining, completedShortBreaks: completed)
            return [.updateStatus(.manualPaused(remaining: remaining)), .log(.paused, nil)]
        case .breakActive(_, _, let completed):
            // Pausing mid-break dismisses it; the full interval is owed on resume.
            state = .manuallyPaused(remainingWork: config.shortInterval, completedShortBreaks: completed)
            return [.hideOverlay, .updateStatus(.manualPaused(remaining: config.shortInterval)), .log(.paused, nil)]
        case .idlePaused(let remainingWork, let completed, _):
            state = .manuallyPaused(remainingWork: remainingWork, completedShortBreaks: completed)
            return [.updateStatus(.manualPaused(remaining: remainingWork)), .log(.paused, nil)]
        case .manuallyPaused(let remainingWork, let completed):
            workStartedAt = now
        state = .working(breakDue: now.addingTimeInterval(remainingWork), completedShortBreaks: completed)
            return [.updateStatus(.working(remaining: remainingWork)), .log(.resumed, nil)]
        case .pendingSuppressed(_, _, let completed):
            // Pausing while a break waits out a meeting: the break stays owed (fires on resume).
            state = .manuallyPaused(remainingWork: 0, completedShortBreaks: completed)
            return [.updateStatus(.manualPaused(remaining: 0)), .log(.paused, nil)]
        }
    }

    public var isManuallyPaused: Bool {
        if case .manuallyPaused = state { return true }
        return false
    }

    /// Menu action: start the pending break immediately.
    public func breakNow(now: Date) -> [Effect] {
        guard case .working(_, let completed) = state else { return [] }
        let kind = pendingBreakKind(completedShortBreaks: completed)
        let duration = config.duration(of: kind)
        state = .breakActive(kind: kind, endsAt: now.addingTimeInterval(duration), completedShortBreaks: completed)
        return [.showOverlay(kind), .updateStatus(.onBreak(kind: kind, remaining: duration))]
    }

    /// Adjust the current break's length by ±seconds (tap to stack). Extends
    /// freely; when reducing, never drops remaining below `floor` and never
    /// bumps a nearly-done break back up.
    public func extendBreak(by seconds: TimeInterval, now: Date, floor: TimeInterval = 5 * 60) -> [Effect] {
        guard case .breakActive(let kind, let endsAt, let completed) = state else { return [] }
        let current = max(0, endsAt.timeIntervalSince(now))
        let target = current + seconds
        let newRemaining = seconds >= 0 ? target : min(current, max(floor, target))
        let newEnd = now.addingTimeInterval(newRemaining)
        state = .breakActive(kind: kind, endsAt: newEnd, completedShortBreaks: completed)
        return [.updateStatus(.onBreak(kind: kind, remaining: newRemaining))]
    }

    /// The break was honored elsewhere (e.g. a Mastishka sit) — complete it
    /// early with full credit: cycle advances, backoff resets.
    public func finishBreak(now: Date) -> [Effect] {
        guard case .breakActive(let kind, _, let completed) = state else { return [] }
        return [.hideOverlay] + completeBreak(of: kind, completedShortBreaks: completed, now: now) + [.log(.completed, kind)]
    }

    /// User dismissed the break from the overlay. Retries after a growing
    /// backoff delay instead of a full interval — the break is still owed.
    public func skip(now: Date) -> [Effect] {
        guard case .breakActive(let kind, _, let completed) = state else { return [] }
        backoffLevel += 1
        let delay = config.backoffDelay(level: backoffLevel)
        // Skipped breaks do not advance the long-break cycle.
        workStartedAt = now
        state = .working(breakDue: now.addingTimeInterval(delay), completedShortBreaks: completed)
        return [.hideOverlay, .updateStatus(.working(remaining: delay)), .log(.skipped, kind)]
            + recordDismissal(weight: 1.0, now: now)
    }

    /// User asked for a few more minutes (also Esc on the overlay).
    public func postpone(now: Date) -> [Effect] {
        guard case .breakActive(let kind, _, let completed) = state else { return [] }
        workStartedAt = now
        state = .working(breakDue: now.addingTimeInterval(config.postponeDelay), completedShortBreaks: completed)
        return [.hideOverlay, .updateStatus(.working(remaining: config.postponeDelay)), .log(.postponed, kind)]
            + recordDismissal(weight: 0.5, now: now)
    }

    /// Track dismissals; enough weight inside the rolling window means the
    /// user is in flow — stop taking the screen for a while.
    private func recordDismissal(weight: Double, now: Date) -> [Effect] {
        skipWeights.append((at: now, weight: weight))
        skipWeights.removeAll { now.timeIntervalSince($0.at) > config.flowWindow }
        let total = skipWeights.reduce(0) { $0 + $1.weight }
        if total >= config.flowThreshold, quietUntil == nil {
            quietUntil = now.addingTimeInterval(config.flowQuietDuration)
            return [.log(.flowEnter, nil)]
        }
        return []
    }

    /// Work interval with the pattern-learning stretch applied.
    private var scaledInterval: TimeInterval {
        config.shortInterval * min(3.0, max(0.5, intervalScale))
    }

    private func pendingBreakKind(completedShortBreaks: Int) -> BreakKind {
        completedShortBreaks >= config.longBreakEvery ? .long : .short
    }

    private func completeBreak(of kind: BreakKind, completedShortBreaks: Int, now: Date) -> [Effect] {
        let newCompleted = kind == .short ? completedShortBreaks + 1 : 0
        // A completed break earns a clean slate.
        backoffLevel = 0
        skipWeights.removeAll()
        workStartedAt = now
        state = .working(breakDue: now.addingTimeInterval(scaledInterval), completedShortBreaks: newCompleted)
        return [.updateStatus(.working(remaining: scaledInterval))]
    }
}
