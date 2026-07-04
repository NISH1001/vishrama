import Foundation

/// This Mac's stable writer identity for the event log
/// (specs/ecosystem-protocol.md: readable name + short unique tail).
enum DeviceIdentity {
    /// "<hostname-slug>-<6 hex>", minted once on first launch, persisted in
    /// LOCAL defaults (never the synced mirror — identity must not follow you),
    /// never recomputed. A hostname change simply keeps the old slug.
    static var slug: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: "deviceSlug") { return existing }
        let name = Host.current().localizedName ?? "mac"
        var slugged = name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        while slugged.contains("--") { slugged = slugged.replacingOccurrences(of: "--", with: "-") }
        slugged = slugged.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6).lowercased()
        let slug = "\(slugged.isEmpty ? "mac" : slugged)-\(suffix)"
        defaults.set(slug, forKey: "deviceSlug")
        return slug
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
