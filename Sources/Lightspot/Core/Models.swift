import AppKit

// MARK: - Result Category

enum ResultCategory: Int, CaseIterable, Sendable, Codable {
    case topHit = 0
    case applications = 1
    case recentProjects = 8
    case systemSettings = 2
    case quickActions = 3
    case customCommands = 7
    case shellHistory = 4
    case devTools = 9
    case browser = 10
    case clipboard = 11
    case snippets = 12
    case calculator = 5
    case webSearch = 6

    var displayName: String {
        switch self {
        case .topHit: return "Top Hit"
        case .applications: return "Applications"
        case .recentProjects: return "Recent Projects"
        case .systemSettings: return "System Settings"
        case .quickActions: return "Quick Actions"
        case .customCommands: return "Custom Commands"
        case .shellHistory: return "Terminal History"
        case .devTools: return "Developer Tools"
        case .browser: return "Browser History & Bookmarks"
        case .clipboard: return "Clipboard History"
        case .snippets: return "Text Snippets"
        case .calculator: return "Calculator"
        case .webSearch: return "Web Search"
        }
    }
}

// MARK: - Browser History Option

public enum BrowserHistoryDays: Int, CaseIterable, Identifiable, Sendable, Codable {
    case disabled = 0
    case threeDays = 3
    case sevenDays = 7

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .disabled: return "Disabled"
        case .threeDays: return "Last 3 Days"
        case .sevenDays: return "Last 7 Days"
        }
    }
}

// MARK: - Search Enums

enum ResultIconType: Sendable, Hashable, Codable {
    case app(path: String)
    case systemSymbol(name: String)
    case customImage(base64: String)
}

enum SearchAction: Sendable, Codable {
    case launchApp(path: String)
    case openSettings(deepLink: String)
    case runQuickAction(script: String, usesOsascript: Bool)
    case copyToClipboard(String)
    case openWebSearch(url: URL)
    case runInTerminal(command: String)
    case openURL(url: URL)
    case openFolder(path: String)
    case openProject(path: String, appBundleID: String?)
    case killProcess(pid: Int32, name: String, force: Bool)
}

// MARK: - Search Result

struct SearchResult: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let iconType: ResultIconType
    let category: ResultCategory
    let score: Double
    let action: SearchAction
    /// Only ever true for `.shellHistory` results the user has pinned. Declared
    /// `var` with a default so the memberwise initializer stays source-compatible
    /// with the providers that do not care about pinning.
    var isPinned: Bool = false

    func withScore(_ newScore: Double) -> SearchResult {
        SearchResult(
            id: id,
            title: title,
            subtitle: subtitle,
            iconType: iconType,
            category: category,
            score: newScore,
            action: action,
            isPinned: isPinned
        )
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // Identity is the id, plus the one field that can change under a stable id:
    // pinning a Terminal History result rewrites `isPinned` while the row keeps its
    // id. Without it here, SwiftUI's diffing (and `performSearch`'s change check)
    // would consider the toggled row unchanged and skip the redraw.
    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
        lhs.id == rhs.id && lhs.isPinned == rhs.isPinned
    }
}

// MARK: - App Category (macOS 27 Categories)

enum AppCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case productivity = "Productivity & Finance"
    case utilities = "Utilities"
    case entertainment = "Entertainment"
    case social = "Social"
    case creativity = "Creativity"
    case developerTools = "Developer Tools"
    case infoReading = "Information & Reading"
    case other = "Other"

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .all: return "All"
        case .productivity: return "Productivity & Finance"
        case .utilities: return "Utilities"
        case .entertainment: return "Entertainment"
        case .social: return "Social"
        case .creativity: return "Creativity"
        case .developerTools: return "Developer Tools"
        case .infoReading: return "Information & Reading"
        case .other: return "Other"
        }
    }

    var iconName: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .productivity: return "briefcase.fill"
        case .utilities: return "wrench.and.screwdriver.fill"
        case .entertainment: return "play.tv.fill"
        case .social: return "message.fill"
        case .creativity: return "paintpalette.fill"
        case .developerTools: return "hammer.fill"
        case .infoReading: return "book.fill"
        case .other: return "folder.fill"
        }
    }
}

