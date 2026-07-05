import Foundation
import UserNotifications
import VishramaCore

/// Gentle notifications used in flow mode instead of the overlay.
@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    nonisolated static let takeBreakAction = "dev.nishparadox.vishrama.takeBreak"
    nonisolated static let categoryID = "dev.nishparadox.vishrama.breakDue"

    var onTakeBreak: (() -> Void)?
    private let center = UNUserNotificationCenter.current()
    private var authorized = false
    /// For the Settings truth line: are our notifications actually visible?
    @Published private(set) var authStatus: UNAuthorizationStatus = .notDetermined

    func refreshStatus() {
        center.getNotificationSettings { [weak self] settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                self?.authStatus = status
                self?.authorized = status == .authorized || status == .provisional
            }
        }
    }

    func setup() {
        center.delegate = self
        let action = UNNotificationAction(identifier: Self.takeBreakAction, title: "Take it now")
        let category = UNNotificationCategory(
            identifier: Self.categoryID, actions: [action], intentIdentifiers: [])
        center.setNotificationCategories([category])
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            Task { @MainActor in
                self?.authorized = granted
                self?.refreshStatus()
                if let error {
                    AppDelegate.log.error("notification auth failed: \(error)")
                }
            }
        }
    }

    func notifyBreakDue(kind: BreakKind, prompt: String) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = kind == .short ? "Eye break is waiting 🌻" : "Standup break is waiting 🌻"
        content.body = "\(prompt) — you seem to be in flow, so no takeover. Whenever you're ready."
        content.categoryIdentifier = Self.categoryID
        content.sound = nil
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// In-meeting 20-20-20 whisper — no sound, no action, no overlay.
    func notifyMicroBreak() {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest your eyes 👁"
        content.body = "Long meeting — 20 seconds on something distant."
        content.sound = nil
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// Heads-up shortly before a break takes the screen.
    func notifyPreBreak(kind: BreakKind, lead: TimeInterval) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        let when = lead >= 60
            ? "\(Int((lead / 60).rounded())) min"
            : "\(Int(lead.rounded()))s"
        content.title = kind == .short ? "Eye break in \(when) 🌻" : "Standup break in \(when) 🌻"
        content.body = "Wrap up your thought — a mindful pause is coming."
        content.categoryIdentifier = Self.categoryID
        content.sound = nil
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if response.actionIdentifier == Self.takeBreakAction
            || response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            await MainActor.run { onTakeBreak?() }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner]
    }
}
