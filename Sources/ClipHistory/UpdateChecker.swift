import Foundation
import Observation

/// Fetches `downloads.cliphistory.stach.uk/appcast.json` and, if the remote
/// version beats the running one (and hasn't been dismissed), publishes an
/// `available`. AppDelegate checks on launch (throttled to ~once/day) and lights
/// the popup's gear dot. Silent failure — a network or JSON error just means no
/// update is shown and we retry next launch.
@MainActor
@Observable
final class UpdateChecker {
    struct Available: Equatable {
        let version: String
        let downloadURL: URL
        let notesURL: URL?
    }

    var available: Available?

    private let appcastURL  = URL(string: "https://downloads.cliphistory.stach.uk/appcast.json")!
    private let lastCheckKey = "lastUpdateCheck"
    private let dismissedKey  = "dismissedUpdateVersion"

    /// Launch path: skip if we checked within the last day (unless forced, e.g.
    /// a future manual "Check Now" button).
    func checkIfDue(force: Bool = false) async {
        if !force,
           let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date,
           Date.now.timeIntervalSince(last) < 86_400 {
            return
        }
        await check()
    }

    func check() async {
        UserDefaults.standard.set(Date.now, forKey: lastCheckKey)
        do {
            var request = URLRequest(url: appcastURL)
            request.cachePolicy = .reloadRevalidatingCacheData
            let (data, _) = try await URLSession.shared.data(for: request)
            let cast = try JSONDecoder().decode(AppCast.self, from: data)

            guard let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                  versionCompare(cast.version, current) == .orderedDescending else {
                available = nil
                return
            }
            // A version the user explicitly skipped stays hidden until a newer one.
            if UserDefaults.standard.string(forKey: dismissedKey) == cast.version {
                available = nil
                return
            }
            available = Available(version: cast.version, downloadURL: cast.url, notesURL: cast.notesURL)
        } catch {
            NSLog("UpdateChecker: \(error.localizedDescription)")
        }
    }

    func dismiss() {
        if let version = available?.version {
            UserDefaults.standard.set(version, forKey: dismissedKey)
        }
        available = nil
    }

    private struct AppCast: Decodable {
        let version: String
        let url: URL
        let notesURL: URL?
    }
}

/// Dotted-integer compare ("1.4.0" > "1.3.0"), tolerant of differing lengths.
private func versionCompare(_ a: String, _ b: String) -> ComparisonResult {
    let lhs = a.split(separator: ".").map { Int($0) ?? 0 }
    let rhs = b.split(separator: ".").map { Int($0) ?? 0 }
    for i in 0..<max(lhs.count, rhs.count) {
        let l = i < lhs.count ? lhs[i] : 0
        let r = i < rhs.count ? rhs[i] : 0
        if l < r { return .orderedAscending }
        if l > r { return .orderedDescending }
    }
    return .orderedSame
}
