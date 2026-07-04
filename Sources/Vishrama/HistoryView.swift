import SwiftUI
import VishramaCore

@MainActor
final class HistoryModel: ObservableObject {
    @Published var rows: [TaggedEvent] = []
    @Published var devices: [String] = []
    /// nil = all devices (the default view); a slug = that device only.
    @Published var deviceFilter: String? {
        didSet { applyFilter() }
    }
    private var allTagged: [TaggedEvent] = []
    private let store: EventLogStore
    /// Invoked after a clear so the app can refresh dependents (pattern learner).
    var onCleared: (() -> Void)?

    init(store: EventLogStore) {
        self.store = store
    }

    func reload() {
        let since = Date().addingTimeInterval(-7 * 86400)
        allTagged = (try? store.taggedEvents(since: since)) ?? []
        devices = (try? store.knownDevices()) ?? []
        applyFilter()
    }

    private func applyFilter() {
        rows = allTagged
            .filter { deviceFilter == nil || $0.device == deviceFilter }
            .reversed()
    }

    /// Clears what the active filter shows: everything, or one device's files.
    func clear() {
        do {
            try store.clear(device: deviceFilter)
        } catch {
            AppDelegate.log.error("clearing event log failed: \(error)")
        }
        deviceFilter = nil
        reload()
        onCleared?()
    }

    var clearScopeLabel: String {
        deviceFilter.map { DeviceIdentity.label(for: $0) } ?? "all devices"
    }
}

/// Human-readable timeline of the last week of break events.
struct HistoryView: View {
    @ObservedObject var model: HistoryModel
    @State private var confirmingClear = false

    var body: some View {
        content
            .safeAreaInset(edge: .bottom) {
                HStack {
                    if !model.devices.isEmpty {
                        Picker("Device", selection: $model.deviceFilter) {
                            Text("All devices").tag(String?.none)
                            ForEach(model.devices, id: \.self) { slug in
                                Text(DeviceIdentity.label(for: slug)).tag(String?.some(slug))
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(maxWidth: 180)
                    }
                    Spacer()
                    Button("Clear Log…", role: .destructive) { confirmingClear = true }
                        .disabled(model.rows.isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .confirmationDialog("Clear break history from \(model.clearScopeLabel)?", isPresented: $confirmingClear) {
                Button("Clear \(model.clearScopeLabel)", role: .destructive) { model.clear() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(model.deviceFilter == nil
                     ? "Permanently deletes the entire event log — the timeline AND everything pattern learning has observed. Settings are not affected. This cannot be undone."
                     : "Permanently deletes this device's events only; other devices' history and settings are untouched. Pattern learning recomputes from what remains. This cannot be undone.")
            }
    }

    private var content: some View {
        Group {
            if model.rows.isEmpty {
                VStack(spacing: 8) {
                    Text("🌻")
                        .font(.system(size: 40))
                    Text("No events yet — history fills in as breaks happen.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groupedByDay, id: \.day) { group in
                        Section(group.day) {
                            ForEach(Array(group.rows.enumerated()), id: \.offset) { _, tagged in
                                row(tagged)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 420, height: 480)
    }

    private var groupedByDay: [(day: String, rows: [TaggedEvent])] {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        var seen: [String] = []
        var groups: [String: [TaggedEvent]] = [:]
        for tagged in model.rows {
            let day = formatter.string(from: tagged.event.ts)
            if groups[day] == nil { seen.append(day) }
            groups[day, default: []].append(tagged)
        }
        return seen.map { (day: $0, rows: groups[$0] ?? []) }
    }

    private func row(_ tagged: TaggedEvent) -> some View {
        let event = tagged.event
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Self.icon(for: event))
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.title(for: event))
                if let detail = Self.detail(for: event) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(event.ts, style: .time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                // Which device, but only in the merged view (redundant otherwise).
                if model.deviceFilter == nil {
                    Text("(\(tagged.device ?? "earlier"))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    static func icon(for event: BreakEvent) -> String {
        switch event.event {
        case .fired: "☕"
        case .completed: "✅"
        case .skipped: "⏭"
        case .postponed: "⏰"
        case .suppressedStart: "🎥"
        case .suppressedEnd: "🎬"
        case .flowEnter: "🌊"
        case .notified: "🔔"
        case .naturalBreak: "🍃"
        case .paused: "🥀"
        case .resumed: "🌻"
        case .slept: "💤"
        }
    }

    static func sleepDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    static func title(for event: BreakEvent) -> String {
        let kind = event.breakKind == .long ? "standup break" : "eye break"
        switch event.event {
        case .fired: return "Break appeared (\(kind))"
        case .completed: return "Completed \(kind)"
        case .skipped: return "Skipped \(kind)"
        case .postponed: return "Postponed \(kind)"
        case .suppressedStart: return "Break held — busy context detected"
        case .suppressedEnd: return "Context cleared — break shown"
        case .flowEnter: return "Flow mode — staying quiet for a while"
        case .notified: return "Gentle reminder sent (\(kind))"
        case .naturalBreak: return "Natural break — you were away"
        case .paused: return "Paused"
        case .resumed: return "Resumed"
        case .slept:
            let span = event.durationSec.map(Self.sleepDuration) ?? "a while"
            return "Slept — \(span)"
        }
    }

    static func detail(for event: BreakEvent) -> String? {
        var parts: [String] = []
        if let app = event.app, !app.isEmpty, event.event == .skipped || event.event == .postponed {
            parts.append("while in \(app.components(separatedBy: ".").last ?? app)")
        }
        if !event.signals.isEmpty {
            parts.append("signals: \(event.signals.joined(separator: ", "))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
