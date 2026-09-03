import Foundation
import AppKit

// MARK: - Custom Command Type

enum CustomCommandType: String, Codable, CaseIterable, Sendable {
    case url = "url"
    case terminal = "terminal"
    case appleScript = "applescript"
    case shell = "shell"

    var displayName: String {
        switch self {
        case .url: return "Open URL"
        case .terminal: return "Terminal"
        case .appleScript: return "AppleScript"
        case .shell: return "Shell Script"
        }
    }

    var sfSymbol: String {
        switch self {
        case .url: return "globe"
        case .terminal: return "terminal.fill"
        case .appleScript: return "applescript"
        case .shell: return "command.square.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .url: return "Open in Browser"
        case .terminal: return "Run in Terminal"
        case .appleScript: return "Run AppleScript"
        case .shell: return "Run Shell Command"
        }
    }

    var placeholder: String {
        switch self {
        case .url: return "https://example.com"
        case .terminal: return "echo 'Hello World'"
        case .appleScript: return #"display dialog "Hello from Lightspot!""#
        case .shell: return "date >> ~/output.log"
        }
    }
}

// MARK: - Custom Command Model

struct CustomCommand: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var name: String
    var type: CustomCommandType
    var target: String
    var keywords: [String]

    init(
        id: UUID = UUID(),
        name: String,
        type: CustomCommandType,
        target: String,
        keywords: [String] = []
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.type = type
        self.target = target.trimmingCharacters(in: .whitespacesAndNewlines)
        self.keywords = keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var normalizedURL: URL? {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("://") {
            return URL(string: trimmed)
        }
        return URL(string: "https://" + trimmed)
    }

    var searchAction: SearchAction {
        switch type {
        case .url:
            let url = normalizedURL ?? URL(string: "https://")!
            return .openURL(url: url)
        case .terminal:
            return .runInTerminal(command: target)
        case .appleScript:
            return .runQuickAction(script: target, usesOsascript: true)
        case .shell:
            return .runQuickAction(script: target, usesOsascript: false)
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: CustomCommand, rhs: CustomCommand) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.type == rhs.type
            && lhs.target == rhs.target
            && lhs.keywords == rhs.keywords
    }
}

// MARK: - Custom Command Search Item (Zero-Allocation Search)

struct CustomCommandItem: Sendable {
    let command: CustomCommand
    let lowercaseName: String
    let searchTokens: [String]
    let initials: String
    let lowercaseKeywords: [String]
    let lowercaseTarget: String

    init(command: CustomCommand) {
        self.command = command
        let lowerName = command.name.lowercased()
        self.lowercaseName = lowerName
        let tokens = lowerName.split(separator: " ").map(String.init)
        self.searchTokens = tokens
        self.initials = String(tokens.compactMap { $0.first })
        self.lowercaseKeywords = command.keywords.map { $0.lowercased() }
        self.lowercaseTarget = command.target.lowercased()
    }
}

// MARK: - Custom Commands Store

final class CustomCommandsStore: @unchecked Sendable {
    static let shared = CustomCommandsStore()

    static let maxCommands = 100
    static let minimumScore: Double = 60.0

    private let defaultsKey = "lightspot_custom_commands"
    private let lock = NSLock()
    private var cached: [CustomCommand]
    private var cachedItems: [CustomCommandItem]

