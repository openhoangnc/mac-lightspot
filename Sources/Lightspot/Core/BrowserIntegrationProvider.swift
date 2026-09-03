import AppKit
import Foundation

// MARK: - Browser Item Model

public struct BrowserItem: Sendable, Hashable {
    public enum ItemType: String, Sendable {
        case bookmark = "Bookmark"
        case openTab = "Open Tab"
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
    private var cachedTabs: [BrowserItem] = []
    private var lastTabsQuery: Date = .distantPast

    private init() {}

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

        // Refresh bookmarks in background if mtime changed
        refreshBookmarksIfNeeded()

        // Get open tabs if default browser is currently running
        let tabs = getOpenTabsIfRunning()

        lock.lock()
        let bookmarks = cachedBookmarks
        lock.unlock()

        var allItems = tabs
        allItems.append(contentsOf: bookmarks)

        guard !allItems.isEmpty else { return [] }

        var matches: [(item: BrowserItem, score: Double)] = []
        matches.reserveCapacity(allItems.count)

        for item in allItems {
            // Match against title
            var score = FuzzyMatcher.score(
                query: query,
                targetLower: item.lowercaseTitle,
                targetTokens: item.titleTokens,
                targetInitials: nil
            )

            // Or match against host domain (e.g. "github", "twitter")
            if score == nil && !item.host.isEmpty {
                if let hScore = FuzzyMatcher.score(query: query, targetLower: item.host, targetTokens: [], targetInitials: nil) {
                    score = hScore * 0.9
                }
            }

            // Or match against path tokens in the detail URL (e.g. "stores", "apps")
            if score == nil {
                for token in item.pathTokens {
                    if let pScore = FuzzyMatcher.score(query: query, targetLower: token, targetTokens: [], targetInitials: nil) {
                        let weighted = pScore * 0.85
                        if let current = score {
                            score = max(current, weighted)
                        } else {
                            score = weighted
                        }
                    }
                }
            }

            if let s = score, s >= 55 {
                // Boost open tabs vs bookmarks
                let finalScore = item.itemType == .openTab ? min(s + 5.0, 99.0) : s
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

    public func refreshBookmarksIfNeeded() {
        guard let (name, bundleID, appPath) = Self.defaultBrowser() else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let loaded = Self.loadDefaultBrowserBookmarks(name: name, bundleID: bundleID, appPath: appPath)
            self.lock.lock()
            self.cachedBookmarks = loaded
            self.lock.unlock()
        }
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

    private func getOpenTabsIfRunning() -> [BrowserItem] {
        lock.lock()
        let isStale = Date().timeIntervalSince(lastTabsQuery) > 5.0
        if !isStale {
            let current = cachedTabs
            lock.unlock()
            return current
        }
        lock.unlock()

        guard let (name, bundleID, appPath) = Self.defaultBrowser() else { return [] }

        // Only query if the browser is currently running!
        let isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        guard isRunning else {
            lock.lock()
            cachedTabs = []
            lastTabsQuery = Date()
            lock.unlock()
            return []
        }

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

        lock.lock()
        cachedTabs = results
        lastTabsQuery = Date()
        lock.unlock()

        return results
    }
}
