import AppKit
import Foundation
import VishramaCore

/// Detects screen sharing / presenting. There is no public "is my screen
/// being captured" API, so this is heuristic: known helper processes
/// (Zoom spawns CptHost while sharing) plus a user-editable app list.
/// The overlay is additionally excluded from capture via sharingType = .none.
@MainActor
final class ScreenShareSignal: SignalProvider {
    let kind = SignalKind.screenShare
    private(set) var isActive = false
    private var timer: Timer?

    /// Process names that mean "actively sharing the screen".
    static let defaultHelperNames: Set<String> = ["CptHost", "caphost"]

    /// Bundle IDs the user marks as "treat as presenting whenever running".
    var presentingBundleIDs: () -> Set<String> = { [] }

    func start() {
        poll()
        let timer = Timer(timeInterval: 5, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isActive = false
    }

    private func poll() {
        let apps = NSWorkspace.shared.runningApplications
        let presenting = presentingBundleIDs()
        isActive = apps.contains { app in
            if let name = app.localizedName, Self.defaultHelperNames.contains(name) { return true }
            if let bundleID = app.bundleIdentifier, presenting.contains(bundleID) { return true }
            return false
        }
    }
}
