import AppKit
import Combine
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
    private var settings: SettingsStore!
    private var settingsWindowController: SettingsWindowController!
    private var historyWindowController: HistoryWindowController!
    private var settingsObserver: AnyCancellable?
    let contextMonitor = ContextMonitor()
    private let notifications = NotificationManager()

    static var eventLogDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vishrama/events", isDirectory: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = SettingsStore()
        engine = ScheduleEngine(config: settings.configuration, startAt: Date())
        eventLog = EventLogStore(directory: Self.eventLogDirectory)
        settingsWindowController = SettingsWindowController(store: settings)
        settingsWindowController.activeSignals = { [weak self] in
            self?.contextMonitor.activeSignals ?? []
        }
        rebuildSignalProviders()

        // Settings edits rebuild the engine (countdown restarts with new values).
        settingsObserver = settings.objectWillChange
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.engine = ScheduleEngine(config: self.settings.configuration, startAt: Date())
                    self.rebuildSignalProviders()
                    Self.log.notice("settings changed; engine rebuilt")
                }
            }

        statusItemController = StatusItemController()
        statusItemController.onBreakNow = { [weak self] in
            guard let self else { return }
            self.apply(self.engine.breakNow(now: Date()))
        }
        statusItemController.onTogglePause = { [weak self] in
            guard let self else { return }
            self.apply(self.engine.togglePause(now: Date()))
        }
        statusItemController.onSettings = { [weak self] in
            self?.settingsWindowController.show()
        }
        statusItemController.onReset = { [weak self] in
            guard let self else { return }
            self.apply(self.engine.reset(now: Date()))
        }
        historyWindowController = HistoryWindowController(store: eventLog)
        statusItemController.onHistory = { [weak self] in
            self?.historyWindowController.show()
        }

        overlayController = OverlayController()
        overlayController.promptsProvider = { [weak self] kind in
            self?.settings.prompts(for: kind) ?? []
        }
        overlayController.onSkip = { [weak self] in
            guard let self else { return }
            self.apply(self.engine.skip(now: Date()))
        }
        overlayController.onPostpone = { [weak self] in
            guard let self else { return }
            self.apply(self.engine.postpone(now: Date()))
        }

        notifications.setup()
        notifications.onTakeBreak = { [weak self] in
            guard let self else { return }
            self.apply(self.engine.breakNow(now: Date()))
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

    private func rebuildSignalProviders() {
        var providers: [SignalProvider] = []
        if settings.signalCameraMic {
            providers.append(CameraMicSignal())
        }
        if settings.signalScreenShare {
            let signal = ScreenShareSignal()
            signal.presentingBundleIDs = { [weak self] in
                Set(self?.settings.presentingApps.map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty } ?? [])
            }
            providers.append(signal)
        }
        if settings.signalCalendar {
            providers.append(CalendarSignal())
        }
        contextMonitor.setProviders(providers)
    }

    private var lastSignals: Set<SignalKind> = []

    @objc private func timerFired() {
        let signals = contextMonitor.activeSignals
        if signals != lastSignals {
            Self.log.notice("signals changed: [\(signals.map(\.rawValue).sorted().joined(separator: ","), privacy: .public)]")
            lastSignals = signals
        }
        let context = ContextSnapshot(
            activeSignals: signals,
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
            case .notifyBreak(let kind):
                let prompt = settings.prompts(for: kind).first ?? "Take a pause"
                notifications.notifyBreakDue(kind: kind, prompt: prompt)
                Self.log.notice("flow-mode notification: \(kind.rawValue, privacy: .public)")
            case .log(let eventKind, let breakKind):
                let event = BreakEvent(
                    ts: Date(),
                    event: eventKind,
                    breakKind: breakKind,
                    app: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                    signals: contextMonitor.activeSignals.map(\.rawValue).sorted(),
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
