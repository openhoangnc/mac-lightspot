import AppKit

final class WebSearchProvider: Sendable {
    static let shared = WebSearchProvider()
    private init() {}

    func search(_ query: String) -> [SearchResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let icon = NSImage(systemSymbolName: "globe", accessibilityDescription: "Web Search")
            ?? NSImage(named: NSImage.networkName)!

        return [SearchResult(
            id: "web-google",
            title: "Search Google for '\(trimmed)'",
            subtitle: "www.google.com",
            icon: icon,
            category: .webSearch,
            score: 30,
            action: { [trimmed] in
                guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                      let url = URL(string: "https://www.google.com/search?q=\(encoded)") else { return }
                NSWorkspace.shared.open(url)
            }
        )]
    }
}
