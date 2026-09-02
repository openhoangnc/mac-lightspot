import AppKit

final class WebSearchProvider: Sendable {
    static let shared = WebSearchProvider()
    private init() {}

    func search(_ query: SearchQuery) -> [SearchResult] {
        if query.isEmpty { return [] }

        let trimmed = query.trimmed
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.google.com/search?q=\(encoded)") else { return [] }

        return [SearchResult(
            id: "web-\(trimmed)",
            title: "Search Google for '\(trimmed)'",
            subtitle: "www.google.com",
            iconType: .systemSymbol(name: "globe"),
            category: .webSearch,
            score: 30,
            action: .openWebSearch(url: url)
        )]
    }
}
