import Foundation

/// What the menu bar should show. The shell owns presentation (icons, fonts);
/// the engine only reports semantics.
public enum StatusInfo: Equatable, Sendable {
    case working(remaining: TimeInterval)
    case onBreak(kind: BreakKind, remaining: TimeInterval)
    case idlePaused(remaining: TimeInterval)
    case manualPaused(remaining: TimeInterval)
    /// A break is due but context (meeting, screen share, …) is holding it back.
    case suppressed(overdue: TimeInterval)
}

/// Side effects the shell must perform after a tick or user action.
public enum Effect: Equatable, Sendable {
    case updateStatus(StatusInfo)
    case showOverlay(BreakKind)
    case hideOverlay
    /// Flow mode: announce the due break gently instead of taking the screen.
    case notifyBreak(BreakKind)
    /// Heads-up: a break arrives in the given number of seconds.
    case notifyPreBreak(BreakKind, TimeInterval)
    /// A meeting starts soon — the break was pulled forward into the gap.
    case showOverlayForMeetingGap(BreakKind)
    /// Record a behavior event; the shell enriches it with timestamp/app/signals.
    case log(BreakEventKind, BreakKind?)
}

/// Internal engine state.
enum ScheduleState: Equatable, Sendable {
    case working(breakDue: Date, completedShortBreaks: Int)
    case breakActive(kind: BreakKind, endsAt: Date, completedShortBreaks: Int)
    case idlePaused(remainingWork: TimeInterval, completedShortBreaks: Int, idleStart: Date)
    case manuallyPaused(remainingWork: TimeInterval, completedShortBreaks: Int)
    /// Break due but suppressed by context; clearSince tracks the all-clear grace wait.
    case pendingSuppressed(dueSince: Date, clearSince: Date?, completedShortBreaks: Int)
}
