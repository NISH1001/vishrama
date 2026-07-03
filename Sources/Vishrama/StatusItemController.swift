import AppKit
import VishramaCore

/// Owns the menu bar presence: a single status item reading "वि ⏸ 24:32".
/// Clicking the pause/play glyph toggles pause; clicking anywhere else
/// (or right-clicking) opens the menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var pauseItem: NSMenuItem?

    var onBreakNow: (() -> Void)?
    var onTogglePause: (() -> Void)?

    private var paused = false
    /// Horizontal range of the pause/play glyph inside the title, for hit-testing.
    private var glyphRange: ClosedRange<CGFloat> = 0...0

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        buildMenu()
        menu.delegate = self

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Click ⏸/▶ to pause · click elsewhere for menu"
        }
        render(time: "--:--")
    }

    func update(_ status: StatusInfo) {
        switch status {
        case .working(let remaining):
            paused = false
            render(time: Self.format(remaining))
        case .onBreak(_, let remaining):
            paused = false
            render(time: Self.format(remaining), prefix: "☕")
        case .idlePaused(let remaining):
            paused = false
            render(time: Self.format(remaining), prefix: "⏸")
        case .manualPaused(let remaining):
            paused = true
            render(time: Self.format(remaining))
        }
        pauseItem?.title = paused ? "Resume" : "Pause"
    }

    // MARK: - Rendering

    private static let textFont = NSFont.monospacedDigitSystemFont(
        ofSize: 14, weight: .medium)
    private static let glyphFont = NSFont.systemFont(
        ofSize: 13, weight: .medium)

    /// Compose "वि <glyph> <time>" and remember where the glyph sits for hit-testing.
    private func render(time: String, prefix: String = "वि") {
        let glyph = paused ? "▶" : "⏸"
        let head = NSMutableAttributedString(
            string: "\(prefix)  ", attributes: [.font: Self.textFont])
        let glyphPart = NSAttributedString(
            string: glyph,
            attributes: [.font: Self.glyphFont, .baselineOffset: 0.5])
        let tail = NSAttributedString(string: "  \(time)", attributes: [.font: Self.textFont])

        let start = head.size().width
        head.append(glyphPart)
        let end = head.size().width
        head.append(tail)

        statusItem.button?.attributedTitle = head
        // Title is centered in the button; account for that when clicks arrive.
        if let button = statusItem.button {
            let inset = max(0, (button.bounds.width - head.size().width) / 2)
            // Generous padding so the tap target isn't pixel-perfect.
            glyphRange = (inset + start - 5)...(inset + end + 5)
        }
    }

    private static func format(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: - Clicks

    @objc private func statusItemClicked() {
        guard let button = statusItem.button, let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showMenu()
            return
        }
        let x = button.convert(event.locationInWindow, from: nil).x
        if glyphRange.contains(x) {
            onTogglePause?()
        } else {
            showMenu()
        }
    }

    /// Assign the menu only while showing it, so plain clicks keep reaching our action.
    private func showMenu() {
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    nonisolated func menuDidClose(_ menu: NSMenu) {
        Task { @MainActor in
            self.statusItem.menu = nil
        }
    }

    private func buildMenu() {
        let pause = NSMenuItem(title: "Pause", action: #selector(togglePauseClicked), keyEquivalent: "p")
        pause.target = self
        menu.addItem(pause)
        pauseItem = pause

        let breakNow = NSMenuItem(title: "Take a Break Now", action: #selector(breakNowClicked), keyEquivalent: "b")
        breakNow.target = self
        menu.addItem(breakNow)

        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit Vishrama",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)
    }

    @objc private func breakNowClicked() {
        onBreakNow?()
    }

    @objc private func togglePauseClicked() {
        onTogglePause?()
    }
}
