import AppKit
import SwiftUI
import VishramaCore

/// Owns the menu bar presence: a single status item reading "वि ⏸ 24:32".
/// Clicking the pause/play glyph toggles pause; clicking anywhere else
/// (or right-clicking) opens the menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var pauseItem: NSMenuItem?
    let statusModel = StatusModel()
    private lazy var popover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .transient
        // Pin to dark so the panel reads the same on every macOS material
        // (Tahoe's Liquid Glass renders the default far too light for our text).
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = NSHostingController(rootView: PopoverView(
            model: statusModel,
            onTogglePause: { [weak self] in self?.onTogglePause?() },
            onBreakNow: { [weak self] in self?.popover.performClose(nil); self?.onBreakNow?() },
            onReset: { [weak self] in self?.onReset?() },
            onHistory: { [weak self] in self?.popover.performClose(nil); self?.onHistory?() },
            onSettings: { [weak self] in self?.popover.performClose(nil); self?.onSettings?() }
        ))
        return popover
    }()

    var onBreakNow: (() -> Void)?
    var onTogglePause: (() -> Void)?
    var onReset: (() -> Void)?
    var onSettings: (() -> Void)?
    var onHistory: (() -> Void)?
    /// Fired on any click of the status item — lets the app tuck auxiliary
    /// windows (Settings/History) away, keeping the menu-bar feel transient.
    var onStatusInteraction: (() -> Void)?

    private var paused = false
    /// Horizontal range of the pause/play glyph inside the title, for hit-testing.
    private var glyphRange: ClosedRange<CGFloat> = 0...0
    /// Accessory apps don't get transient-popover dismissal for free; watch
    /// for clicks in other apps and close ourselves.
    private var outsideClickMonitor: Any?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        buildMenu()
        menu.delegate = self

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Click 🌻 to pause/resume · click elsewhere for menu"
        }
        render(time: "--:--")
    }

    func update(_ status: StatusInfo) {
        statusModel.status = status
        switch status {
        case .working(let remaining):
            paused = false
            render(time: Self.format(remaining))
        case .onBreak(_, let remaining):
            paused = false
            render(time: Self.format(remaining), badge: "☕")
        case .idlePaused(let remaining):
            paused = false
            // Dimmed time = auto-paused because you're away.
            render(time: Self.format(remaining), dimmed: true)
        case .manualPaused(let remaining):
            paused = true
            render(time: Self.format(remaining), dimmed: true)
        case .suppressed(let overdue):
            paused = false
            // Break is owed but held back by a meeting/share.
            render(time: "+\(Self.format(overdue))", badge: "⏳")
        }
        pauseItem?.title = paused ? "Resume" : "Pause"
    }

    // MARK: - Rendering

    private static let textFont = NSFont.monospacedDigitSystemFont(
        ofSize: 14, weight: .medium)
    private static let glyphFont = NSFont.systemFont(
        ofSize: 13, weight: .medium)

    /// Compose "🌻 <badge> <time>" — the flower itself is the pause/play button
    /// (wilts to 🥀 while paused). Remember where it sits for hit-testing.
    private func render(time: String, badge: String? = nil, dimmed: Bool = false) {
        let flower = paused ? "🥀" : "🌻"
        let timeColor: NSColor = dimmed ? .tertiaryLabelColor : .labelColor
        let head = NSMutableAttributedString(
            string: flower, attributes: [.font: Self.glyphFont])
        let flowerWidth = head.size().width
        let rest = badge.map { "  \($0) \(time)" } ?? "  \(time)"
        head.append(NSAttributedString(
            string: rest,
            attributes: [.font: Self.textFont, .foregroundColor: timeColor]))

        statusItem.button?.attributedTitle = head
        // Title is centered in the button; account for that when clicks arrive.
        if let button = statusItem.button {
            let inset = max(0, (button.bounds.width - head.size().width) / 2)
            // Generous padding so the tap target isn't pixel-perfect.
            glyphRange = (inset - 6)...(inset + flowerWidth + 6)
        }
    }

    private static func format(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: - Clicks

    @objc private func statusItemClicked() {
        guard let button = statusItem.button, let event = NSApp.currentEvent else { return }
        onStatusInteraction?()
        if event.type == .rightMouseUp {
            showMenu()
            return
        }
        let x = button.convert(event.locationInWindow, from: nil).x
        if glyphRange.contains(x) {
            onTogglePause?()
        } else if popover.isShown {
            closePopover()
        } else {
            // The panel springs from the icon — no disjointed windows.
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                Task { @MainActor in self?.closePopover() }
            }
        }
    }

    /// Screenshot support: open the panel without a click.
    func debugShowPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func closePopover() {
        popover.performClose(nil)
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
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

        let reset = NSMenuItem(title: "Reset Timer", action: #selector(resetClicked), keyEquivalent: "r")
        reset.target = self
        menu.addItem(reset)

        menu.addItem(.separator())
        let history = NSMenuItem(title: "History", action: #selector(historyClicked), keyEquivalent: "h")
        history.target = self
        menu.addItem(history)

        let settings = NSMenuItem(title: "Settings…", action: #selector(settingsClicked), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

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

    @objc private func settingsClicked() {
        onSettings?()
    }

    @objc private func resetClicked() {
        onReset?()
    }

    @objc private func historyClicked() {
        onHistory?()
    }
}
