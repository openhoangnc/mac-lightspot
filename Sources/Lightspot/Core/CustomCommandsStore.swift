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
        case .url: return "https://github.com/search?q={query}"
        case .terminal: return "echo 'Hello World'"
        case .appleScript: return #"display dialog "Hello from Lightspot!""#
        case .shell: return "date >> ~/output.log"
        }
    }
}

// MARK: - Custom Command Icon Source

enum CustomCommandIconSource: String, Codable, Sendable, CaseIterable {
    case runner = "runner"      // Default icon from runner application (Chrome, Terminal, etc.)
    case custom = "custom"      // User-selected image/app file saved as base64
    case symbol = "symbol"      // SF Symbol
}

// MARK: - Custom Command Model

struct CustomCommand: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var name: String
    var type: CustomCommandType
    var target: String
    var keywords: [String]
    var prefix: String?
    var iconSource: CustomCommandIconSource?
    var iconBase64: String?

    init(
        id: UUID = UUID(),
        name: String,
        type: CustomCommandType,
        target: String,
        keywords: [String] = [],
        prefix: String? = nil,
        iconSource: CustomCommandIconSource? = nil,
        iconBase64: String? = nil
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.type = type
        self.target = target.trimmingCharacters(in: .whitespacesAndNewlines)
        self.keywords = keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let trimmedPrefix = prefix?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.prefix = (trimmedPrefix?.isEmpty == false) ? trimmedPrefix : nil
        self.iconSource = iconSource
        let trimmedBase64 = iconBase64?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.iconBase64 = (trimmedBase64?.isEmpty == false) ? trimmedBase64 : nil
    }

    enum CodingKeys: String, CodingKey {
        case id, name, type, target, keywords, prefix, iconSource, iconBase64
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.type = try container.decode(CustomCommandType.self, forKey: .type)
        self.target = try container.decode(String.self, forKey: .target)
        self.keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        self.prefix = try container.decodeIfPresent(String.self, forKey: .prefix)
        self.iconSource = try container.decodeIfPresent(CustomCommandIconSource.self, forKey: .iconSource)
        self.iconBase64 = try container.decodeIfPresent(String.self, forKey: .iconBase64)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(target, forKey: .target)
        try container.encode(keywords, forKey: .keywords)
        try container.encodeIfPresent(prefix, forKey: .prefix)
        try container.encodeIfPresent(iconSource, forKey: .iconSource)
        try container.encodeIfPresent(iconBase64, forKey: .iconBase64)
    }

    // MARK: - Icon Resolution

    var effectiveIconSource: CustomCommandIconSource {
        if let source = iconSource {
            return source
        }
        if iconBase64 != nil && !iconBase64!.isEmpty {
            return .custom
        }
        return .runner
    }

    var runnerAppPath: String? {
        switch type {
        case .url:
            return BrowserIntegrationProvider.defaultBrowser()?.appPath
                ?? NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://apple.com")!)?.path
                ?? "/Applications/Safari.app"
        case .terminal, .shell:
            let term = TerminalLauncher.currentTerminal
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: term.bundleIdentifier)?.path
                ?? "/System/Applications/Utilities/Terminal.app"
        case .appleScript:
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ScriptEditor2")?.path
                ?? "/System/Applications/Utilities/Script Editor.app"
        }
    }

    var runnerAppName: String {
        switch type {
        case .url:
            return BrowserIntegrationProvider.defaultBrowser()?.name ?? "Default Browser"
        case .terminal, .shell:
            return TerminalLauncher.currentTerminal.displayName
        case .appleScript:
            return "Script Editor"
        }
    }

    var runnerIconType: ResultIconType {
        if let path = runnerAppPath, FileManager.default.fileExists(atPath: path) {
            return .app(path: path)
        }
        return .systemSymbol(name: type.sfSymbol)
    }

    var resolvedIconType: ResultIconType {
        switch effectiveIconSource {
        case .custom:
            if let base64 = iconBase64, !base64.isEmpty {
                return .customImage(base64: base64)
            }
            return runnerIconType
        case .runner:
            return runnerIconType
        case .symbol:
            return .systemSymbol(name: type.sfSymbol)
        }
    }

    // MARK: - Query Interpolation

    func interpolatedTarget(with query: String) -> String {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            // Remove placeholders cleanly
            var clean = target
                .replacingOccurrences(of: "{query}", with: "")
                .replacingOccurrences(of: "%s", with: "")
                .replacingOccurrences(of: "%@", with: "")
            if type == .url && clean.hasSuffix("?q=") {
                clean = String(clean.dropLast(3))
            } else if type == .url && (clean.hasSuffix("?") || clean.hasSuffix("&")) {
                clean = String(clean.dropLast())
            }
            return clean
        }

        switch type {
        case .url:
            let encoded = URLQueryEncoder.encode(trimmedQuery) ?? trimmedQuery
            if target.contains("{query}") || target.contains("%s") || target.contains("%@") {
                return target
                    .replacingOccurrences(of: "{query}", with: encoded)
                    .replacingOccurrences(of: "%s", with: encoded)
                    .replacingOccurrences(of: "%@", with: encoded)
            } else {
                if target.contains("?") {
                    return "\(target)&q=\(encoded)"
                } else {
                    return "\(target)?q=\(encoded)"
                }
            }
        case .terminal, .shell:
            if target.contains("{query}") || target.contains("%s") || target.contains("%@") {
                return target
                    .replacingOccurrences(of: "{query}", with: trimmedQuery)
                    .replacingOccurrences(of: "%s", with: trimmedQuery)
                    .replacingOccurrences(of: "%@", with: trimmedQuery)
            } else {
                return "\(target) \(trimmedQuery)"
            }
        case .appleScript:
            if target.contains("{query}") || target.contains("%s") || target.contains("%@") {
                let escapedAppleScript = trimmedQuery.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                return target
                    .replacingOccurrences(of: "{query}", with: escapedAppleScript)
                    .replacingOccurrences(of: "%s", with: escapedAppleScript)
                    .replacingOccurrences(of: "%@", with: escapedAppleScript)
            } else {
                return target
            }
        }
    }

    var normalizedURL: URL? {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("://") {
            return URL(string: trimmed)
        }
        return URL(string: "https://" + trimmed)
    }

    func searchAction(with query: String? = nil) -> SearchAction {
        let finalTarget: String
        if let query = query, !query.isEmpty {
            finalTarget = interpolatedTarget(with: query)
        } else {
            finalTarget = interpolatedTarget(with: "")
        }

        switch type {
        case .url:
            let trimmed = finalTarget.trimmingCharacters(in: .whitespacesAndNewlines)
            let url: URL
            if trimmed.contains("://") {
                url = URL(string: trimmed) ?? URL(string: "https://")!
            } else {
                url = URL(string: "https://" + trimmed) ?? URL(string: "https://")!
            }
            return .openURL(url: url)
        case .terminal:
            return .runInTerminal(command: finalTarget)
        case .appleScript:
            return .runQuickAction(script: finalTarget, usesOsascript: true)
        case .shell:
            return .runQuickAction(script: finalTarget, usesOsascript: false)
        }
    }

    var searchAction: SearchAction {
        searchAction(with: nil)
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
            && lhs.prefix == rhs.prefix
            && lhs.iconSource == rhs.iconSource
            && lhs.iconBase64 == rhs.iconBase64
    }
}

