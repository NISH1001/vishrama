import Foundation

public enum BreakKind: String, Codable, Sendable, Equatable {
    case short  // eye break: look away, water, neck
    case long   // standup break: walk, Anapana
}

public struct BreakConfiguration: Sendable, Equatable {
    /// Work time before a short break is due.
    public var shortInterval: TimeInterval
    public var shortDuration: TimeInterval
    public var longDuration: TimeInterval
    /// A long break replaces the short one after this many completed short breaks.
    public var longBreakEvery: Int
    /// Idle time after which the work countdown freezes.
    public var idlePauseThreshold: TimeInterval
    /// Postpone pushes the break out by this much.
    public var postponeDelay: TimeInterval
    /// After a meeting/share ends, wait this long before showing the overdue break.
    public var suppressionGrace: TimeInterval
    /// Retry delays after the 1st, 2nd, 3rd… consecutive skip (last one repeats).
    public var backoffDelays: [TimeInterval]
    /// Scales backoff delays: Gentle 2.0 / Normal 1.0 / Persistent 0.5.
    public var backoffScale: Double
    /// Skip-weight within this rolling window that means "user is in flow".
    public var flowWindow: TimeInterval
    public var flowThreshold: Double
    /// How long flow mode quiets overlays once detected.
    public var flowQuietDuration: TimeInterval
    /// Gentle heads-up this long before a break fires (0 = off).
    public var preBreakWarning: TimeInterval
    /// In-meeting eye-reminder cadence while a break is suppressed (0 = off).
    public var microNudgeInterval: TimeInterval

    public init(
        shortInterval: TimeInterval = 25 * 60,
        shortDuration: TimeInterval = 5 * 60,
        longDuration: TimeInterval = 10 * 60,
        longBreakEvery: Int = 2,
        idlePauseThreshold: TimeInterval = 120,
        postponeDelay: TimeInterval = 5 * 60,
        suppressionGrace: TimeInterval = 60,
        backoffDelays: [TimeInterval] = [5 * 60, 10 * 60, 20 * 60],
        backoffScale: Double = 1.0,
        flowWindow: TimeInterval = 90 * 60,
        flowThreshold: Double = 3.0,
        flowQuietDuration: TimeInterval = 45 * 60,
        preBreakWarning: TimeInterval = 60,
        microNudgeInterval: TimeInterval = 20 * 60
    ) {
        self.shortInterval = shortInterval
        self.shortDuration = shortDuration
        self.longDuration = longDuration
        self.longBreakEvery = longBreakEvery
        self.idlePauseThreshold = idlePauseThreshold
        self.postponeDelay = postponeDelay
        self.suppressionGrace = suppressionGrace
        self.backoffDelays = backoffDelays
        self.backoffScale = backoffScale
        self.flowWindow = flowWindow
        self.flowThreshold = flowThreshold
        self.flowQuietDuration = flowQuietDuration
        self.preBreakWarning = preBreakWarning
        self.microNudgeInterval = microNudgeInterval
    }

    /// Delay before retrying after the Nth consecutive skip (1-based).
    public func backoffDelay(level: Int) -> TimeInterval {
        guard let last = backoffDelays.last else { return shortInterval }
        let raw = level <= backoffDelays.count ? backoffDelays[level - 1] : last
        return raw * backoffScale
    }

    public func duration(of kind: BreakKind) -> TimeInterval {
        kind == .short ? shortDuration : longDuration
    }
}
