import AppKit

// MARK: - Search Engine Option

public enum SearchEngineOption: String, CaseIterable, Identifiable, Sendable {
    case google = "google"
    case duckDuckGo = "duckduckgo"
    case kagi = "kagi"
    case bing = "bing"
    case brave = "brave"
    case ecosia = "ecosia"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .google: return "Google"
        case .duckDuckGo: return "DuckDuckGo"
        case .kagi: return "Kagi"
        case .bing: return "Bing"
        case .brave: return "Brave Search"
        case .ecosia: return "Ecosia"
        }
    }

    public var domain: String {
        switch self {
        case .google: return "www.google.com"
        case .duckDuckGo: return "duckduckgo.com"
        case .kagi: return "kagi.com"
        case .bing: return "www.bing.com"
        case .brave: return "search.brave.com"
        case .ecosia: return "www.ecosia.org"
        }
    }

    public var urlTemplate: String {
        switch self {
        case .google: return "https://www.google.com/search?q=%@"
        case .duckDuckGo: return "https://duckduckgo.com/?q=%@"
        case .kagi: return "https://kagi.com/search?q=%@"
        case .bing: return "https://www.bing.com/search?q=%@"
        case .brave: return "https://search.brave.com/search?q=%@"
        case .ecosia: return "https://www.ecosia.org/search?q=%@"
        }
    }
}

// MARK: - Web Search Prefix Definition

public struct WebSearchPrefix: Sendable {
    public let prefix: String
    public let name: String
    public let domain: String
    public let urlTemplate: String
    public let sfSymbol: String

    public init(prefix: String, name: String, domain: String, urlTemplate: String, sfSymbol: String = "globe") {
        self.prefix = prefix
        self.name = name
        self.domain = domain
        self.urlTemplate = urlTemplate
        self.sfSymbol = sfSymbol
    }
}

// MARK: - Web Search Provider

public final class WebSearchProvider: @unchecked Sendable {
    public static let shared = WebSearchProvider()

    private let userDefaultsKey = "lightspot_search_engine"
    private let lock = NSLock()

    public static let builtInPrefixes: [WebSearchPrefix] = [
        WebSearchPrefix(prefix: "g", name: "Google", domain: "google.com", urlTemplate: "https://www.google.com/search?q=%@"),
        WebSearchPrefix(prefix: "ddg", name: "DuckDuckGo", domain: "duckduckgo.com", urlTemplate: "https://duckduckgo.com/?q=%@"),
        WebSearchPrefix(prefix: "gh", name: "GitHub", domain: "github.com", urlTemplate: "https://github.com/search?q=%@&type=repositories", sfSymbol: "chevron.left.forwardslash.chevron.right"),
        WebSearchPrefix(prefix: "yt", name: "YouTube", domain: "youtube.com", urlTemplate: "https://www.youtube.com/results?search_query=%@", sfSymbol: "play.rectangle.fill"),
        WebSearchPrefix(prefix: "so", name: "Stack Overflow", domain: "stackoverflow.com", urlTemplate: "https://stackoverflow.com/search?q=%@", sfSymbol: "questionmark.circle.fill"),
        WebSearchPrefix(prefix: "npm", name: "npm", domain: "npmjs.com", urlTemplate: "https://www.npmjs.com/search?q=%@", sfSymbol: "shippingbox.fill"),
        WebSearchPrefix(prefix: "crates", name: "crates.io", domain: "crates.io", urlTemplate: "https://crates.io/search?q=%@", sfSymbol: "cube.fill"),
        WebSearchPrefix(prefix: "wiki", name: "Wikipedia", domain: "wikipedia.org", urlTemplate: "https://en.wikipedia.org/w/index.php?search=%@", sfSymbol: "book.fill"),
        WebSearchPrefix(prefix: "mdn", name: "MDN Web Docs", domain: "developer.mozilla.org", urlTemplate: "https://developer.mozilla.org/en-US/search?q=%@", sfSymbol: "doc.text.magnifyingglass"),
        WebSearchPrefix(prefix: "brew", name: "Homebrew", domain: "formulae.brew.sh", urlTemplate: "https://formulae.brew.sh/formula/%@", sfSymbol: "mug.fill")
    ]

