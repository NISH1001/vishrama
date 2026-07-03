import Foundation
import Testing
@testable import VishramaCore

private var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

/// A Tuesday (weekday) at the given hour, offset by `day` weeks to spread samples.
private func weekdayDate(hour: Int, week: Int = 0) -> Date {
    utcCalendar.date(from: DateComponents(year: 2026, month: 6, day: 2 + week * 7, hour: hour))!
}

private func event(_ kind: BreakEventKind, at ts: Date, app: String = "com.test.ide") -> BreakEvent {
    BreakEvent(ts: ts, event: kind, breakKind: .short, app: app, calendar: utcCalendar)
}

@Suite struct PatternModelTests {
    @Test func highSkipBucketIsFlagged() {
        // 10 fired, 8 skipped, all weekday 10–11am in the IDE.
        var events: [BreakEvent] = []
        for week in 0..<10 {
            events.append(event(.fired, at: weekdayDate(hour: 10, week: week % 4)))
        }
        for week in 0..<8 {
            events.append(event(.skipped, at: weekdayDate(hour: 10, week: week % 4)))
        }
        let buckets = PatternModel.compute(events: events, calendar: utcCalendar)
        let flagged = buckets.filter(\.stretches)
        #expect(flagged.count == 1)
        #expect(flagged.first?.dayClass == "weekday")
        #expect(flagged.first?.hourSlot == 10)
        #expect(flagged.first?.app == "com.test.ide")
    }

    @Test func sparseBucketsNeverAct() {
        // Only 5 fired/skips — below the minimum sample size.
        var events: [BreakEvent] = []
        for i in 0..<5 {
            events.append(event(.fired, at: weekdayDate(hour: 14, week: i % 3)))
            events.append(event(.skipped, at: weekdayDate(hour: 14, week: i % 3)))
        }
        let buckets = PatternModel.compute(events: events, calendar: utcCalendar)
        #expect(buckets.allSatisfy { !$0.stretches })
    }

    @Test func lowSkipRateBucketsDoNotStretch() {
        // Plenty of samples but the user takes their breaks.
        var events: [BreakEvent] = []
        for week in 0..<12 {
            events.append(event(.fired, at: weekdayDate(hour: 10, week: week % 4)))
            events.append(event(.completed, at: weekdayDate(hour: 10, week: week % 4)))
        }
        events.append(event(.skipped, at: weekdayDate(hour: 10)))
        let buckets = PatternModel.compute(events: events, calendar: utcCalendar)
        #expect(buckets.allSatisfy { !$0.stretches })
    }

    @Test func bucketsSeparateByApp() {
        var events: [BreakEvent] = []
        // Heavy skipper in the IDE...
        for week in 0..<10 {
            events.append(event(.fired, at: weekdayDate(hour: 10, week: week % 4), app: "com.test.ide"))
            events.append(event(.skipped, at: weekdayDate(hour: 10, week: week % 4), app: "com.test.ide"))
        }
        // ...but takes breaks while in the browser at the same hour.
        for week in 0..<10 {
            events.append(event(.fired, at: weekdayDate(hour: 10, week: week % 4), app: "com.test.browser"))
        }
        let buckets = PatternModel.compute(events: events, calendar: utcCalendar)
        let ide = buckets.first { $0.app == "com.test.ide" }
        let browser = buckets.first { $0.app == "com.test.browser" }
        #expect(ide?.stretches == true)
        #expect(browser?.stretches == false)
    }

    @Test func lookupMatchesDateAndApp() {
        var events: [BreakEvent] = []
        for week in 0..<10 {
            events.append(event(.fired, at: weekdayDate(hour: 10, week: week % 4)))
            events.append(event(.skipped, at: weekdayDate(hour: 10, week: week % 4)))
        }
        let buckets = PatternModel.compute(events: events, calendar: utcCalendar)
        let hit = PatternModel.bucket(
            in: buckets, for: weekdayDate(hour: 11), app: "com.test.ide", calendar: utcCalendar)
        #expect(hit?.stretches == true)
        // Different hour slot → no match.
        let miss = PatternModel.bucket(
            in: buckets, for: weekdayDate(hour: 15), app: "com.test.ide", calendar: utcCalendar)
        #expect(miss == nil)
    }
}

@Suite struct EngineIntervalScale {
    @Test func stretchedIntervalDelaysNextBreak() {
        let engine = ScheduleEngine(
            config: BreakConfiguration(), startAt: Date(timeIntervalSinceReferenceDate: 0))
        engine.intervalScale = 1.5
        let due = Date(timeIntervalSinceReferenceDate: 25 * 60)
        _ = engine.tick(now: due, context: ContextSnapshot())
        // Complete the break; the next interval is 25 × 1.5 = 37.5 min.
        let end = due.addingTimeInterval(5 * 60)
        let effects = engine.tick(now: end, context: ContextSnapshot())
        #expect(effects.contains(.updateStatus(.working(remaining: 37.5 * 60.0))))
    }
}
