import Foundation
import AppKit

// MARK: - History & Ranking Models

struct KeywordUsage: Codable, Sendable, Equatable {
    var count: Int
    var lastSelected: Date

    init(count: Int, lastSelected: Date) {
        self.count = count
        self.lastSelected = lastSelected
    }
}

struct ItemUsageRecord: Codable, Sendable, Equatable {
    var totalCount: Int
    var lastSelected: Date
    var keywords: [String: KeywordUsage]

    init(totalCount: Int, lastSelected: Date, keywords: [String: KeywordUsage] = [:]) {
        self.totalCount = totalCount
        self.lastSelected = lastSelected
        self.keywords = keywords
    }
}

struct SearchHistoryEntry: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let itemId: String
    let query: String
    let title: String
    let subtitle: String
    let category: ResultCategory
    let iconType: ResultIconType
    let action: SearchAction
    let selectedAt: Date
    var selectionCount: Int

    init(
        id: String = UUID().uuidString,
        itemId: String,
        query: String,
        title: String,
        subtitle: String,
        category: ResultCategory,
        iconType: ResultIconType,
        action: SearchAction,
        selectedAt: Date = Date(),
        selectionCount: Int = 1
    ) {
        self.id = id
        self.itemId = itemId
        self.query = query
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.iconType = iconType
        self.action = action
        self.selectedAt = selectedAt
        self.selectionCount = selectionCount
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SearchHistoryEntry, rhs: SearchHistoryEntry) -> Bool {
        lhs.id == rhs.id
    }
}

private struct PersistedHistoryData: Codable {
    var entries: [SearchHistoryEntry]
    var itemStats: [String: ItemUsageRecord]
}

// MARK: - Search History Manager

final class SearchHistoryManager: @unchecked Sendable {
    static let shared = SearchHistoryManager()

    static let maxEntries = 200
    static let maxItems = 500
    static let maxKeywordsPerItem = 20

    private let defaultsKey = "lightspot_search_history"
    private let lock = NSLock()
    private let persistQueue = DispatchQueue(label: "com.lightspot.searchhistory", qos: .utility)

