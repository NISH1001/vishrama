import SwiftUI
import VishramaCore

@MainActor
final class HistoryModel: ObservableObject {
    @Published var events: [BreakEvent] = []
    private let store: EventLogStore

    init(store: EventLogStore) {
        self.store = store
    }

    func reload() {
        let since = Date().addingTimeInterval(-7 * 86400)
        events = ((try? store.events(since: since)) ?? []).reversed()
    }
}

/// Human-readable timeline of the last week of break events.
struct HistoryView: View {
    @ObservedObject var model: HistoryModel

    var body: some View {
        Group {
            if model.events.isEmpty {
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
                            ForEach(Array(group.events.enumerated()), id: \.offset) { _, event in
                                row(event)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 420, height: 480)
    }

    private var groupedByDay: [(day: String, events: [BreakEvent])] {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        var seen: [String] = []
        var groups: [String: [BreakEvent]] = [:]
        for event in model.events {
            let day = formatter.string(from: event.ts)
            if groups[day] == nil { seen.append(day) }
            groups[day, default: []].append(event)
        }
        return seen.map { (day: $0, events: groups[$0] ?? []) }
    }

    private func row(_ event: BreakEvent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
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
            Text(event.ts, style: .time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
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
        }
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
