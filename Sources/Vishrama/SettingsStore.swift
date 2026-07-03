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
    @Published var shortPrompts: [String] {
        didSet { defaults.set(shortPrompts, forKey: "shortPrompts") }
    }
    @Published var longPrompts: [String] {
        didSet { defaults.set(longPrompts, forKey: "longPrompts") }
    }
    @Published var launchAtLogin: Bool {
        didSet { updateLoginItem() }
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
        shortPrompts = defaults.stringArray(forKey: "shortPrompts") ?? Self.defaultShortPrompts
        longPrompts = defaults.stringArray(forKey: "longPrompts") ?? Self.defaultLongPrompts
        launchAtLogin = SMAppService.mainApp.status == .enabled
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
                postponeDelay: TimeInterval(postponeMin)
            )
        }
        return BreakConfiguration(
            shortInterval: TimeInterval(shortIntervalMin * 60),
            shortDuration: TimeInterval(shortDurationMin * 60),
            longDuration: TimeInterval(longDurationMin * 60),
            longBreakEvery: longBreakEvery,
            idlePauseThreshold: TimeInterval(idlePauseMin * 60),
            postponeDelay: TimeInterval(postponeMin * 60)
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
