import Foundation

/// One learned cell of behavior: how often breaks get skipped in a
/// (weekday/weekend × 2-hour slot × app) context.
public struct PatternBucket: Codable, Equatable, Sendable, Identifiable {
    public var id: String { key }
    public let dayClass: String   // "weekday" | "weekend"
    public let hourSlot: Int      // 0, 2, 4, … 22 (start of the 2-hour slot)
    public let app: String        // bundle ID or "other"
    public let fired: Int
    public let skipped: Int
    /// Laplace-smoothed skip rate: (s+1)/(n+2) where n = fired.
    public let skipRate: Double
    /// True when the model wants to stretch the interval in this context.
    public let stretches: Bool

    public var key: String { "\(dayClass)|\(hourSlot)|\(app)" }
}

/// Layer-2 learning: mine the behavior log for contexts where breaks are
/// habitually skipped. Pure functions — trivially testable, no hidden state.
public enum PatternModel {
    public static let minSamples = 8
    public static let highSkipRate = 0.7
    /// Apps outside the top-N by event volume collapse into "other".
    public static let topApps = 10

    public static func compute(
        events: [BreakEvent],
        minSamples: Int = PatternModel.minSamples,
        highSkipRate: Double = PatternModel.highSkipRate,
        calendar: Calendar = .current
    ) -> [PatternBucket] {
        let relevant = events.filter { $0.event == .fired || $0.event == .skipped }
        guard !relevant.isEmpty else { return [] }

        // Rank apps so rare ones fold into "other" and buckets stay dense.
        var appCounts: [String: Int] = [:]
        for event in relevant {
            appCounts[event.app ?? "other", default: 0] += 1
        }
        let top = Set(appCounts.sorted { $0.value > $1.value }.prefix(topApps).map(\.key))

        struct Tally { var fired = 0; var skipped = 0 }
        var tallies: [String: (dayClass: String, slot: Int, app: String, tally: Tally)] = [:]
        for event in relevant {
            let dayClass = Self.dayClass(dow: event.dow)
            let slot = (event.hour / 2) * 2
            let rawApp = event.app ?? "other"
            let app = top.contains(rawApp) ? rawApp : "other"
            let key = "\(dayClass)|\(slot)|\(app)"
            var entry = tallies[key] ?? (dayClass, slot, app, Tally())
            if event.event == .fired { entry.tally.fired += 1 } else { entry.tally.skipped += 1 }
            tallies[key] = entry
        }

        return tallies.values.map { entry in
            let n = entry.tally.fired
            let s = entry.tally.skipped
            let rate = Double(s + 1) / Double(n + 2)
            return PatternBucket(
                dayClass: entry.dayClass,
                hourSlot: entry.slot,
                app: entry.app,
                fired: n,
                skipped: s,
                skipRate: rate,
                stretches: n >= minSamples && rate >= highSkipRate
            )
        }
        .sorted { ($0.fired + $0.skipped) > ($1.fired + $1.skipped) }
    }

    /// The bucket that applies right now, if any.
    public static func bucket(
        in buckets: [PatternBucket],
        for date: Date,
        app: String?,
        calendar: Calendar = .current
    ) -> PatternBucket? {
        let dayClass = Self.dayClass(dow: calendar.component(.weekday, from: date))
        let slot = (calendar.component(.hour, from: date) / 2) * 2
        let appKey = app ?? "other"
        return buckets.first { $0.dayClass == dayClass && $0.hourSlot == slot && $0.app == appKey }
            ?? buckets.first { $0.dayClass == dayClass && $0.hourSlot == slot && $0.app == "other" }
    }

    static func dayClass(dow: Int) -> String {
        (dow == 1 || dow == 7) ? "weekend" : "weekday"
    }
}
