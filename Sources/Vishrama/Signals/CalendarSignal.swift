import EventKit
import Foundation
import VishramaCore

/// Busy calendar event happening right now (Google accounts included, via
/// macOS Internet Accounts). Requires the Calendar full-access TCC prompt.
@MainActor
final class CalendarSignal: SignalProvider {
    let kind = SignalKind.calendarBusy
    private(set) var isActive = false
    private(set) var authorized = false

    private let store = EKEventStore()
    private var timer: Timer?
    private var changeObserver: NSObjectProtocol?
    /// Cached today's events, refreshed on change/hourly; scanned every poll.
    private var cachedEvents: [EKEvent] = []

    func start() {
        requestAccessIfNeeded()
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshEvents() }
        }
        let timer = Timer(timeInterval: 30, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let observer = changeObserver {
            NotificationCenter.default.removeObserver(observer)
            changeObserver = nil
        }
        isActive = false
    }

    private func requestAccessIfNeeded() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            authorized = true
            refreshEvents()
        case .notDetermined:
            store.requestFullAccessToEvents { [weak self] granted, _ in
                Task { @MainActor in
                    self?.authorized = granted
                    if granted { self?.refreshEvents() }
                }
            }
        default:
            authorized = false
        }
    }

    private func refreshEvents() {
        guard authorized else { return }
        let now = Date()
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-2 * 3600),
            end: now.addingTimeInterval(24 * 3600),
            calendars: nil
        )
        cachedEvents = store.events(matching: predicate)
        poll()
    }

    private func poll() {
        guard authorized else {
            isActive = false
            return
        }
        let now = Date()
        isActive = cachedEvents.contains { event in
            guard !event.isAllDay,
                  event.availability != .free,
                  let start = event.startDate, let end = event.endDate
            else { return false }
            // Declined events don't make you busy.
            if event.attendees?.first(where: { $0.isCurrentUser })?.participantStatus == .declined {
                return false
            }
            return start <= now && now < end
        }
    }
}
