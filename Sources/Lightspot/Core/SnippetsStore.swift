import AppKit
import Foundation

// MARK: - Snippet Model

public struct Snippet: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var name: String
    public var keyword: String
    public var body: String

    public init(id: UUID = UUID(), name: String, keyword: String, body: String) {
        self.id = id
        self.name = name
        self.keyword = keyword
        self.body = body
    }
}

// MARK: - Snippets Store

public final class SnippetsStore: @unchecked Sendable {
    public static let shared = SnippetsStore()

    private static let storageKey = "lightspot_snippets"
    private let lock = NSLock()
    private var cachedSnippets: [Snippet] = []

    private init() {
        loadSnippets()
    }

    // MARK: - Persistence

    private func loadSnippets() {
        lock.lock()
        defer { lock.unlock() }

        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([Snippet].self, from: data) {
            cachedSnippets = decoded
        } else {
            // Seed defaults
            let defaults: [Snippet] = [
                Snippet(name: "Current Date", keyword: "date", body: "{{date}}"),
                Snippet(name: "ISO Timestamp", keyword: "iso", body: "{{iso}}"),
                Snippet(name: "New UUID", keyword: "uuid", body: "{{uuid}}"),
                Snippet(name: "Shrug Emoji", keyword: "shrug", body: "¯\\_(ツ)_/¯"),
                Snippet(name: "Table Flip Emoji", keyword: "flip", body: "(╯°□°)╯︵ ┻━┻")
            ]
            cachedSnippets = defaults
            saveSnippetsLocked()
        }
    }

    private func saveSnippetsLocked() {
        if let data = try? JSONEncoder().encode(cachedSnippets) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    public func allSnippets() -> [Snippet] {
        lock.lock()
        defer { lock.unlock() }
        return cachedSnippets
    }

    public func addSnippet(_ snippet: Snippet) {
        lock.lock()
        cachedSnippets.append(snippet)
        saveSnippetsLocked()
        lock.unlock()
    }

    public func removeSnippet(id: UUID) {
        lock.lock()
        cachedSnippets.removeAll { $0.id == id }
        saveSnippetsLocked()
        lock.unlock()
    }

    // MARK: - Variable Expansion

    public static func expandVariables(in template: String) -> String {
        var expanded = template

        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        if expanded.contains("{{date}}") {
            dateFormatter.dateFormat = "yyyy-MM-dd"
            expanded = expanded.replacingOccurrences(of: "{{date}}", with: dateFormatter.string(from: now))
        }

        if expanded.contains("{{time}}") {
            dateFormatter.dateFormat = "HH:mm:ss"
            expanded = expanded.replacingOccurrences(of: "{{time}}", with: dateFormatter.string(from: now))
        }

        if expanded.contains("{{iso}}") {
            expanded = expanded.replacingOccurrences(of: "{{iso}}", with: ISO8601DateFormatter().string(from: now))
        }

        if expanded.contains("{{uuid}}") {
            expanded = expanded.replacingOccurrences(of: "{{uuid}}", with: UUID().uuidString.lowercased())
        }

        if expanded.contains("{{clipboard}}") {
            let clip = NSPasteboard.general.string(forType: .string) ?? ""
            expanded = expanded.replacingOccurrences(of: "{{clipboard}}", with: clip)
        }

        return expanded
    }

    // MARK: - Search

    func search(_ query: SearchQuery) -> [SearchResult] {
        let trimmed = query.trimmed
        guard !trimmed.isEmpty else { return [] }

        lock.lock()
        let items = cachedSnippets
        lock.unlock()

        let lower = query.lowercased
        var results: [SearchResult] = []

        for snippet in items {
            let lowerKw = snippet.keyword.lowercased()
            let lowerName = snippet.name.lowercased()

            var score: Double?
            if lowerKw == lower {
                score = 96
            } else if lowerKw.hasPrefix(lower) {
                score = 90
            } else if lowerName.contains(lower) {
                score = 75
            }

            if let s = score {
                let expanded = Self.expandVariables(in: snippet.body)
                let preview = expanded.components(separatedBy: .newlines).first ?? expanded

                results.append(SearchResult(
                    id: "snippet-\(snippet.id.uuidString)",
                    title: snippet.name,
                    subtitle: "\(preview) · Press ↵ to copy",
                    iconType: .systemSymbol(name: "text.quote"),
                    category: .snippets,
                    score: s,
                    action: .copyToClipboard(expanded)
                ))
            }
        }

        results.sort { $0.score > $1.score }
        return Array(results.prefix(4))
    }
}
