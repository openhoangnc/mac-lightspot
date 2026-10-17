import Foundation

/// Deletes the HTTP cache and cookie store that versions up to 1.2.0 left on disk.
///
/// Their update check (and, before the privacy fix, the `api.ipify.org` lookup) went
/// through `URLSession.shared`, so CFNetwork kept every response, the user's public IP
/// included, in `~/Library/Caches/<bundle id>/Cache.db` and its cookies and HSTS state
/// in `~/Library/HTTPStorages`. 1.2.1 moved both requests to ephemeral sessions, which
/// write nothing, but an upgraded install kept the old files.
///
/// Runs at every launch instead of behind a "done" flag: it only checks a handful of
/// known paths, deletes the ones that exist and creates nothing, so a fresh install is
/// left exactly as it was. Not `URLCache.shared.removeAllCachedResponses()`: merely
/// touching `URLCache.shared` creates `Cache.db` (measured), the opposite of the point.
enum LegacyNetworkStores {
    /// Everything `URLSession.shared` writes for an app, as measured under a throwaway
    /// home against a local server that sets a cookie: the response cache and its
    /// on-disk bodies, the HSTS / alt-svc store, and the cookie jar beside it.
    static func knownPaths(bundleIdentifier: String, libraryPath: String) -> [String] {
        // An empty or path-like identifier would point at `Caches` itself.
        guard !bundleIdentifier.isEmpty, bundleIdentifier != ".", bundleIdentifier != "..",
              !bundleIdentifier.contains("/") else { return [] }
        let (cache, storage) = containerPaths(bundleIdentifier: bundleIdentifier, libraryPath: libraryPath)
        return ["Cache.db", "Cache.db-wal", "Cache.db-shm", "fsCachedData"].map { join(cache, $0) }
            + ["httpstorages.sqlite", "httpstorages.sqlite-wal", "httpstorages.sqlite-shm"].map { join(storage, $0) }
            + [join(libraryPath, "HTTPStorages/\(bundleIdentifier).binarycookies")]
    }

    /// The known entries that are on disk now.
    static func leftovers(bundleIdentifier: String, libraryPath: String,
                          fileManager: FileManager = .default) -> [String] {
        knownPaths(bundleIdentifier: bundleIdentifier, libraryPath: libraryPath).filter {
            // lstat, so a dangling symlink still counts as an entry to remove.
            (try? fileManager.attributesOfItem(atPath: $0)) != nil
        }
    }

    /// Deletes the leftovers, then the two per-app folders if nothing else is in them.
    /// Returns what it deleted. Blocking; call it off the main thread.
    @discardableResult
    static func remove(bundleIdentifier: String, libraryPath: String,
                       fileManager: FileManager = .default) -> [String] {
        let found = leftovers(bundleIdentifier: bundleIdentifier, libraryPath: libraryPath, fileManager: fileManager)
        guard !found.isEmpty else { return [] }
        let removed = found.filter { (try? fileManager.removeItem(atPath: $0)) != nil }

        let (cache, storage) = containerPaths(bundleIdentifier: bundleIdentifier, libraryPath: libraryPath)
        for folder in [cache, storage] {
            if let contents = try? fileManager.contentsOfDirectory(atPath: folder), contents.isEmpty {
                try? fileManager.removeItem(atPath: folder)
            }
        }
        return removed
    }

    /// Launch-time entry point: resolves `~/Library` and cleans up on a utility queue.
    static func removeInBackground(bundleIdentifier: String) {
        DispatchQueue.global(qos: .utility).async {
            guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
            let removed = remove(bundleIdentifier: bundleIdentifier, libraryPath: library.path)
            if !removed.isEmpty {
                NSLog("Lightspot: removed %ld HTTP cache and cookie files left by versions up to 1.2.0.", removed.count)
            }
        }
    }

    private static func containerPaths(bundleIdentifier: String, libraryPath: String) -> (cache: String, storage: String) {
        (join(libraryPath, "Caches/\(bundleIdentifier)"), join(libraryPath, "HTTPStorages/\(bundleIdentifier)"))
    }

    private static func join(_ base: String, _ component: String) -> String {
        (base as NSString).appendingPathComponent(component)
    }
}
