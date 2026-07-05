import SwiftUI

enum InsightsTab: String, CaseIterable {
    case stats = "Stats"
    case history = "History"
}

/// One window holding both Stats and History, switched by a segmented control,
/// with a single device filter shared across both.
struct InsightsView: View {
    @ObservedObject var stats: StatsModel
    @ObservedObject var history: HistoryModel
    @State private var tab: InsightsTab

    init(stats: StatsModel, history: HistoryModel, initialTab: InsightsTab) {
        self.stats = stats
        self.history = history
        _tab = State(initialValue: initialTab)
    }

    /// Drives both models from one control so the two tabs stay in sync.
    private var deviceFilter: Binding<String?> {
        Binding(
            get: { stats.deviceFilter },
            set: { stats.deviceFilter = $0; history.deviceFilter = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $tab) {
                    ForEach(InsightsTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
                Spacer()
                if !stats.devices.isEmpty {
                    Picker("Device", selection: deviceFilter) {
                        Text("All devices").tag(String?.none)
                        ForEach(stats.devices, id: \.self) { slug in
                            Text(DeviceIdentity.label(for: slug)).tag(String?.some(slug))
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(maxWidth: 170)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)
            Divider()
            switch tab {
            case .stats: StatsView(model: stats)
            case .history: HistoryView(model: history)
            }
        }
        .frame(width: 560, height: 640)
        .environment(\.colorScheme, .dark)
        .background(Color(red: 0.086, green: 0.10, blue: 0.13))
    }
}
