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

    public init(
        shortInterval: TimeInterval = 25 * 60,
        shortDuration: TimeInterval = 5 * 60,
        longDuration: TimeInterval = 10 * 60,
        longBreakEvery: Int = 2,
        idlePauseThreshold: TimeInterval = 120,
        postponeDelay: TimeInterval = 5 * 60
    ) {
        self.shortInterval = shortInterval
        self.shortDuration = shortDuration
        self.longDuration = longDuration
        self.longBreakEvery = longBreakEvery
        self.idlePauseThreshold = idlePauseThreshold
        self.postponeDelay = postponeDelay
    }

    public func duration(of kind: BreakKind) -> TimeInterval {
        kind == .short ? shortDuration : longDuration
    }
}
