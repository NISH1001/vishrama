import AppKit

/// Owns the menu bar presence: countdown title + control menu.
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.attributedTitle = Self.title("वि 25:00")
        }
        statusItem.menu = buildMenu()
    }

    /// Monospaced digits so the title width doesn't jitter as seconds tick.
    static func title(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [.font: NSFont.monospacedDigitSystemFont(
                ofSize: NSFont.systemFontSize(for: .small), weight: .regular)]
        )
    }

    func setTitle(_ text: String) {
        statusItem.button?.attributedTitle = Self.title(text)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let quit = NSMenuItem(
            title: "Quit Vishrama",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)
        return menu
    }
}
