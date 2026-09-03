import Foundation

// MARK: - Shell Command (one de-duplicated history entry)

/// A single command from the user's zsh history.
///
/// The lowercased form, tokens and initials are pre-computed at parse time for the
/// same reason `AppInfo` pre-computes them: `FuzzyMatcher.score` runs against every
/// entry on every keystroke, so scoring itself must not allocate.
struct ShellCommand: Sendable, Hashable {
    let command: String
    let lowercased: String
    let tokens: [String]
    let initials: String

    init(command: String) {
        self.command = command
        let lower = command.lowercased()
        self.lowercased = lower
        let tokens = lower.split(separator: " ").map(String.init)
        self.tokens = tokens
        self.initials = String(tokens.compactMap { $0.first })
    }

    /// Single-line form for display — zsh stores multi-line commands as one entry.
    var displayTitle: String {
        guard command.contains("\n") else { return command }
        return command
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ⏎ ")
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(command)
    }

    static func == (lhs: ShellCommand, rhs: ShellCommand) -> Bool {
        lhs.command == rhs.command
    }
}

// MARK: - Pinned Commands Store

/// The user's pinned commands, in their chosen order.
///
/// Pins survive history rotation: a pinned command stays searchable and runnable
/// even after it has aged out of `~/.zsh_history`, so the list is the source of
/// truth rather than an index into the history file.
final class PinnedCommandsStore: @unchecked Sendable {
    static let shared = PinnedCommandsStore()

    static let maxPinned = 50

    private let defaultsKey = "lightspot_pinned_commands"
    private let lock = NSLock()
    private var cached: [ShellCommand]

    private init() {
        let stored = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        cached = stored
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(Self.maxPinned)
            .map { ShellCommand(command: $0) }
    }

    /// Pre-tokenized pins, in display order. Safe to call from any thread.
    func entries() -> [ShellCommand] {
        lock.lock()
        defer { lock.unlock() }
        return cached
    }

    /// Raw commands, in display order.
    func commands() -> [String] {
        entries().map { $0.command }
    }

    func isPinned(_ command: String) -> Bool {
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        defer { lock.unlock() }
        return cached.contains { $0.command == normalized }
    }

    /// Pins a command at the top of the list. No-op if it is already pinned.
    func pin(_ command: String) {
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        lock.lock()
        if cached.contains(where: { $0.command == normalized }) {
            lock.unlock()
            return
        }
        cached.insert(ShellCommand(command: normalized), at: 0)
        if cached.count > Self.maxPinned {
            cached.removeLast(cached.count - Self.maxPinned)
        }
        let snapshot = cached
        lock.unlock()

        persist(snapshot)
    }

    func unpin(_ command: String) {
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)

        lock.lock()
        let before = cached.count
        cached.removeAll { $0.command == normalized }
        let changed = cached.count != before
        let snapshot = cached
        lock.unlock()

        if changed { persist(snapshot) }
    }

    /// Returns the new pinned state of `command`.
    @discardableResult
    func toggle(_ command: String) -> Bool {
        if isPinned(command) {
            unpin(command)
            return false
        }
        pin(command)
        return true
    }

    /// Moves the pin at `index` by `offset` places, clamped to the list bounds.
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
        let entry = cached.remove(at: index)
        cached.insert(entry, at: destination)
        let snapshot = cached
        lock.unlock()

        persist(snapshot)
    }

    /// Replaces the pinned commands with the given list and persists them.
    func reset(to commands: [String]) {
        lock.lock()
        cached = commands
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(Self.maxPinned)
            .map { ShellCommand(command: $0) }
        let snapshot = cached
        lock.unlock()

        persist(snapshot)
    }

    private func persist(_ entries: [ShellCommand]) {
        UserDefaults.standard.set(entries.map { $0.command }, forKey: defaultsKey)
    }
}

// MARK: - Shell History Provider

/// Searches the user's own zsh history file.
///
/// This is *not* a filesystem index: exactly one file is read (`~/.zsh_history`,
/// or `$HISTFILE` / `$ZDOTDIR/.zsh_history` when those point elsewhere), it is
/// parsed off the main thread, and only the tail of it is ever touched. No
/// directory is walked and no `NSMetadataQuery` is involved.
final class ShellHistoryProvider: @unchecked Sendable {
    static let shared = ShellHistoryProvider()

    /// Only the tail of the file is read — anything older than the most recent
    /// `maxEntries` unique commands is dead weight for a launcher.
    private static let maxTailBytes: UInt64 = 2 * 1024 * 1024
    private static let maxEntries = 1200
    private static let maxCommandLength = 300

    /// Substring quality bar. Subsequence hits (score 40) would make a two-letter
    /// query match most of the history, so history results start at "the query
    /// appears verbatim" (65) and go up from there.
    static let minimumScore: Double = 65
    static let minimumQueryLength = 2

