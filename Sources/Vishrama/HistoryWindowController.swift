import AppKit
import SwiftUI
import VishramaCore

@MainActor
final class HistoryWindowController {
    private var window: NSWindow?
    private let model: HistoryModel

    init(store: EventLogStore) {
        model = HistoryModel(store: store)
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Vishrama History"
            window.contentViewController = NSHostingController(rootView: HistoryView(model: model))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        model.reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
