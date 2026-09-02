import AppKit

final class SearchEngine: @unchecked Sendable {
    static let shared = SearchEngine()

    private var currentWorkItem: DispatchWorkItem?
    private let searchQueue = DispatchQueue(label: "com.lightspot.search", qos: .userInteractive)
    private let debounceInterval: TimeInterval = 0.15
    private let maxResultsPerCategory = 4

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

        // Group by category, limit per category
        var grouped: [ResultCategory: [SearchResult]] = [:]
        grouped.reserveCapacity(ResultCategory.allCases.count)

        // Find the top hit (highest score across all non-web/non-calc categories)
        let topHitCandidates = allResults.filter {
            $0.category != .webSearch && $0.category != .calculator
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
                action: topHit.action
            )
            grouped[.topHit] = [promoted]
        }

        // Group remaining by their original category (excluding the item already promoted to Top Hit)
        for category in ResultCategory.allCases where category != .topHit {
            let categoryResults = allResults
                .filter { $0.category == category && $0.id != topHitOriginalID }
                .sorted { $0.score > $1.score }
                .prefix(maxResultsPerCategory)

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
