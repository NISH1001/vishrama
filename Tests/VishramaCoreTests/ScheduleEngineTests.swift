import Foundation
import Testing
@testable import VishramaCore

private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

private func makeEngine(
    shortInterval: TimeInterval = 25 * 60,
    shortDuration: TimeInterval = 5 * 60,
    longDuration: TimeInterval = 10 * 60,
    longBreakEvery: Int = 2
) -> ScheduleEngine {
    ScheduleEngine(
        config: BreakConfiguration(
            shortInterval: shortInterval,
            shortDuration: shortDuration,
            longDuration: longDuration,
            longBreakEvery: longBreakEvery
        ),
        startAt: t0
    )
}

/// Drive the engine through a completed break so cycle-counting tests can reuse it.
private func completeBreak(_ engine: ScheduleEngine, from due: Date, duration: TimeInterval) -> Date {
    _ = engine.tick(now: due, context: ContextSnapshot())
    let end = due.addingTimeInterval(duration)
    _ = engine.tick(now: end, context: ContextSnapshot())
    return end
}

@Suite struct WorkingCountdown {
    @Test func firstTickReportsFullIntervalRemaining() {
        let engine = makeEngine()
        let effects = engine.tick(now: t0, context: ContextSnapshot())
        #expect(effects == [.updateStatus(.working(remaining: 25 * 60.0))])
    }

    @Test func countdownDecreasesWithTime() {
        let engine = makeEngine()
        _ = engine.tick(now: t0, context: ContextSnapshot())
        let effects = engine.tick(now: t0.addingTimeInterval(60), context: ContextSnapshot())
        #expect(effects == [.updateStatus(.working(remaining: 24 * 60.0))])
    }
}

@Suite struct BreakFiring {
    @Test func shortBreakFiresWhenDue() {
        let engine = makeEngine()
        let due = t0.addingTimeInterval(25 * 60)
        let effects = engine.tick(now: due, context: ContextSnapshot())
        #expect(effects.contains(.showOverlay(.short)))
        #expect(effects.contains(.updateStatus(.onBreak(kind: .short, remaining: 5 * 60.0))))
    }

    @Test func breakEndsAfterDurationAndWorkRestarts() {
        let engine = makeEngine()
        let due = t0.addingTimeInterval(25 * 60)
        _ = engine.tick(now: due, context: ContextSnapshot())
        let end = due.addingTimeInterval(5 * 60)
        let effects = engine.tick(now: end, context: ContextSnapshot())
        #expect(effects.contains(.hideOverlay))
        #expect(effects.contains(.updateStatus(.working(remaining: 25 * 60.0))))
    }

    @Test func longBreakFiresAfterConfiguredCompletedShortBreaks() {
        let engine = makeEngine(longBreakEvery: 2)
        // Complete two short breaks.
        var cursor = t0
        for _ in 0..<2 {
            cursor = completeBreak(engine, from: cursor.addingTimeInterval(25 * 60), duration: 5 * 60)
        }
        // Third break due should be long.
        let due = cursor.addingTimeInterval(25 * 60)
        let effects = engine.tick(now: due, context: ContextSnapshot())
        #expect(effects.contains(.showOverlay(.long)))
    }

    @Test func cycleResetsAfterLongBreak() {
        let engine = makeEngine(longBreakEvery: 1)
        // One completed short break → next is long.
        var cursor = completeBreak(engine, from: t0.addingTimeInterval(25 * 60), duration: 5 * 60)
        cursor = completeBreak(engine, from: cursor.addingTimeInterval(25 * 60), duration: 10 * 60)
        // After the long break the cycle restarts with a short one.
        let due = cursor.addingTimeInterval(25 * 60)
        let effects = engine.tick(now: due, context: ContextSnapshot())
        #expect(effects.contains(.showOverlay(.short)))
    }
}

@Suite struct SkipAndPostpone {
    @Test func skipHidesOverlayAndRetriesAfterBackoff() {
        let engine = makeEngine()
        let due = t0.addingTimeInterval(25 * 60)
        _ = engine.tick(now: due, context: ContextSnapshot())
        let effects = engine.skip(now: due.addingTimeInterval(10))
        #expect(effects.contains(.hideOverlay))
        // First skip: the break is owed again in 5 minutes, not a full interval.
        #expect(effects.contains(.updateStatus(.working(remaining: 5 * 60.0))))
    }

    @Test func skippedBreakDoesNotAdvanceLongBreakCycle() {
        let engine = makeEngine(longBreakEvery: 1)
        // Skip the first short break — the next break must still be short.
        let due = t0.addingTimeInterval(25 * 60)
        _ = engine.tick(now: due, context: ContextSnapshot())
        _ = engine.skip(now: due)
        let nextDue = due.addingTimeInterval(25 * 60)
        let effects = engine.tick(now: nextDue, context: ContextSnapshot())
        #expect(effects.contains(.showOverlay(.short)))
    }

