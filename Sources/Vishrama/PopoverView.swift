import SwiftUI
import VishramaCore

/// Live state shared between the status item and the popover.
@MainActor
final class StatusModel: ObservableObject {
    @Published var status: StatusInfo = .working(remaining: 0)

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
struct PopoverView: View {
    @ObservedObject var model: StatusModel
    let onTogglePause: () -> Void
    let onBreakNow: () -> Void
    let onReset: () -> Void
    let onHistory: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Button(action: onTogglePause) {
                ZStack {
                    Circle()
                        .fill(.quaternary.opacity(0.6))
                        .frame(width: 130, height: 130)
                    Image(systemName: model.paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.75))
                }
            }
            .buttonStyle(.plain)
            .help(model.paused ? "Resume" : "Pause")

            VStack(spacing: 4) {
                Text(model.timeText)
                    .font(.system(size: 38, weight: .light).monospacedDigit())
                Text(model.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                Button("Reset", action: onReset)
                Button("Break Now", action: onBreakNow)
            }
            .controlSize(.large)

            Divider()

            HStack {
                Button("History", action: onHistory)
                Spacer()
                Button("Settings", action: onSettings)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.link)
            .font(.callout)
        }
        .padding(22)
        .frame(width: 280)
    }
}
