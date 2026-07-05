import AppKit
import Foundation

/// Compares the running version against the latest GitHub release (the repo
/// is public — anonymous API, no tokens).
@MainActor
final class UpdateChecker: ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate(String)               // current version
        case available(String, URL)         // latest tag + release page
        case failed
    }

    @Published private(set) var status: Status = .idle

    static let latestAPI = URL(string: "https://api.github.com/repos/NISH1001/vishrama/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/NISH1001/vishrama/releases/latest")!

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    func check() async {
        status = .checking
        do {
            var request = URLRequest(url: Self.latestAPI)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 10
            let (data, _) = try await URLSession.shared.data(for: request)
            struct Release: Decodable {
                let tag_name: String
                let html_url: String
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            if Self.isNewer(release.tag_name, than: currentVersion) {
                status = .available(release.tag_name, URL(string: release.html_url) ?? Self.releasesPage)
            } else {
                status = .upToDate(currentVersion)
            }
        } catch {
            AppDelegate.log.error("update check failed: \(error)")
            status = .failed
        }
    }

    /// For the menu: run the check, then say the outcome in a dialog.
    func checkAndPresentAlert() {
        Task { @MainActor in
            await check()
            let alert = NSAlert()
            switch status {
            case .available(let tag, let url):
                alert.messageText = "\(tag) is available"
                alert.informativeText = "You're running \(currentVersion). Download the new release?"
                alert.addButton(withTitle: "Open Release")
                alert.addButton(withTitle: "Later")
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(url)
                }
            case .upToDate(let version):
                alert.messageText = "You're up to date"
                alert.informativeText = "Vishrama \(version) is the latest release."
                alert.runModal()
            default:
                alert.messageText = "Couldn't check for updates"
                alert.informativeText = "Opening the releases page instead."
                alert.runModal()
                NSWorkspace.shared.open(Self.releasesPage)
            }
        }
    }

    /// "v0.2.10" newer than "0.2.9"? Numeric, component-wise.
    static func isNewer(_ tag: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                .split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = parts(tag), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
