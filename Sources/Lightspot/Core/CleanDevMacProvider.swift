import AppKit

// MARK: - Clean Dev Mac (cdm) Provider
//
// cdm's scan-and-clean, inside Lightspot: the "Clean Dev Mac" search row, and the state
// behind the cleaner overlay. A scan loads cdm's rules, expands their patterns and measures
// every match like `du`; a clean deletes what the user ticked, each path through cdm's
// safety gate, and appends a receipt to cdm's log. Both run on a background queue and
// publish snapshots, so `search()` and the overlay only ever read memory (invariant 0).

final class CleanDevMacProvider: @unchecked Sendable {
    static let shared = CleanDevMacProvider()

    // MARK: Search row

    static let resultID = "action-clean-dev-mac"
    /// The row's action. A sentinel, like `internal:copy-ip`: `SearchAction` is Codable and
    /// persisted in search history, and the view model opens the cleaner on it.
    static let openScript = "internal:clean-dev-mac"
    static let title = "Clean Dev Mac"
    /// Stored in search history in place of the live subtitle, whose sizes go stale.
    static let fixedSubtitle = "Reclaim disk from dev caches & build artifacts (cdm)"
    static let symbol = "sparkles"

    static let keywords = [
        "cdm", "cleandevmac", "clean mac", "cleanup", "clean up", "cleaner", "disk cleanup",
        "reclaim disk", "reclaim space", "free up space", "free up disk", "dev caches",
        "developer caches", "build caches", "clear cache", "clear caches", "cache cleaner",
        "derived data", "deriveddata", "xcode cache", "npm cache", "gradle cache", "junk",
    ]
    private static let lowercaseTitle = title.lowercased()

    /// The whole cdm, for what only it can clean (project junk, Docker / Podman, orphaned
    /// app data): run the way its README runs it, straight from the latest release, with
    /// nothing installed.
    static let terminalCommand = "curl -fsSL https://github.com/cleandevmac/cdm/releases/latest/download/cdm | bash"

    static func openInTerminal() {
        TerminalLauncher.run(terminalCommand)
    }

    func search(_ query: SearchQuery) -> [SearchResult] {
        guard !query.isEmpty else { return [] }
        var best = FuzzyMatcher.score(query: query, targetLower: Self.lowercaseTitle, targetTokens: [], targetInitials: nil)
        for keyword in Self.keywords {
            if let score = FuzzyMatcher.score(query: query, targetLower: keyword, targetTokens: [], targetInitials: nil) {
                best = max(best ?? 0, score * 0.95)
            }
        }
        guard let score = best else { return [] }
        return [SearchResult(
            id: Self.resultID,
            title: Self.title,
            subtitle: Self.subtitle(for: snapshot),
            iconType: .systemSymbol(name: Self.symbol),
            category: .quickActions,
            score: score,
            action: .runQuickAction(script: Self.openScript, usesOsascript: false)
        )]
    }

    static func subtitle(for snapshot: Snapshot) -> String {
        switch snapshot.phase {
        case .idle, .failed:
            return "Find dev caches & build junk to reclaim (cdm) · ↵ Scan · ⌘↵ cdm in Terminal"
        case .loadingRules:
            return "Loading cdm's rules…"
        case .measuring(let done, let total):
            return "Measuring reclaimable space… \(done) of \(total)"
        case .ready:
            guard !snapshot.entries.isEmpty else { return "Nothing to reclaim · ↵ Rescan · ⌘↵ cdm in Terminal" }
            let count = snapshot.entries.count
            return "\(CleanDevMacEngine.humanKB(uniqueKB(snapshot.entries))) reclaimable in \(count) \(count == 1 ? "category" : "categories") · ↵ Review · ⌘↵ cdm in Terminal"
        case .cleaning(let done, let total):
            return "Cleaning… \(done) of \(total)"
        case .finished:
            return "Freed \(CleanDevMacEngine.humanKB(snapshot.receipt?.freedKB ?? 0)) · ↵ Rescan"
        }
    }

    // MARK: State

    /// One category the scan found something for.
    struct Entry: Sendable, Equatable, Identifiable {
        /// The rule's position in its rule set; stable for one scan.
        let id: Int
        let rule: CleanDevMacRule
        let paths: [String]
        /// KiB per path, aligned with `paths`.
        let sizes: [Int]

        var sizeKB: Int { sizes.reduce(0, +) }
    }

