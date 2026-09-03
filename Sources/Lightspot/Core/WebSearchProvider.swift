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

    private init() {}

    func search(_ query: SearchQuery) -> [SearchResult] {
        if query.isEmpty { return [] }

        let trimmed = query.trimmed

        // Check for instant prefix match (e.g. "gh react", "yt swift")
        if let prefixResult = matchPrefix(trimmed) {
            return [prefixResult]
        }

        // Generic fallback search with configured default engine
        let engine = defaultEngine
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: String(format: engine.urlTemplate, encoded)) else {
            return []
        }

        return [SearchResult(
            id: "web-\(trimmed)",
            title: "Search \(engine.displayName) for '\(trimmed)'",
            subtitle: engine.domain,
            iconType: .systemSymbol(name: "globe"),
            category: .webSearch,
            score: 30,
            action: .openWebSearch(url: url)
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

        guard let encoded = queryPart.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
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