    public var defaultEngine: SearchEngineOption {
        get {
            lock.lock()
            defer { lock.unlock() }
            if let saved = UserDefaults.standard.string(forKey: userDefaultsKey),
               let option = SearchEngineOption(rawValue: saved) {
                return option
            }
            return .google
        }
        set {
            lock.lock()
            UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey)
            lock.unlock()
        }
    }

    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private static let nonDomainExtensions: Set<String> = [
        "txt", "pdf", "png", "jpg", "jpeg", "gif", "svg", "webp", "zip", "tar", "gz", "rar", "7z",
        "dmg", "iso", "mp3", "mp4", "mov", "wav", "flac", "json", "xml", "csv", "tsv", "yaml", "yml",
        "md", "swift", "py", "rs", "go", "c", "cpp", "h", "js", "ts", "jsx", "tsx", "html", "css",
        "java", "kt", "rb", "php", "sh", "bat", "exe", "bin", "dylib", "lock", "log"
    ]

    private static let modernTLDs: Set<String> = [
        "dev", "app", "io", "ai", "co", "me", "tech", "site", "online", "xyz", "cloud",
        "design", "studio", "live", "store", "shop", "blog", "space", "guru", "agency",
        "run", "page", "wiki", "life", "world", "zone", "cc", "tv", "gg", "fm", "is", "to", "ly"
    ]

    private static let ipv4Pattern = "^((25[0-5]|(2[0-4]|1\\d|[1-9]|)\\d)\\.){3}(25[0-5]|(2[0-4]|1\\d|[1-9]|)\\d)(:\\d+)?(/.*)?$"

    public static func detectURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains(where: { $0.isWhitespace || $0.isNewline }) {
            return nil
        }

        let lower = trimmed.lowercased()

        // 1. Explicit scheme
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            if let url = URL(string: trimmed), let host = url.host, !host.isEmpty {
                return url
            }
            return nil
        }

        // 2. Localhost
        if lower == "localhost" || lower.hasPrefix("localhost:") || lower.hasPrefix("localhost/") {
            return URL(string: "http://\(trimmed)")
        }

        // 3. IPv4 address
        if trimmed.range(of: ipv4Pattern, options: .regularExpression) != nil {
            return URL(string: "http://\(trimmed)")
        }

        // 4. Domain with TLD
        guard trimmed.contains(".") else { return nil }

        let hostPart = trimmed.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let hostWithoutPort = String(hostPart.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)[0])
        let labels = hostWithoutPort.split(separator: ".")
        guard labels.count >= 2 else { return nil }

        let isAllNumbers = labels.allSatisfy { Int($0) != nil }
        if isAllNumbers { return nil }

        guard let lastLabel = labels.last else { return nil }
        let tld = String(lastLabel).lowercased()
        guard tld.count >= 2, tld.allSatisfy({ $0.isLetter }) else { return nil }
        if nonDomainExtensions.contains(tld) { return nil }

        let testString = "https://\(trimmed)"
        var isValid = false
        if let detector = linkDetector {
            let matches = detector.matches(in: testString, options: [], range: NSRange(location: 0, length: testString.utf16.count))
            if matches.contains(where: { $0.range.location == 0 && $0.range.length == testString.utf16.count }) {
                isValid = true
            }
        }

        if !isValid && modernTLDs.contains(tld) {
            isValid = true
        }

        return isValid ? URL(string: testString) : nil
    }

    func search(_ query: SearchQuery) -> [SearchResult] {
        if query.isEmpty { return [] }

        let trimmed = query.trimmed

        // Check for instant prefix match (e.g. "gh react", "yt swift")
        if let prefixResult = matchPrefix(trimmed) {
            return [prefixResult]
        }

        let engine = defaultEngine
        let searchURL: URL? = {
            guard let encoded = URLQueryEncoder.encode(trimmed) else { return nil }
            return URL(string: String(format: engine.urlTemplate, encoded))
        }()

        // Check for auto-detected direct URL (e.g. "facebook.com", "localhost:3000", "https://...")
        if let detectedURL = Self.detectURL(trimmed) {
            var results: [SearchResult] = [
                SearchResult(
                    id: "web-url-\(trimmed)",
                    title: "Open \(trimmed)",
                    subtitle: detectedURL.absoluteString,
                    iconType: .systemSymbol(name: "globe"),
                    category: .webSearch,
                    score: 95,
                    action: .openURL(url: detectedURL)
                )
            ]

            // Include fallback search option if applicable
            let hasExplicitScheme = trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://")
            if !hasExplicitScheme, let searchURL {
                results.append(SearchResult(
                    id: "web-\(trimmed)",
                    title: "Search \(engine.displayName) for '\(trimmed)'",
                    subtitle: engine.domain,
                    iconType: .systemSymbol(name: "globe"),
                    category: .webSearch,
                    score: 25,
                    action: .openWebSearch(url: searchURL)
                ))
            }
            return results
        }

        // Generic fallback search with configured default engine
        guard let searchURL else { return [] }

        return [SearchResult(
            id: "web-\(trimmed)",
            title: "Search \(engine.displayName) for '\(trimmed)'",
            subtitle: engine.domain,
            iconType: .systemSymbol(name: "globe"),
            category: .webSearch,
            score: 30,
            action: .openWebSearch(url: searchURL)
        )]
    }

    private func matchPrefix(_ trimmed: String) -> SearchResult? {
        // Split on first whitespace
        guard let spaceIdx = trimmed.firstIndex(of: " ") else {
            return nil
        }

        let prefixPart = String(trimmed[..<spaceIdx]).lowercased()
        let queryPart = String(trimmed[trimmed.index(after: spaceIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !queryPart.isEmpty else { return nil }

        guard let matched = Self.builtInPrefixes.first(where: { $0.prefix == prefixPart }) else {
            return nil
        }

        guard let encoded = URLQueryEncoder.encode(queryPart),
              let url = URL(string: String(format: matched.urlTemplate, encoded)) else {
            return nil
        }

        return SearchResult(
            id: "web-prefix-\(matched.prefix)-\(queryPart)",
            title: "Search \(matched.name) for '\(queryPart)'",
            subtitle: "\(matched.domain) · '\(matched.prefix)' shortcut",
            iconType: .systemSymbol(name: matched.sfSymbol),
            category: .webSearch,
            score: 95,
            action: .openWebSearch(url: url)
        )
    }
}
