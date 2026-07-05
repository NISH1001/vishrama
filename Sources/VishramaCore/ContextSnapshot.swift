import Foundation

/// A context signal that can suppress or defer breaks.
public enum SignalKind: String, Codable, Sendable, CaseIterable {
    case cameraMic     // camera or microphone in use (meeting proxy)
    case screenShare   // screen is being shared / presented
    case calendarBusy  // calendar shows a busy event now
    case focus         // macOS Focus / Do Not Disturb active
}

/// What the shell observed about the world at one tick.
public struct ContextSnapshot: Sendable, Equatable {
    public var activeSignals: Set<SignalKind>
    public var idleSeconds: TimeInterval
    /// Frontmost app bundle identifier, if known.
    public var frontmostApp: String?
    /// Start of the next busy calendar event, if the calendar signal knows one.
    public var nextBusyStart: Date?
    /// End of the busy event happening right now, if the calendar knows one.
    public var currentBusyEnd: Date?

    public init(
        activeSignals: Set<SignalKind> = [],
        idleSeconds: TimeInterval = 0,
        frontmostApp: String? = nil,
        nextBusyStart: Date? = nil,
        currentBusyEnd: Date? = nil
    ) {
        self.activeSignals = activeSignals
        self.idleSeconds = idleSeconds
        self.frontmostApp = frontmostApp
        self.nextBusyStart = nextBusyStart
        self.currentBusyEnd = currentBusyEnd
    }
}
