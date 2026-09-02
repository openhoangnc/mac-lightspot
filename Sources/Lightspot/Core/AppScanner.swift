import AppKit

final class AppScanner: @unchecked Sendable {
    static let shared = AppScanner()

    private let lock = NSLock()
    private var cachedApps: [AppInfo] = []
    private var lastScanTime: Date = .distantPast
    private let staleDuration: TimeInterval = 60

    private let scanPaths: [String] = [
        "/Applications",
        "/System/Applications",
        "/System/Applications/Utilities",
        "/System/Library/CoreServices/Applications",
        NSHomeDirectory() + "/Applications"
    ]

    private init() {
        // Initial fast synchronous scan on init or can be triggered
        performScan()
    }

    /// Performs background re-scan
    func startScanning() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.performScan()
        }
    }

    /// Re-scan if cache is stale
    func refreshIfNeeded() {
        var needsRefresh = false
        lock.lock()
        if Date().timeIntervalSince(lastScanTime) > staleDuration {
            needsRefresh = true
        }
        lock.unlock()

        if needsRefresh {
            startScanning()
        }
    }

    /// Search cached apps with fuzzy matching
    func search(_ query: String) -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        lock.lock()
        let apps = cachedApps
        lock.unlock()

        var results: [SearchResult] = []

        for app in apps {
            if let score = FuzzyMatcher.score(query: trimmed, target: app.name) {
                let result = SearchResult(
                    id: "app-\(app.bundleIdentifier)",
                    title: app.name,
                    subtitle: "Application",
                    icon: app.icon32,
                    category: .applications,
                    score: score,
                    action: { [path = app.path] in
                        AppScanner.launchApp(at: path)
                    }
                )
                results.append(result)
            }
        }

        return results.sorted { $0.score > $1.score }
    }

    /// Search cached apps returning AppInfo items
    func searchApps(_ query: String) -> [AppInfo] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        let apps = cachedApps
        lock.unlock()

        guard !trimmed.isEmpty else { return apps }

        var scored: [(app: AppInfo, score: Double)] = []
        for app in apps {
            if let score = FuzzyMatcher.score(query: trimmed, target: app.name) {
                scored.append((app, score))
            }
        }
        return scored.sorted { $0.score > $1.score }.map { $0.app }
    }

    /// Get all scanned apps
    func allApps() -> [AppInfo] {
        lock.lock()
        defer { lock.unlock() }
        return cachedApps
    }

    /// Get apps for a specific category
    func apps(for category: AppCategory) -> [AppInfo] {
        lock.lock()
        defer { lock.unlock() }
        if category == .all {
            return cachedApps
        }
        return cachedApps.filter { $0.category == category }
    }

    /// Get the large icon for an app by its bundle identifier
    func largeIcon(for bundleID: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        return cachedApps.first(where: { $0.bundleIdentifier == bundleID })?.icon128
    }

    // MARK: - Private

    private func findAppBundles(in directory: String, depth: Int = 0, maxDepth: Int = 3) -> [String] {
        guard depth < maxDepth else { return [] }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: directory) else { return [] }

        var appPaths: [String] = []
        for item in contents {
            if item.hasPrefix(".") { continue }
            let fullPath = (directory as NSString).appendingPathComponent(item)
            if item.hasSuffix(".app") {
                appPaths.append(fullPath)
            } else {
                var isDirectory: ObjCBool = false
                if fm.fileExists(atPath: fullPath, isDirectory: &isDirectory), isDirectory.boolValue {
                    let lower = item.lowercased()
                    if !lower.hasSuffix(".framework") && !lower.hasSuffix(".plugin") && !lower.hasSuffix(".bundle") &&
                       lower != "contents" && lower != "frameworks" && lower != "resources" &&
                       lower != ".git" && lower != ".build" && lower != "node_modules" && lower != "build" {
                        appPaths.append(contentsOf: findAppBundles(in: fullPath, depth: depth + 1, maxDepth: maxDepth))
                    }
                }
            }
        }
        return appPaths
    }

    private func performScan() {
        var apps: [AppInfo] = []
        var seenBundleIDs = Set<String>()
        var seenPaths = Set<String>()

        for scanPath in scanPaths {
            let appPaths = findAppBundles(in: scanPath)
            for fullPath in appPaths {
                guard !seenPaths.contains(fullPath) else { continue }
                seenPaths.insert(fullPath)

                let bundle = Bundle(path: fullPath)
                let item = (fullPath as NSString).lastPathComponent
                let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? (item as NSString).deletingPathExtension

                let bundleID = bundle?.bundleIdentifier ?? ("local." + fullPath)

                guard !seenBundleIDs.contains(bundleID) else { continue }
                seenBundleIDs.insert(bundleID)

                let lsCategory = bundle?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
                let category = categorize(name: name, bundleID: bundleID, lsCategory: lsCategory)

                let icon = NSWorkspace.shared.icon(forFile: fullPath)
                let icon32 = resizedIcon(icon, to: 32)
                let icon128 = resizedIcon(icon, to: 128)

                apps.append(AppInfo(
                    name: name,
                    bundleIdentifier: bundleID,
                    path: fullPath,
                    icon32: icon32,
                    icon128: icon128,
                    category: category
                ))
            }
        }

        apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        lock.lock()
        cachedApps = apps
        lastScanTime = Date()
        lock.unlock()
    }

    private func categorize(name: String, bundleID: String, lsCategory: String?) -> AppCategory {
        if let ls = lsCategory?.lowercased() {
            if ls.contains("developer") { return .developerTools }
            if ls.contains("productivity") || ls.contains("finance") || ls.contains("business") { return .productivity }
            if ls.contains("graphics") || ls.contains("photography") || ls.contains("video") || ls.contains("music-creation") { return .creativity }
            if ls.contains("entertainment") || ls.contains("games") || ls.contains("music") { return .entertainment }
            if ls.contains("social") { return .social }
            if ls.contains("news") || ls.contains("books") || ls.contains("education") || ls.contains("reference") || ls.contains("weather") { return .infoReading }
            if ls.contains("utilities") { return .utilities }
        }

        let lower = (name + " " + bundleID).lowercased()
        if lower.contains("code") || lower.contains("antigravity") || lower.contains("claude") ||
           lower.contains("studio") || lower.contains("terminal") || lower.contains("iterm") ||
           lower.contains("warp") || lower.contains("orbstack") || lower.contains("codex") ||
           lower.contains("git") || lower.contains("xcode") || lower.contains("docker") ||
           lower.contains("sublime") || lower.contains("postman") || lower.contains("tableplus") {
            return .developerTools
        }
        if lower.contains("photo") || lower.contains("design") || lower.contains("resolve") ||
           lower.contains("figma") || lower.contains("blend") || lower.contains("draw") ||
           lower.contains("dia") || lower.contains("illustrator") || lower.contains("premiere") ||
           lower.contains("final cut") || lower.contains("logic pro") || lower.contains("garageband") ||
           lower.contains("pixelmator") || lower.contains("affinity") || lower.contains("sketch") {
            return .creativity
        }
        if lower.contains("chat") || lower.contains("message") || lower.contains("facetime") ||
           lower.contains("telegram") || lower.contains("slack") || lower.contains("discord") ||
           lower.contains("zoom") || lower.contains("whatsapp") || lower.contains("signal") ||
           lower.contains("wechat") || lower.contains("teams") {
            return .social
        }
        if lower.contains("safari") || lower.contains("chrome") || lower.contains("arc") ||
           lower.contains("browser") || lower.contains("firefox") || lower.contains("edge") ||
           lower.contains("notes") || lower.contains("calendar") || lower.contains("mail") ||
           lower.contains("clickup") || lower.contains("calc") || lower.contains("notion") ||
           lower.contains("linear") || lower.contains("reminders") || lower.contains("numbers") ||
           lower.contains("pages") || lower.contains("keynote") || lower.contains("excel") ||
           lower.contains("word") || lower.contains("powerpoint") || lower.contains("password") {
            return .productivity
        }
        if lower.contains("book") || lower.contains("news") || lower.contains("weather") ||
           lower.contains("map") || lower.contains("stock") || lower.contains("dictionary") ||
           lower.contains("tips") || lower.contains("grapher") || lower.contains("kindle") {
            return .infoReading
        }
        if lower.contains("util") || lower.contains("cleaner") || lower.contains("stats") ||
           lower.contains("disk") || lower.contains("activity") || lower.contains("console") ||
           lower.contains("airport") || lower.contains("bluetooth") || lower.contains("colorsync") ||
           lower.contains("automator") || lower.contains("audio midi") || lower.contains("font book") ||
           lower.contains("migration") || lower.contains("keychain") {
            return .utilities
        }
        if lower.contains("music") || lower.contains("play") || lower.contains("game") ||
           lower.contains("chess") || lower.contains("tv") || lower.contains("spotify") ||
           lower.contains("vlc") || lower.contains("iina") || lower.contains("steam") ||
           lower.contains("netflix") || lower.contains("disney") {
            return .entertainment
        }

        return .other
    }

    private func resizedIcon(_ image: NSImage, to size: CGFloat) -> NSImage {
        let newImage = NSImage(size: NSSize(width: size, height: size))
        newImage.lockFocus()
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .sourceOver,
                   fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }

    static func launchApp(at path: String) {
        let url = URL(fileURLWithPath: path)
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error = error {
                print("Failed to launch app: \(error.localizedDescription)")
            }
        }
    }
}
