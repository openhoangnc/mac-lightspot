import AppKit
import Foundation
import SQLite3

// MARK: - Browser Item Model

public struct BrowserItem: Sendable, Hashable {
    public enum ItemType: String, Sendable {
        case bookmark = "Bookmark"
        case openTab = "Open Tab"
        case history = "History"
    }

    public let title: String
    public let urlString: String
    public let url: URL
    public let itemType: ItemType
    public let browserName: String
    public let browserAppPath: String?

    public let lowercaseTitle: String
    public let titleTokens: [String]
    public let host: String
    public let displayURL: String
    public let pathTokens: [String]

    public init(
        title: String,
        urlString: String,
        itemType: ItemType,
        browserName: String,
        browserAppPath: String?
    ) {
        self.title = title
        self.urlString = urlString
        self.url = URL(string: urlString) ?? URL(string: "about:blank")!
        self.itemType = itemType
        self.browserName = browserName
        self.browserAppPath = browserAppPath

        let lower = title.lowercased()
        self.lowercaseTitle = lower
        let separators = CharacterSet(charactersIn: " -_.:/[]()")
        self.titleTokens = lower.components(separatedBy: separators).filter { !$0.isEmpty }
        self.host = self.url.host?.lowercased() ?? ""
        self.displayURL = BrowserIntegrationProvider.formatDisplayURL(urlString)

        let urlLower = urlString.lowercased()
        let pathSeps = CharacterSet(charactersIn: " /?&=#-_.:")
        self.pathTokens = urlLower.components(separatedBy: pathSeps).filter { !$0.isEmpty && $0 != "http" && $0 != "https" }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(urlString)
        hasher.combine(itemType.rawValue)
    }

    public static func == (lhs: BrowserItem, rhs: BrowserItem) -> Bool {
        lhs.urlString == rhs.urlString && lhs.itemType == rhs.itemType
    }
}

// MARK: - Browser Integration Provider

public final class BrowserIntegrationProvider: @unchecked Sendable {
    public static let shared = BrowserIntegrationProvider()

    private let lock = NSLock()
    private var cachedBookmarks: [BrowserItem] = []
    private var bookmarksSignature: String = ""
    private var isRefreshingBookmarks = false
    private var cachedTabs: [BrowserItem] = []
    private var lastTabsQuery: Date = .distantPast
    private var isRefreshingTabs = false

    private let historyDefaultsKey = "lightspot_browser_history_days"
    private var cachedHistory: [BrowserItem] = []
    private var historySignature: String = ""
    private var isRefreshingHistory = false
    private var lastHistoryCheck: Date = .distantPast
    private let historyCheckInterval: TimeInterval = 10.0

    /// NSAppleScript is not thread-safe, so every tab query is serialized here.
    /// It must never run on the main thread: querying Chrome/Safari for open tabs
    /// measures ~300 ms, and search() runs on every keystroke.
    private let tabsQueue = DispatchQueue(label: "com.lightspot.browser.tabs", qos: .utility)
    private let bookmarksQueue = DispatchQueue(label: "com.lightspot.browser.bookmarks", qos: .utility)
    private let historyQueue = DispatchQueue(label: "com.lightspot.browser.history", qos: .utility)
    private let tabsStaleInterval: TimeInterval = 5.0
    private let bookmarksCheckInterval: TimeInterval = 2.0
    private var lastBookmarksCheck: Date = .distantPast

    public var historyLimitDays: BrowserHistoryDays {
        get {
            lock.lock()
            defer { lock.unlock() }
            let val = UserDefaults.standard.object(forKey: historyDefaultsKey) as? Int ?? BrowserHistoryDays.sevenDays.rawValue
            return BrowserHistoryDays(rawValue: val) ?? .sevenDays
        }
        set {
            lock.lock()
            UserDefaults.standard.set(newValue.rawValue, forKey: historyDefaultsKey)
            cachedHistory = []
            historySignature = ""
            lastHistoryCheck = .distantPast
            lock.unlock()
            refreshHistoryIfNeeded(force: true)
        }
    }

    private init() {}