    enum Phase: Sendable, Equatable {
        case idle
        case loadingRules
        case measuring(done: Int, total: Int)
        case ready
        case cleaning(done: Int, total: Int)
        case finished
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .loadingRules, .measuring, .cleaning: return true
            case .idle, .ready, .finished, .failed: return false
            }
        }
    }

    struct Receipt: Sendable, Equatable {
        /// Measured size of what was deleted or moved to the Trash.
        let freedKB: Int
        let removedCount: Int
        let movedToTrash: Bool
        /// One line per path that was refused or could not be removed.
        let problems: [String]
        let diskBefore: CleanDevMacEngine.DiskStats?
        let diskAfter: CleanDevMacEngine.DiskStats?
    }

    struct Snapshot: Sendable, Equatable {
        var phase: Phase = .idle
        /// Biggest first.
        var entries: [Entry] = []
        /// Categories only cdm cleans; the overlay names them next to ⌘↵.
        var terminalOnly: [String] = []
        var source: CleanDevMacRuleSet.Source?
        var disk: CleanDevMacEngine.DiskStats?
        var scannedAt: Date?
        var receipt: Receipt?
        /// Bumped by every completed scan, so the overlay resets its ticks to the defaults.
        var generation = 0
    }

    struct Environment: Sendable {
        var home: String
        var bundledRules: URL?
        var processEnvironment: [String: String]
        var fetchRemoteRules: @Sendable (@escaping @Sendable (CleanDevMacRuleSet?) -> Void) -> Void
        var moveToTrash: @Sendable (URL) throws -> Void

        static var live: Environment {
            Environment(
                home: NSHomeDirectory(),
                bundledRules: CleanDevMacRules.bundledDirectory,
                processEnvironment: ProcessInfo.processInfo.environment,
                fetchRemoteRules: { CleanDevMacRules.fetchRemote(completion: $0) },
                moveToTrash: { try CleanDevMacEngine.moveToTrash($0) }
            )
        }
    }

    /// A finished scan stands this long before opening the cleaner measures again.
    static let rescanAfter: TimeInterval = 5 * 60
    /// Rules fetched from GitHub are reused this long.
    static let remoteRulesLifetime: TimeInterval = 60 * 60

    let environment: Environment
    private let lock = NSLock()
    private var state = Snapshot()
    private var remoteRules: (rules: CleanDevMacRuleSet, fetchedAt: Date)?
    private var observer: (@Sendable () -> Void)?
    private var lastProgressReport = Date.distantPast
    private let queue = DispatchQueue(label: "com.lightspot.cleandevmac", qos: .userInitiated)

    init(environment: Environment = .live) {
        self.environment = environment
    }

    /// Non-blocking: the latest state, for `search()` and the overlay.
    var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    /// Called on the main queue after each change of `snapshot`.
    func setObserver(_ observer: (@Sendable () -> Void)?) {
        lock.lock()
        self.observer = observer
        lock.unlock()
    }

    private func notify() {
        lock.lock()
        let observer = self.observer
        lock.unlock()
        if let observer { DispatchQueue.main.async(execute: observer) }
    }

    private func update(_ change: (inout Snapshot) -> Void) {
        lock.lock()
        change(&state)
        lock.unlock()
        notify()
    }

    /// Progress is reported at most ten times a second: a scan measures a few hundred
    /// paths, and every report is a SwiftUI pass.
    private func reportProgress(_ phase: Phase) {
        lock.lock()
        state.phase = phase
        let now = Date()
        let due = now.timeIntervalSince(lastProgressReport) >= 0.1
        if due { lastProgressReport = now }
        lock.unlock()
        if due { notify() }
    }

    /// Size of `entries` with a path that two categories share counted once.
    static func uniqueKB(_ entries: [Entry]) -> Int {
        var seen = Set<String>()
        var total = 0
        for entry in entries {
            for (path, size) in zip(entry.paths, entry.sizes) where seen.insert(path).inserted {
                total += size
            }
        }
        return total
    }

    // MARK: Scanning

    /// Starts a scan unless one is running, or (without `force`) a recent one stands.
    func startScan(force: Bool = false) {
        lock.lock()
        let fresh = state.phase == .ready && state.scannedAt.map { Date().timeIntervalSince($0) < Self.rescanAfter } == true
        guard !state.phase.isBusy, force || !fresh else {
            lock.unlock()
            return
        }
        state.phase = .loadingRules
        lock.unlock()
        notify()

        resolveRules { [self] result in
            queue.async { [self] in
                switch result {
                case .success(let rules):
                    let scan = scanEntries(rules) { done, total in
                        self.reportProgress(.measuring(done: done, total: total))
                    }
                    let disk = CleanDevMacEngine.diskStats(path: environment.home)
                    update { state in
                        state.phase = .ready
                        state.entries = scan.entries
                        state.terminalOnly = scan.terminalOnly
                        state.source = rules.source
                        state.disk = disk
                        state.scannedAt = Date()
                        state.receipt = nil
                        state.generation += 1
                    }
                case .failure(let message):
                    update { $0.phase = .failed(message.text) }
                }
            }
        }
    }

    struct LoadFailure: Error {
        let text: String
    }

    /// cdm's order: its local rules folder if there is one, then GitHub, then — unlike
    /// piped cdm, which has no copy of its own — the rules shipped in the app. A local
    /// folder that cannot be read is an error, not a reason to go online: the user wrote
    /// those rules, possibly to keep something out of reach.
    func resolveRules(completion: @escaping @Sendable (Result<CleanDevMacRuleSet, LoadFailure>) -> Void) {
        queue.async { [self] in
            let local = CleanDevMacRules.localDirectory(home: environment.home)
            if FileManager.default.fileExists(atPath: local.appendingPathComponent(CleanDevMacRules.indexFileName).path) {
                if let rules = CleanDevMacRules.load(directory: local, source: .local) {
                    completion(.success(rules))
                } else {
                    completion(.failure(LoadFailure(text: "The rules in ~/.cleandevmac/rules could not be read.")))
                }
                return
            }
            lock.lock()
            let cached = remoteRules.flatMap { Date().timeIntervalSince($0.fetchedAt) < Self.remoteRulesLifetime ? $0.rules : nil }
            lock.unlock()
            if let cached {
                completion(.success(cached))
                return
            }
            environment.fetchRemoteRules { [self] fetched in
                if let fetched {
                    lock.lock()
                    remoteRules = (fetched, Date())
                    lock.unlock()
                    completion(.success(fetched))
                } else if let bundled = environment.bundledRules.flatMap({ CleanDevMacRules.load(directory: $0, source: .bundled) }) {
                    completion(.success(bundled))
                } else {
                    completion(.failure(LoadFailure(text: "cdm's rules could not be loaded from GitHub.")))
                }
            }
        }
    }

    /// Blocking: what `rules` find under the home folder, biggest first, plus the names of
    /// the categories left to cdm (its own terminal-only ones, and any whose every pattern
    /// lies in a folder Lightspot does not read).
    func scanEntries(_ rules: CleanDevMacRuleSet,
                     progress: (@Sendable (_ done: Int, _ total: Int) -> Void)? = nil) -> (entries: [Entry], terminalOnly: [String]) {
        let home = environment.home
        let physicalHome = CleanDevMacEngine.physicalPath(home)
        let imagesInUse = rules.rules.contains { $0.kind == .androidImages }
            ? CleanDevMacEngine.avdImageRefs(home: home, environment: environment.processEnvironment)
            : []
        var terminalOnly = rules.terminalOnly
        var candidates: [(id: Int, rule: CleanDevMacRule, paths: [String])] = []
        for (id, rule) in rules.rules.enumerated() {
            if rule.patterns.allSatisfy({ CleanDevMacEngine.isOutOfScope(CleanDevMacEngine.expandTilde($0, home: home), home: home) }) {
                terminalOnly.append(rule.name)
                continue
            }
            var paths = CleanDevMacEngine.matchedPaths(
                patterns: rule.patterns, home: home, physicalHome: physicalHome,
                skip: rule.kind == .androidImages ? imagesInUse : []
            )
            if rule.method == .emptytrash {
                paths = paths.filter { $0 == CleanDevMacEngine.trashPath(home: home) }
            }
            if !paths.isEmpty { candidates.append((id, rule, paths)) }
        }

        // Measure every path, several at a time: it is file-system walking, and the big
        // caches (DerivedData, Gradle, the module caches) dominate however it is ordered.
        let found = candidates
        let jobs = found.enumerated().flatMap { candidate in
            candidate.element.paths.enumerated().map { (candidate: candidate.offset, index: $0.offset, path: $0.element) }
        }
        let sizes = Measurements(found.map { $0.paths.count })
        progress?(0, jobs.count)
        DispatchQueue.concurrentPerform(iterations: jobs.count) { index in
            let job = jobs[index]
            let done = sizes.record(CleanDevMacEngine.allocatedKB(job.path), candidate: job.candidate, path: job.index)
            progress?(done, jobs.count)
        }

        let measured = sizes.all
        let entries = found.enumerated()
            .map { Entry(id: $0.element.id, rule: $0.element.rule, paths: $0.element.paths, sizes: measured[$0.offset]) }
            .filter { $0.sizeKB > 0 }
            .sorted { $0.sizeKB != $1.sizeKB ? $0.sizeKB > $1.sizeKB : $0.id < $1.id }
        return (entries, terminalOnly)
    }

    private final class Measurements: @unchecked Sendable {
        private let lock = NSLock()
        private var sizes: [[Int]]
        private var done = 0

        init(_ counts: [Int]) {
            sizes = counts.map { [Int](repeating: 0, count: $0) }
        }

        /// Stores one path's size and returns how many paths are measured in all.
        func record(_ kb: Int, candidate: Int, path: Int) -> Int {
            lock.lock()
            defer { lock.unlock() }
            sizes[candidate][path] = kb
            done += 1
            return done
        }

        var all: [[Int]] {
            lock.lock()
            defer { lock.unlock() }
            return sizes
        }
    }

    // MARK: Cleaning

    /// Cleans the entries of the current scan whose IDs are given. Only from `.ready`:
    /// the overlay confirms the plan first, and a second clean of the same scan would act
    /// on sizes that no longer exist.
    func clean(_ ids: Set<Int>) {
        lock.lock()
        let selected = state.entries.filter { ids.contains($0.id) }
        guard state.phase == .ready, !selected.isEmpty else {
            lock.unlock()
            return
        }
        let total = selected.reduce(0) { $0 + $1.paths.count }
        state.phase = .cleaning(done: 0, total: total)
        lock.unlock()
        notify()

        queue.async { [self] in
            let receipt = performClean(selected) { done in
                self.reportProgress(.cleaning(done: done, total: total))
            }
            update { state in
                state.phase = .finished
                state.receipt = receipt
                state.entries = []
                state.disk = receipt.diskAfter ?? state.disk
            }
        }
    }

    /// Blocking: removes every path of `entries` with its category's method, each through
    /// the safety gate, and appends the run to cdm's log. A path two categories share is
    /// removed, and counted, once.
    func performClean(_ entries: [Entry], now: Date = Date(), progress: ((Int) -> Void)? = nil) -> Receipt {
        let home = environment.home
        let physicalHome = CleanDevMacEngine.physicalPath(home)
        let diskBefore = CleanDevMacEngine.diskStats(path: home)
        let rule = String(repeating: "=", count: 50)
        var log = "\(rule)\nCleanDevMac run (Lightspot): \(CleanDevMacEngine.logDate(now))\n\(rule)\n"
        var freed = 0
        var removed = 0
        var movedToTrash = false
        var problems: [String] = []
        var done = 0
        for entry in entries {
            log += "▸ \(entry.rule.name)\n"
            for (path, size) in zip(entry.paths, entry.sizes) {
                let shown = CleanDevMacEngine.displayPath(path, home: home)
                let outcome = CleanDevMacEngine.delete(path, method: entry.rule.method, home: home,
                                                       physicalHome: physicalHome, trash: environment.moveToTrash)
                switch outcome {
                case .alreadyGone:
                    break
                case .deleted:
                    switch entry.rule.method {
                    case .emptytrash: log += "  Trash emptied.\n"
                    case .rmforce: log += "  cleared: \(shown)\n"
                    case .rm, .trash: log += "  deleted: \(shown)\n"
                    }
                case .trashed:
                    log += "  trashed: \(shown)\n"
                    movedToTrash = true
                case .unsafe:
                    log += "  skip (unsafe): \(path)\n"
                    problems.append("Skipped (unsafe): \(shown)")
                case .failed(let reason):
                    let verb = entry.rule.method == .trash ? "trash" : "delete"
                    log += "  failed to \(verb): \(shown) (\(reason))\n"
                    problems.append("Could not \(verb) \(shown): \(reason)")
                }
                if outcome.removed {
                    freed += size
                    removed += 1
                }
                done += 1
                progress?(done)
            }
        }
        log += "\(rule)\nFinished: \(CleanDevMacEngine.logDate(Date()))\n\(rule)\n"
        CleanDevMacEngine.appendToLog(log, home: home, now: now)
        return Receipt(
            freedKB: freed,
            removedCount: removed,
            movedToTrash: movedToTrash,
            problems: problems,
            diskBefore: diskBefore,
            diskAfter: CleanDevMacEngine.diskStats(path: home)
        )
    }

    /// The `procs` of `entries` that are running now: apps that would rewrite the caches
    /// they own while they are cleared. Each named once, in rule order.
    static func runningApps(for entries: [Entry], running: Set<String> = CleanDevMacEngine.runningProcessNames()) -> [String] {
        var names: [String] = []
        for name in entries.flatMap(\.rule.procs) where running.contains(name) && !names.contains(name) {
            names.append(name)
        }
        return names
    }
}
