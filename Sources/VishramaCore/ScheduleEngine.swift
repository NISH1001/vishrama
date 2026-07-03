import Foundation

/// Pure schedule state machine, driven at 1 Hz by the shell.
/// All time comes in through parameters — fully deterministic and testable.
public final class ScheduleEngine {
    public let config: BreakConfiguration
    private(set) var state: ScheduleState

    public init(config: BreakConfiguration = BreakConfiguration(), startAt now: Date) {
        self.config = config
        self.state = .working(breakDue: now.addingTimeInterval(config.shortInterval), completedShortBreaks: 0)
    }

    public func tick(now: Date, context: ContextSnapshot) -> [Effect] {
        switch state {
        case .working(let breakDue, let completed):
            if context.idleSeconds >= config.idlePauseThreshold {
                // Freeze the countdown at the moment activity stopped.
                let idleStart = now.addingTimeInterval(-context.idleSeconds)
                let remaining = max(0, breakDue.timeIntervalSince(idleStart))
                state = .idlePaused(remainingWork: remaining, completedShortBreaks: completed, idleStart: idleStart)
                return [.updateStatus(.idlePaused(remaining: remaining))]
            }
            if now >= breakDue {
                let kind = pendingBreakKind(completedShortBreaks: completed)
                let duration = config.duration(of: kind)
                state = .breakActive(kind: kind, endsAt: now.addingTimeInterval(duration), completedShortBreaks: completed)
                return [.showOverlay(kind), .updateStatus(.onBreak(kind: kind, remaining: duration)), .log(.fired, kind)]
            }
            return [.updateStatus(.working(remaining: breakDue.timeIntervalSince(now)))]

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
                state = .working(breakDue: now.addingTimeInterval(config.shortInterval), completedShortBreaks: completed)
                return [.updateStatus(.working(remaining: config.shortInterval))]
            }
            // Brief absence: resume the frozen countdown.
            state = .working(breakDue: now.addingTimeInterval(remainingWork), completedShortBreaks: completed)
            return [.updateStatus(.working(remaining: remainingWork))]

        case .manuallyPaused(let remainingWork, _):
            // Paused means paused — idle and due times are irrelevant until resume.
            return [.updateStatus(.manualPaused(remaining: remainingWork))]
        }
    }

    /// Menu-bar pause button: freeze everything until pressed again.
    public func togglePause(now: Date) -> [Effect] {
        switch state {
        case .working(let breakDue, let completed):
            let remaining = max(0, breakDue.timeIntervalSince(now))
            state = .manuallyPaused(remainingWork: remaining, completedShortBreaks: completed)
            return [.updateStatus(.manualPaused(remaining: remaining))]
        case .breakActive(_, _, let completed):
            // Pausing mid-break dismisses it; the full interval is owed on resume.
            state = .manuallyPaused(remainingWork: config.shortInterval, completedShortBreaks: completed)
            return [.hideOverlay, .updateStatus(.manualPaused(remaining: config.shortInterval))]
        case .idlePaused(let remainingWork, let completed, _):
            state = .manuallyPaused(remainingWork: remainingWork, completedShortBreaks: completed)
            return [.updateStatus(.manualPaused(remaining: remainingWork))]
        case .manuallyPaused(let remainingWork, let completed):
            state = .working(breakDue: now.addingTimeInterval(remainingWork), completedShortBreaks: completed)
            return [.updateStatus(.working(remaining: remainingWork))]
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

    /// User dismissed the break from the overlay.
    public func skip(now: Date) -> [Effect] {
        guard case .breakActive(let kind, _, let completed) = state else { return [] }
        // Skipped breaks do not advance the long-break cycle.
        state = .working(breakDue: now.addingTimeInterval(config.shortInterval), completedShortBreaks: completed)
        return [.hideOverlay, .updateStatus(.working(remaining: config.shortInterval)), .log(.skipped, kind)]
    }

    /// User asked for a few more minutes (also Esc on the overlay).
    public func postpone(now: Date) -> [Effect] {
        guard case .breakActive(let kind, _, let completed) = state else { return [] }
        state = .working(breakDue: now.addingTimeInterval(config.postponeDelay), completedShortBreaks: completed)
        return [.hideOverlay, .updateStatus(.working(remaining: config.postponeDelay)), .log(.postponed, kind)]
    }

    private func pendingBreakKind(completedShortBreaks: Int) -> BreakKind {
        completedShortBreaks >= config.longBreakEvery ? .long : .short
    }

    private func completeBreak(of kind: BreakKind, completedShortBreaks: Int, now: Date) -> [Effect] {
        let newCompleted = kind == .short ? completedShortBreaks + 1 : 0
        state = .working(breakDue: now.addingTimeInterval(config.shortInterval), completedShortBreaks: newCompleted)
        return [.updateStatus(.working(remaining: config.shortInterval))]
    }
}