// MARK: - Custom Command Preset

struct CustomCommandPreset: Identifiable, Sendable {
    let id: String
    let name: String
    let type: CustomCommandType
    let target: String
    let prefix: String
    let keywords: [String]
    let description: String

    var command: CustomCommand {
        CustomCommand(
            name: name,
            type: type,
            target: target,
            keywords: keywords,
            prefix: prefix,
            iconSource: .runner
        )
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
    let prefix: String?

    init(command: CustomCommand) {
        self.command = command
        let lowerName = command.name.lowercased()
        self.lowercaseName = lowerName
        let tokens = lowerName.split(separator: " ").map(String.init)
        self.searchTokens = tokens
        self.initials = String(tokens.compactMap { $0.first })
        self.lowercaseKeywords = command.keywords.map { $0.lowercased() }
        self.lowercaseTarget = command.target.lowercased()
        self.prefix = command.prefix?.lowercased()
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

    static let presets: [CustomCommandPreset] = [
        CustomCommandPreset(
            id: "preset-gh",
            name: "GitHub",
            type: .url,
            target: "https://github.com/search?q={query}&type=repositories",
            prefix: "gh",
            keywords: ["github", "git", "repo", "code"],
            description: "Search repositories on GitHub"
        ),
        CustomCommandPreset(
            id: "preset-g",
            name: "Google",
            type: .url,
            target: "https://www.google.com/search?q={query}",
            prefix: "g",
            keywords: ["google", "web", "search"],
            description: "Search Google"
        ),
        CustomCommandPreset(
            id: "preset-yt",
            name: "YouTube",
            type: .url,
            target: "https://www.youtube.com/results?search_query={query}",
            prefix: "yt",
            keywords: ["youtube", "video", "media"],
            description: "Search videos on YouTube"
        ),
        CustomCommandPreset(
            id: "preset-so",
            name: "Stack Overflow",
            type: .url,
            target: "https://stackoverflow.com/search?q={query}",
            prefix: "so",
            keywords: ["stackoverflow", "code", "programming", "errors"],
            description: "Search questions on Stack Overflow"
        ),
        CustomCommandPreset(
            id: "preset-ddg",
            name: "DuckDuckGo",
            type: .url,
            target: "https://duckduckgo.com/?q={query}",
            prefix: "ddg",
            keywords: ["duckduckgo", "privacy", "search"],
            description: "Search DuckDuckGo"
        ),
        CustomCommandPreset(
            id: "preset-wiki",
            name: "Wikipedia",
            type: .url,
            target: "https://en.wikipedia.org/w/index.php?search={query}",
            prefix: "wiki",
            keywords: ["wikipedia", "wiki", "encyclopedia"],
            description: "Search Wikipedia"
        ),
        CustomCommandPreset(
            id: "preset-npm",
            name: "npm",
            type: .url,
            target: "https://www.npmjs.com/search?q={query}",
            prefix: "npm",
            keywords: ["npm", "node", "javascript", "package"],
            description: "Search npm packages"
        ),
        CustomCommandPreset(
            id: "preset-ping",
            name: "Ping Host",
            type: .terminal,
            target: "ping -c 4 {query}",
            prefix: "png",
            keywords: ["ping", "network", "icmp", "latency"],
            description: "Ping a host in Terminal"
        ),
        CustomCommandPreset(
            id: "preset-curl",
            name: "Curl Headers",
            type: .terminal,
            target: "curl -IL {query}",
            prefix: "c",
            keywords: ["curl", "http", "headers"],
            description: "Inspect HTTP response headers"
        )
    ]

    static let defaultCommands: [CustomCommand] = [
        CustomCommand(
            name: "Open GitHub",
            type: .url,
            target: "https://github.com/search?q={query}&type=repositories",
            keywords: ["github", "git", "repo", "code"],
            prefix: "gh",
            iconSource: .runner
        ),
        CustomCommand(
            name: "System Info",
            type: .terminal,
            target: "uname -a && sw_vers",
            keywords: ["system", "info", "os", "mac", "specs"],
            prefix: nil,
            iconSource: .runner
        ),
        CustomCommand(
            name: "Show Notification",
            type: .appleScript,
            target: #"display notification "Hello from Lightspot!" with title "Custom Command""#,
            keywords: ["notify", "alert", "hello"],
            prefix: nil,
            iconSource: .runner
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
        var matchedIDs = Set<UUID>()
        let trimmed = query.trimmed

        // 1. Prefix command matching with query argument (e.g. "gh spotlight" or "g swift")
        if let spaceIdx = trimmed.firstIndex(of: " ") {
            let prefixPart = String(trimmed[..<spaceIdx]).lowercased()
            let queryPart = String(trimmed[trimmed.index(after: spaceIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)

            if !queryPart.isEmpty {
                for item in items {
                    if let cmdPrefix = item.prefix, cmdPrefix == prefixPart {
                        matchedIDs.insert(item.command.id)
                        let displayTitle: String
                        let lowerName = item.command.name.lowercased()
                        if lowerName.hasPrefix("search ") {
                            displayTitle = "\(item.command.name) for '\(queryPart)'"
                        } else if lowerName.hasPrefix("open ") {
                            displayTitle = "Search \(item.command.name.dropFirst(5)) for '\(queryPart)'"
                        } else {
                            displayTitle = "\(item.command.name) for '\(queryPart)'"
                        }

                        let interpolated = item.command.interpolatedTarget(with: queryPart)
                        let displaySubtitle = "\(interpolated) · '\(cmdPrefix)' shortcut"

                        results.append(SearchResult(
                            id: "custom-prefix-\(item.command.id.uuidString)-\(queryPart)",
                            title: displayTitle,
                            subtitle: displaySubtitle,
                            iconType: item.command.resolvedIconType,
                            category: .customCommands,
                            score: 98.0,
                            action: item.command.searchAction(with: queryPart)
                        ))
                    }
                }
            }
        }

        // 2. Direct prefix match without arguments (e.g. user just types "gh")
        for item in items where !matchedIDs.contains(item.command.id) {
            if let cmdPrefix = item.prefix, cmdPrefix == query.lowercased {
                matchedIDs.insert(item.command.id)
                let subtitleText = item.command.target.isEmpty
                    ? "\(item.command.type.subtitle) · '\(cmdPrefix)' prefix"
                    : "\(item.command.target) · '\(cmdPrefix)' prefix"

                results.append(SearchResult(
                    id: "custom-\(item.command.id.uuidString)",
                    title: item.command.name,
                    subtitle: subtitleText,
                    iconType: item.command.resolvedIconType,
                    category: .customCommands,
                    score: 96.0,
                    action: item.command.searchAction(with: nil)
                ))
            }
        }

        // 3. General fuzzy matching
        for item in items where !matchedIDs.contains(item.command.id) {
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
                let prefixSuffix = item.prefix != nil ? " · '\(item.prefix!)'" : ""
                let subtitleText: String
                if item.command.target.isEmpty {
                    subtitleText = "\(item.command.type.subtitle)\(prefixSuffix)"
                } else {
                    subtitleText = "\(item.command.type.subtitle) · \(item.command.target)\(prefixSuffix)"
                }

                results.append(SearchResult(
                    id: "custom-\(item.command.id.uuidString)",
                    title: item.command.name,
                    subtitle: subtitleText,
                    iconType: item.command.resolvedIconType,
                    category: .customCommands,
                    score: score,
                    action: item.command.searchAction(with: nil)
                ))
            }
        }

        return results.sorted { $0.score > $1.score }
    }
}
