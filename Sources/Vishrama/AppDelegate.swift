import AppKit
import OSLog
import VishramaCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let log = Logger(subsystem: "dev.nishparadox.vishrama", category: "app")

    private var engine: ScheduleEngine!
    private var statusItemController: StatusItemController!
    private var overlayController: OverlayController!
    private var timer: Timer?
    private var eventLog: EventLogStore!

    static var eventLogDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vishrama/events", isDirectory: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config = Self.makeConfiguration()
        engine = ScheduleEngine(config: config, startAt: Date())
        eventLog = EventLogStore(directory: Self.eventLogDirectory)

        statusItemController = StatusItemController()
        statusItemController.onBreakNow = { [weak self] in
            guard let self else { return }
            self.apply(self.engine.breakNow(now: Date()))
        }
        statusItemController.onTogglePause = { [weak self] in
            guard let self else { return }
            self.apply(self.engine.togglePause(now: Date()))
        }

        overlayController = OverlayController()
        overlayController.onSkip = { [weak self] in
            guard let self else { return }
            self.apply(self.engine.skip(now: Date()))
        }
        overlayController.onPostpone = { [weak self] in
            guard let self else { return }
            self.apply(self.engine.postpone(now: Date()))
        }

        // .common mode so the countdown keeps ticking while menus are open.
        let timer = Timer(timeInterval: 1.0, target: self, selector: #selector(timerFired), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        Self.log.notice("vishrama launched (fastMode: \(Self.isFastMode))")
    }

    /// Env var for direct launches; defaults key so fast mode also works via
    /// `defaults write dev.nishparadox.vishrama debugFast -bool true` + `open`.
    static var isFastMode: Bool {
        ProcessInfo.processInfo.environment["VISHRAMA_DEBUG_FAST"] == "1"
            || UserDefaults.standard.bool(forKey: "debugFast")
    }

    /// Fast mode compresses minutes to seconds so a full break cycle is observable in ~1 minute.
    private static func makeConfiguration() -> BreakConfiguration {
        if isFastMode {
            return BreakConfiguration(
                shortInterval: 25,
                shortDuration: 6,
                longDuration: 10,
                longBreakEvery: 2,
                idlePauseThreshold: 20,
                postponeDelay: 8
            )
        }
        return BreakConfiguration()
    }

    @objc private func timerFired() {
        let context = ContextSnapshot(
            activeSignals: [],
            idleSeconds: IdleMonitor.systemIdleSeconds(),
            frontmostApp: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
        apply(engine.tick(now: Date(), context: context))
    }

    private func apply(_ effects: [Effect]) {
        for effect in effects {
            switch effect {
            case .updateStatus(let status):
                statusItemController.update(status)
                if case .onBreak(_, let remaining) = status {
                    overlayController.updateRemaining(remaining)
                }
            case .showOverlay(let kind):
                overlayController.show(kind: kind, remaining: engine.config.duration(of: kind))
                Self.log.notice("overlay shown: \(kind.rawValue)")
            case .hideOverlay:
                overlayController.hide()
                Self.log.notice("overlay hidden")
            case .log(let eventKind, let breakKind):
                let event = BreakEvent(
                    ts: Date(),
                    event: eventKind,
                    breakKind: breakKind,
                    app: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                    signals: [],
                    idleSec: IdleMonitor.systemIdleSeconds()
                )
                do {
                    try eventLog.append(event)
                } catch {
                    Self.log.error("event log append failed: \(error)")
                }
            }
        }
    }
}
