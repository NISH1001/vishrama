import Foundation

/// One event plus which device's file it came from (nil = legacy shared file).
public struct TaggedEvent: Equatable, Sendable {
    public let event: BreakEvent
    public let device: String?

    public init(event: BreakEvent, device: String?) {
        self.event = event
        self.device = device
    }
}

/// Append-only JSONL behavior log, one file per device per month
/// (events/mac-air-3f9a2c.2026-07.jsonl). Single-writer-per-file keeps
/// whole-file cloud sync (iCloud Drive, Google Drive) conflict-free by
/// construction — see mastishka's specs/ecosystem-protocol.md.
///
/// Merging happens HERE, at read time, and nowhere else: every consumer
/// (history, stats, pattern learning) receives the union of all devices'
/// files as one time-sorted stream.
public final class EventLogStore {
    public let directory: URL
    /// Stable per-device id (name + short uuid); nil = legacy single-file layout.
    public let deviceSlug: String?

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let monthFormatter: DateFormatter

    public init(directory: URL, deviceSlug: String? = nil) {
        self.directory = directory
        self.deviceSlug = deviceSlug
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "yyyy-MM"
        monthFormatter.timeZone = TimeZone(identifier: "UTC")
        monthFormatter.locale = Locale(identifier: "en_US_POSIX")
    }

    public func append(_ event: BreakEvent) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let month = monthFormatter.string(from: event.ts)
        let name = deviceSlug.map { "\($0).\(month).jsonl" } ?? "\(month).jsonl"
        let file = directory.appendingPathComponent(name)
        var line = try encoder.encode(event)
        line.append(UInt8(ascii: "\n"))
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: file, options: .atomic)
        }
    }

    /// Erase the entire log: remove every month file, every device's.
    /// The directory (and non-log files like settings.json) is left alone.
    public func clear() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
        for file in files {
            try FileManager.default.removeItem(at: file)
        }
    }

    /// All events at or after `since`, across all devices' files, oldest first.
    /// Pattern learning consumes this unfiltered union — habits are per-person,
    /// not per-machine.
    public func events(since: Date) throws -> [BreakEvent] {
        try taggedEvents(since: since).map(\.event)
    }

    /// Like `events(since:)` but each event carries its source device
    /// (parsed from the filename; corrupt lines are skipped, never fatal).
    public func taggedEvents(since: Date) throws -> [TaggedEvent] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var result: [TaggedEvent] = []
        for file in files {
            let device = Self.deviceSlug(fromFileName: file.lastPathComponent)
            let data = try Data(contentsOf: file)
            for line in data.split(separator: UInt8(ascii: "\n")) {
                guard let event = try? decoder.decode(BreakEvent.self, from: line) else { continue }
                if event.ts >= since { result.append(TaggedEvent(event: event, device: device)) }
            }
        }
        // Devices' files interleave in time — order by when things happened.
        return result.sorted { $0.event.ts < $1.event.ts }
    }

    /// Distinct device slugs present in the log (legacy shared files excluded).
    public func knownDevices() throws -> [String] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".jsonl") }
        return Set(names.compactMap(Self.deviceSlug(fromFileName:))).sorted()
    }

    /// "mac-air-3f9a2c.2026-07.jsonl" → "mac-air-3f9a2c"; "2026-07.jsonl" → nil.
    static func deviceSlug(fromFileName name: String) -> String? {
        let stem = name.hasSuffix(".jsonl") ? String(name.dropLast(6)) : name
        let parts = stem.split(separator: ".")
        guard parts.count == 2 else { return nil }
        return String(parts[0])
    }
}
