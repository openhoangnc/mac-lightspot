import AppKit

final class SearchEngine: @unchecked Sendable {
    static let shared = SearchEngine()

    private var currentWorkItem: DispatchWorkItem?
    private let searchQueue = DispatchQueue(label: "com.lightspot.search", qos: .userInteractive)
    private let debounceInterval: TimeInterval = 0.15
    private let maxResultsPerCategory = 4

    private init() {}

    /// Debounced search: calls completion on main thread with grouped results
    func search(_ query: String, completion: @escaping @Sendable ([ResultCategory: [SearchResult]]) -> Void) {
        currentWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let results = self.performSearch(query)
            DispatchQueue.main.async {
                completion(results)
            }
        }

        currentWorkItem = workItem
        searchQueue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    /// Immediate search (no debounce)
    func searchImmediate(_ query: String) -> [ResultCategory: [SearchResult]] {
        performSearch(query)
    }

    private func performSearch(_ query: String) -> [ResultCategory: [SearchResult]] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [:] }

        // Collect results from all providers
        var allResults: [SearchResult] = []

        // Applications
        let apps = AppScanner.shared.search(trimmed)
        allResults.append(contentsOf: apps)

        // System Settings
        let settings = SettingsProvider.shared.search(trimmed)
        allResults.append(contentsOf: settings)

        // Quick Actions
        let actions = QuickActionsProvider.shared.search(trimmed)
        allResults.append(contentsOf: actions)

        // Calculator
        if let calcResult = CalculatorEngine.evaluate(trimmed) {
            let icon = NSImage(systemSymbolName: "equal.circle.fill", accessibilityDescription: "Calculator")
            allResults.append(SearchResult(
                id: "calc-result",
                title: calcResult,
                subtitle: trimmed,
                icon: icon,
                category: .calculator,
                score: 90,
                action: { [calcResult] in
                    // Copy result to clipboard
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(calcResult, forType: .string)
                }
            ))
        }

        // Web Search (always last)
        let webResults = WebSearchProvider.shared.search(trimmed)
        allResults.append(contentsOf: webResults)

        // Group by category, limit per category
        var grouped: [ResultCategory: [SearchResult]] = [:]

        // Find the top hit (highest score across all non-web/non-calc categories)
        let topHitCandidates = allResults.filter {
            $0.category != .webSearch && $0.category != .calculator
        }
        if let topHit = topHitCandidates.max(by: { $0.score < $1.score }), topHit.score >= 60 {
            let promoted = SearchResult(
                id: "top-\(topHit.id)",
                title: topHit.title,
                subtitle: topHit.subtitle,
                icon: topHit.icon,
                category: .topHit,
                score: topHit.score,
                action: topHit.action
            )
            grouped[.topHit] = [promoted]
        }

        // Group remaining by their original category
        for category in ResultCategory.allCases where category != .topHit {
            let categoryResults = allResults
                .filter { $0.category == category }
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
