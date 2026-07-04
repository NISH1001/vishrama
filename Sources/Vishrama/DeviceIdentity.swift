import Foundation

/// This Mac's stable writer identity for the event log
/// (specs/ecosystem-protocol.md: readable name + short unique tail).
enum DeviceIdentity {
    /// "<chip-slug>-<6 hex>" (e.g. apple-m3-max-a9dd3f) — the hardware name
    /// says which machine this is better than a hostname, and doesn't put a
    /// person's name in filenames. Minted once on first launch, persisted in
    /// LOCAL defaults (never the synced mirror — identity must not follow you),
    /// never recomputed.
    static var slug: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: "deviceSlug") { return existing }
        let name = chipName ?? Host.current().localizedName ?? "mac"
        var slugged = name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        while slugged.contains("--") { slugged = slugged.replacingOccurrences(of: "--", with: "-") }
        slugged = slugged.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6).lowercased()
        let slug = "\(slugged.isEmpty ? "mac" : slugged)-\(suffix)"
        defaults.set(slug, forKey: "deviceSlug")
        return slug
    }

    /// "Apple M3 Max" and friends, from sysctl.
    private static var chipName: String? {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else { return nil }
        let name = String(cString: buffer).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// Display label: the slug without its uniqueness tail; nil = legacy file.
    static func label(for slug: String?) -> String {
        guard let slug else { return "earlier" }
        let parts = slug.split(separator: "-")
        if let last = parts.last, last.count == 6, last.allSatisfy(\.isHexDigit) {
            return parts.dropLast().joined(separator: "-")
        }
        return slug
    }
}
