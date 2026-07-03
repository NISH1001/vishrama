import AppKit
import SwiftUI
import VishramaCore

/// Borderless windows refuse key status by default; the overlay needs it for buttons/Esc.
private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Full-screen break overlay, one window per display.
@MainActor
final class OverlayController {
    let model = BreakViewModel()
    var onSkip: (() -> Void)?
    var onPostpone: (() -> Void)?

    private var windows: [OverlayWindow] = []
    private var keyMonitor: Any?

    private static let shortPrompts = [
        "Look away at something distant",
        "Close your eyes and breathe",
        "Drink some water",
        "Relax your neck — slow circles",
    ]
    private static let longPrompts = [
        "Stand up and take a little walk",
        "Anapana — observe your breath",
        "Stretch your upper body",
    ]
    private var promptIndex = 0

    func show(kind: BreakKind, remaining: TimeInterval) {
        guard windows.isEmpty else { return }
        model.kind = kind
        model.remaining = remaining
        let prompts = kind == .short ? Self.shortPrompts : Self.longPrompts
        model.prompt = prompts[promptIndex % prompts.count]
        promptIndex += 1

        for screen in NSScreen.screens {
            let window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            // Never visible to screen capture / sharing, even if detection misses.
            window.sharingType = .none
            window.isOpaque = false
            window.backgroundColor = .clear
            window.alphaValue = 0
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: BreakView(
                model: model,
                onSkip: { [weak self] in self?.onSkip?() },
                onPostpone: { [weak self] in self?.onPostpone?() }
            ))
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.5
            for window in windows { window.animator().alphaValue = 1 }
        }

        // Esc postpones — the overlay is never a cage.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.onPostpone?()
                return nil
            }
            return event
        }
    }

    func updateRemaining(_ remaining: TimeInterval) {
        model.remaining = remaining
    }

    func hide() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        let closing = windows
        windows = []
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            for window in closing { window.animator().alphaValue = 0 }
        }, completionHandler: {
            Task { @MainActor in
                for window in closing { window.orderOut(nil) }
            }
        })
    }
}
