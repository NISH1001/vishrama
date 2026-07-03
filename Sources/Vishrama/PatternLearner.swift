import Combine
import Foundation
import VishramaCore

/// Owns the layer-2 model: recomputes buckets from the event log and answers
/// "how much should the interval stretch right now?". Every learned rule is
/// visible and individually disableable in Settings — nothing acts invisibly.
@MainActor
final class PatternLearner: ObservableObject {
    @Published private(set) var buckets: [PatternBucket] = []
    @Published var disabledKeys: Set<String> {
        didSet { UserDefaults.standard.set(Array(disabledKeys), forKey: "patternDisabledKeys") }
    }
    private(set) var lastComputed: Date?

    init() {
        disabledKeys = Set(UserDefaults.standard.stringArray(forKey: "patternDisabledKeys") ?? [])
    }

    /// Mine the last 60 days of history. Cheap (a few thousand events at most).
    func recompute(from store: EventLogStore) {
        let since = Date().addingTimeInterval(-60 * 86400)
        buckets = PatternModel.compute(events: (try? store.events(since: since)) ?? [])
        lastComputed = Date()
        AppDelegate.log.notice("pattern model recomputed: \(self.buckets.count) buckets, \(self.buckets.filter(\.stretches).count) stretching")
    }

    /// Interval multiplier for the current moment/app (1.0 = no adjustment).
    func scale(now: Date, app: String?, enabled: Bool, strength: Double) -> Double {
        guard enabled,
              let bucket = PatternModel.bucket(in: buckets, for: now, app: app),
              bucket.stretches,
              !disabledKeys.contains(bucket.key)
        else { return 1.0 }
        return strength
    }
}
