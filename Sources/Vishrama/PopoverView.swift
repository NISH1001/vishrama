import SwiftUI
import VishramaCore

/// Live state shared between the status item and the popover.
@MainActor
final class StatusModel: ObservableObject {
    @Published var status: StatusInfo = .working(remaining: 0)
    /// "6 poms · 2 skips" — nil while the day is empty (line hides entirely).
    @Published var todayLine: String?
    /// Panel size multiplier from Settings (compact 1.0 … large 1.4).
    @Published var panelScale: Double = 1.2

    var paused: Bool {
        if case .manualPaused = status { return true }
        return false
    }

    var timeText: String {
        let t: TimeInterval
        switch status {
        case .working(let r), .onBreak(_, let r), .idlePaused(let r), .manualPaused(let r):
            t = r
        case .suppressed(let overdue):
            t = overdue
        }
        let s = max(0, Int(t.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    var subtitle: String {
        switch status {
        case .working: "until the next break"
        case .onBreak(let kind, _): kind == .short ? "eye break in progress" : "standup break in progress"
        case .idlePaused: "paused — you're away"
        case .manualPaused: "paused"
        case .suppressed: "break waiting — you look busy"
        }
    }
}

/// The Take-a-Break-style panel that springs from the menu bar icon.
/// It paints its own opaque dark chrome instead of relying on OS popover
/// materials — Tahoe's Liquid Glass renders those too light to read.
struct PopoverView: View {
    @ObservedObject var model: StatusModel
    let onTogglePause: () -> Void
    let onBreakNow: () -> Void
    let onReset: () -> Void
    let onInsights: () -> Void
    let onSettings: () -> Void

    /// All key dimensions multiply by the settings-chosen scale.
    private var s: Double { model.panelScale }

    var body: some View {
        VStack(spacing: 12 * s) {
            Button(action: onTogglePause) {
                ZStack {
                    Circle()
                        .fill(.quaternary.opacity(0.6))
                        .frame(width: 74 * s, height: 74 * s)
                    Image(systemName: model.paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 26 * s, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.75))
                }
            }
            .buttonStyle(.plain)
            .help(model.paused ? "Resume" : "Pause")

            VStack(spacing: 2 * s) {
                Text(model.timeText)
                    .font(.system(size: 26 * s, weight: .light).monospacedDigit())
                Text(model.subtitle)
                    .font(.system(size: 10 * s))
                    .foregroundStyle(.secondary)
                if let todayLine = model.todayLine {
                    Text(todayLine)
                        .font(.system(size: 9 * s))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }

            HStack(spacing: 10 * s) {
                Button("Reset", action: onReset)
                Button("Break Now", action: onBreakNow)
            }
            .controlSize(s >= 1.2 ? .regular : .small)

            Divider()

            HStack {
                Button("Insights", action: onInsights)
                Spacer()
                Button("Settings", action: onSettings)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.link)
            .font(.system(size: 10 * s))
        }
        .padding(14 * s)
        .frame(width: 240 * s)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.13, green: 0.15, blue: 0.20), Color(red: 0.08, green: 0.09, blue: 0.13)],
                    startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1))
        )
        .environment(\.colorScheme, .dark)
    }
}
