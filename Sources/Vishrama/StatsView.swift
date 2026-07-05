import Charts
import SwiftUI
import VishramaCore

/// Chart palette — validated for the dark surface (lightness band, chroma
/// floor, CVD separation, contrast) with scripts/validate_palette.js.
private enum ChartColor {
    static let taken = Color(red: 0xBE / 255.0, green: 0x85 / 255.0, blue: 0x1F / 255.0)
    static let skipped = Color(red: 0x62 / 255.0, green: 0x72 / 255.0, blue: 0xC4 / 255.0)
}

@MainActor
final class StatsModel: ObservableObject {
    @Published var today = TodaySummary()
    @Published var daily: [DailyStat] = []
    @Published var heat: [HeatCell] = []
    @Published var devices: [String] = []
    /// nil = all devices (default); a slug = that device only. Display lens
    /// only — pattern learning always consumes the unfiltered union.
    @Published var deviceFilter: String? {
        didSet { recompute() }
    }
    /// For the ~focus estimate (completed poms × configured interval).
    var focusMinutesPerPom: () -> Int = { 25 }

    private var allTagged: [TaggedEvent] = []
    private let store: EventLogStore

    init(store: EventLogStore) {
        self.store = store
    }

    func reload() {
        let now = Date()
        allTagged = (try? store.taggedEvents(since: now.addingTimeInterval(-60 * 86400))) ?? []
        devices = (try? store.knownDevices()) ?? []
        recompute()
    }

    private func recompute() {
        let now = Date()
        let events = allTagged
            .filter { deviceFilter == nil || $0.device == deviceFilter }
            .map(\.event)
        today = Stats.today(events: events, now: now)
        daily = Stats.daily(events: events, days: 14, now: now)
        heat = Stats.heatmap(events: events)
    }

    var focusEstimate: String {
        let minutes = today.poms * focusMinutesPerPom()
        guard minutes > 0 else { return "—" }
        return minutes < 60 ? "~\(minutes)m" : String(format: "~%.1fh", Double(minutes) / 60)
    }
}

struct StatsView: View {
    @ObservedObject var model: StatsModel
    @State private var heatMetric = HeatMetric.completed

    enum HeatMetric: String, CaseIterable {
        case completed = "Breaks taken"
        case skips = "Skips"
    }

    // Content only — the window chrome and the shared device filter live in
    // InsightsView, which hosts this alongside History.
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            tiles
            barSection
            heatSection
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Today tiles

    private var tiles: some View {
        HStack(spacing: 10) {
            tile(value: "\(model.today.poms)", label: "poms today")
            tile(value: "\(model.today.standups)", label: "standups")
            tile(value: "\(model.today.skipped)", label: "skipped")
            tile(value: model.focusEstimate, label: "focus (est.)")
        }
    }

    private func tile(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 24, weight: .light).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.05)))
    }

    // MARK: 14-day bars

    private var barSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last 14 days")
                .font(.caption)
                .foregroundStyle(.secondary)
            Chart(model.daily) { day in
                BarMark(
                    x: .value("Day", day.day, unit: .day),
                    y: .value("Breaks", day.completed)
                )
                .foregroundStyle(by: .value("Kind", "Taken"))
                .cornerRadius(2)
                BarMark(
                    x: .value("Day", day.day, unit: .day),
                    y: .value("Breaks", day.skipped)
                )
                .foregroundStyle(by: .value("Kind", "Skipped"))
                .cornerRadius(2)
            }
            .chartForegroundStyleScale(["Taken": ChartColor.taken, "Skipped": ChartColor.skipped])
            // Auto legend (derived from the style scale) above the plot so it
            // never crowds the date axis; right-aligned to echo the heatmap's
            // control below and stay clear of the left-aligned title.
            .chartLegend(position: .top, alignment: .trailing, spacing: 8)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.day(), centered: true)
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(.white.opacity(0.06))
                    AxisValueLabel().font(.caption2)
                }
            }
            .frame(height: 140)
        }
    }

    // MARK: Hour × weekday heatmap

    private static let weekdayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private var heatSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Your rhythm (last 60 days)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $heatMetric) {
                    ForEach(HeatMetric.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 200)
            }
            Chart(model.heat) { cell in
                RectangleMark(
                    x: .value("Hour", String(cell.hour)),
                    y: .value("Day", Self.weekdayLabel(dow: cell.dow)),
                    width: .ratio(0.86),
                    // Ratio, not fixed: a cell can never overflow its row into
                    // the axis below — the bug that dogged the bottom (Sun) row.
                    height: .ratio(0.72)
                )
                .foregroundStyle(cellColor(for: cell))
                .cornerRadius(2)
            }
            .chartYScale(domain: Self.weekdayLabels)
            .chartXScale(domain: (0...23).map(String.init))
            .chartXAxis {
                // Skip the 0-hour tick: at the plot's left edge its label clips.
                // 6am/noon/6pm sit inland and read cleanly; midnight is the edge.
                AxisMarks(values: ["6", "12", "18"]) { value in
                    AxisValueLabel {
                        if let hour = value.as(String.self) {
                            Text(Self.hourLabel(hour)).font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { _ in AxisValueLabel().font(.caption2) }
            }
            // Tall enough for 7 weekday rows so cells never overlap the hour axis.
            .frame(height: 200)
        }
    }

    private static func weekdayLabel(dow: Int) -> String {
        // Calendar dow: 1 = Sunday … 7 = Saturday.
        ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][dow]
    }

    /// "0"→"12am", "6"→"6am", "12"→"noon", "18"→"6pm".
    private static func hourLabel(_ hour: String) -> String {
        switch hour {
        case "0": "12am"
        case "12": "noon"
        case let h where (Int(h) ?? 0) < 12: "\(h)am"
        default: "\((Int(hour) ?? 0) - 12)pm"
        }
    }

    /// Single-hue sequential ramp: intensity scales with the chosen metric.
    private func cellColor(for cell: HeatCell) -> Color {
        let value = heatMetric == .completed ? cell.completed : cell.skipped
        let peak = model.heat.map { heatMetric == .completed ? $0.completed : $0.skipped }.max() ?? 1
        guard value > 0, peak > 0 else { return Color.white.opacity(0.04) }
        let intensity = 0.25 + 0.75 * Double(value) / Double(peak)
        let base = heatMetric == .completed ? ChartColor.taken : ChartColor.skipped
        return base.opacity(intensity)
    }
}