    /// Recency and pin ordering are folded into the score because `SearchEngine`
    /// sorts every category by score alone. The recency bonus stays below 5 so it
    /// can only reorder entries *within* a `FuzzyMatcher` tier, never across one.
    private static let maxRecencyBonus: Double = 4.5
    /// Pinned matches always sort above unpinned ones. This cannot leak into the
    /// Top Hit: `SearchEngine` excludes `.shellHistory` from promotion entirely.
    private static let pinnedBoost: Double = 200
    private static let maxResults = 12

    private let lock = NSLock()
    private var entries: [ShellCommand] = []
    private var loadedSignature: String = ""
    private var isLoading = false

    private init() {}

    // MARK: - Loading

    /// Parses the history file on a background queue.
    func startLoading() {
        load(force: true)
    }

    /// Re-parses only when the history file changed (size or mtime) since the last load.
    func refreshIfNeeded() {
        load(force: false)
    }

    /// History entries are deliberately kept resident, like app metadata: the panel
    /// must be able to answer the first keystroke after being shown without waiting
    /// on file I/O. The tail cap bounds what "resident" can cost.
    func reclaimMemory() {}

    func commandCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    private func load(force: Bool) {
        lock.lock()
        if isLoading {
            lock.unlock()
            return
        }
        isLoading = true
        let previousSignature = loadedSignature
        lock.unlock()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            defer {
                self.lock.lock()
                self.isLoading = false
                self.lock.unlock()
            }

            guard let url = Self.historyFileURL() else {
                self.lock.lock()
                self.entries = []
                self.loadedSignature = ""
                self.lock.unlock()
                return
            }

            let signature = Self.signature(for: url)
            if !force && !signature.isEmpty && signature == previousSignature { return }

            let parsed = Self.loadEntries(from: url)

            self.lock.lock()
            self.entries = parsed
            self.loadedSignature = signature
            self.lock.unlock()
        }
    }

    // MARK: - Search

    func search(_ query: SearchQuery) -> [SearchResult] {
        guard query.lowercased.count >= Self.minimumQueryLength else { return [] }

        let pinned = PinnedCommandsStore.shared.entries()
        lock.lock()
        let history = entries
        lock.unlock()

        return Self.search(query, pinned: pinned, history: history)
    }

    /// The ranking core, split out from the shared state it normally reads so the
    /// scoring rules can be exercised directly without a history file on disk.
    static func search(_ query: SearchQuery, pinned: [ShellCommand], history: [ShellCommand]) -> [SearchResult] {
        guard query.lowercased.count >= minimumQueryLength else { return [] }
        if pinned.isEmpty && history.isEmpty { return [] }

        // Score into index/score pairs first: building a `SearchResult` per match
        // would allocate strings for hundreds of entries just to throw them away.
        var scored: [(index: Int, score: Double, pinned: Bool)] = []
        scored.reserveCapacity(32)

        for (index, entry) in pinned.enumerated() {
            guard let base = baseScore(query: query, entry: entry) else { continue }
            let bonus = orderBonus(index: index, count: pinned.count)
            scored.append((index, pinnedBoost + min(base + bonus, 100), true))
        }

        var pinnedCommands = Set<String>(minimumCapacity: pinned.count)
        for entry in pinned { pinnedCommands.insert(entry.command) }

        for (index, entry) in history.enumerated() {
            if pinnedCommands.contains(entry.command) { continue }
            guard let base = baseScore(query: query, entry: entry) else { continue }
            let bonus = orderBonus(index: index, count: history.count)
            scored.append((index, min(base + bonus, 100), false))
        }

        if scored.isEmpty { return [] }

        scored.sort { $0.score > $1.score }

        return scored.prefix(maxResults).map { item in
            let entry = item.pinned ? pinned[item.index] : history[item.index]
            return makeResult(for: entry, score: item.score, isPinned: item.pinned)
        }
    }

    private static func baseScore(query: SearchQuery, entry: ShellCommand) -> Double? {
        guard let score = FuzzyMatcher.score(
            query: query,
            targetLower: entry.lowercased,
            targetTokens: entry.tokens,
            targetInitials: entry.initials
        ), score >= minimumScore else { return nil }
        return score
    }

    /// Earlier positions (more recent history, higher pins) score marginally higher.
    private static func orderBonus(index: Int, count: Int) -> Double {
        guard count > 1 else { return maxRecencyBonus }
        let position = Double(count - 1 - index) / Double(count - 1)
        return maxRecencyBonus * position
    }

    static func makeResult(for entry: ShellCommand, score: Double, isPinned: Bool) -> SearchResult {
        SearchResult(
            id: "history-\(entry.command)",
            title: entry.displayTitle,
            subtitle: isPinned ? "Pinned · Run in Terminal" : "Run in Terminal",
            iconType: .systemSymbol(name: "terminal.fill"),
            category: .shellHistory,
            score: score,
            action: .runInTerminal(command: entry.command),
            isPinned: isPinned
        )
    }

    // MARK: - History File Location

    /// First existing candidate wins. `HISTFILE` / `ZDOTDIR` are only set for
    /// processes launched from a shell, so the plain `~/.zsh_history` path is what
    /// a Finder- or login-item-launched Lightspot normally uses.
    static func historyFileURL() -> URL? {
        let fileManager = FileManager.default
        let home = NSHomeDirectory() as NSString
        let environment = ProcessInfo.processInfo.environment

        var candidates: [String] = []
        if let histfile = environment["HISTFILE"], !histfile.isEmpty {
            candidates.append((histfile as NSString).expandingTildeInPath)
        }
        if let zdotdir = environment["ZDOTDIR"], !zdotdir.isEmpty {
            candidates.append((zdotdir as NSString).appendingPathComponent(".zsh_history"))
        }
        candidates.append(home.appendingPathComponent(".zsh_history"))
        candidates.append(home.appendingPathComponent(".zhistory"))

        for path in candidates where fileManager.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    static func signature(for url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return "" }
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(url.path)|\(size)|\(modified)"
    }

    // MARK: - Parsing

    static func loadEntries(from url: URL) -> [ShellCommand] {
        guard let tail = readTail(of: url, maxBytes: maxTailBytes) else { return [] }
        let text = unmetafy(tail.data)
        let commands = parseCommands(from: text, dropFirstLine: tail.truncated)
        return dedupedEntries(from: commands, limit: maxEntries)
    }

    /// Reads at most `maxBytes` from the end of the file. `truncated` is true when
    /// the read started mid-file, in which case the first (partial) line is dropped.
    static func readTail(of url: URL, maxBytes: UInt64) -> (data: Data, truncated: Bool)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        do {
            let size = try handle.seekToEnd()
            var truncated = false
            if size > maxBytes {
                try handle.seek(toOffset: size - maxBytes)
                truncated = true
            } else {
                try handle.seek(toOffset: 0)
            }
            let data = try handle.readToEnd() ?? Data()
            return (data, truncated)
        } catch {
            return nil
        }
    }

    /// Undoes zsh's "metafication": bytes it cannot store verbatim are written as
    /// `0x83` followed by the original byte XOR 32. Skipping this step mangles every
    /// non-ASCII command in the file.
    static func unmetafy(_ data: Data) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(data.count)

        var pendingMeta = false
        for byte in data {
            if pendingMeta {
                bytes.append(byte ^ 32)
                pendingMeta = false
            } else if byte == 0x83 {
                pendingMeta = true
            } else {
                bytes.append(byte)
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Turns raw history text into commands, oldest first.
    ///
    /// Handles both plain lines and the `EXTENDED_HISTORY` form
    /// (`: <started>:<elapsed>;<command>`), and rejoins the `\`-continued lines
    /// zsh writes for commands that span more than one line.
    static func parseCommands(from text: String, dropFirstLine: Bool = false) -> [String] {
        var commands: [String] = []
        var continued: String? = nil
        var isFirstLine = true

        text.enumerateLines { line, _ in
            let isFirst = isFirstLine
            isFirstLine = false

            // A tail read can start mid-entry; that fragment is not a real command.
            if isFirst && dropFirstLine && continued == nil { return }

            var body: String
            if let pending = continued {
                body = pending + "\n" + line
            } else {
                body = stripTimestamp(line)
            }

            if body.hasSuffix("\\") {
                body.removeLast()
                continued = body
                return
            }
            continued = nil

            let command = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard command.count >= 2, command.count <= maxCommandLength else { return }
            commands.append(command)
        }

        if let pending = continued {
            let command = pending.trimmingCharacters(in: .whitespacesAndNewlines)
            if command.count >= 2 && command.count <= maxCommandLength {
                commands.append(command)
            }
        }

        return commands
    }

    /// Strips the `: <started>:<elapsed>;` prefix of an `EXTENDED_HISTORY` entry.
    /// Lines that only look like one (`: not a timestamp;foo`) are left alone.
    static func stripTimestamp(_ line: String) -> String {
        guard line.hasPrefix(": "), let semicolon = line.firstIndex(of: ";") else { return line }

        let header = line[line.index(line.startIndex, offsetBy: 2)..<semicolon]
        let fields = header.split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count == 2,
              !fields[0].isEmpty, !fields[1].isEmpty,
              fields[0].allSatisfy({ $0.isNumber }),
              fields[1].allSatisfy({ $0.isNumber }) else { return line }

        return String(line[line.index(after: semicolon)...])
    }

    /// De-duplicates newest-first, keeping the most recent occurrence of a command.
    static func dedupedEntries(from commands: [String], limit: Int) -> [ShellCommand] {
        guard limit > 0 else { return [] }

        var seen = Set<String>(minimumCapacity: min(commands.count, limit))
        var entries: [ShellCommand] = []
        entries.reserveCapacity(min(commands.count, limit))

        for command in commands.reversed() {
            if seen.contains(command) { continue }
            seen.insert(command)
            entries.append(ShellCommand(command: command))
            if entries.count >= limit { break }
        }
        return entries
    }
}
