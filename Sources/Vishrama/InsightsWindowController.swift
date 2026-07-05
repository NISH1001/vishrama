import AppKit
import SwiftUI
import VishramaCore

/// The single window for Stats + History. Both menu items open it, selecting
/// the matching tab.
@MainActor
final class InsightsWindowController {
    private var window: NSWindow?
    let stats: StatsModel
    let history: HistoryModel

    var onCleared: (() -> Void)? {
        get { history.onCleared }
        set { history.onCleared = newValue }
    }

    init(store: EventLogStore) {
        stats = StatsModel(store: store)
        history = HistoryModel(store: store)
    }

    func show(tab: InsightsTab) {
        if window == nil {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Vishrama Insights"
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        stats.reload()
        history.reload()
        window?.contentViewController = NSHostingController(
            rootView: InsightsView(stats: stats, history: history, initialTab: tab))
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
    }
}
