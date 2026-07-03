import SwiftUI
import VishramaCore

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    /// Live signal readout, injected by the app.
    var activeSignals: () -> Set<VishramaCore.SignalKind> = { [] }

    var body: some View {
        TabView {
            breaksTab
                .tabItem { Label("Breaks", systemImage: "cup.and.saucer") }
            contextTab
                .tabItem { Label("Context", systemImage: "person.wave.2") }
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 500, height: 560)
    }

    /// Signals that hold breaks back, with live on/off dots.
    private var contextTab: some View {
        Form {
            Section {
                signalRow(
                    toggle: $store.signalCameraMic, kind: .cameraMic,
                    title: "Camera or microphone in use",
                    detail: "The strongest \"in a meeting\" signal — covers Zoom, Meet, Teams calls. No permissions needed."
                )
                signalRow(
                    toggle: $store.signalScreenShare, kind: .screenShare,
                    title: "Screen sharing / presenting",
                    detail: "Detects Zoom's share helper and the apps listed below. The break overlay is also invisible to screen capture as a safety net."
                )
                signalRow(
                    toggle: $store.signalCalendar, kind: .calendarBusy,
                    title: "Busy calendar event",
                    detail: "Reads macOS Calendar (asks permission once). Google calendars work if the account is added in System Settings → Internet Accounts."
                )
            } header: {
                Text("While any of these is active, breaks wait — the timer shows ⏳ and the break appears one minute after you're free.")
                    .font(.caption)
            }

            Section("Treat these apps as presenting (bundle IDs, one per line)") {
                PromptsEditor(lines: $store.presentingApps)
                Text("Example: com.apple.iWork.Keynote")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
    }

    private func signalRow(
        toggle: Binding<Bool>, kind: VishramaCore.SignalKind, title: String, detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(isOn: toggle) {
                HStack(spacing: 6) {
                    TimelineView(.periodic(from: .now, by: 2)) { _ in
                        Circle()
                            .fill(toggle.wrappedValue && activeSignals().contains(kind)
                                  ? Color.green : Color.gray.opacity(0.35))
                            .frame(width: 8, height: 8)
                    }
                    Text(title)
                }
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 20)
        }
    }

    /// Each break type owns its timing AND its messages — they're one concept.
    private var breaksTab: some View {
        Form {
            Section {
                Stepper("Every \(store.shortIntervalMin) min of work", value: $store.shortIntervalMin, in: 5...120, step: 5)
                Stepper("Lasts \(store.shortDurationMin) min", value: $store.shortDurationMin, in: 1...30)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reminders shown (one per line)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    PromptsEditor(lines: $store.shortPrompts)
                }
            } header: {
                Label("Eye break", systemImage: "eye")
            } footer: {
                Text("A short pause to rest your eyes, sip water, unclench.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Stepper("After every \(store.longBreakEvery) eye breaks", value: $store.longBreakEvery, in: 1...10)
                Stepper("Lasts \(store.longDurationMin) min", value: $store.longDurationMin, in: 5...60, step: 5)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reminders shown (one per line)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    PromptsEditor(lines: $store.longPrompts)
                }
            } header: {
                Label("Standup break", systemImage: "figure.walk")
            } footer: {
                Text("A longer reset — walk, stretch, Anapana.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Behavior") {
                Stepper("Pause countdown after \(store.idlePauseMin) min away", value: $store.idlePauseMin, in: 1...15)
                Stepper("Postpone pushes break by \(store.postponeMin) min", value: $store.postponeMin, in: 1...30)
            }
        }
        .formStyle(.grouped)
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch Vishrama at login", isOn: $store.launchAtLogin)
            }
            Section {
                LabeledContent("Behavior log") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([AppDelegate.eventLogDirectory])
                    }
                }
            } footer: {
                Text("Vishrama records break events (completed, skipped, postponed) locally so it can learn your rhythm. Nothing leaves this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Newline-joined editor for a list of prompt strings.
private struct PromptsEditor: View {
    @Binding var lines: [String]

    var body: some View {
        TextEditor(text: Binding(
            get: { lines.joined(separator: "\n") },
            set: { lines = $0.components(separatedBy: "\n") }
        ))
        .font(.body)
        .frame(minHeight: 80)
        .scrollContentBackground(.hidden)
    }
}