    @Test func postponeHidesOverlayAndRefiresAfterDelay() {
        let engine = makeEngine()
        let due = t0.addingTimeInterval(25 * 60)
        _ = engine.tick(now: due, context: ContextSnapshot())
        let effects = engine.postpone(now: due)
        #expect(effects.contains(.hideOverlay))
        // 5 minutes later (postponeDelay) the break fires again.
        let refire = engine.tick(now: due.addingTimeInterval(5 * 60), context: ContextSnapshot())
        #expect(refire.contains(.showOverlay(.short)))
    }
}

@Suite struct IdleHandling {
    @Test func idleBeyondThresholdFreezesCountdown() {
        let engine = makeEngine()
        _ = engine.tick(now: t0, context: ContextSnapshot())
        // 3 minutes in, user has been idle for 2 minutes (threshold).
        let now = t0.addingTimeInterval(3 * 60)
        let effects = engine.tick(now: now, context: ContextSnapshot(idleSeconds: 120))
        // Countdown freezes at the moment activity stopped: 25 - (3-2) = 24 min.
        #expect(effects == [.updateStatus(.idlePaused(remaining: 24 * 60.0))])
    }

    @Test func returningFromShortIdleResumesFrozenCountdown() {
        let engine = makeEngine()
        _ = engine.tick(now: t0, context: ContextSnapshot())
        _ = engine.tick(now: t0.addingTimeInterval(3 * 60), context: ContextSnapshot(idleSeconds: 120))
        // User returns 1 minute later (total idle 3 min < break duration).
        let back = t0.addingTimeInterval(4 * 60)
        let effects = engine.tick(now: back, context: ContextSnapshot(idleSeconds: 0))
        #expect(effects == [.updateStatus(.working(remaining: 24 * 60.0))])
    }

    @Test func longIdleCountsAsNaturalBreakAndResetsTimer() {
        let engine = makeEngine()
        _ = engine.tick(now: t0, context: ContextSnapshot())
        _ = engine.tick(now: t0.addingTimeInterval(3 * 60), context: ContextSnapshot(idleSeconds: 120))
        // User returns after 6 more minutes: total idle ≥ short break duration (5 min).
        let back = t0.addingTimeInterval(9 * 60)
        let effects = engine.tick(now: back, context: ContextSnapshot(idleSeconds: 0))
        #expect(effects.contains(.updateStatus(.working(remaining: 25 * 60.0))))
    }

    @Test func idleLongerThanLongBreakAdvancesCycle() {
        let engine = makeEngine(longBreakEvery: 1)
        // Complete one short break so the next would be long.
        let cursor = completeBreak(engine, from: t0.addingTimeInterval(25 * 60), duration: 5 * 60)
        // Now go idle for ≥ long break duration (10 min) — counts as the long break.
        let idleAt = cursor.addingTimeInterval(3 * 60)
        _ = engine.tick(now: idleAt, context: ContextSnapshot(idleSeconds: 120))
        let back = idleAt.addingTimeInterval(11 * 60)
        _ = engine.tick(now: back, context: ContextSnapshot(idleSeconds: 0))
        // Cycle reset: the next due break is short again.
        let due = back.addingTimeInterval(25 * 60)
        let effects = engine.tick(now: due, context: ContextSnapshot())
        #expect(effects.contains(.showOverlay(.short)))
    }
}

@Suite struct ManualTrigger {
    @Test func breakNowFiresImmediately() {
        let engine = makeEngine()
        _ = engine.tick(now: t0, context: ContextSnapshot())
        let effects = engine.breakNow(now: t0.addingTimeInterval(60))
        #expect(effects.contains(.showOverlay(.short)))
    }

    @Test func breakNowDuringBreakDoesNothing() {
        let engine = makeEngine()
        let due = t0.addingTimeInterval(25 * 60)
        _ = engine.tick(now: due, context: ContextSnapshot())
        #expect(engine.breakNow(now: due) == [])
    }
}

@Suite struct EventLogging {
    @Test func firingLogsFiredEvent() {
        let engine = makeEngine()
        let due = t0.addingTimeInterval(25 * 60)
        let effects = engine.tick(now: due, context: ContextSnapshot())
        #expect(effects.contains(.log(.fired, .short)))
    }

    @Test func completionLogsCompletedEvent() {
        let engine = makeEngine()
        let due = t0.addingTimeInterval(25 * 60)
        _ = engine.tick(now: due, context: ContextSnapshot())
        let effects = engine.tick(now: due.addingTimeInterval(5 * 60), context: ContextSnapshot())
        #expect(effects.contains(.log(.completed, .short)))
    }

    @Test func skipLogsSkippedEvent() {
        let engine = makeEngine()
        let due = t0.addingTimeInterval(25 * 60)
        _ = engine.tick(now: due, context: ContextSnapshot())
        #expect(engine.skip(now: due).contains(.log(.skipped, .short)))
    }

    @Test func postponeLogsPostponedEvent() {
        let engine = makeEngine()
        let due = t0.addingTimeInterval(25 * 60)
        _ = engine.tick(now: due, context: ContextSnapshot())
        #expect(engine.postpone(now: due).contains(.log(.postponed, .short)))
    }

