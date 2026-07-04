import Foundation
import Testing
@testable import VishramaCore

private var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

/// July 3, 2026 (a Friday) at the given hour UTC, offset by `dayOffset` days.
private func date(hour: Int, dayOffset: Int = 0) -> Date {
    let base = utcCalendar.date(from: DateComponents(year: 2026, month: 7, day: 3, hour: hour))!
    return utcCalendar.date(byAdding: .day, value: dayOffset, to: base)!
}

private func event(_ kind: BreakEventKind, breakKind: BreakKind = .short, at ts: Date) -> BreakEvent {
    BreakEvent(ts: ts, event: kind, breakKind: breakKind, calendar: utcCalendar)
}

@Suite struct TodaySummaryTests {
    @Test func countsTodayOnly() {
        let events = [
            event(.completed, at: date(hour: 9)),
            event(.completed, at: date(hour: 11)),
            event(.completed, breakKind: .long, at: date(hour: 13)),
            event(.skipped, at: date(hour: 15)),
            event(.naturalBreak, at: date(hour: 16)),
            // Yesterday — must not count.
            event(.completed, at: date(hour: 10, dayOffset: -1)),
            event(.skipped, at: date(hour: 10, dayOffset: -1)),
        ]
        let today = Stats.today(events: events, now: date(hour: 18), calendar: utcCalendar)
        #expect(today.poms == 2)
        #expect(today.standups == 1)
        #expect(today.skipped == 1)
        #expect(today.naturalBreaks == 1)
    }

    @Test func emptyDayIsEmpty() {
        let today = Stats.today(events: [], now: date(hour: 9), calendar: utcCalendar)
        #expect(today.isEmpty)
    }
}

@Suite struct DailyStatsTests {
    @Test func lastNDaysInOrderWithEmptyDaysZeroed() {
        let events = [
            event(.completed, at: date(hour: 9)),               // today
            event(.completed, at: date(hour: 9)),
            event(.skipped, at: date(hour: 9, dayOffset: -1)),  // yesterday
            event(.completed, at: date(hour: 9, dayOffset: -3)),
        ]
        let daily = Stats.daily(events: events, days: 4, now: date(hour: 18), calendar: utcCalendar)
        #expect(daily.count == 4)
        // Oldest first; day -2 has no events but still appears.
        #expect(daily[0].completed == 1 && daily[0].skipped == 0)
        #expect(daily[1].completed == 0 && daily[1].skipped == 0)
        #expect(daily[2].completed == 0 && daily[2].skipped == 1)
        #expect(daily[3].completed == 2 && daily[3].skipped == 0)
    }
}

@Suite struct HeatmapTests {
    @Test func cellsAggregateByWeekdayAndHour() {
        // Friday (dow 6) 9am: two completions and a skip; Friday 2pm: one skip.
        let events = [
            event(.completed, at: date(hour: 9)),
            event(.completed, at: date(hour: 9, dayOffset: -7)),
            event(.skipped, at: date(hour: 9)),
            event(.skipped, at: date(hour: 14)),
        ]
        let cells = Stats.heatmap(events: events)
        let nine = cells.first { $0.dow == 6 && $0.hour == 9 }
        let two = cells.first { $0.dow == 6 && $0.hour == 14 }
        #expect(nine?.completed == 2)
        #expect(nine?.skipped == 1)
        #expect(two?.completed == 0)
        #expect(two?.skipped == 1)
    }
}
