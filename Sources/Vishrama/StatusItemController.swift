import AppKit
import VishramaCore

/// Owns the menu bar presence: countdown title + control menu.
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    /// Separate one-click pause/play button sitting next to the timer.
    private let pauseButtonItem: NSStatusItem
    private var pauseItem: NSMenuItem?
    var onBreakNow: (() -> Void)?
    var onTogglePause: (() -> Void)?

    init() {
        // Created first so it sits to the right of the pause button.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        pauseButtonItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        statusItem.button?.attributedTitle = Self.title("वि --:--")
        statusItem.menu = buildMenu()

        if let button = pauseButtonItem.button {
            button.image = Self.pauseImage(paused: false)
            button.action = #selector(togglePauseClicked)
            button.target = self
            button.toolTip = "Pause/resume break reminders"
        }
    }

    private static func pauseImage(paused: Bool) -> NSImage? {
        let image = NSImage(
            systemSymbolName: paused ? "play.fill" : "pause.fill",
            accessibilityDescription: paused ? "Resume breaks" : "Pause breaks"
        )
        image?.isTemplate = true
        return image
    }

    func update(_ status: StatusInfo) {
        let paused: Bool
        switch status {
        case .working(let remaining):
            setTitle("वि \(Self.format(remaining))")
            paused = false
        case .onBreak(_, let remaining):
            setTitle("☕ \(Self.format(remaining))")
            paused = false
        case .idlePaused(let remaining):
            setTitle("⏸ \(Self.format(remaining))")
            paused = false
        case .manualPaused(let remaining):
            setTitle("वि \(Self.format(remaining))")
            paused = true
        }
        pauseItem?.title = paused ? "Resume" : "Pause"
        pauseButtonItem.button?.image = Self.pauseImage(paused: paused)
    }

    private func setTitle(_ text: String) {
        statusItem.button?.attributedTitle = Self.title(text)
    }

    /// Monospaced digits so the title width doesn't jitter as seconds tick.
    private static func title(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [.font: NSFont.monospacedDigitSystemFont(
                ofSize: NSFont.systemFontSize(for: .small), weight: .regular)]
        )
    }

    private static func format(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

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
        return menu
    }

    @objc private func breakNowClicked() {
        onBreakNow?()
    }

    @objc private func togglePauseClicked() {
        onTogglePause?()
    }
}
