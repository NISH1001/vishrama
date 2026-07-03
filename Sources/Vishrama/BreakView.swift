import SwiftUI
import VishramaCore

@MainActor
final class BreakViewModel: ObservableObject {
    @Published var kind: BreakKind = .short
    @Published var remaining: TimeInterval = 0
    @Published var prompt: String = ""

    var title: String {
        kind == .short ? "Eye Break" : "Standup Break"
    }
}

struct BreakView: View {
    @ObservedObject var model: BreakViewModel
    let onSkip: () -> Void
    let onPostpone: () -> Void

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
                HStack(spacing: 20) {
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
            }
        }
        .ignoresSafeArea()
    }

    static func format(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
