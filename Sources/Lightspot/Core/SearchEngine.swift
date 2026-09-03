import AppKit

final class SearchEngine: @unchecked Sendable {
    static let shared = SearchEngine()

    private var currentWorkItem: DispatchWorkItem?
    private let searchQueue = DispatchQueue(label: "com.lightspot.search", qos: .userInteractive)
    private let debounceInterval: TimeInterval = 0.15
    private let maxResultsPerCategory = 4
    /// The history is the one open-ended category, so it gets a taller cap than the
    /// curated ones — four rows is not enough to find a command among near-misses.
    private let maxShellHistoryResults = 6

    private init() {}

    /// Fast in-memory search: executes immediately on caller thread
    func search(_ query: SearchQuery, completion: @escaping @Sendable ([ResultCategory: [SearchResult]]) -> Void) {
        let results = self.performSearch(query)
        completion(results)
    }

    /// Immediate search (no debounce)
    func searchImmediate(_ query: SearchQuery) -> [ResultCategory: [SearchResult]] {
        performSearch(query)
    }

    private func performSearch(_ query: SearchQuery) -> [ResultCategory: [SearchResult]] {
        if query.isEmpty { return [:] }

        // Collect results from all providers
        var allResults: [SearchResult] = []
        allResults.reserveCapacity(32) // Prevent reallocation

        // Applications
        allResults.append(contentsOf: AppScanner.shared.search(query))

        // System Settings
        allResults.append(contentsOf: SettingsProvider.shared.search(query))

        // Quick Actions
        allResults.append(contentsOf: QuickActionsProvider.shared.search(query))

        // Custom Commands
        allResults.append(contentsOf: CustomCommandsStore.shared.search(query))

        // VS Code Recent Projects
        allResults.append(contentsOf: VSCodeProjectsProvider.shared.search(query))

        // Shell (zsh) history
        allResults.append(contentsOf: ShellHistoryProvider.shared.search(query))

        // Calculator
        if let calcResult = CalculatorEngine.evaluate(query.trimmed) {
            allResults.append(SearchResult(
                id: "calc-\(query.trimmed)",
                title: calcResult,
                subtitle: query.trimmed,
                iconType: .systemSymbol(name: "equal.circle.fill"),
                category: .calculator,
                score: 90,
                action: .copyToClipboard(calcResult)
            ))
        }

        // Web Search (always last)
        allResults.append(contentsOf: WebSearchProvider.shared.search(query))

        // Apply search matching ranking boost: same keyword + recent selected + selected times
        let rankedResults: [SearchResult] = allResults.map { result in
            guard result.category != .webSearch && result.category != .calculator else {
                return result
            }
            let boost = SearchHistoryManager.shared.rankingBoost(for: result.id, query: query)
            if boost > 0 {
                return result.withScore(result.score + boost)
            }
            return result
        }

        // Group by category, limit per category
        var grouped: [ResultCategory: [SearchResult]] = [:]
        grouped.reserveCapacity(ResultCategory.allCases.count)

        // Find the top hit (highest score across all non-web/non-calc categories).
        // General unpinned shell history is excluded on purpose to avoid accidental
        // Return execution of fuzzy commands from ~/.zsh_history. However, explicitly
        // PINNED commands or commands previously SELECTED by the user for this query are
        // intentional user choices and can be promoted to Top Hit.
        let topHitCandidates = rankedResults.filter { result in
            guard result.category != .webSearch && result.category != .calculator else {
                return false
            }
            if result.category == .shellHistory {
                let hasKeywordSelection = SearchHistoryManager.shared.itemRecord(for: result.id)?.keywords[query.lowercased] != nil
                return result.isPinned || hasKeywordSelection
            }
            return true
        }
        var topHitOriginalID: String? = nil
        if let topHit = topHitCandidates.max(by: { $0.score < $1.score }), topHit.score >= 60 {
            topHitOriginalID = topHit.id
            let promoted = SearchResult(
                id: "top-\(topHit.id)",
                title: topHit.title,
                subtitle: topHit.subtitle,
                iconType: topHit.iconType,
                category: .topHit,
                score: topHit.score,
                action: topHit.action,
                isPinned: topHit.isPinned
            )
            grouped[.topHit] = [promoted]
        }

        // Group remaining by their original category (excluding the item already promoted to Top Hit)
        for category in ResultCategory.allCases where category != .topHit {
            let cap = category == .shellHistory ? maxShellHistoryResults : maxResultsPerCategory
            let categoryResults = rankedResults
                .filter { $0.category == category && $0.id != topHitOriginalID }
                .sorted { $0.score > $1.score }
                .prefix(cap)

            if !categoryResults.isEmpty {
                grouped[category] = Array(categoryResults)
            }
        }

        return grouped
    }

    /// Ordered categories for display
    static func orderedCategories(from grouped: [ResultCategory: [SearchResult]]) -> [ResultCategory] {
        ResultCategory.allCases.filter { grouped[$0] != nil }
    }

    /// Flat list of all results in display order
    static func flatResults(from grouped: [ResultCategory: [SearchResult]]) -> [SearchResult] {
        orderedCategories(from: grouped).flatMap { grouped[$0] ?? [] }
    }
}