    private var cachedEntries: [SearchHistoryEntry]
    private var cachedItemStats: [String: ItemUsageRecord]

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(PersistedHistoryData.self, from: data) {
            cachedEntries = decoded.entries
            cachedItemStats = decoded.itemStats
        } else {
            cachedEntries = []
            cachedItemStats = [:]
        }
    }

    // MARK: - Thread-Safe Read Access

    /// Returns the chronological list of history entries, newest first.
    func entries() -> [SearchHistoryEntry] {
        lock.lock()
        defer { lock.unlock() }
        return cachedEntries
    }

    /// Returns snapshot of both history entries and ranking stats for backup export.
    func currentHistoryData() -> (entries: [SearchHistoryEntry], itemStats: [String: ItemUsageRecord]) {
        lock.lock()
        defer { lock.unlock() }
        return (cachedEntries, cachedItemStats)
    }

    /// Retrieve item usage stats for ranking inspection.
    func itemRecord(for itemId: String) -> ItemUsageRecord? {
        let canonical = canonicalId(for: itemId)
        lock.lock()
        defer { lock.unlock() }
        return cachedItemStats[canonical]
    }

    // MARK: - Ranking Boost Calculation

    /// Computes ranking boost based on:
    /// 1. Same keyword match (up to +20 pts exact, or up to +10 pts prefix)
    /// 2. Recent selected time decay (up to +15 pts, 2-day half-life)
    /// 3. Selected times frequency (up to +15 pts, logarithmic scaling)
    func rankingBoost(for itemId: String, query: SearchQuery, now: Date = Date()) -> Double {
        let q = query.lowercased
        guard !q.isEmpty else { return 0.0 }

        let canonical = canonicalId(for: itemId)

        lock.lock()
        guard let record = cachedItemStats[canonical] else {
            lock.unlock()
            return 0.0
        }
        lock.unlock()

        // 1. Same keyword bonus
        var sameKeywordBonus: Double = 0.0
        var keywordLastSelected: Date? = nil

        if let exact = record.keywords[q] {
            sameKeywordBonus = 20.0
            keywordLastSelected = exact.lastSelected
        } else {
            var bestRatio: Double = 0.0
            for (kw, usage) in record.keywords {
                if kw.hasPrefix(q) && kw.count > q.count {
                    let ratio = Double(q.count) / Double(kw.count)
                    if ratio > bestRatio {
                        bestRatio = ratio
                        keywordLastSelected = usage.lastSelected
                    }
                }
            }
            if bestRatio > 0.0 {
                sameKeywordBonus = 10.0 * bestRatio
            }
        }

        // 2. Recent selected bonus (smooth continuous decay with 2-day half life)
        let lastDate = keywordLastSelected ?? record.lastSelected
        let elapsed = max(0, now.timeIntervalSince(lastDate))
        let recencyFactor = 1.0 / (1.0 + elapsed / (86400.0 * 2.0))
        let recencyBonus = 15.0 * recencyFactor

        // 3. Selected times bonus (logarithmic scaling)
        let frequencyBonus = min(15.0, log2(Double(record.totalCount) + 1.0) * 3.5)

        return sameKeywordBonus + recencyBonus + frequencyBonus
    }

    // MARK: - Recording Selections

    /// Record a selection from search results.
    func recordSelection(result: SearchResult, query: String, date: Date = Date()) {
        let canonical = canonicalId(for: result.id)
        let originalCategory = result.category == .topHit ? .applications : result.category

        recordSelection(
            itemId: canonical,
            title: result.title,
            subtitle: result.subtitle,
            category: originalCategory,
            iconType: result.iconType,
            action: result.action,
            query: query,
            date: date
        )
    }

    /// Record a selection by canonical ID and details.
    func recordSelection(
        itemId: String,
        title: String,
        subtitle: String,
        category: ResultCategory,
        iconType: ResultIconType,
        action: SearchAction,
        query: String,
        date: Date = Date()
    ) {
        let canonical = canonicalId(for: itemId)
        guard !canonical.isEmpty else { return }
        let normQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        lock.lock()

        // 1. Update aggregated statistics
        var stat = cachedItemStats[canonical] ?? ItemUsageRecord(totalCount: 0, lastSelected: date)
        stat.totalCount += 1
        stat.lastSelected = date

        if !normQuery.isEmpty {
            var kw = stat.keywords[normQuery] ?? KeywordUsage(count: 0, lastSelected: date)
            kw.count += 1
            kw.lastSelected = date
            stat.keywords[normQuery] = kw

            // Prune excess keywords per item
            if stat.keywords.count > Self.maxKeywordsPerItem {
                let sortedKws = stat.keywords.sorted { $0.value.lastSelected > $1.value.lastSelected }
                stat.keywords = Dictionary(uniqueKeysWithValues: sortedKws.prefix(Self.maxKeywordsPerItem).map { ($0.key, $0.value) })
            }
        }
        cachedItemStats[canonical] = stat

        // Prune excess items
        if cachedItemStats.count > Self.maxItems {
            let sortedItems = cachedItemStats.sorted { $0.value.lastSelected > $1.value.lastSelected }
            cachedItemStats = Dictionary(uniqueKeysWithValues: sortedItems.prefix(Self.maxItems).map { ($0.key, $0.value) })
        }

        // 2. Add or update chronological history entry
        let existingIndex = cachedEntries.firstIndex {
            $0.itemId == canonical && $0.query == normQuery
        }

        let newCount = stat.totalCount
        if let idx = existingIndex {
            cachedEntries.remove(at: idx)
        }

        let newEntry = SearchHistoryEntry(
            itemId: canonical,
            query: normQuery,
            title: title,
            subtitle: subtitle,
            category: category,
            iconType: iconType,
            action: action,
            selectedAt: date,
            selectionCount: newCount
        )
        cachedEntries.insert(newEntry, at: 0)

        if cachedEntries.count > Self.maxEntries {
            cachedEntries.removeLast(cachedEntries.count - Self.maxEntries)
        }

        let snapshotEntries = cachedEntries
        let snapshotStats = cachedItemStats
        lock.unlock()

        persist(entries: snapshotEntries, stats: snapshotStats)
    }

    // MARK: - Deletion & Clearing

    /// Remove a single history entry by its entry ID.
    func deleteEntry(id: String) {
        lock.lock()
        cachedEntries.removeAll { $0.id == id }
        let snapshotEntries = cachedEntries
        let snapshotStats = cachedItemStats
        lock.unlock()

        persist(entries: snapshotEntries, stats: snapshotStats)
    }

    /// Clear all search history and ranking statistics.
    func clearHistory() {
        lock.lock()
        cachedEntries.removeAll(keepingCapacity: false)
        cachedItemStats.removeAll(keepingCapacity: false)
        lock.unlock()

        persistQueue.async { [defaultsKey] in
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
    }

    /// Reset in-memory and persistent state (useful for tests).
    func reset() {
        clearHistory()
    }

    /// Restore history entries and ranking statistics from a backup.
    func restore(entries: [SearchHistoryEntry], stats: [String: ItemUsageRecord]) {
        lock.lock()
        cachedEntries = Array(entries.prefix(Self.maxEntries))
        cachedItemStats = stats
        let snapshotEntries = cachedEntries
        let snapshotStats = cachedItemStats
        lock.unlock()

        persist(entries: snapshotEntries, stats: snapshotStats)
    }

    // MARK: - Helpers & Persistence

    private func canonicalId(for id: String) -> String {
        if id.hasPrefix("top-") {
            return String(id.dropFirst("top-".count))
        }
        return id
    }

    private func persist(entries: [SearchHistoryEntry], stats: [String: ItemUsageRecord]) {
        let data = PersistedHistoryData(entries: entries, itemStats: stats)
        persistQueue.async { [defaultsKey] in
            if let encoded = try? JSONEncoder().encode(data) {
                UserDefaults.standard.set(encoded, forKey: defaultsKey)
            }
        }
    }
}
