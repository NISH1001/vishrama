import SwiftUI
import VishramaCore

@MainActor
final class BreakViewModel: ObservableObject {
    @Published var kind: BreakKind = .short
    @Published var remaining: TimeInterval = 0
    @Published var prompt: String = ""
    /// Full length of this break — lets the view know when half has elapsed.
    @Published var duration: TimeInterval = 0

    /// "Done" earns its place after a quarter of the break has been rested.
    var doneAvailable: Bool { duration > 0 && remaining <= duration * 0.75 }
    /// −5 min is available only while it wouldn't drop below the 5-min floor.
    var canReduce: Bool { remaining > 5 * 60 }

    var title: String {
        kind == .short ? "Eye Break" : "Standup Break"
    }
}

struct BreakView: View {
    @ObservedObject var model: BreakViewModel
    let onSkip: () -> Void
    let onPostpone: () -> Void
    /// Adjust the break length by ±minutes (tap to stack).
    var onAdjust: ((TimeInterval) -> Void)?
    /// Shown after half the break: full credit, back to work early.
    var onDone: (() -> Void)?
    /// Long breaks only: hand this break to Mastishka for a proper sit.
    var onSitWithMastishka: (() -> Void)?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.09, green: 0.11, blue: 0.16), Color(red: 0.04, green: 0.05, blue: 0.08)],
                startPoint: .top, endPoint: .bottom
            )
            VStack(spacing: 28) {
                Text("विश्राम")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.white.opacity(0.45))
                Text(model.title)
                    .font(.system(size: 15, weight: .medium))
                    .textCase(.uppercase)
                    .kerning(3)
                    .foregroundStyle(.white.opacity(0.5))
                Text(model.prompt)
                    .font(.system(size: 34, weight: .regular, design: .serif))
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 640)
                Text(Self.format(model.remaining))
                    .font(.system(size: 56, weight: .thin).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 8)
                if let onAdjust {
                    HStack(spacing: 18) {
                        Button { onAdjust(-5 * 60) } label: {
                            Text("−5 min").padding(.horizontal, 10).padding(.vertical, 5)
                        }
                        .disabled(!model.canReduce)
                        .help("Shorten the break by 5 minutes")
                        Button { onAdjust(5 * 60) } label: {
                            Text("+5 min").padding(.horizontal, 10).padding(.vertical, 5)
                        }
                        .help("Extend the break by 5 minutes")
                    }
                    .font(.system(size: 13))
                    .buttonStyle(.borderless)
                    .foregroundStyle(.white.opacity(0.5))
                }
                HStack(spacing: 20) {
                    if model.doneAvailable, let onDone {
                        Button(action: onDone) {
                            Text("Done — back to work")
                                .padding(.horizontal, 18).padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.25))
                    }
                    Button(action: onPostpone) {
                        Text("Postpone 5 min")
                            .padding(.horizontal, 18).padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    Button(action: onSkip) {
                        Text("Skip")
                            .padding(.horizontal, 18).padding(.vertical, 8)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.top, 12)
                if model.kind == .long, let onSitWithMastishka {
                    Button(action: onSitWithMastishka) {
                        Text("Sit with Mastishka 🧘")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 2)
                }
            }
        }
        .ignoresSafeArea()
    }

    static func format(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
