import Foundation
import AppKit

@MainActor
final class RecentAppsManager {
    static let shared = RecentAppsManager()

    private let defaultsKey = "lightspot_recent_app_bundle_ids"
    private let maxStoredCount = 30

    private init() {}

    private var cachedRecentApps: [AppInfo]?

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
        cachedRecentApps = nil // invalidate cache
    }

    /// Retrieve the top N recent apps, filling from running applications if needed
    func getRecentApps(limit: Int = 7) -> [AppInfo] {
        if let cached = cachedRecentApps, cached.count == limit {
            return cached
        }

        let allApps = AppScanner.shared.allApps()
        var results: [AppInfo] = []
        var seenIDs = Set<String>()

        // Helper
        func addApp(id: String) {
            guard !seenIDs.contains(id), let app = allApps.first(where: { $0.bundleIdentifier == id }) else { return }
            results.append(app)
            seenIDs.insert(id)
        }

        // 1. First add explicitly launched recent apps
        for bundleID in storedBundleIDs() {
            addApp(id: bundleID)
            if results.count >= limit { break }
        }

        // 2. Next fill with currently running regular GUI applications
        if results.count < limit {
            let runningIDs = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
                .compactMap { $0.bundleIdentifier }
            for bundleID in runningIDs {
                addApp(id: bundleID)
                if results.count >= limit { break }
            }
        }

        // 3. Fallback: fill from allApps
        if results.count < limit {
            for app in allApps {
                addApp(id: app.bundleIdentifier)
                if results.count >= limit { break }
            }
        }

        cachedRecentApps = results
        return results
    }

    /// Clear cache on hide
    func reclaimMemory() {
        cachedRecentApps = nil
    }

    /// Restore recent apps from backup
    func restore(bundleIDs: [String]) {
        let recents = bundleIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let clamped = Array(recents.prefix(maxStoredCount))
        UserDefaults.standard.set(clamped, forKey: defaultsKey)
        cachedRecentApps = nil
    }

    private func storedBundleIDs() -> [String] {
        UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
    }
}
