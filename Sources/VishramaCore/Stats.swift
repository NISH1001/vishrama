import Foundation

public struct TodaySummary: Equatable, Sendable {
    public var poms: Int          // completed eye breaks
    public var standups: Int      // completed long breaks
    public var skipped: Int
    public var naturalBreaks: Int

    public var isEmpty: Bool {
        poms == 0 && standups == 0 && skipped == 0 && naturalBreaks == 0
    }

    public init(poms: Int = 0, standups: Int = 0, skipped: Int = 0, naturalBreaks: Int = 0) {
        self.poms = poms
        self.standups = standups
        self.skipped = skipped
        self.naturalBreaks = naturalBreaks
    }
}

public struct DailyStat: Equatable, Sendable, Identifiable {
    public let day: Date          // start of day
    public let completed: Int     // breaks completed (any kind)
    public let skipped: Int

    public var id: Date { day }
}

public struct HeatCell: Equatable, Sendable, Identifiable {
    public let dow: Int           // 1–7, Sunday = 1 (Calendar convention)
    public let hour: Int          // 0–23
    public let completed: Int
    public let skipped: Int

    public var id: String { "\(dow)-\(hour)" }
}

/// Pure aggregations over the behavior log for the Stats UI.
public enum Stats {
    public static func today(events: [BreakEvent], now: Date, calendar: Calendar = .current) -> TodaySummary {
        var summary = TodaySummary(poms: 0, standups: 0, skipped: 0, naturalBreaks: 0)
        for event in events where calendar.isDate(event.ts, inSameDayAs: now) {
            switch event.event {
            case .completed:
                if event.breakKind == .long { summary.standups += 1 } else { summary.poms += 1 }
            case .skipped:
                summary.skipped += 1
            case .naturalBreak:
                summary.naturalBreaks += 1
            default:
                break
            }
        }
        return summary
    }

    /// One entry per calendar day, oldest first, ending on `now`'s day.
    /// Days with no events appear as zeros so charts keep a stable axis.
    public static func daily(events: [BreakEvent], days: Int, now: Date, calendar: Calendar = .current) -> [DailyStat] {
        let todayStart = calendar.startOfDay(for: now)
        var buckets: [Date: (completed: Int, skipped: Int)] = [:]
        for event in events {
            let day = calendar.startOfDay(for: event.ts)
            switch event.event {
            case .completed: buckets[day, default: (0, 0)].completed += 1
            case .skipped: buckets[day, default: (0, 0)].skipped += 1
            default: break
            }
        }
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { return nil }
            let counts = buckets[day] ?? (0, 0)
            return DailyStat(day: day, completed: counts.completed, skipped: counts.skipped)
        }
    }

    /// Weekday × hour grid using the context each event already carries.
    public static func heatmap(events: [BreakEvent]) -> [HeatCell] {
        var buckets: [String: (dow: Int, hour: Int, completed: Int, skipped: Int)] = [:]
        for event in events {
            let key = "\(event.dow)-\(event.hour)"
            var cell = buckets[key] ?? (event.dow, event.hour, 0, 0)
            switch event.event {
            case .completed: cell.completed += 1
            case .skipped: cell.skipped += 1
            default: continue
            }
            buckets[key] = cell
        }
        return buckets.values.map {
            HeatCell(dow: $0.dow, hour: $0.hour, completed: $0.completed, skipped: $0.skipped)
        }
    }
}
