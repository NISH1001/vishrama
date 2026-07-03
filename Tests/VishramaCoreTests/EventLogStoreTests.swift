import Foundation
import Testing
@testable import VishramaCore

private func makeTempStore() throws -> EventLogStore {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("vishrama-tests-\(UUID().uuidString)")
    return EventLogStore(directory: dir)
}

private func makeEvent(ts: Date, event: BreakEventKind = .fired) -> BreakEvent {
    BreakEvent(ts: ts, event: event, breakKind: .short, app: "com.test.app", workedSec: 1500)
}

@Suite struct EventLogStoreTests {
    @Test func appendedEventRoundTrips() throws {
        let store = try makeTempStore()
        let ts = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let event = makeEvent(ts: ts, event: .skipped)
        try store.append(event)
        let read = try store.events(since: .distantPast)
        #expect(read == [event])
    }

    @Test func appendIsOrderedAndCumulative() throws {
        let store = try makeTempStore()
        let base = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let events = (0..<5).map { makeEvent(ts: base.addingTimeInterval(Double($0) * 60)) }
        for event in events { try store.append(event) }
        let read = try store.events(since: .distantPast)
        #expect(read == events)
    }

    @Test func sinceFiltersOldEvents() throws {
        let store = try makeTempStore()
        let base = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let old = makeEvent(ts: base)
        let recent = makeEvent(ts: base.addingTimeInterval(3600))
        try store.append(old)
        try store.append(recent)
        let read = try store.events(since: base.addingTimeInterval(1800))
        #expect(read == [recent])
    }

    @Test func eventsSpanMonthFiles() throws {
        let store = try makeTempStore()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let june = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 10))!
        let july = calendar.date(from: DateComponents(year: 2026, month: 7, day: 2, hour: 10))!
        try store.append(makeEvent(ts: june))
        try store.append(makeEvent(ts: july))
        // Two separate month files exist.
        let files = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
            .filter { $0.hasSuffix(".jsonl") }.sorted()
        #expect(files.count == 2)
        // And reading spans both.
        let read = try store.events(since: .distantPast)
        #expect(read.count == 2)
    }

    @Test func corruptLinesAreSkippedNotFatal() throws {
        let store = try makeTempStore()
        let ts = Date(timeIntervalSinceReferenceDate: 700_000_000)
        try store.append(makeEvent(ts: ts))
        // Simulate a torn write / corrupt line.
        let file = try #require(try FileManager.default.contentsOfDirectory(
            at: store.directory, includingPropertiesForKeys: nil
        ).first { $0.pathExtension == "jsonl" })
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{not json}\n".utf8))
        try handle.close()
        try store.append(makeEvent(ts: ts.addingTimeInterval(60)))
        let read = try store.events(since: .distantPast)
        #expect(read.count == 2)
    }
}