    @Test func longAbsenceLogsNaturalBreak() {
        let engine = makeEngine()
        _ = engine.tick(now: t0, context: ContextSnapshot())
        _ = engine.tick(now: t0.addingTimeInterval(3 * 60), context: ContextSnapshot(idleSeconds: 120))
        let back = t0.addingTimeInterval(9 * 60)
        let effects = engine.tick(now: back, context: ContextSnapshot(idleSeconds: 0))
        #expect(effects.contains(.log(.naturalBreak, .short)))
    }
}

@Suite struct ManualPause {
    @Test func pauseFreezesCountdownAndBlocksBreaks() {
        let engine = makeEngine()
        _ = engine.tick(now: t0, context: ContextSnapshot())
        let paused = engine.togglePause(now: t0.addingTimeInterval(60))
        #expect(paused.contains(.updateStatus(.manualPaused(remaining: 24 * 60.0))))
        // Way past the original due time: still paused, no overlay.
        let effects = engine.tick(now: t0.addingTimeInterval(60 * 60), context: ContextSnapshot())
        #expect(effects == [.updateStatus(.manualPaused(remaining: 24 * 60.0))])
    }

    @Test func resumeContinuesFromFrozenRemaining() {
        let engine = makeEngine()
        _ = engine.tick(now: t0, context: ContextSnapshot())
        _ = engine.togglePause(now: t0.addingTimeInterval(60))
        let later = t0.addingTimeInterval(60 * 60)
        let resumed = engine.togglePause(now: later)
        #expect(resumed.contains(.updateStatus(.working(remaining: 24 * 60.0))))
        // Break fires 24 minutes after resume.
        let effects = engine.tick(now: later.addingTimeInterval(24 * 60), context: ContextSnapshot())
        #expect(effects.contains(.showOverlay(.short)))
    }

    @Test func pauseDuringBreakDismissesOverlay() {
        let engine = makeEngine()
        let due = t0.addingTimeInterval(25 * 60)
        _ = engine.tick(now: due, context: ContextSnapshot())
        let effects = engine.togglePause(now: due.addingTimeInterval(2))
        #expect(effects.contains(.hideOverlay))
        #expect(effects.contains(.updateStatus(.manualPaused(remaining: 25 * 60.0))))
    }

    @Test func pauseWinsOverIdle() {
        let engine = makeEngine()
        _ = engine.tick(now: t0, context: ContextSnapshot())
        _ = engine.togglePause(now: t0.addingTimeInterval(60))
        // Long idle while paused must not trigger idle handling or natural breaks.
        let effects = engine.tick(now: t0.addingTimeInterval(30 * 60), context: ContextSnapshot(idleSeconds: 20 * 60))
        #expect(effects == [.updateStatus(.manualPaused(remaining: 24 * 60.0))])
    }
}

@Suite struct ContextSuppression {
    let meeting = ContextSnapshot(activeSignals: [.cameraMic])

    @Test func breakDueDuringMeetingIsSuppressed() {
        let engine = makeEngine()
        let due = t0.addingTimeInterval(25 * 60)
        let effects = engine.tick(now: due, context: meeting)
        #expect(!effects.contains(.showOverlay(.short)))
        #expect(effects.contains(.updateStatus(.suppressed(overdue: 0))))
        #expect(effects.contains(.log(.suppressedStart, .short)))
    }

    @Test func overdueTimeGrowsWhileSuppressed() {
        let engine = makeEngine()
        let due = t0.addingTimeInterval(25 * 60)
        _ = engine.tick(now: due, context: meeting)
        let effects = engine.tick(now: due.addingTimeInterval(120), context: meeting)
        #expect(effects.contains(.updateStatus(.suppressed(overdue: 120))))
    }

    @Test func breakFiresAfterSignalsClearPlusGrace() {
        let engine = makeEngine()
        let due = t0.addingTimeInterval(25 * 60)
        _ = engine.tick(now: due, context: meeting)
        // Meeting ends 10 min later.
        let clear = due.addingTimeInterval(10 * 60)
        let clearEffects = engine.tick(now: clear, context: ContextSnapshot())
        #expect(!clearEffects.contains(.showOverlay(.short)))
        // 60s grace after all-clear, the break fires.
        let effects = engine.tick(now: clear.addingTimeInterval(60), context: ContextSnapshot())
        #expect(effects.contains(.showOverlay(.short)))
        #expect(effects.contains(.log(.suppressedEnd, .short)))
    }

    @Test func signalReturningDuringGraceRestartsWait() {
        let engine = makeEngine()
        let due = t0.addingTimeInterval(25 * 60)
        _ = engine.tick(now: due, context: meeting)
        let clear = due.addingTimeInterval(10 * 60)
        _ = engine.tick(now: clear, context: ContextSnapshot())
        // 30s into the grace the meeting resumes.
        _ = engine.tick(now: clear.addingTimeInterval(30), context: meeting)
        // 60s after the FIRST clear: must NOT fire (wait restarted).
        let effects = engine.tick(now: clear.addingTimeInterval(60), context: meeting)
        #expect(!effects.contains(.showOverlay(.short)))
    }

