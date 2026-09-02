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
                    subtitle: app.path,
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

    /// Get the large icon for an app by its bundle identifier
    func largeIcon(for bundleID: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        return cachedApps.first(where: { $0.bundleIdentifier == bundleID })?.icon128
    }

    // MARK: - Private

    private func performScan() {
        var apps: [AppInfo] = []
        let fm = FileManager.default
        var seen = Set<String>() // deduplicate by bundle ID

        for scanPath in scanPaths {
            guard let contents = try? fm.contentsOfDirectory(atPath: scanPath) else { continue }
            for item in contents where item.hasSuffix(".app") {
                let fullPath = (scanPath as NSString).appendingPathComponent(item)
                guard let bundle = Bundle(path: fullPath),
                      let bundleID = bundle.bundleIdentifier else { continue }

                guard !seen.contains(bundleID) else { continue }
                seen.insert(bundleID)

                let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? (item as NSString).deletingPathExtension

                let icon = NSWorkspace.shared.icon(forFile: fullPath)
                let icon32 = resizedIcon(icon, to: 32)
                let icon128 = resizedIcon(icon, to: 128)

                apps.append(AppInfo(
                    name: name,
                    bundleIdentifier: bundleID,
                    path: fullPath,
                    icon32: icon32,
                    icon128: icon128
                ))
            }
        }

        apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        lock.lock()
        cachedApps = apps
        lastScanTime = Date()
        lock.unlock()
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

    private static func launchApp(at path: String) {
        let url = URL(fileURLWithPath: path)
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error = error {
                print("Failed to launch app: \(error.localizedDescription)")
            }
        }
    }
}