    /// Primes all caches without blocking. Call when the panel is shown so the
    /// first keystroke already has data to match against.
    public func warmUp() {
        refreshBookmarksIfNeeded()
        refreshHistoryIfNeeded()
        _ = cachedTabsRefreshingIfStale()
    }

    // MARK: - URL Formatting

    public static func formatDisplayURL(_ urlString: String) -> String {
        guard let url = URL(string: urlString) else {
            return urlString
        }
        let host = url.host ?? ""
        var pathAndQuery = url.path
        if let query = url.query, !query.isEmpty {
            pathAndQuery += "?\(query)"
        }
        if pathAndQuery == "/" {
            pathAndQuery = ""
        }
        let formatted = host + pathAndQuery
        if !formatted.isEmpty {
            return formatted
        }
        if urlString.hasPrefix("https://") {
            return String(urlString.dropFirst("https://".count))
        } else if urlString.hasPrefix("http://") {
            return String(urlString.dropFirst("http://".count))
        }
        return urlString
    }

    // MARK: - Default Browser Resolution

    public static func defaultBrowser() -> (name: String, bundleID: String, appPath: String)? {
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://apple.com")!),
              let bundle = Bundle(url: appURL),
              let bundleID = bundle.bundleIdentifier else {
            return nil
        }
        let name = bundle.infoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle.infoDictionary?["CFBundleName"] as? String
            ?? appURL.deletingPathExtension().lastPathComponent
        return (name, bundleID, appURL.path)
    }

    // MARK: - Search

    func search(_ query: SearchQuery) -> [SearchResult] {
        guard query.trimmed.count >= 2 else { return [] }

        // All calls return immediately; all real work happens off the keystroke
        // path. Nothing here may block — search() runs on every keystroke.
        refreshBookmarksIfNeeded()
        refreshHistoryIfNeeded()
        let tabs = cachedTabsRefreshingIfStale()

        lock.lock()
        let bookmarks = cachedBookmarks
        let history = cachedHistory
        lock.unlock()

        var seenURLs = Set<String>()
        var allItems: [BrowserItem] = []
        allItems.reserveCapacity(tabs.count + bookmarks.count + history.count)

        // 1. Open tabs have highest priority
        for tab in tabs {
            if seenURLs.insert(tab.urlString).inserted {
                allItems.append(tab)
            }
        }

        // 2. Bookmarks have next priority
        for bm in bookmarks {
            if seenURLs.insert(bm.urlString).inserted {
                allItems.append(bm)
            }
        }

        // 3. History has standard priority
        for h in history {
            if seenURLs.insert(h.urlString).inserted {
                allItems.append(h)
            }
        }

        guard !allItems.isEmpty else { return [] }

        var matches: [(item: BrowserItem, score: Double)] = []
        matches.reserveCapacity(allItems.count)

        // Anything under `acceptThreshold` is discarded below, so tell the matcher not
        // to bother with tiers that cannot survive the weighting applied to each field.
        let acceptThreshold = 55.0
        let hostFloor = acceptThreshold / 0.9
        let pathFloor = acceptThreshold / 0.85

        for item in allItems {
            // Match against title
            var score = FuzzyMatcher.score(
                query: query,
                targetLower: item.lowercaseTitle,
                targetTokens: item.titleTokens,
                targetInitials: nil,
                minimumScore: acceptThreshold
            )

            // Or match against host domain (e.g. "github", "twitter")
            if score == nil && !item.host.isEmpty {
                if let hScore = FuzzyMatcher.score(query: query, targetLower: item.host, targetTokens: [], targetInitials: nil, minimumScore: hostFloor) {
                    score = hScore * 0.9
                }
            }

            // Or match against path tokens in the detail URL (e.g. "stores", "apps")
            if score == nil {
                for token in item.pathTokens {
                    if let pScore = FuzzyMatcher.score(query: query, targetLower: token, targetTokens: [], targetInitials: nil, minimumScore: pathFloor) {
                        let weighted = pScore * 0.85
                        if let current = score {
                            score = max(current, weighted)
                        } else {
                            score = weighted
                        }
                    }
                }
            }

            if let s = score, s >= acceptThreshold {
                // Boost open tabs vs bookmarks vs history
                let finalScore: Double
                switch item.itemType {
                case .openTab:
                    finalScore = min(s + 5.0, 99.0)
                case .bookmark:
                    finalScore = s
                case .history:
                    finalScore = max(s - 2.0, acceptThreshold)
                }
                matches.append((item, finalScore))
            }
        }

        matches.sort { $0.score > $1.score }

        return matches.prefix(8).map { match in
            let item = match.item
            let icon: ResultIconType = item.browserAppPath != nil ? .app(path: item.browserAppPath!) : .systemSymbol(name: "safari.fill")
            let subtitle = "\(item.displayURL) · \(item.itemType.rawValue) · \(item.browserName)"

            return SearchResult(
                id: "browser-\(item.itemType.rawValue)-\(item.urlString)",
                title: item.title.isEmpty ? item.displayURL : item.title,
                subtitle: subtitle,
                iconType: icon,
                category: .browser,
                score: match.score,
                action: .openURL(url: item.url)
            )
        }
    }