    @Test func meetingPreventsIdlePause() {
        // Sitting quietly in a meeting is not "away": countdown keeps running.
        let engine = makeEngine()
        _ = engine.tick(now: t0, context: ContextSnapshot())
        let now = t0.addingTimeInterval(10 * 60)
        let effects = engine.tick(now: now, context: ContextSnapshot(activeSignals: [.cameraMic], idleSeconds: 300))
        #expect(effects == [.updateStatus(.working(remaining: 15 * 60.0))])
    }

    @Test func breakNeverFiresMidMeetingEvenLongAfterDue() {
        let engine = makeEngine()
        let due = t0.addingTimeInterval(25 * 60)
        _ = engine.tick(now: due, context: meeting)
        let effects = engine.tick(now: due.addingTimeInterval(60 * 60), context: meeting)
        #expect(!effects.contains(.showOverlay(.short)))
    }
}

@Suite struct SkipBackoff {
    @Test func firstSkipRetriesAfterShortBackoffNotFullInterval() {
        let engine = makeEngine()
        let due = t0.addingTimeInterval(25 * 60)
        _ = engine.tick(now: due, context: ContextSnapshot())
        _ = engine.skip(now: due)
        // 5 minutes later the break comes back (not 25).
        let effects = engine.tick(now: due.addingTimeInterval(5 * 60), context: ContextSnapshot())
        #expect(effects.contains(.showOverlay(.short)))
    }

    @Test func backoffDelayGrowsWithConsecutiveSkips() {
        let engine = makeEngine()
        var due = t0.addingTimeInterval(25 * 60)
        _ = engine.tick(now: due, context: ContextSnapshot())
        _ = engine.skip(now: due)               // retry in 5
        due = due.addingTimeInterval(5 * 60)
        _ = engine.tick(now: due, context: ContextSnapshot())
        _ = engine.skip(now: due)               // retry in 10
        // 5 min later: too early now.
        let early = engine.tick(now: due.addingTimeInterval(5 * 60), context: ContextSnapshot())
        #expect(!early.contains(.showOverlay(.short)))
        let onTime = engine.tick(now: due.addingTimeInterval(10 * 60), context: ContextSnapshot())
        #expect(onTime.contains(.showOverlay(.short)))
    }

    @Test func completedBreakResetsBackoff() {
        let engine = makeEngine()
        var due = t0.addingTimeInterval(25 * 60)
        _ = engine.tick(now: due, context: ContextSnapshot())
        _ = engine.skip(now: due)
        due = due.addingTimeInterval(5 * 60)
        // Complete this one fully.
        _ = engine.tick(now: due, context: ContextSnapshot())
        _ = engine.tick(now: due.addingTimeInterval(5 * 60), context: ContextSnapshot())
        // Next cycle: skip again → back to the FIRST backoff step (5 min).
        let nextDue = due.addingTimeInterval(5 * 60 + 25 * 60)
        _ = engine.tick(now: nextDue, context: ContextSnapshot())
        _ = engine.skip(now: nextDue)
        let effects = engine.tick(now: nextDue.addingTimeInterval(5 * 60), context: ContextSnapshot())
        #expect(effects.contains(.showOverlay(.short)))
    }

    @Test func backoffLevelIsExposedForLogging() {
        let engine = makeEngine()
        let due = t0.addingTimeInterval(25 * 60)
        #expect(engine.backoffLevel == 0)
        _ = engine.tick(now: due, context: ContextSnapshot())
        _ = engine.skip(now: due)
        #expect(engine.backoffLevel == 1)
    }
}

@Suite struct FlowMode {
    /// Drive three quick fire+skip rounds to trip flow detection.
    private func skipThreeTimes(_ engine: ScheduleEngine) -> Date {
        var due = t0.addingTimeInterval(25 * 60)
        for delay in [5 * 60.0, 10 * 60.0] {
            _ = engine.tick(now: due, context: ContextSnapshot())
            _ = engine.skip(now: due)
            due = due.addingTimeInterval(delay)
        }
        _ = engine.tick(now: due, context: ContextSnapshot())
        _ = engine.skip(now: due)
        return due
    }

    @Test func threeSkipsInWindowEnterFlowQuiet() {
        let engine = makeEngine()
        let lastSkip = skipThreeTimes(engine)
        // Third skip's backoff is 20 min; when that break comes due,
        // flow mode swaps the overlay for a gentle notification.
        let effects = engine.tick(now: lastSkip.addingTimeInterval(20 * 60), context: ContextSnapshot())
        #expect(!effects.contains(.showOverlay(.short)))
        #expect(effects.contains(.notifyBreak(.short)))
    }

