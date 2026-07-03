import Foundation

/// Append-only JSONL behavior log, one file per month (events/2026-07.jsonl).
public final class EventLogStore {
    public let directory: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let monthFormatter: DateFormatter

    public init(directory: URL) {
        self.directory = directory
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
        let file = directory.appendingPathComponent("\(monthFormatter.string(from: event.ts)).jsonl")
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

    /// All events at or after `since`, across month files, in file order.
    /// Corrupt lines (torn writes) are skipped, never fatal.
    public func events(since: Date) throws -> [BreakEvent] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var result: [BreakEvent] = []
        for file in files {
            let data = try Data(contentsOf: file)
            for line in data.split(separator: UInt8(ascii: "\n")) {
                guard let event = try? decoder.decode(BreakEvent.self, from: line) else { continue }
                if event.ts >= since { result.append(event) }
            }
        }
        return result
    }
}
