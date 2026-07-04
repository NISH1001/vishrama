import AppKit
import SwiftUI
import VishramaCore

@MainActor
final class StatsWindowController {
    private var window: NSWindow?
    let model: StatsModel

    init(store: EventLogStore) {
        model = StatsModel(store: store)
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Vishrama Stats"
            window.contentViewController = NSHostingController(rootView: StatsView(model: model))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        model.reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
    }
}