    @Test func flowEnterIsLogged() {
        let engine = makeEngine()
        var due = t0.addingTimeInterval(25 * 60)
        _ = engine.tick(now: due, context: ContextSnapshot())
        _ = engine.skip(now: due)
        due = due.addingTimeInterval(5 * 60)
        _ = engine.tick(now: due, context: ContextSnapshot())
        _ = engine.skip(now: due)
        due = due.addingTimeInterval(10 * 60)
        _ = engine.tick(now: due, context: ContextSnapshot())
        let effects = engine.skip(now: due)
        #expect(effects.contains(.log(.flowEnter, nil)))
    }

    @Test func flowQuietExpiresAndOverlaysReturn() {
        let engine = makeEngine()
        let lastSkip = skipThreeTimes(engine)
        // Notified break during flow reschedules a full interval.
        let notifyAt = lastSkip.addingTimeInterval(20 * 60)
        _ = engine.tick(now: notifyAt, context: ContextSnapshot())
        // Flow quiet lasts 45 min from the third skip; the next due break
        // (25 min after the notification) is past it → overlay again.
        let effects = engine.tick(now: notifyAt.addingTimeInterval(25 * 60), context: ContextSnapshot())
        #expect(effects.contains(.showOverlay(.short)))
    }
}

@Suite struct PauseLogging {
    @Test func pauseAndResumeAreLogged() {
        let engine = makeEngine()
        _ = engine.tick(now: t0, context: ContextSnapshot())
        let paused = engine.togglePause(now: t0.addingTimeInterval(60))
        #expect(paused.contains(.log(.paused, nil)))
        let resumed = engine.togglePause(now: t0.addingTimeInterval(120))
        #expect(resumed.contains(.log(.resumed, nil)))
    }
}

@Suite struct ResetTimer {
    @Test func resetRestartsFullIntervalAndClearsBackoff() {
        let engine = makeEngine()
        let due = t0.addingTimeInterval(25 * 60)
        _ = engine.tick(now: due, context: ContextSnapshot())
        _ = engine.skip(now: due)   // backoff level 1
        let effects = engine.reset(now: due.addingTimeInterval(60))
        #expect(effects.contains(.updateStatus(.working(remaining: 25 * 60.0))))
        #expect(engine.backoffLevel == 0)
    }

    @Test func resetDuringBreakDismissesOverlay() {
        let engine = makeEngine()
        let due = t0.addingTimeInterval(25 * 60)
        _ = engine.tick(now: due, context: ContextSnapshot())
        let effects = engine.reset(now: due)
        #expect(effects.contains(.hideOverlay))
        #expect(effects.contains(.updateStatus(.working(remaining: 25 * 60.0))))
    }
}

@Suite struct PreBreakHeadsUp {
    private func engineWithWarning(_ lead: TimeInterval) -> ScheduleEngine {
        ScheduleEngine(
            config: BreakConfiguration(preBreakWarning: lead),
            startAt: t0
        )
    }

    @Test func headsUpFiresAtConfiguredLeadBeforeBreak() {
        let engine = engineWithWarning(60)
        _ = engine.tick(now: t0, context: ContextSnapshot())
        let effects = engine.tick(now: t0.addingTimeInterval(24 * 60), context: ContextSnapshot())
        #expect(effects.contains(.notifyPreBreak(.short, 60)))
        // Still working — the break itself hasn't fired.
        #expect(effects.contains(.updateStatus(.working(remaining: 60))))
    }

    @Test func headsUpFiresOnlyOncePerBreak() {
        let engine = engineWithWarning(60)
        _ = engine.tick(now: t0, context: ContextSnapshot())
        _ = engine.tick(now: t0.addingTimeInterval(24 * 60), context: ContextSnapshot())
        let again = engine.tick(now: t0.addingTimeInterval(24 * 60 + 30), context: ContextSnapshot())
        #expect(!again.contains(.notifyPreBreak(.short, 60)))
    }

    @Test func zeroLeadDisablesHeadsUp() {
        let engine = engineWithWarning(0)
        _ = engine.tick(now: t0, context: ContextSnapshot())
        let effects = engine.tick(now: t0.addingTimeInterval(25 * 60 - 1), context: ContextSnapshot())
        #expect(!effects.contains { if case .notifyPreBreak = $0 { return true } else { return false } })
    }

    @Test func noHeadsUpDuringMeeting() {
        // The break will be suppressed anyway — don't tease it.
        let engine = engineWithWarning(60)
        _ = engine.tick(now: t0, context: ContextSnapshot())
        let effects = engine.tick(
            now: t0.addingTimeInterval(24 * 60),
            context: ContextSnapshot(activeSignals: [.cameraMic]))
        #expect(!effects.contains { if case .notifyPreBreak = $0 { return true } else { return false } })
    }

    @Test func postponedBreakGetsAFreshHeadsUp() {
        let engine = engineWithWarning(60)
        let due = t0.addingTimeInterval(25 * 60)
        _ = engine.tick(now: due.addingTimeInterval(-60), context: ContextSnapshot())  // first warning
        _ = engine.tick(now: due, context: ContextSnapshot())                          // break fires
        _ = engine.postpone(now: due)                                                  // +5 min
        let effects = engine.tick(now: due.addingTimeInterval(4 * 60), context: ContextSnapshot())
        #expect(effects.contains(.notifyPreBreak(.short, 60)))
    }
}

