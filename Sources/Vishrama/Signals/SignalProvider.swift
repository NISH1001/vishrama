import Foundation
import VishramaCore

/// A pluggable context detector. Providers poll cheaply and cache their state;
/// `isActive` must be safe to read every tick.
@MainActor
protocol SignalProvider: AnyObject {
    var kind: SignalKind { get }
    var isActive: Bool { get }
    func start()
    func stop()
}

/// Aggregates enabled providers into the engine's ContextSnapshot signal set.
@MainActor
final class ContextMonitor {
    private(set) var providers: [SignalProvider] = []

    func setProviders(_ providers: [SignalProvider]) {
        self.providers.forEach { $0.stop() }
        self.providers = providers
        providers.forEach { $0.start() }
    }

    var activeSignals: Set<SignalKind> {
        Set(providers.filter(\.isActive).map(\.kind))
    }
}
