import AppKit
import SwiftUI
import VishramaCore

/// Lazily-created settings window; LSUIElement apps must activate to show it.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let store: SettingsStore
    private let learner: PatternLearner
    var activeSignals: () -> Set<VishramaCore.SignalKind> = { [] }

    init(store: SettingsStore, learner: PatternLearner) {
        self.store = store
        self.learner = learner
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Vishrama Settings"
            let signals = activeSignals
            window.contentViewController = NSHostingController(
                rootView: SettingsView(store: store, learner: learner, activeSignals: signals))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