    // MARK: - Bookmarks Parsing (Default Browser Only)

    /// Re-parses bookmarks only when the source file actually changed. This used to
    /// dispatch a full parse on every keystroke (~12 ms of CPU for 337 bookmarks),
    /// piling up one background parse per character typed.
    public func refreshBookmarksIfNeeded() {
        guard let (name, bundleID, appPath) = Self.defaultBrowser() else { return }

        lock.lock()
        let tooSoon = Date().timeIntervalSince(lastBookmarksCheck) < bookmarksCheckInterval
        if tooSoon || isRefreshingBookmarks {
            lock.unlock()
            return
        }
        isRefreshingBookmarks = true
        lastBookmarksCheck = Date()
        let knownSignature = bookmarksSignature
        lock.unlock()

        bookmarksQueue.async { [weak self] in
            guard let self = self else { return }
            defer {
                self.lock.lock()
                self.isRefreshingBookmarks = false
                self.lock.unlock()
            }

            // Skip the parse entirely when the file has not changed.
            let signature = Self.bookmarksSignature(bundleID: bundleID)
            if let signature, signature == knownSignature { return }

            let loaded = Self.loadDefaultBrowserBookmarks(name: name, bundleID: bundleID, appPath: appPath)
            self.lock.lock()
            self.cachedBookmarks = loaded
            if let signature { self.bookmarksSignature = signature }
            self.lock.unlock()
        }
    }

    /// mtime+size of the bookmark source, or nil when the location is not a single
    /// known file (Firefox rotates backup files), in which case we always re-parse.
    private static func bookmarksSignature(bundleID: String) -> String? {
        let home = NSHomeDirectory()
        let path: String
        switch bundleID {
        case "com.google.Chrome":
            path = "\(home)/Library/Application Support/Google/Chrome/Default/Bookmarks"
        case "com.brave.Browser":
            path = "\(home)/Library/Application Support/BraveSoftware/Brave-Browser/Default/Bookmarks"
        case "com.microsoft.edgemac":
            path = "\(home)/Library/Application Support/Microsoft Edge/Default/Bookmarks"
        case "company.thebrowser.Browser":
            path = "\(home)/Library/Application Support/Arc/StorableSidebar.json"
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
            path = "\(home)/Library/Safari/Bookmarks.plist"
        default:
            return nil
        }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        return "\(mtime)-\(size)"
    }

