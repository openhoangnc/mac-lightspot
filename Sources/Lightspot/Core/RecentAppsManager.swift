import Foundation
import AppKit

@MainActor
final class RecentAppsManager {
    static let shared = RecentAppsManager()

    private let defaultsKey = "lightspot_recent_app_bundle_ids"
    private let maxStoredCount = 30

    private init() {}

    /// Record an app launch to recent history
    func recordLaunch(bundleIdentifier: String) {
        guard !bundleIdentifier.isEmpty else { return }
        var recents = storedBundleIDs()
        recents.removeAll(where: { $0 == bundleIdentifier })
        recents.insert(bundleIdentifier, at: 0)
        if recents.count > maxStoredCount {
            recents = Array(recents.prefix(maxStoredCount))
        }
        UserDefaults.standard.set(recents, forKey: defaultsKey)
    }

    /// Retrieve the top N recent apps, filling from running applications if needed
    func getRecentApps(from allApps: [AppInfo], limit: Int = 7) -> [AppInfo] {
        let appMap = Dictionary(uniqueKeysWithValues: allApps.map { ($0.bundleIdentifier, $0) })
        var results: [AppInfo] = []
        var seenIDs = Set<String>()

        // 1. First add explicitly launched recent apps
        let savedIDs = storedBundleIDs()
        for bundleID in savedIDs {
            if let app = appMap[bundleID], !seenIDs.contains(bundleID) {
                results.append(app)
                seenIDs.insert(bundleID)
                if results.count >= limit {
                    return results
                }
            }
        }

        // 2. Next fill with currently running regular GUI applications
        let runningIDs = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .compactMap { $0.bundleIdentifier }

        for bundleID in runningIDs {
            if let app = appMap[bundleID], !seenIDs.contains(bundleID) {
                results.append(app)
                seenIDs.insert(bundleID)
                if results.count >= limit {
                    return results
                }
            }
        }

        // 3. Fallback: fill from allApps
        for app in allApps {
            if !seenIDs.contains(app.bundleIdentifier) {
                results.append(app)
                seenIDs.insert(app.bundleIdentifier)
                if results.count >= limit {
                    return results
                }
            }
        }

        return results
    }

    private func storedBundleIDs() -> [String] {
        UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
    }
}
