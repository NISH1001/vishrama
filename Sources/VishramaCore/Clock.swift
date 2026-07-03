import Foundation

/// Injectable time source so the schedule engine is fully testable.
public protocol NowProvider: Sendable {
    var now: Date { get }
}

public struct SystemClock: NowProvider {
    public init() {}
    public var now: Date { Date() }
}
