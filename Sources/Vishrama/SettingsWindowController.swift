import AppKit
import SwiftUI
import VishramaCore

/// Lazily-created settings window; LSUIElement apps must activate to show it.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let store: SettingsStore
    private let learner: PatternLearner
    private let notifications: NotificationManager
    private let updates: UpdateChecker
    var activeSignals: () -> Set<VishramaCore.SignalKind> = { [] }

    init(store: SettingsStore, learner: PatternLearner, notifications: NotificationManager, updates: UpdateChecker) {
        self.store = store
        self.learner = learner
        self.notifications = notifications
        self.updates = updates
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
                rootView: SettingsView(store: store, learner: learner, notifications: notifications, updates: updates, activeSignals: signals))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        notifications.refreshStatus()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
    }
}