// MARK: - App Info (cached application data)

struct AppInfo: Sendable, Identifiable, Hashable {
    var id: String { bundleIdentifier }
    let name: String
    let lowercaseName: String
    let searchTokens: [String]
    let initials: String
    let bundleIdentifier: String
    let path: String
    let category: AppCategory
    
    init(name: String, bundleIdentifier: String, path: String, category: AppCategory) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.path = path
        self.category = category
        
        let lower = name.lowercased()
        self.lowercaseName = lower
        self.searchTokens = lower.split(separator: " ").map(String.init)
        self.initials = String(self.searchTokens.compactMap { $0.first })
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleIdentifier)
    }
}

// MARK: - Settings Item

struct SettingsItem: Sendable {
    let id: String
    let name: String
    let lowercaseName: String
    let lowercaseKeywords: [String]
    let sfSymbol: String
    let deepLink: String
    let subtitle: String
    
    init(name: String, keywords: [String], sfSymbol: String, deepLink: String, subtitle: String) {
        let lower = name.lowercased()
        self.id = "settings-\(lower.replacingOccurrences(of: " ", with: "-"))"
        self.name = name
        self.lowercaseName = lower
        self.lowercaseKeywords = keywords.map { $0.lowercased() }
        self.sfSymbol = sfSymbol
        self.deepLink = deepLink
        self.subtitle = subtitle
    }
}

// MARK: - Quick Action

struct QuickAction: Sendable {
    let id: String
    let name: String
    let lowercaseName: String
    let lowercaseKeywords: [String]
    let sfSymbol: String
    let subtitle: String
    let script: String
    let usesOsascript: Bool
    
    init(name: String, keywords: [String], sfSymbol: String, subtitle: String, script: String, usesOsascript: Bool) {
        let lower = name.lowercased()
        self.id = "action-\(lower.replacingOccurrences(of: " ", with: "-"))"
        self.name = name
        self.lowercaseName = lower
        self.lowercaseKeywords = keywords.map { $0.lowercased() }
        self.sfSymbol = sfSymbol
        self.subtitle = subtitle
        self.script = script
        self.usesOsascript = usesOsascript
    }
}

// MARK: - Search Query State

struct SearchQuery: Sendable {
    let raw: String
    let trimmed: String
    let lowercased: String
    
    init(_ query: String) {
        self.raw = query
        self.trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lowercased = self.trimmed.lowercased()
    }
    
    var isEmpty: Bool { trimmed.isEmpty }
}

// MARK: - Fuzzy Match Scoring

enum FuzzyMatcher {
    /// Zero-allocation scoring against pre-computed target tokens
    /// `minimumScore` lets a caller that will discard anything below a threshold skip
    /// the tiers that cannot reach it. This matters for the subsequence tier, whose
    /// scan is O(target) and runs for every *non*-matching candidate: a provider with
    /// a 55 cutoff would pay for it on every item and then throw the result away.
    static func score(query: SearchQuery, targetLower: String, targetTokens: [String], targetInitials: String? = nil, minimumScore: Double = 0) -> Double? {
        let q = query.lowercased
        if q.isEmpty { return nil }
        
        // Exact match
        if targetLower == q { return 100 }
        if minimumScore > 95 { return nil }
        
        // Prefix match
        if targetLower.hasPrefix(q) { return 95 }
        if minimumScore > 85 { return nil }
        
        // Word-boundary prefix match (e.g. "act" matches "Activity Monitor")
        for word in targetTokens {
            if word.hasPrefix(q) {
                return 85
            }
        }
        if minimumScore > 80 { return nil }
        
        // Initials match
        if let initials = targetInitials, initials.hasPrefix(q) {
            return 80
        }
        if minimumScore > 65 { return nil }
        
        // Fast direct substring contains match (avoids expensive locale collation)
        if targetLower.contains(q) {
            return 65
        }
        if minimumScore > 40 { return nil }
        
        // Fuzzy subsequence match
        var qIdx = q.startIndex
        for char in targetLower {
            if qIdx < q.endIndex && char == q[qIdx] {
                qIdx = q.index(after: qIdx)
            }
        }
        if qIdx == q.endIndex {
            return 40
        }
        
        return nil
    }
}