    public static func loadDefaultBrowserBookmarks(name: String, bundleID: String, appPath: String) -> [BrowserItem] {
        let home = NSHomeDirectory()
        let fm = FileManager.default

        // 1. Google Chrome
        if bundleID == "com.google.Chrome" {
            let path = "\(home)/Library/Application Support/Google/Chrome/Default/Bookmarks"
            return parseChromiumBookmarks(filePath: path, browserName: name, appPath: appPath)
        }

        // 2. Brave
        if bundleID == "com.brave.Browser" {
            let path = "\(home)/Library/Application Support/BraveSoftware/Brave-Browser/Default/Bookmarks"
            return parseChromiumBookmarks(filePath: path, browserName: name, appPath: appPath)
        }

        // 3. Microsoft Edge
        if bundleID == "com.microsoft.edgemac" {
            let path = "\(home)/Library/Application Support/Microsoft Edge/Default/Bookmarks"
            return parseChromiumBookmarks(filePath: path, browserName: name, appPath: appPath)
        }

        // 4. Arc
        if bundleID == "company.thebrowser.Browser" {
            let path = "\(home)/Library/Application Support/Arc/StorableSidebar.json"
            return parseArcBookmarks(filePath: path, browserName: name, appPath: appPath)
        }

        // 5. Safari
        if bundleID == "com.apple.Safari" || bundleID == "com.apple.SafariTechnologyPreview" {
            let path = "\(home)/Library/Safari/Bookmarks.plist"
            if fm.isReadableFile(atPath: path) {
                return parseSafariBookmarks(filePath: path, browserName: name, appPath: appPath)
            }
        }

        // 6. Firefox
        if bundleID == "org.mozilla.firefox" {
            let dir = "\(home)/Library/Application Support/Firefox/Profiles"
            if let profiles = try? fm.contentsOfDirectory(atPath: dir) {
                for prof in profiles {
                    let backupDir = "\(dir)/\(prof)/bookmarkbackups"
                    if let backups = try? fm.contentsOfDirectory(atPath: backupDir) {
                        let sorted = backups.filter { $0.hasSuffix(".json") }.sorted().reversed()
                        if let latest = sorted.first {
                            return parseFirefoxJSON(filePath: "\(backupDir)/\(latest)", browserName: name, appPath: appPath)
                        }
                    }
                }
            }
        }

        return []
    }

    // MARK: - Chromium Bookmarks (Chrome, Brave, Edge)

    private static func parseChromiumBookmarks(filePath: String, browserName: String, appPath: String) -> [BrowserItem] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = json["roots"] as? [String: Any] else {
            return []
        }

        var results: [BrowserItem] = []

        func extract(from node: [String: Any]) {
            if let type = node["type"] as? String {
                if type == "url",
                   let name = node["name"] as? String,
                   let url = node["url"] as? String,
                   !url.hasPrefix("javascript:") {
                    results.append(BrowserItem(
                        title: name,
                        urlString: url,
                        itemType: .bookmark,
                        browserName: browserName,
                        browserAppPath: appPath
                    ))
                } else if type == "folder",
                          let children = node["children"] as? [[String: Any]] {
                    for child in children {
                        extract(from: child)
                    }
                }
            }
        }

        for (_, rootNode) in roots {
            if let node = rootNode as? [String: Any] {
                extract(from: node)
            }
        }

