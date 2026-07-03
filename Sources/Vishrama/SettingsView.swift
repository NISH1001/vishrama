import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        TabView {
            scheduleTab
                .tabItem { Label("Schedule", systemImage: "clock") }
            messagesTab
                .tabItem { Label("Messages", systemImage: "text.quote") }
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 460, height: 340)
    }

    private var scheduleTab: some View {
        Form {
            Section("Eye break (short)") {
                Stepper("Every \(store.shortIntervalMin) min of work", value: $store.shortIntervalMin, in: 5...120, step: 5)
                Stepper("Lasts \(store.shortDurationMin) min", value: $store.shortDurationMin, in: 1...30)
            }
            Section("Standup break (long)") {
                Stepper("After every \(store.longBreakEvery) short breaks", value: $store.longBreakEvery, in: 1...10)
                Stepper("Lasts \(store.longDurationMin) min", value: $store.longDurationMin, in: 5...60, step: 5)
            }
            Section("Behavior") {
                Stepper("Pause countdown after \(store.idlePauseMin) min away", value: $store.idlePauseMin, in: 1...15)
                Stepper("Postpone pushes break by \(store.postponeMin) min", value: $store.postponeMin, in: 1...30)
            }
        }
        .formStyle(.grouped)
    }

    private var messagesTab: some View {
        Form {
            Section("Eye break prompts (one per line)") {
                PromptsEditor(lines: $store.shortPrompts)
            }
            Section("Standup break prompts (one per line)") {
                PromptsEditor(lines: $store.longPrompts)
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