@Suite struct FinishBreakEarly {
    @Test func finishCompletesActiveBreakEarly() {
        let engine = makeEngine()
        let due = t0.addingTimeInterval(25 * 60)
        _ = engine.tick(now: due, context: ContextSnapshot())
        let effects = engine.finishBreak(now: due.addingTimeInterval(60))
        #expect(effects.contains(.hideOverlay))
        #expect(effects.contains(.log(.completed, .short)))
        #expect(effects.contains(.updateStatus(.working(remaining: 25 * 60.0))))
    }

    @Test func finishAdvancesLongBreakCycle() {
        let engine = makeEngine(longBreakEvery: 1)
        let due = t0.addingTimeInterval(25 * 60)
        _ = engine.tick(now: due, context: ContextSnapshot())
        _ = engine.finishBreak(now: due)
        // Completed (not skipped): next break is the long one.
        let next = due.addingTimeInterval(25 * 60)
        #expect(engine.tick(now: next, context: ContextSnapshot()).contains(.showOverlay(.long)))
    }

    @Test func finishOutsideABreakDoesNothing() {
        let engine = makeEngine()
        _ = engine.tick(now: t0, context: ContextSnapshot())
        #expect(engine.finishBreak(now: t0.addingTimeInterval(60)) == [])
    }
}

@Suite struct SleepWake {
    @Test func longSleepCreditsTheNaturalBreak() {
        let engine = makeEngine()
        _ = engine.tick(now: t0, context: ContextSnapshot())
        // Lid closed at t0+20min, slept 8h.
        let wake = t0.addingTimeInterval(20 * 60 + 8 * 3600)
        let effects = engine.systemSlept(for: 8 * 3600, now: wake)
        #expect(effects.contains(.log(.naturalBreak, .short)))
        #expect(effects.contains(.updateStatus(.working(remaining: 25 * 60.0))))
    }

    @Test func shortNapDefersTheDueBreakInsteadOfAmbushing() {
        let engine = makeEngine()
        _ = engine.tick(now: t0, context: ContextSnapshot())
        // Lid closed 1 min before the break was due; napped 3 min (< break length).
        let wake = t0.addingTimeInterval(24 * 60 + 3 * 60)
        let effects = engine.systemSlept(for: 3 * 60, now: wake)
        #expect(effects.contains(.updateStatus(.working(remaining: 60.0))))
        // No overlay on the wake tick...
        let tick = engine.tick(now: wake.addingTimeInterval(1), context: ContextSnapshot())
        #expect(!tick.contains(.showOverlay(.short)))
        // ...but the break arrives after the remaining minute.
        let due = engine.tick(now: wake.addingTimeInterval(61), context: ContextSnapshot())
        #expect(due.contains(.showOverlay(.short)))
    }

    @Test func sleepWhilePausedChangesNothing() {
        let engine = makeEngine()
        _ = engine.tick(now: t0, context: ContextSnapshot())
        _ = engine.togglePause(now: t0.addingTimeInterval(60))
        #expect(engine.systemSlept(for: 3600, now: t0.addingTimeInterval(2 * 3600)) == [])
    }
}

@Suite struct SnapshotRestore {
    @Test func snapshotCarriesRemainingCycleAndBackoff() {
        let engine = makeEngine(longBreakEvery: 2)
        // One completed break (cycle=1), one skip (backoff=1), 10 min into work.
        var cursor = completeBreak(engine, from: t0.addingTimeInterval(25 * 60), duration: 5 * 60)
        _ = engine.tick(now: cursor.addingTimeInterval(25 * 60), context: ContextSnapshot())
        _ = engine.skip(now: cursor.addingTimeInterval(25 * 60))
        cursor = cursor.addingTimeInterval(25 * 60)
        let at = cursor.addingTimeInterval(60)
        _ = engine.tick(now: at, context: ContextSnapshot())

        let snapshot = engine.snapshot(now: at)
        let restored = ScheduleEngine(config: engine.config, startAt: at, restoring: snapshot)
        // Remaining continues where it left off (skip backoff was 5 min; 1 min elapsed).
        let effects = restored.tick(now: at, context: ContextSnapshot())
        #expect(effects.contains(.updateStatus(.working(remaining: 4 * 60.0))))
        #expect(restored.backoffLevel == 1)
        // Cycle position survives: next completed break is the second → then long.
        _ = restored.tick(now: at.addingTimeInterval(4 * 60), context: ContextSnapshot())
        _ = restored.tick(now: at.addingTimeInterval(9 * 60), context: ContextSnapshot())  // completes
        let due = at.addingTimeInterval(9 * 60 + 25 * 60)
        #expect(restored.tick(now: due, context: ContextSnapshot()).contains(.showOverlay(.long)))
    }