    static let defaultCommands: [CustomCommand] = [
        CustomCommand(
            name: "Open GitHub",
            type: .url,
            target: "https://github.com",
            keywords: ["github", "git", "repo", "code"]
        ),
        CustomCommand(
            name: "System Info",
            type: .terminal,
            target: "uname -a && sw_vers",
            keywords: ["system", "info", "os", "mac", "specs"]
        ),
        CustomCommand(
            name: "Show Notification",
            type: .appleScript,
            target: #"display notification "Hello from Lightspot!" with title "Custom Command""#,
            keywords: ["notify", "alert", "hello"]
        )
    ]

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([CustomCommand].self, from: data) {
            cached = decoded
            cachedItems = decoded.map { CustomCommandItem(command: $0) }
        } else {
            let defaults = Self.defaultCommands
            cached = defaults
            cachedItems = defaults.map { CustomCommandItem(command: $0) }
            persist(defaults)
        }
    }

    // MARK: - Accessors

    func entries() -> [CustomCommand] {
        lock.lock()
        defer { lock.unlock() }
        return cached
    }

    func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return cached.count
    }

    // MARK: - Mutations

    func add(_ command: CustomCommand) {
        lock.lock()
        // If already exists with same id, replace it
        if let idx = cached.firstIndex(where: { $0.id == command.id }) {
            cached[idx] = command
        } else {
            cached.insert(command, at: 0)
            if cached.count > Self.maxCommands {
                cached.removeLast(cached.count - Self.maxCommands)
            }
        }
        cachedItems = cached.map { CustomCommandItem(command: $0) }
        let snapshot = cached
        lock.unlock()

        persist(snapshot)
    }

    func update(_ command: CustomCommand) {
        lock.lock()
        guard let idx = cached.firstIndex(where: { $0.id == command.id }) else {
            lock.unlock()
            return
        }
        cached[idx] = command
        cachedItems = cached.map { CustomCommandItem(command: $0) }
        let snapshot = cached
        lock.unlock()

        persist(snapshot)
    }

    func delete(id: UUID) {
        lock.lock()
        let before = cached.count
        cached.removeAll { $0.id == id }
        let changed = cached.count != before
        cachedItems = cached.map { CustomCommandItem(command: $0) }
        let snapshot = cached
        lock.unlock()

        if changed {
            persist(snapshot)
        }
    }

    func move(from index: Int, offset: Int) {
        lock.lock()
        guard index >= 0, index < cached.count else {
            lock.unlock()
            return
        }
        let destination = min(max(index + offset, 0), cached.count - 1)
        guard destination != index else {
            lock.unlock()
            return
        }
        let item = cached.remove(at: index)
        cached.insert(item, at: destination)
        cachedItems = cached.map { CustomCommandItem(command: $0) }
        let snapshot = cached
        lock.unlock()

        persist(snapshot)
    }

    func reset(to commands: [CustomCommand]) {
        lock.lock()
        cached = commands
        cachedItems = commands.map { CustomCommandItem(command: $0) }
        let snapshot = cached
        lock.unlock()

        persist(snapshot)
    }

    private func persist(_ entries: [CustomCommand]) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    // MARK: - Search

    func search(_ query: SearchQuery) -> [SearchResult] {
        if query.isEmpty { return [] }

        lock.lock()
        let items = cachedItems
        lock.unlock()

        var results: [SearchResult] = []
        results.reserveCapacity(items.count)

        for item in items {
            var highestScore: Double? = FuzzyMatcher.score(
                query: query,
                targetLower: item.lowercaseName,
                targetTokens: item.searchTokens,
                targetInitials: item.initials
            )

            // Keyword matches (scaled by 0.95, matching QuickActions convention)
            for kw in item.lowercaseKeywords {
                let kwTokens = kw.split(separator: " ").map(String.init)
                let kwInitials = String(kwTokens.compactMap { $0.first })
                if let kwScore = FuzzyMatcher.score(
                    query: query,
                    targetLower: kw,
                    targetTokens: kwTokens,
                    targetInitials: kwInitials
                ) {
                    let weighted = kwScore * 0.95
                    if let current = highestScore {
                        highestScore = max(current, weighted)
                    } else {
                        highestScore = weighted
                    }
                }
            }

            // Target content match (scaled by 0.95)
            if !item.lowercaseTarget.isEmpty {
                let targetTokens = item.lowercaseTarget.split(separator: " ").map(String.init)
                if let targetScore = FuzzyMatcher.score(
                    query: query,
                    targetLower: item.lowercaseTarget,
                    targetTokens: targetTokens,
                    targetInitials: nil
                ) {
                    let weighted = targetScore * 0.95
                    if let current = highestScore {
                        highestScore = max(current, weighted)
                    } else {
                        highestScore = weighted
                    }
                }
            }

            if let score = highestScore, score >= Self.minimumScore {
                let subtitleText: String
                if item.command.target.isEmpty {
                    subtitleText = item.command.type.subtitle
                } else {
                    subtitleText = "\(item.command.type.subtitle) · \(item.command.target)"
                }

                results.append(SearchResult(
                    id: "custom-\(item.command.id.uuidString)",
                    title: item.command.name,
                    subtitle: subtitleText,
                    iconType: .systemSymbol(name: item.command.type.sfSymbol),
                    category: .customCommands,
                    score: score,
                    action: item.command.searchAction
                ))
            }
        }

        return results.sorted { $0.score > $1.score }
    }
}
