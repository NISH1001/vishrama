import Foundation

/// What happened, for the behavior log the pattern learner consumes.
public enum BreakEventKind: String, Codable, Sendable, Equatable {
    case fired          // overlay shown on schedule
    case completed      // break ran to completion
    case skipped
    case postponed
    case suppressedStart
    case suppressedEnd
    case flowEnter
    case notified       // flow mode: notification instead of overlay
    case paused         // user paused from the menu bar
    case resumed
    case slept          // hardware sleep (lid closed); logged on wake with duration
    case naturalBreak   // long idle counted as a break
}

/// One line in the JSONL behavior log.
public struct BreakEvent: Codable, Equatable, Sendable {
    public var v: Int
    public var ts: Date
    public var event: BreakEventKind
    public var breakKind: BreakKind?
    /// Day of week 1–7 (Sunday = 1, matching Calendar) and local hour 0–23.
    public var dow: Int
    public var hour: Int
    /// Frontmost app bundle ID at the time.
    public var app: String?
    public var signals: [String]
    public var idleSec: Double
    public var backoffLevel: Int
    public var workedSec: Double
    /// Span of the event where one applies (e.g. slept). Optional so lines
    /// written by older versions keep decoding.
    public var durationSec: Double?

    public init(
        ts: Date,
        event: BreakEventKind,
        breakKind: BreakKind? = nil,
        app: String? = nil,
        signals: [String] = [],
        idleSec: Double = 0,
        backoffLevel: Int = 0,
        workedSec: Double = 0,
        durationSec: Double? = nil,
        calendar: Calendar = .current
    ) {
        self.v = 1
        self.ts = ts
        self.event = event
        self.breakKind = breakKind
        self.dow = calendar.component(.weekday, from: ts)
        self.hour = calendar.component(.hour, from: ts)
        self.app = app
        self.signals = signals
        self.idleSec = idleSec
        self.backoffLevel = backoffLevel
        self.workedSec = workedSec
        self.durationSec = durationSec
    }
}