    @Test func restoreAfterShortDowntimeSubtractsTheGap() {
        let engine = makeEngine()
        _ = engine.tick(now: t0, context: ContextSnapshot())
        let saved = engine.snapshot(now: t0.addingTimeInterval(60))   // 24 min left
        // Relaunched 2 minutes later.
        let later = t0.addingTimeInterval(3 * 60)
        let restored = ScheduleEngine(config: engine.config, startAt: later, restoring: saved)
        let effects = restored.tick(now: later, context: ContextSnapshot())
        #expect(effects.contains(.updateStatus(.working(remaining: 22 * 60.0))))
    }

    @Test func restoreAfterLongDowntimeStartsFreshButKeepsCycle() {
        let engine = makeEngine(longBreakEvery: 1)
        let cursor = completeBreak(engine, from: t0.addingTimeInterval(25 * 60), duration: 5 * 60)
        let saved = engine.snapshot(now: cursor.addingTimeInterval(60))
        // Relaunched 2 hours later: fresh interval, but cycle position kept.
        let later = cursor.addingTimeInterval(2 * 3600)
        let restored = ScheduleEngine(config: engine.config, startAt: later, restoring: saved)
        let effects = restored.tick(now: later, context: ContextSnapshot())
        #expect(effects.contains(.updateStatus(.working(remaining: 25 * 60.0))))
        let due = later.addingTimeInterval(25 * 60)
        #expect(restored.tick(now: due, context: ContextSnapshot()).contains(.showOverlay(.long)))
    }

    @Test func snapshotDuringBreakRestoresAsFreshWork() {
        let engine = makeEngine()
        let due = t0.addingTimeInterval(25 * 60)
        _ = engine.tick(now: due, context: ContextSnapshot())
        let saved = engine.snapshot(now: due.addingTimeInterval(60))
        let restored = ScheduleEngine(config: engine.config, startAt: due, restoring: saved)
        // Mid-break snapshots don't try to resurrect the overlay.
        let effects = restored.tick(now: due.addingTimeInterval(2 * 60), context: ContextSnapshot())
        #expect(effects.contains(.updateStatus(.working(remaining: 23 * 60.0))))
    }
}

@Suite struct MeetingGap {
    @Test func meetingSoonPullsTheBreakForward() {
        let engine = makeEngine()
        _ = engine.tick(now: t0, context: ContextSnapshot())
        // 16 min in (>60% of 25), meeting starts in 8 min (≤ 5min break + 5 grace).
        let now = t0.addingTimeInterval(16 * 60)
        let effects = engine.tick(now: now, context: ContextSnapshot(
            nextBusyStart: now.addingTimeInterval(8 * 60)))
        #expect(effects.contains(.showOverlayForMeetingGap(.short)))
        #expect(effects.contains(.log(.fired, .short)))
    }

    @Test func noEarlyBreakWhenBarelyIntoTheInterval() {
        let engine = makeEngine()
        _ = engine.tick(now: t0, context: ContextSnapshot())
        let now = t0.addingTimeInterval(5 * 60)   // only 20% in
        let effects = engine.tick(now: now, context: ContextSnapshot(
            nextBusyStart: now.addingTimeInterval(8 * 60)))
        #expect(!effects.contains(.showOverlayForMeetingGap(.short)))
        #expect(effects.contains(.updateStatus(.working(remaining: 20 * 60.0))))
    }

    @Test func noEarlyBreakWhenMeetingIsFarAway() {
        let engine = makeEngine()
        _ = engine.tick(now: t0, context: ContextSnapshot())
        let now = t0.addingTimeInterval(20 * 60)
        let effects = engine.tick(now: now, context: ContextSnapshot(
            nextBusyStart: now.addingTimeInterval(45 * 60)))
        #expect(!effects.contains(.showOverlayForMeetingGap(.short)))
    }

    @Test func noEarlyBreakWhileAlreadyInAMeeting() {
        let engine = makeEngine()
        _ = engine.tick(now: t0, context: ContextSnapshot())
        let now = t0.addingTimeInterval(20 * 60)
        let effects = engine.tick(now: now, context: ContextSnapshot(
            activeSignals: [.cameraMic],
            nextBusyStart: now.addingTimeInterval(8 * 60)))
        #expect(!effects.contains(.showOverlayForMeetingGap(.short)))
    }
}

@Suite struct IdleAmnestyAfterBreaks {
    @Test func handsOffBreakDoesNotLeakIdleIntoFreshInterval() {
        let engine = makeEngine()
        let due = t0.addingTimeInterval(25 * 60)
        _ = engine.tick(now: due, context: ContextSnapshot())
        // User keeps hands off for the whole break (idle grows to ~5 min).
        let end = due.addingTimeInterval(5 * 60)
        _ = engine.tick(now: end, context: ContextSnapshot(idleSeconds: 5 * 60))
        // One second into the fresh interval, system idle still says ~5 min —
        // but that idle belongs to the break, not to the new work period.
        let effects = engine.tick(now: end.addingTimeInterval(1), context: ContextSnapshot(idleSeconds: 5 * 60 + 1))
        #expect(effects.contains(.updateStatus(.working(remaining: 25 * 60.0 - 1))))
        #expect(!effects.contains { if case .updateStatus(.idlePaused) = $0 { return true } else { return false } })
    }

