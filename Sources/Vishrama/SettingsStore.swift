import Combine
import Foundation
import ServiceManagement
import VishramaCore

/// User-configurable settings backed by UserDefaults, observable by SwiftUI.
@MainActor
final class SettingsStore: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var shortIntervalMin: Int {
        didSet { defaults.set(shortIntervalMin, forKey: "shortIntervalMin") }
    }
    @Published var shortDurationMin: Int {
        didSet { defaults.set(shortDurationMin, forKey: "shortDurationMin") }
    }
    @Published var longDurationMin: Int {
        didSet { defaults.set(longDurationMin, forKey: "longDurationMin") }
    }
    @Published var longBreakEvery: Int {
        didSet { defaults.set(longBreakEvery, forKey: "longBreakEvery") }
    }
    @Published var idlePauseMin: Int {
        didSet { defaults.set(idlePauseMin, forKey: "idlePauseMin") }
    }
    @Published var postponeMin: Int {
        didSet { defaults.set(postponeMin, forKey: "postponeMin") }
    }
    /// Heads-up notification this many seconds before a break (0 = off).
    @Published var preBreakWarnSec: Int {
        didSet { defaults.set(preBreakWarnSec, forKey: "preBreakWarnSec") }
    }

    enum PanelSize: String, CaseIterable {
        case compact, comfortable, large

        var scale: Double {
            switch self {
            case .compact: 1.0
            case .comfortable: 1.2
            case .large: 1.4
            }
        }
    }

    /// Size of the menu bar panel.
    @Published var panelSize: PanelSize {
        didSet { defaults.set(panelSize.rawValue, forKey: "panelSize") }
    }
    @Published var shortPrompts: [String] {
        didSet { defaults.set(shortPrompts, forKey: "shortPrompts") }
    }
    @Published var longPrompts: [String] {
        didSet { defaults.set(longPrompts, forKey: "longPrompts") }
    }
    @Published var launchAtLogin: Bool {
        didSet { updateLoginItem() }
    }
    @Published var signalCameraMic: Bool {
        didSet { defaults.set(signalCameraMic, forKey: "signalCameraMic") }
    }
    @Published var signalScreenShare: Bool {
        didSet { defaults.set(signalScreenShare, forKey: "signalScreenShare") }
    }
    @Published var signalCalendar: Bool {
        didSet { defaults.set(signalCalendar, forKey: "signalCalendar") }
    }
    /// Bundle IDs treated as "presenting" whenever they run (e.g. Keynote).
    @Published var presentingApps: [String] {
        didSet { defaults.set(presentingApps, forKey: "presentingApps") }
    }
    enum DataLocationChoice: String, CaseIterable {
        case icloud, local, custom
    }

    enum AdaptivityStrength: String, CaseIterable {
        case gentle, normal, strong

        var factor: Double {
            switch self {
            case .gentle: 1.25
            case .normal: 1.5
            case .strong: 2.0
            }
        }
    }

    /// Layer-2 pattern learning on/off + how boldly it stretches intervals.
    @Published var patternLearningEnabled: Bool {
        didSet { defaults.set(patternLearningEnabled, forKey: "patternLearningEnabled") }
    }
    @Published var adaptivityStrength: AdaptivityStrength {
        didSet { defaults.set(adaptivityStrength.rawValue, forKey: "adaptivityStrength") }
    }

    /// Where settings + history live. iCloud Drive by default so the app
    /// feels identical across Macs.
    @Published var dataLocationChoice: DataLocationChoice {
        didSet {
            defaults.set(dataLocationChoice.rawValue, forKey: "dataLocationChoice")
            importMirroredSettingsIfPresent()
        }
    }
    @Published var customDataPath: String {
        didSet {
            defaults.set(customDataPath, forKey: "customDataPath")
            if dataLocationChoice == .custom { importMirroredSettingsIfPresent() }
        }
    }

    /// Resolved root folder for events/ and settings.json.
    var dataRoot: URL {
        switch dataLocationChoice {
        case .icloud:
            return DataLocation.iCloudRoot ?? DataLocation.localRoot
        case .custom:
            let trimmed = (customDataPath as NSString).expandingTildeInPath
            return trimmed.isEmpty ? DataLocation.localRoot : URL(fileURLWithPath: trimmed, isDirectory: true)
        case .local:
            return DataLocation.localRoot
        }
    }

    static let defaultShortPrompts = [
        "Look away at something distant",
        "Close your eyes and breathe",
        "Drink some water",
        "Relax your neck — slow circles",
    ]
    static let defaultLongPrompts = [
        "Stand up and take a little walk",
        "Anapana — observe your breath",
        "Stretch your upper body",
    ]

    init() {
        shortIntervalMin = defaults.object(forKey: "shortIntervalMin") as? Int ?? 25
        shortDurationMin = defaults.object(forKey: "shortDurationMin") as? Int ?? 5
        longDurationMin = defaults.object(forKey: "longDurationMin") as? Int ?? 10
        longBreakEvery = defaults.object(forKey: "longBreakEvery") as? Int ?? 2
        idlePauseMin = defaults.object(forKey: "idlePauseMin") as? Int ?? 2
        postponeMin = defaults.object(forKey: "postponeMin") as? Int ?? 5
        preBreakWarnSec = defaults.object(forKey: "preBreakWarnSec") as? Int ?? 60
        panelSize = defaults.string(forKey: "panelSize").flatMap(PanelSize.init) ?? .comfortable
        shortPrompts = defaults.stringArray(forKey: "shortPrompts") ?? Self.defaultShortPrompts
        longPrompts = defaults.stringArray(forKey: "longPrompts") ?? Self.defaultLongPrompts
        launchAtLogin = SMAppService.mainApp.status == .enabled
        signalCameraMic = defaults.object(forKey: "signalCameraMic") as? Bool ?? true
        signalScreenShare = defaults.object(forKey: "signalScreenShare") as? Bool ?? true
        signalCalendar = defaults.object(forKey: "signalCalendar") as? Bool ?? false
        presentingApps = defaults.stringArray(forKey: "presentingApps") ?? []
        // Default straight to iCloud Drive when it exists — cross-Mac out of the box.
        let storedChoice = defaults.string(forKey: "dataLocationChoice").flatMap(DataLocationChoice.init)
        dataLocationChoice = storedChoice ?? (DataLocation.iCloudAvailable ? .icloud : .local)
        customDataPath = defaults.string(forKey: "customDataPath") ?? ""
        patternLearningEnabled = defaults.object(forKey: "patternLearningEnabled") as? Bool ?? true
        adaptivityStrength = defaults.string(forKey: "adaptivityStrength")
            .flatMap(AdaptivityStrength.init) ?? .normal
        importMirroredSettingsIfPresent()
    }

    // MARK: - iCloud Drive settings mirror

    private struct Snapshot: Codable {
        var shortIntervalMin: Int
        var shortDurationMin: Int
        var longDurationMin: Int
        var longBreakEvery: Int
        var idlePauseMin: Int
        var postponeMin: Int
        // Optional so settings.json written by older versions still imports.
        var preBreakWarnSec: Int?
        var shortPrompts: [String]
        var longPrompts: [String]
        var signalCameraMic: Bool
        var signalScreenShare: Bool
        var signalCalendar: Bool
        var presentingApps: [String]
    }

    /// Mirror current settings into the data root (call after changes, debounced).
    func writeMirroredSettings() {
        let snapshot = Snapshot(
            shortIntervalMin: shortIntervalMin, shortDurationMin: shortDurationMin,
            longDurationMin: longDurationMin, longBreakEvery: longBreakEvery,
            idlePauseMin: idlePauseMin, postponeMin: postponeMin,
            preBreakWarnSec: preBreakWarnSec,
            shortPrompts: shortPrompts, longPrompts: longPrompts,
            signalCameraMic: signalCameraMic, signalScreenShare: signalScreenShare,
            signalCalendar: signalCalendar, presentingApps: presentingApps
        )
        let file = dataRoot.appendingPathComponent("settings.json")
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(snapshot).write(to: file, options: .atomic)
        } catch {
            AppDelegate.log.error("settings mirror write failed: \(error)")
        }
    }

    /// On launch / when the location changes: the mirrored file wins if present.
    private func importMirroredSettingsIfPresent() {
        let file = dataRoot.appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: file),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        shortIntervalMin = snapshot.shortIntervalMin
        shortDurationMin = snapshot.shortDurationMin
        longDurationMin = snapshot.longDurationMin
        longBreakEvery = snapshot.longBreakEvery
        idlePauseMin = snapshot.idlePauseMin
        postponeMin = snapshot.postponeMin
        if let warn = snapshot.preBreakWarnSec { preBreakWarnSec = warn }
        shortPrompts = snapshot.shortPrompts
        longPrompts = snapshot.longPrompts
        signalCameraMic = snapshot.signalCameraMic
        signalScreenShare = snapshot.signalScreenShare
        signalCalendar = snapshot.signalCalendar
        presentingApps = snapshot.presentingApps
        AppDelegate.log.notice("imported mirrored settings from data root")
    }

    /// Debug fast mode compresses minutes to seconds so cycles are testable in ~1 min.
    var configuration: BreakConfiguration {
        if AppDelegate.isFastMode {
            return BreakConfiguration(
                shortInterval: TimeInterval(shortIntervalMin),
                shortDuration: TimeInterval(max(4, shortDurationMin)),
                longDuration: TimeInterval(longDurationMin),
                longBreakEvery: longBreakEvery,
                idlePauseThreshold: 20,
                postponeDelay: TimeInterval(postponeMin),
                preBreakWarning: preBreakWarnSec > 0 ? 5 : 0
            )
        }
        return BreakConfiguration(
            shortInterval: TimeInterval(shortIntervalMin * 60),
            shortDuration: TimeInterval(shortDurationMin * 60),
            longDuration: TimeInterval(longDurationMin * 60),
            longBreakEvery: longBreakEvery,
            idlePauseThreshold: TimeInterval(idlePauseMin * 60),
            postponeDelay: TimeInterval(postponeMin * 60),
            preBreakWarning: TimeInterval(preBreakWarnSec)
        )
    }

    func prompts(for kind: BreakKind) -> [String] {
        let list = kind == .short ? shortPrompts : longPrompts
        let cleaned = list.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return cleaned.isEmpty
            ? (kind == .short ? Self.defaultShortPrompts : Self.defaultLongPrompts)
            : cleaned
    }

    private func updateLoginItem() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            AppDelegate.log.error("launch-at-login change failed: \(error)")
        }
    }
}
