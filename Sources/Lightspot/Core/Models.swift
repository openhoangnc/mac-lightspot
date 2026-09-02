import AppKit

// MARK: - Result Category

enum ResultCategory: Int, CaseIterable, Sendable {
    case topHit = 0
    case applications
    case systemSettings
    case quickActions
    case calculator
    case webSearch

    var displayName: String {
        switch self {
        case .topHit: return "Top Hit"
        case .applications: return "Applications"
        case .systemSettings: return "System Settings"
        case .quickActions: return "Quick Actions"
        case .calculator: return "Calculator"
        case .webSearch: return "Web Search"
        }
    }
}

// MARK: - Search Result

final class SearchResult: Identifiable, @unchecked Sendable {
    let id: String
    let title: String
    let subtitle: String
    let icon: NSImage?
    let category: ResultCategory
    let score: Double
    let action: @Sendable () -> Void

    init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String = "",
        icon: NSImage? = nil,
        category: ResultCategory,
        score: Double = 0,
        action: @escaping @Sendable () -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.category = category
        self.score = score
        self.action = action
    }
}

extension SearchResult: Hashable {
    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - App Info (cached application data)

struct AppInfo: Sendable {
    let name: String
    let bundleIdentifier: String
    let path: String
    let icon32: NSImage
    let icon128: NSImage
}

// MARK: - Settings Item

struct SettingsItem: Sendable {
    let name: String
    let keywords: [String]
    let sfSymbol: String
    let deepLink: String
    let subtitle: String
}

// MARK: - Quick Action

struct QuickAction: Sendable {
    let name: String
    let keywords: [String]
    let sfSymbol: String
    let subtitle: String
    let script: String
    let usesOsascript: Bool // true = osascript, false = direct command
}

// MARK: - Fuzzy Match Scoring

enum FuzzyMatcher {
    /// Returns a score 0-100, or nil if no match at all
    static func score(query: String, target: String) -> Double? {
        let q = query.lowercased()
        let t = target.lowercased()

        if q.isEmpty { return nil }

        // Exact match
        if t == q { return 100 }

        // Prefix match
        if t.hasPrefix(q) { return 95 }

        // Word-boundary prefix match (e.g. "act" matches "Activity Monitor")
        let words = t.split(separator: " ").map(String.init)
        for word in words {
            if word.lowercased().hasPrefix(q) {
                return 85
            }
        }

        // Initials match (e.g. "am" matches "Activity Monitor")
        if words.count >= 2 {
            let initials = String(words.compactMap { $0.first }).lowercased()
            if initials.hasPrefix(q) {
                return 80
            }
        }

        // Contains match
        if t.localizedStandardContains(q) {
            return 65
        }

        // Fuzzy subsequence match
        var qIdx = q.startIndex
        for char in t {
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