    @Test func stayingAwayAfterTheBreakStillCountsFromBreakEnd() {
        let engine = makeEngine()
        let due = t0.addingTimeInterval(25 * 60)
        _ = engine.tick(now: due, context: ContextSnapshot())
        let end = due.addingTimeInterval(5 * 60)
        _ = engine.tick(now: end, context: ContextSnapshot(idleSeconds: 5 * 60))
        // User genuinely leaves for 6 more minutes AFTER the break ended.
        _ = engine.tick(now: end.addingTimeInterval(3 * 60), context: ContextSnapshot(idleSeconds: 8 * 60))
        let back = end.addingTimeInterval(6 * 60)
        let effects = engine.tick(now: back, context: ContextSnapshot(idleSeconds: 0))
        // Post-break absence ≥ break length → natural break, counted from break END.
        #expect(effects.contains(.log(.naturalBreak, .short)))
    }

    @Test func briefLingerAfterBreakThenReturnJustResumes() {
        let engine = makeEngine()
        let due = t0.addingTimeInterval(25 * 60)
        _ = engine.tick(now: due, context: ContextSnapshot())
        let end = due.addingTimeInterval(5 * 60)
        _ = engine.tick(now: end, context: ContextSnapshot(idleSeconds: 5 * 60))
        // Idle-paused 3 min after the break, then returns: NOT a natural break.
        _ = engine.tick(now: end.addingTimeInterval(3 * 60), context: ContextSnapshot(idleSeconds: 8 * 60))
        let back = end.addingTimeInterval(3 * 60 + 30)
        let effects = engine.tick(now: back, context: ContextSnapshot(idleSeconds: 0))
        #expect(!effects.contains { if case .log(.naturalBreak, _) = $0 { return true } else { return false } })
        #expect(effects.contains { if case .updateStatus(.working) = $0 { return true } else { return false } })
    }
}

@Suite struct MicroNudges {
    private func engineWithNudges(_ interval: TimeInterval = 20 * 60) -> ScheduleEngine {
        ScheduleEngine(config: BreakConfiguration(microNudgeInterval: interval), startAt: t0)
    }
    private let meeting = ContextSnapshot(activeSignals: [.cameraMic])

    @Test func nudgeAfterSuppressionReachesInterval() {
        let engine = engineWithNudges()
        let due = t0.addingTimeInterval(25 * 60)
        _ = engine.tick(now: due, context: meeting)
        let early = engine.tick(now: due.addingTimeInterval(19 * 60), context: meeting)
        #expect(!early.contains(.notifyMicroBreak))
        let effects = engine.tick(now: due.addingTimeInterval(20 * 60), context: meeting)
        #expect(effects.contains(.notifyMicroBreak))
        #expect(effects.contains(.log(.microNudge, nil)))
    }

    @Test func nudgeRepeatsAtEachInterval() {
        let engine = engineWithNudges()
        let due = t0.addingTimeInterval(25 * 60)
        _ = engine.tick(now: due, context: meeting)
        _ = engine.tick(now: due.addingTimeInterval(20 * 60), context: meeting)
        let tooSoon = engine.tick(now: due.addingTimeInterval(30 * 60), context: meeting)
        #expect(!tooSoon.contains(.notifyMicroBreak))
        let second = engine.tick(now: due.addingTimeInterval(40 * 60), context: meeting)
        #expect(second.contains(.notifyMicroBreak))
    }

    @Test func silentWhileScreenSharing() {
        let engine = engineWithNudges()
        let due = t0.addingTimeInterval(25 * 60)
        let sharing = ContextSnapshot(activeSignals: [.cameraMic, .screenShare])
        _ = engine.tick(now: due, context: sharing)
        let effects = engine.tick(now: due.addingTimeInterval(20 * 60), context: sharing)
        #expect(!effects.contains(.notifyMicroBreak))
    }

    @Test func heldWhenMeetingEndsSoon() {
        let engine = engineWithNudges()
        let due = t0.addingTimeInterval(25 * 60)
        _ = engine.tick(now: due, context: meeting)
        let at = due.addingTimeInterval(20 * 60)
        let endingSoon = ContextSnapshot(
            activeSignals: [.cameraMic],
            currentBusyEnd: at.addingTimeInterval(3 * 60))
        let effects = engine.tick(now: at, context: endingSoon)
        #expect(!effects.contains(.notifyMicroBreak))
    }

    @Test func zeroIntervalDisablesNudges() {
        let engine = engineWithNudges(0)
        let due = t0.addingTimeInterval(25 * 60)
        _ = engine.tick(now: due, context: meeting)
        let effects = engine.tick(now: due.addingTimeInterval(60 * 60), context: meeting)
        #expect(!effects.contains(.notifyMicroBreak))
    }
}
