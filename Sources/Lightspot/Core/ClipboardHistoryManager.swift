import AppKit
import Foundation

// MARK: - Clipboard Entry Model

public struct ClipboardEntry: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let content: String
    public let timestamp: Date
    public let characterCount: Int
    public let firstLine: String

    public init(content: String, timestamp: Date = Date()) {
        self.id = UUID()
        self.content = content
        self.timestamp = timestamp
        self.characterCount = content.count
        let line = content.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? ""
        self.firstLine = line.isEmpty ? "Empty" : String(line.prefix(80))
    }
}

// MARK: - Clipboard History Manager

public final class ClipboardHistoryManager: @unchecked Sendable {
    public static let shared = ClipboardHistoryManager()

    public static let maxItems = 50

    private let lock = NSLock()
    private var entries: [ClipboardEntry] = []
    private var lastChangeCount: Int = -1
    private var timer: Timer?

    // Sensitive pasteboard types ignored for privacy
    private static let ignoredTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "com.agilebits.onepassword",
        "de.petermaurer.TransientPasteboardType",
        "net.wafflesoftware.KeywordPasteboardType",
        "com.typeit4me.clipping",
        "Pasteboard generator type"
    ]

    private init() {}

    // MARK: - Lifecycle

    public func startMonitoring() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lastChangeCount = NSPasteboard.general.changeCount
            self.timer?.invalidate()
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
                self?.pollPasteboard()
            }
        }
    }

    public func stopMonitoring() {
        DispatchQueue.main.async { [weak self] in
            self?.timer?.invalidate()
            self?.timer = nil
        }
    }

    public func clearHistory() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    public func allEntries() -> [ClipboardEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    // MARK: - Polling

    private func pollPasteboard() {
        let pb = NSPasteboard.general
        let currentCount = pb.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // Check for password manager concealed types
        if let types = pb.types {
            for type in types {
                if Self.ignoredTypes.contains(type.rawValue) {
                    return
                }
            }
        }

        guard let text = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return
        }

        addEntry(content: text)
    }

    public func addEntry(content: String) {
        lock.lock()
        defer { lock.unlock() }

        // Deduplicate top entry
        if let first = entries.first, first.content == content {
            return
        }

        // Remove older duplicates of the exact content
        entries.removeAll { $0.content == content }

        let entry = ClipboardEntry(content: content)
        entries.insert(entry, at: 0)

        if entries.count > Self.maxItems {
            entries = Array(entries.prefix(Self.maxItems))
        }
    }

    // MARK: - Search

    func search(_ query: SearchQuery) -> [SearchResult] {
        let trimmed = query.trimmed
        let lower = query.lowercased

        let isExplicitClip = lower.hasPrefix("clip ") || lower == "clip" || lower == "clipboard"
        let keyword = isExplicitClip && lower.hasPrefix("clip ") ? String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines) : trimmed

        lock.lock()
        let items = entries
        lock.unlock()

        guard !items.isEmpty else { return [] }

        if isExplicitClip && keyword.isEmpty {
            // Return latest 8 clipboard entries
            return items.prefix(8).map { entry in
                SearchResult(
                    id: "clip-\(entry.id.uuidString)",
                    title: entry.firstLine,
                    subtitle: "\(entry.characterCount) characters · Press ↵ to copy",
                    iconType: .systemSymbol(name: "doc.on.clipboard.fill"),
                    category: .clipboard,
                    score: 95,
                    action: .copyToClipboard(entry.content)
                )
            }
        }

        guard keyword.count >= 2 else { return [] }

        let subQuery = SearchQuery(keyword)
        var matches: [(entry: ClipboardEntry, score: Double)] = []

        for entry in items {
            let lowerContent = entry.content.lowercased()
            if let score = FuzzyMatcher.score(query: subQuery, targetLower: lowerContent, targetTokens: [], targetInitials: nil) {
                if score >= 60 {
                    matches.append((entry, score))
                }
            }
        }

        matches.sort { $0.score > $1.score }

        return matches.prefix(5).map { match in
            let entry = match.entry
            return SearchResult(
                id: "clip-\(entry.id.uuidString)",
                title: entry.firstLine,
                subtitle: "\(entry.characterCount) characters · Press ↵ to copy",
                iconType: .systemSymbol(name: "doc.on.clipboard.fill"),
                category: .clipboard,
                score: match.score,
                action: .copyToClipboard(entry.content)
            )
        }
    }
}
