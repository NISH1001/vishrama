import SwiftUI
import VishramaCore

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var learner: PatternLearner
    /// Live signal readout, injected by the app.
    var activeSignals: () -> Set<VishramaCore.SignalKind> = { [] }

    var body: some View {
        TabView {
            breaksTab
                .tabItem { Label("Breaks", systemImage: "cup.and.saucer") }
            contextTab
                .tabItem { Label("Context", systemImage: "person.wave.2") }
            adaptivityTab
                .tabItem { Label("Adaptivity", systemImage: "brain") }
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 520, height: 560)
    }

    /// Everything the pattern learner knows, out in the open.
    private var adaptivityTab: some View {
        Form {
            Section {
                Toggle("Learn from my behavior", isOn: $store.patternLearningEnabled)
                Picker("When a pattern is found, stretch the interval", selection: $store.adaptivityStrength) {
                    Text("Gently (×1.25)").tag(SettingsStore.AdaptivityStrength.gentle)
                    Text("Normally (×1.5)").tag(SettingsStore.AdaptivityStrength.normal)
                    Text("Strongly (×2)").tag(SettingsStore.AdaptivityStrength.strong)
                }
            } footer: {
                Text("Vishrama mines your last 60 days of break history for contexts where you habitually skip (e.g. weekday mornings in the IDE) and quietly spaces breaks out there. It only acts on a pattern after \(PatternModel.minSamples)+ observations with a ≥\(Int(PatternModel.highSkipRate * 100))% skip rate.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("What it has learned") {
                if learner.buckets.filter(\.stretches).isEmpty {
                    Text("No strong patterns yet — keep using Vishrama and check back in a week or two.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(learner.buckets.filter(\.stretches)) { bucket in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Self.bucketTitle(bucket))
                                Text("\(bucket.skipped) skips over \(bucket.fired) breaks (\(Int(bucket.skipRate * 100))%)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { !learner.disabledKeys.contains(bucket.key) },
                                set: { on in
                                    if on { learner.disabledKeys.remove(bucket.key) }
                                    else { learner.disabledKeys.insert(bucket.key) }
                                }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                        }
                    }
                    Button("Re-enable all patterns") { learner.disabledKeys.removeAll() }
                        .disabled(learner.disabledKeys.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }

    static func bucketTitle(_ bucket: PatternBucket) -> String {
        let day = bucket.dayClass == "weekday" ? "Weekdays" : "Weekends"
        let slot = "\(bucket.hourSlot):00–\(bucket.hourSlot + 2):00"
        let app = bucket.app == "other" ? "any app" : (bucket.app.components(separatedBy: ".").last ?? bucket.app)
        return "\(day) \(slot) · in \(app)"
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
                Picker("Heads-up before a break", selection: $store.preBreakWarnSec) {
                    Text("Off").tag(0)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                    Text("5 minutes").tag(300)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch Vishrama at login", isOn: $store.launchAtLogin)
                Picker("Panel size", selection: $store.panelSize) {
                    Text("Compact").tag(SettingsStore.PanelSize.compact)
                    Text("Comfortable").tag(SettingsStore.PanelSize.comfortable)
                    Text("Large").tag(SettingsStore.PanelSize.large)
                }
            }

            Section {
                Picker("Store data in", selection: $store.dataLocationChoice) {
                    Text("iCloud Drive (syncs across Macs)")
                        .tag(SettingsStore.DataLocationChoice.icloud)
                        .disabled(!DataLocation.iCloudAvailable)
                    Text("This Mac only").tag(SettingsStore.DataLocationChoice.local)
                    Text("Custom folder").tag(SettingsStore.DataLocationChoice.custom)
                }
                .pickerStyle(.radioGroup)

                if store.dataLocationChoice == .custom {
                    LabeledContent("Folder") {
                        HStack {
                            Text(store.customDataPath.isEmpty ? "None chosen" : store.customDataPath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                            Button("Choose…") { chooseCustomFolder() }
                        }
                    }
                }

                LabeledContent("Current location") {
                    HStack {
                        Text(Self.friendlyPath(store.dataRoot))
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([store.dataRoot])
                        }
                    }
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Settings and break history live here (settings.json + events/). Point both your Macs at the same iCloud Drive or shared folder and Vishrama feels like one app across them. Nothing ever leaves your own storage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 10) {
                    Group {
                        if let icon = Self.mastishkaIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 32, height: 32)
                        } else {
                            // Mastishka's own menu-bar glyph, in its mint.
                            Image(systemName: "circle.circle")
                                .font(.system(size: 24, weight: .light))
                                .foregroundStyle(Self.mastishkaInstalled
                                    ? Color(red: 0x8F / 255.0, green: 0xD3 / 255.0, blue: 0xC2 / 255.0)
                                    : Color.secondary)
                                .frame(width: 32, height: 32)
                        }
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Mastishka — मस्तिष्क")
                            .font(.system(size: 13, weight: .medium))
                        Text(Self.mastishkaInstalled
                             ? "detected on this Mac ✓"
                             : "not installed — breaks will open the web sit")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !Self.mastishkaInstalled {
                        Button("Get Mastishka") {
                            NSWorkspace.shared.open(URL(string: "https://nishparadox.com/mastishka/")!)
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 2)

                Toggle("Offer \"Sit with Mastishka\" on standup breaks", isOn: $store.mastishkaEnabled)
                if store.mastishkaEnabled {
                    Picker("Practice", selection: $store.mastishkaPractice) {
                        Text("Anapana").tag("anapana")
                        Text("Vipassana").tag("vipassana")
                        Text("Metta").tag("metta")
                        Text("Meditation").tag("meditation")
                    }
                }
            } header: {
                Text("Ecosystem")
            } footer: {
                Text("Vishrama hands the meditation session off to Mastishka — when the sit ends, the break is credited as completed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Version") {
                    Text(Self.versionString)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    static var mastishkaInstalled: Bool {
        guard let url = URL(string: "mastishka://sit") else { return false }
        return NSWorkspace.shared.urlForApplication(toOpen: url) != nil
    }

    /// The real app icon when mastishka-mac ships one; nil → glyph fallback.
    /// (A bundle with no declared icon would render macOS's generic grid,
    /// which reads as broken — prefer the sibling's own menu-bar glyph.)
    static var mastishkaIcon: NSImage? {
        guard let url = URL(string: "mastishka://sit"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: url),
              let bundle = Bundle(url: appURL),
              bundle.object(forInfoDictionaryKey: "CFBundleIconFile") != nil
                || bundle.object(forInfoDictionaryKey: "CFBundleIconName") != nil
        else { return nil }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    /// Display-only prettification: "iCloud Drive ▸ Vishrama" or "~/…".
    static func friendlyPath(_ url: URL) -> String {
        let path = url.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let cloudDocs = home + "/Library/Mobile Documents/com~apple~CloudDocs"
        if path.hasPrefix(cloudDocs) {
            let rest = String(path.dropFirst(cloudDocs.count)).trimmingCharacters(in: ["/"])
            return rest.isEmpty ? "iCloud Drive" : "iCloud Drive ▸ \(rest.replacingOccurrences(of: "/", with: " ▸ "))"
        }
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func chooseCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        if panel.runModal() == .OK, let url = panel.url {
            store.customDataPath = url.path
        }
    }
}

/// Newline-joined editor for a list of prompt strings.
/// Owns its text locally while editing — a computed two-way binding would
/// re-render stale content mid-keystroke and eat trailing characters.
private struct PromptsEditor: View {
    @Binding var lines: [String]
    @State private var text = ""

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .frame(minHeight: 80)
            .scrollContentBackground(.hidden)
            .onAppear { text = lines.joined(separator: "\n") }
            .onChange(of: text) { _, newValue in
                lines = newValue.components(separatedBy: "\n")
            }
    }
}
