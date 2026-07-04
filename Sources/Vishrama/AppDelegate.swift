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
    private var statsWindowController: StatsWindowController!
    private var settingsObserver: AnyCancellable?
    let contextMonitor = ContextMonitor()
    private let notifications = NotificationManager()
    private let learner = PatternLearner()
    private var learnerTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = SettingsStore()
        engine = ScheduleEngine(config: settings.configuration, startAt: Date())
        remakeEventLog()
        // Ensure the config mirror exists from day one, not only after a change.
        settings.writeMirroredSettings()

        // Layer-2 learning recomputes every 6 hours (and whenever the event
        // log moves — see remakeEventLog, which already ran once above).
        let learnerTimer = Timer(timeInterval: 6 * 3600, target: self, selector: #selector(recomputePatterns), userInfo: nil, repeats: true)
        RunLoop.main.add(learnerTimer, forMode: .common)
        self.learnerTimer = learnerTimer
        settingsWindowController = SettingsWindowController(store: settings, learner: learner)
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
                    self.statusItemController.statusModel.panelScale = self.settings.panelSize.scale
                    if self.eventLog.directory != self.currentEventsDirectory {
                        self.remakeEventLog()
                    }
                    self.settings.writeMirroredSettings()
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
        statusItemController.onHistory = { [weak self] in
            self?.historyWindowController.show()
        }
        statusItemController.onStats = { [weak self] in
            self?.statsWindowController.show()
        }
        // Any menu-bar interaction tucks the auxiliary windows away.
        statusItemController.onStatusInteraction = { [weak self] in
            self?.settingsWindowController.close()
            self?.historyWindowController.close()
            self?.statsWindowController.close()
        }
        refreshTodayLine()
        statusItemController.statusModel.panelScale = settings.panelSize.scale

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
        overlayController.onSitWithMastishka = { [weak self] in
            self?.openMastishkaSit()
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

        // Screenshot support: VISHRAMA_DEBUG_OPEN=settings|history|popover|break
        if let open = ProcessInfo.processInfo.environment["VISHRAMA_DEBUG_OPEN"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self else { return }
                switch open {
                case "settings": self.settingsWindowController.show()
                case "history": self.historyWindowController.show()
                case "stats": self.statsWindowController.show()
                case "popover": self.statusItemController.debugShowPopover()
                case "break": self.apply(self.engine.breakNow(now: Date()))
                default: break
                }
            }
        }
    }

    /// Env var for direct launches; defaults key so fast mode also works via
    /// `defaults write dev.nishparadox.vishrama debugFast -bool true` + `open`.
    static var isFastMode: Bool {
        ProcessInfo.processInfo.environment["VISHRAMA_DEBUG_FAST"] == "1"
            || UserDefaults.standard.bool(forKey: "debugFast")
    }

    private var currentEventsDirectory: URL {
        settings.dataRoot.appendingPathComponent("events", isDirectory: true)
    }

    /// (Re)point the event log at the chosen data root, bringing local
    /// history along (copy-only; nothing is ever deleted).
    private func remakeEventLog() {
        let dir = currentEventsDirectory
        if dir.path != DataLocation.localEventsDirectory.path {
            DataLocation.copyMissingEventFiles(from: DataLocation.localEventsDirectory, to: dir)
        }
        eventLog = EventLogStore(directory: dir)
        historyWindowController = HistoryWindowController(store: eventLog)
        statsWindowController = StatsWindowController(store: eventLog)
        statsWindowController.model.focusMinutesPerPom = { [weak self] in
            self?.settings.shortIntervalMin ?? 25
        }
        // Clearing the log also resets what pattern learning knows.
        historyWindowController.onCleared = { [weak self] in
            guard let self else { return }
            self.learner.recompute(from: self.eventLog)
        }
        learner.recompute(from: eventLog)
        Self.log.notice("event log at \(dir.path, privacy: .public)")
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

    @objc private func recomputePatterns() {
        learner.recompute(from: eventLog)
    }

    // MARK: - Mastishka handshake (specs/ecosystem-protocol.md in the mastishka repo)

    /// Hand the current long break to Mastishka for a proper sit. The overlay
    /// steps aside; the break keeps counting and completes via the callback
    /// (or naturally at its scheduled end).
    private func openMastishkaSit() {
        let minutes = max(1, Int((overlayController.model.remaining / 60).rounded(.up)))
        let sitURL = URL(string: "mastishka://sit?practice=anapana&minutes=\(minutes)&autostart=1&source=vishrama")!
        overlayController.hide()
        // Protocol: senders MUST check a handler exists; else fall back to the web sit.
        if NSWorkspace.shared.urlForApplication(toOpen: sitURL) != nil {
            NSWorkspace.shared.open(sitURL)
            Self.log.notice("handed break to mastishka (\(minutes)min sit)")
        } else {
            NSWorkspace.shared.open(URL(string: "https://nishparadox.com/mastishka/")!)
            Self.log.notice("mastishka not installed; opened web sit")
        }
    }

    /// vishrama://sitCompleted — Mastishka finished a sit we initiated:
    /// the break was honored, mark it completed (not skipped).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "vishrama" && url.host == "sitCompleted" {
            apply(engine.finishBreak(now: Date()))
            Self.log.notice("mastishka sit completed; break credited")
        }
    }

    /// "6 poms · 2 skips" under the panel countdown; hidden on an empty day.
    private func refreshTodayLine() {
        let now = Date()
        let events = (try? eventLog.events(since: Calendar.current.startOfDay(for: now))) ?? []
        let today = Stats.today(events: events, now: now)
        guard !today.isEmpty else {
            statusItemController.statusModel.todayLine = nil
            return
        }
        var parts: [String] = []
        if today.poms > 0 { parts.append("\(today.poms) pom\(today.poms == 1 ? "" : "s")") }
        if today.standups > 0 { parts.append("\(today.standups) standup\(today.standups == 1 ? "" : "s")") }
        if today.skipped > 0 { parts.append("\(today.skipped) skip\(today.skipped == 1 ? "" : "s")") }
        if today.naturalBreaks > 0 { parts.append("\(today.naturalBreaks) natural") }
        statusItemController.statusModel.todayLine = parts.joined(separator: " · ")
    }

    @objc private func timerFired() {
        let signals = contextMonitor.activeSignals
        if signals != lastSignals {
            Self.log.notice("signals changed: [\(signals.map(\.rawValue).sorted().joined(separator: ","), privacy: .public)]")
            lastSignals = signals
        }
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        engine.intervalScale = learner.scale(
            now: Date(),
            app: frontmost,
            enabled: settings.patternLearningEnabled,
            strength: settings.adaptivityStrength.factor
        )
        let context = ContextSnapshot(
            activeSignals: signals,
            idleSeconds: IdleMonitor.systemIdleSeconds(),
            frontmostApp: frontmost
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
            case .notifyPreBreak(let kind, let lead):
                notifications.notifyPreBreak(kind: kind, lead: lead)
                Self.log.notice("pre-break heads-up: \(kind.rawValue, privacy: .public) in \(Int(lead))s")
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
                refreshTodayLine()
            }
        }
    }
}