        return results
    }

    // MARK: - Arc Bookmarks

    private static func parseArcBookmarks(filePath: String, browserName: String, appPath: String) -> [BrowserItem] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var results: [BrowserItem] = []

        func recurse(dict: [String: Any]) {
            if let tab = dict["tab"] as? [String: Any],
               let savedURL = tab["savedURL"] as? String,
               let savedTitle = tab["savedTitle"] as? String {
                results.append(BrowserItem(
                    title: savedTitle,
                    urlString: savedURL,
                    itemType: .bookmark,
                    browserName: browserName,
                    browserAppPath: appPath
                ))
            }
            for (_, val) in dict {
                if let subDict = val as? [String: Any] {
                    recurse(dict: subDict)
                } else if let array = val as? [[String: Any]] {
                    for item in array { recurse(dict: item) }
                }
            }
        }

        recurse(dict: json)
        return results
    }

    // MARK: - Safari Bookmarks

    private static func parseSafariBookmarks(filePath: String, browserName: String, appPath: String) -> [BrowserItem] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return []
        }

        var results: [BrowserItem] = []

        func extract(from dict: [String: Any]) {
            if let webBookmarkType = dict["WebBookmarkType"] as? String {
                if webBookmarkType == "WebBookmarkTypeLeaf",
                   let uri = dict["URLString"] as? String,
                   let dictTitle = (dict["URIDictionary"] as? [String: Any])?["title"] as? String {
                    results.append(BrowserItem(
                        title: dictTitle,
                        urlString: uri,
                        itemType: .bookmark,
                        browserName: browserName,
                        browserAppPath: appPath
                    ))
                } else if let children = dict["Children"] as? [[String: Any]] {
                    for child in children {
                        extract(from: child)
                    }
                }
            }
        }

        extract(from: plist)
        return results
    }

    // MARK: - Firefox Bookmarks

    private static func parseFirefoxJSON(filePath: String, browserName: String, appPath: String) -> [BrowserItem] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var results: [BrowserItem] = []

        func extract(from node: [String: Any]) {
            if let uri = node["uri"] as? String,
               let title = node["title"] as? String {
                results.append(BrowserItem(
                    title: title,
                    urlString: uri,
                    itemType: .bookmark,
                    browserName: browserName,
                    browserAppPath: appPath
                ))
            }
            if let children = node["children"] as? [[String: Any]] {
                for child in children {
                    extract(from: child)
                }
            }
        }

        extract(from: json)
        return results
    }

    // MARK: - Open Tabs Query (AppleScript, Throttled to 5s, Running Check)

    /// Returns the cached tabs immediately and kicks a background refresh when they
    /// are stale. Previously this ran the AppleScript inline, so roughly one
    /// keystroke in every five seconds of typing blocked for ~300 ms.
    private func cachedTabsRefreshingIfStale() -> [BrowserItem] {
        lock.lock()
        let current = cachedTabs
        let isStale = Date().timeIntervalSince(lastTabsQuery) > tabsStaleInterval
        let shouldRefresh = isStale && !isRefreshingTabs
        if shouldRefresh {
            isRefreshingTabs = true
            // Claim the slot now so a burst of keystrokes queues only one query.
            lastTabsQuery = Date()
        }
        lock.unlock()

        if shouldRefresh {
            tabsQueue.async { [weak self] in self?.refreshTabsNow() }
        }
        return current
    }

    /// Blocking AppleScript tab query. Only ever called on `tabsQueue`.
    private func refreshTabsNow() {
        func finish(_ items: [BrowserItem]) {
            lock.lock()
            cachedTabs = items
            lastTabsQuery = Date()
            isRefreshingTabs = false
            lock.unlock()
        }

        guard let (name, bundleID, appPath) = Self.defaultBrowser() else { return finish([]) }

        // Only query if the browser is currently running!
        let isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        guard isRunning else { return finish([]) }

        // AppleScript based on browser family
        let scriptSource: String
        if bundleID == "com.apple.Safari" || bundleID == "com.apple.SafariTechnologyPreview" {
            scriptSource = """
            tell application "Safari"
                set output to ""
                repeat with w in windows
                    repeat with t in tabs of w
                        set output to output & (name of t) & "|||" & (URL of t) & "\n"
                    end repeat
                end repeat
                return output
            end tell
            """
        } else {
            // Chromium-based script (Chrome, Brave, Arc, Edge)
            scriptSource = """
            tell application id "\(bundleID)"
                set output to ""
                repeat with w in windows
                    repeat with t in tabs of w
                        set output to output & (title of t) & "|||" & (URL of t) & "\n"
                    end repeat
                end repeat
                return output
            end tell
            """
        }

        var results: [BrowserItem] = []
        if let script = NSAppleScript(source: scriptSource) {
            var error: NSDictionary?
            let descriptor = script.executeAndReturnError(&error)
            if let stringOutput = descriptor.stringValue {
                let lines = stringOutput.components(separatedBy: .newlines)
                for line in lines {
                    let parts = line.components(separatedBy: "|||")
                    if parts.count >= 2 {
                        let title = parts[0].trimmingCharacters(in: .whitespaces)
                        let urlStr = parts[1].trimmingCharacters(in: .whitespaces)
                        if !urlStr.isEmpty && !urlStr.hasPrefix("chrome://") && !urlStr.hasPrefix("edge://") && !urlStr.hasPrefix("about:") {
                            results.append(BrowserItem(
                                title: title.isEmpty ? urlStr : title,
                                urlString: urlStr,
                                itemType: .openTab,
                                browserName: name,
                                browserAppPath: appPath
                            ))
                        }
                    }
                }
            }
        }

        finish(results)
    }

    // MARK: - Browser History Parsing (Default Browser Only)

    public func refreshHistoryIfNeeded(force: Bool = false) {
        guard let (name, bundleID, appPath) = Self.defaultBrowser() else { return }
        let limit = historyLimitDays
        guard limit != .disabled else {
            lock.lock()
            if !cachedHistory.isEmpty { cachedHistory = [] }
            lock.unlock()
            return
        }

        lock.lock()
        let tooSoon = !force && Date().timeIntervalSince(lastHistoryCheck) < historyCheckInterval
        if tooSoon || isRefreshingHistory {
            lock.unlock()
            return
        }
        isRefreshingHistory = true
        lastHistoryCheck = Date()
        let knownSignature = historySignature
        lock.unlock()

        historyQueue.async { [weak self] in
            guard let self = self else { return }
            defer {
                self.lock.lock()
                self.isRefreshingHistory = false
                self.lock.unlock()
            }

            let signature = Self.historySignature(bundleID: bundleID)
            if !force, let signature, signature == knownSignature { return }

            let loaded = Self.loadDefaultBrowserHistory(name: name, bundleID: bundleID, appPath: appPath, days: limit.rawValue)
            self.lock.lock()
            self.cachedHistory = loaded
            if let signature { self.historySignature = signature }
            self.lock.unlock()
        }
    }

    private static func historyFilePath(bundleID: String) -> String? {
        let home = NSHomeDirectory()
        let fm = FileManager.default
        switch bundleID {
        case "com.google.Chrome":
            let p1 = "\(home)/Library/Application Support/Google/Chrome/Default/History"
            if fm.fileExists(atPath: p1) { return p1 }
            let p2 = "\(home)/Library/Application Support/Google/Chrome/Profile 1/History"
            if fm.fileExists(atPath: p2) { return p2 }
            return p1
        case "com.brave.Browser":
            let p1 = "\(home)/Library/Application Support/BraveSoftware/Brave-Browser/Default/History"
            if fm.fileExists(atPath: p1) { return p1 }
            return p1
        case "com.microsoft.edgemac":
            let p1 = "\(home)/Library/Application Support/Microsoft Edge/Default/History"
            if fm.fileExists(atPath: p1) { return p1 }
            return p1
        case "company.thebrowser.Browser":
            let p1 = "\(home)/Library/Application Support/Arc/User Data/Default/History"
            if fm.fileExists(atPath: p1) { return p1 }
            return p1
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
            let p1 = "\(home)/Library/Safari/History.db"
            if fm.fileExists(atPath: p1) { return p1 }
            return p1
        case "org.mozilla.firefox":
            let dir = "\(home)/Library/Application Support/Firefox/Profiles"
            if let profiles = try? fm.contentsOfDirectory(atPath: dir) {
                for prof in profiles {
                    let path = "\(dir)/\(prof)/places.sqlite"
                    if fm.fileExists(atPath: path) { return path }
                }
            }
            return nil
        default:
            return nil
        }
    }

    private static func historySignature(bundleID: String) -> String? {
        guard let path = historyFilePath(bundleID: bundleID),
              let attrs = try? FileManager.default.attributesOfItem(atPath: path) else {
            return nil
        }
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        return "\(mtime)-\(size)"
    }

    public static func loadDefaultBrowserHistory(name: String, bundleID: String, appPath: String, days: Int) -> [BrowserItem] {
        guard days > 0 else { return [] }
        guard let path = historyFilePath(bundleID: bundleID) else { return [] }

        switch bundleID {
        case "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser":
            return parseChromiumHistory(filePath: path, browserName: name, appPath: appPath, days: days)
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
            return parseSafariHistory(filePath: path, browserName: name, appPath: appPath, days: days)
        case "org.mozilla.firefox":
            return parseFirefoxHistory(filePath: path, browserName: name, appPath: appPath, days: days)
        default:
            return []
        }
    }

    private static func parseChromiumHistory(filePath: String, browserName: String, appPath: String, days: Int) -> [BrowserItem] {
        let uri = "file:\(filePath)?mode=ro&immutable=1"
        var db: OpaquePointer?
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_close(db) }

        // Chrome microseconds epoch: Jan 1 1601 UTC
        let cutoffUnix = Date().timeIntervalSince1970 - Double(days * 86400)
        let cutoffChrome = Int64((cutoffUnix * 1_000_000.0) + 11644473600000000.0)

        let query = "SELECT title, url FROM urls WHERE hidden = 0 AND last_visit_time >= ? ORDER BY last_visit_time DESC LIMIT 1500"
        var stmt: OpaquePointer?
        var items: [BrowserItem] = []
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, cutoffChrome)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let title = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                let urlStr = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                if !urlStr.isEmpty &&
                   !urlStr.hasPrefix("chrome://") &&
                   !urlStr.hasPrefix("chrome-extension://") &&
                   !urlStr.hasPrefix("edge://") &&
                   !urlStr.hasPrefix("about:") &&
                   !urlStr.hasPrefix("blob:") {
                    items.append(BrowserItem(
                        title: title.isEmpty ? formatDisplayURL(urlStr) : title,
                        urlString: urlStr,
                        itemType: .history,
                        browserName: browserName,
                        browserAppPath: appPath
                    ))
                }
            }
            sqlite3_finalize(stmt)
        }
        return items
    }

    private static func parseSafariHistory(filePath: String, browserName: String, appPath: String, days: Int) -> [BrowserItem] {
        let uri = "file:\(filePath)?mode=ro&immutable=1"
        var db: OpaquePointer?
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_close(db) }

        // Safari epoch: seconds since Jan 1 2001 (Cocoa reference date)
        let cutoffDate = Date().addingTimeInterval(-Double(days * 86400))
        let cutoffSafari = cutoffDate.timeIntervalSinceReferenceDate

        let query = """
        SELECT history_items.url, history_visits.title
        FROM history_items
        JOIN history_visits ON history_items.id = history_visits.history_item
        WHERE history_visits.visit_time >= ?
        ORDER BY history_visits.visit_time DESC
        LIMIT 1500
        """
        var stmt: OpaquePointer?
        var items: [BrowserItem] = []
        var seen = Set<String>()
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_double(stmt, 1, cutoffSafari)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let urlStr = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                let title = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                if !urlStr.isEmpty && !urlStr.hasPrefix("about:") && !urlStr.hasPrefix("blob:") {
                    if seen.insert(urlStr).inserted {
                        items.append(BrowserItem(
                            title: title.isEmpty ? formatDisplayURL(urlStr) : title,
                            urlString: urlStr,
                            itemType: .history,
                            browserName: browserName,
                            browserAppPath: appPath
                        ))
                    }
                }
            }
            sqlite3_finalize(stmt)
        }
        return items
    }

    private static func parseFirefoxHistory(filePath: String, browserName: String, appPath: String, days: Int) -> [BrowserItem] {
        let uri = "file:\(filePath)?mode=ro&immutable=1"
        var db: OpaquePointer?
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_close(db) }

        // Firefox epoch: microseconds since Jan 1 1970
        let cutoffUnix = Date().timeIntervalSince1970 - Double(days * 86400)
        let cutoffFirefox = Int64(cutoffUnix * 1_000_000.0)

        let query = "SELECT url, title FROM moz_places WHERE hidden = 0 AND last_visit_date >= ? ORDER BY last_visit_date DESC LIMIT 1500"
        var stmt: OpaquePointer?
        var items: [BrowserItem] = []
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, cutoffFirefox)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let urlStr = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                let title = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                if !urlStr.isEmpty && !urlStr.hasPrefix("about:") && !urlStr.hasPrefix("moz-extension://") {
                    items.append(BrowserItem(
                        title: title.isEmpty ? formatDisplayURL(urlStr) : title,
                        urlString: urlStr,
                        itemType: .history,
                        browserName: browserName,
                        browserAppPath: appPath
                    ))
                }
            }
            sqlite3_finalize(stmt)
        }
        return items
    }
}
