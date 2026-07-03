import CoreGraphics
import Foundation

enum IdleMonitor {
    /// Seconds since the user last touched keyboard/mouse/trackpad.
    static func systemIdleSeconds() -> TimeInterval {
        // kCGAnyInputEventType (~0) isn't imported into Swift; the raw-value
        // round-trip is the standard way to get it.
        let anyInput = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }
}
