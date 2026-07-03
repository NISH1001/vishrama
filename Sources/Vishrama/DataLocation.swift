import Foundation

/// Where vishrama keeps its data. iCloud "sync" writes into the user's
/// iCloud Drive folder — no entitlements needed, and it follows them
/// across Macs signed into the same Apple ID.
enum DataLocation {
    static var localRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vishrama", isDirectory: true)
    }

    /// ~/Library/Mobile Documents/com~apple~CloudDocs/Vishrama, if iCloud Drive exists.
    static var iCloudRoot: URL? {
        let cloudDocs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: cloudDocs.path) else { return nil }
        return cloudDocs.appendingPathComponent("Vishrama", isDirectory: true)
    }

    static var iCloudAvailable: Bool { iCloudRoot != nil }

    static var localEventsDirectory: URL {
        localRoot.appendingPathComponent("events", isDirectory: true)
    }

    /// When sync turns on, bring over any local month files that aren't in
    /// iCloud yet (copy only — local data is never deleted).
    static func copyMissingEventFiles(from source: URL, to destination: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else { return }
        try? fm.createDirectory(at: destination, withIntermediateDirectories: true)
        for file in files where file.pathExtension == "jsonl" {
            let target = destination.appendingPathComponent(file.lastPathComponent)
            if !fm.fileExists(atPath: target.path) {
                try? fm.copyItem(at: file, to: target)
            }
        }
    }
}
