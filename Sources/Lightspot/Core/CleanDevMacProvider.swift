import AppKit

// MARK: - Clean Dev Mac (cdm) Provider
//
// cdm's scan-and-clean, inside Lightspot: the "Clean Dev Mac" search row, and the state
// behind the cleaner overlay. A scan loads cdm's rules, expands their patterns and measures
// every match like `du`, and with it cdm's two notes (what a restart would free, Claude
// Code's history); then, if the user asks, the repo scan adds one row per code repo;
// a clean deletes what the user ticked, each path through cdm's safety gate, and appends a
// receipt to cdm's log. All of it runs on a background queue and publishes snapshots, so
// `search()` and the overlay only ever read memory (invariant 0).

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

    /// The whole cdm, for what only it can clean (Docker / Podman, Rust toolchains,
    /// orphaned app data, and project junk on a Mac without git): run the way its README
    /// runs it, straight from the latest release, with nothing installed.
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
        case .scanningRepos(let done, let total):
            return total == 0 ? "Looking for code repos…" : "Scanning code repos… \(done) of \(total)"
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
        /// The rule's position in its rule set, or `projectIDBase` + n for a repo's row;
        /// stable for one scan.
        let id: Int
        let rule: CleanDevMacRule
        let paths: [String]
        /// KiB per path, aligned with `paths`, as one `du -sk` over all of them prints it:
        /// a file hard-linked into two of them counts in the first.
        let sizes: [Int]
        /// What happens to each path, aligned with `paths`: the rule's method, except in a
        /// repo's row, where regenerable folders are deleted and other ignored files go to
        /// the Trash.
        let methods: [CleanDevMacRule.Method]

        init(id: Int, rule: CleanDevMacRule, paths: [String], sizes: [Int], methods: [CleanDevMacRule.Method]? = nil) {
            self.id = id
            self.rule = rule
            self.paths = paths
            self.sizes = sizes
            self.methods = methods ?? Array(repeating: rule.method, count: paths.count)
        }

        var sizeKB: Int { sizes.reduce(0, +) }
    }

    /// Where repo rows' IDs start, far above any rule's position.
    static let projectIDBase = 100_000

    enum Phase: Sendable, Equatable {
        case idle
        case loadingRules
        case measuring(done: Int, total: Int)
        /// Listing repos with git; `total` is 0 while the home folder is still being walked.
        case scanningRepos(done: Int, total: Int)
        case ready
        case cleaning(done: Int, total: Int)
        case finished
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .loadingRules, .measuring, .scanningRepos, .cleaning: return true
            case .idle, .ready, .finished, .failed: return false
            }
        }
    }

    /// cdm's project scan, from the cleaner's side.
    enum RepoScan: Sendable, Equatable {
        /// No project rules, or no git to prove anything with.
        case unavailable
        /// The caches are measured; scanning the repos is the user's call, as cdm asks.
        case offered
        /// Done, with the number of repos found.
        case scanned(repos: Int)
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
        /// What a restart would free, measured with each scan (cdm's restart estimate).
        var restart: CleanDevMacEngine.RestartEstimate?
        /// Claude Code's session history, when it holds transcripts past Claude Code's own
        /// age limit and nothing has Claude Code age Desktop sessions out.
        var claudeHistory: CleanDevMacEngine.ClaudeHistory?
        var repos: RepoScan = .unavailable
        /// Bumped by every completed scan, so the overlay resets its ticks to the defaults.
        /// The repo scan only adds rows, so it leaves this, and the ticks, alone.
        var generation = 0
    }

    struct Environment: Sendable {
        var home: String
        var bundledRules: URL?
        var processEnvironment: [String: String]
        var fetchRemoteRules: @Sendable (@escaping @Sendable (CleanDevMacRuleSet?) -> Void) -> Void
        var moveToTrash: @Sendable (URL) throws -> Void
        /// The git that proves repo junk ignored; without one the repo scan is cdm's alone.
        var git: String? = CleanDevMacProjects.gitExecutable()
        /// cdm's restart estimate, measured with each scan; nil leaves it out. It reads the
        /// whole machine, not the home folder, so only the live environment measures it.
        var restartEstimate: @Sendable () -> CleanDevMacEngine.RestartEstimate? = { nil }

        static var live: Environment {
            let home = NSHomeDirectory()
            return Environment(
                home: home,
                bundledRules: CleanDevMacRules.bundledDirectory,
                processEnvironment: ProcessInfo.processInfo.environment,
                fetchRemoteRules: { CleanDevMacRules.fetchRemote(completion: $0) },
                moveToTrash: { try CleanDevMacEngine.moveToTrash($0) },
                restartEstimate: { CleanDevMacEngine.restartEstimate(home: home) }
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
    /// The rules of the last scan, which the repo scan reads.
    private var scannedRules: CleanDevMacRuleSet?
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
    /// `includeRepos` runs the repo scan right after, as cdm's rescan does once the user
    /// accepted it.
    func startScan(force: Bool = false, includeRepos: Bool = false) {
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
                    // cdm's notes beside its disk line, measured while the caches are: lsof
                    // alone can take seconds.
                    let notes = Notes()
                    let measuringNotes = DispatchGroup()
                    DispatchQueue.global(qos: .userInitiated).async(group: measuringNotes) { [environment] in
                        notes.restart = environment.restartEstimate()
                        notes.claudeHistory = CleanDevMacEngine.claudeHistory(
                            folder: CleanDevMacEngine.claudeFolder(home: environment.home, environment: environment.processEnvironment),
                            now: Int(Date().timeIntervalSince1970)
                        )
                    }
                    let scan = scanEntries(rules) { done, total in
                        self.reportProgress(.measuring(done: done, total: total))
                    }
                    measuringNotes.wait()
                    let disk = CleanDevMacEngine.diskStats(path: environment.home)
                    let canScanRepos = !rules.projects.isEmpty && environment.git != nil
                    lock.lock()
                    scannedRules = rules
                    lock.unlock()
                    update { state in
                        state.phase = .ready
                        state.entries = scan.entries
                        state.terminalOnly = scan.terminalOnly
                        state.source = rules.source
                        state.disk = disk
                        state.restart = notes.restart
                        state.claudeHistory = notes.claudeHistory
                        state.scannedAt = Date()
                        state.receipt = nil
                        state.repos = canScanRepos ? .offered : .unavailable
                        state.generation += 1
                    }
                    if includeRepos { scanRepos() }
                case .failure(let message):
                    update { $0.phase = .failed(message.text) }
                }
            }
        }
    }

    struct LoadFailure: Error {
        let text: String
    }

    /// Carries the notes out of the block that measures them; read only after it is done.
    private final class Notes: @unchecked Sendable {
        var restart: CleanDevMacEngine.RestartEstimate?
        var claudeHistory: CleanDevMacEngine.ClaudeHistory?
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

    /// Where the IDs of a rule's rows start when it offers one row per item (an idle
    /// AVD's image): above every rule's position, below `projectIDBase`.
    static let itemIDBase = 50_000

    /// Blocking: what `rules` find under the home folder, biggest first, plus the names of
    /// the categories left to cdm (its own terminal-only ones, and any whose every pattern
    /// lies in a folder Lightspot does not read).
    func scanEntries(_ rules: CleanDevMacRuleSet, now: Date = Date(),
                     progress: (@Sendable (_ done: Int, _ total: Int) -> Void)? = nil) -> (entries: [Entry], terminalOnly: [String]) {
        let home = environment.home
        let physicalHome = CleanDevMacEngine.physicalPath(home)
        let seconds = Int(now.timeIntervalSince1970)
        let avdUsers = rules.rules.contains { $0.kind == .androidImages || $0.kind == .androidIdleImages }
            ? CleanDevMacEngine.avdImageUsers(home: home, environment: environment.processEnvironment)
            : []
        let imagesInUse = avdUsers.map(\.ref)
        var terminalOnly = rules.terminalOnly
        if !rules.projects.isEmpty && environment.git == nil {
            // Nothing can be proven ignored without git, so the repo scan stays with cdm.
            terminalOnly += rules.projects.categoryNames
        }
        var candidates: [(id: Int, rule: CleanDevMacRule, paths: [String])] = []
        var nextItemID = Self.itemIDBase
        for (id, rule) in rules.rules.enumerated() {
            if rule.patterns.allSatisfy({ CleanDevMacEngine.isOutOfScope(CleanDevMacEngine.expandTilde($0, home: home), home: home) }) {
                terminalOnly.append(rule.name)
                continue
            }
            switch rule.kind {
            case .androidIdleImages:
                guard let days = rule.idleDays else { continue }
                for image in CleanDevMacEngine.idleImages(patterns: rule.patterns, users: avdUsers, days: days, now: seconds,
                                                          home: home, physicalHome: physicalHome) {
                    candidates.append((nextItemID, Self.idleImageRule(rule, image), [image.path]))
                    nextItemID += 1
                }
            case .claudeTranscripts:
                guard let days = rule.idleDays else { continue }
                let old = CleanDevMacEngine.oldTranscripts(patterns: rule.patterns, days: days, now: seconds,
                                                           home: home, physicalHome: physicalHome)
                if old.sessions > 0 { candidates.append((id, Self.transcriptsRule(rule, sessions: old.sessions), old.paths)) }
            case .olderVersions:
                let paths = CleanDevMacEngine.olderVersionPaths(patterns: rule.patterns, home: home, physicalHome: physicalHome)
                if !paths.isEmpty { candidates.append((id, rule, paths)) }
            case .paths, .androidImages, .project:
                var paths = CleanDevMacEngine.matchedPaths(
                    patterns: rule.patterns, home: home, physicalHome: physicalHome,
                    skip: rule.kind == .androidImages ? imagesInUse : []
                )
                if rule.method == .emptytrash {
                    paths = paths.filter { $0 == CleanDevMacEngine.trashPath(home: home) }
                }
                if !paths.isEmpty { candidates.append((id, rule, paths)) }
            }
        }

        let measured = Self.measure(candidates.map(\.paths), progress: progress)
        let entries = candidates.enumerated()
            .map { Entry(id: $0.element.id, rule: $0.element.rule, paths: $0.element.paths, sizes: measured[$0.offset]) }
        return (Self.biggestFirst(entries), terminalOnly)
    }

    /// One idle image's row, as cdm writes it: named after the image, and saying which
    /// AVDs would no longer boot and how to reinstall it.
    static func idleImageRule(_ rule: CleanDevMacRule, _ image: CleanDevMacEngine.IdleImage) -> CleanDevMacRule {
        let relative = image.path.range(of: "/system-images/").map { String(image.path[$0.upperBound...]) }
            ?? (image.path as NSString).lastPathComponent
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let since = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(image.lastStarted)))
        let package = "system-images;" + relative.replacingOccurrences(of: "/", with: ";")
        return CleanDevMacRule(
            kind: rule.kind, icon: rule.icon, name: "\(rule.name): \(relative)",
            desc: "Booted only by \(image.avds.joined(separator: ", ")), last started \(since). \(rule.desc) Reinstall: sdkmanager \"\(package)\"",
            method: rule.method, isDefault: rule.isDefault, patterns: rule.patterns, procs: rule.procs, idleDays: rule.idleDays
        )
    }

    /// The old transcripts' row, saying how many sessions it holds, as cdm's row does.
    static func transcriptsRule(_ rule: CleanDevMacRule, sessions: Int) -> CleanDevMacRule {
        CleanDevMacRule(
            kind: rule.kind, icon: rule.icon, name: rule.name,
            desc: "\(sessions) \(sessions == 1 ? "session" : "sessions"). \(rule.desc)",
            method: rule.method, isDefault: rule.isDefault, patterns: rule.patterns, procs: rule.procs, idleDays: rule.idleDays
        )
    }

    /// Measures every path, several at a time: it is file-system walking, and the big
    /// caches (DerivedData, Gradle, node_modules) dominate however it is ordered. Each list
    /// is sized as cdm sizes a row, with one `du` over all its paths, so a file hard-linked
    /// into two of them counts once (`CleanDevMacEngine.allocatedKB(_:)`). Sizes come back
    /// aligned with `pathLists`.
    static func measure(_ pathLists: [[String]], progress: (@Sendable (_ done: Int, _ total: Int) -> Void)? = nil) -> [[Int]] {
        let jobs = pathLists.enumerated().flatMap { list in
            list.element.enumerated().map { (list: list.offset, index: $0.offset, path: $0.element) }
        }
        let sizes = Measurements(pathLists.map(\.count))
        progress?(0, jobs.count)
        DispatchQueue.concurrentPerform(iterations: jobs.count) { index in
            let job = jobs[index]
            let done = sizes.record(CleanDevMacEngine.usage(job.path) ?? CleanDevMacEngine.Usage(), list: job.list, path: job.index)
            progress?(done, jobs.count)
        }
        return sizes.all
    }

    /// Entries with something in them, biggest first; equal sizes keep rule order.
    static func biggestFirst(_ entries: [Entry]) -> [Entry] {
        entries.filter { $0.sizeKB > 0 }.sorted { $0.sizeKB != $1.sizeKB ? $0.sizeKB > $1.sizeKB : $0.id < $1.id }
    }

    // MARK: Repo scan

    /// cdm's "Also scan your code repos for build/dependency junk?": only after a cache
    /// scan that offered it. Adds one row per repo (or group root) to the list, unticked,
    /// and keeps whatever the user had ticked.
    func scanRepos() {
        lock.lock()
        guard state.phase == .ready, state.repos == .offered, let rules = scannedRules, let git = environment.git else {
            lock.unlock()
            return
        }
        state.phase = .scanningRepos(done: 0, total: 0)
        lock.unlock()
        notify()

        queue.async { [self] in
            let found = CleanDevMacProjects.scan(rules.projects, home: environment.home, git: git) { done, total in
                self.reportProgress(.scanningRepos(done: done, total: total))
            }
            let rows = projectEntries(found.projects) { done, total in
                self.reportProgress(.measuring(done: done, total: total))
            }
            let disk = CleanDevMacEngine.diskStats(path: environment.home)
            update { state in
                state.phase = .ready
                state.entries = Self.biggestFirst(state.entries + rows)
                state.repos = .scanned(repos: found.repoCount)
                state.disk = disk ?? state.disk
            }
        }
    }

    /// Blocking: measured rows for `projects`, named after each repo, as cdm names them.
    func projectEntries(_ projects: [CleanDevMacProjects.Project],
                        progress: (@Sendable (_ done: Int, _ total: Int) -> Void)? = nil) -> [Entry] {
        let home = environment.home
        let measured = Self.measure(projects.map(\.paths), progress: progress)
        return projects.enumerated().map { index, project in
            let shown = CleanDevMacEngine.displayPath(project.key, home: home)
            let rule = CleanDevMacRule(
                kind: .project,
                icon: "📁",
                name: shown,
                desc: "Project junk in \(shown): \(project.summary). Everything here is git-ignored: regenerable build/dependency dirs are deleted; other ignored items (e.g. local config, logs) go to the Trash (recoverable); .env* files are always left alone.",
                method: .rm,
                isDefault: false,
                patterns: [],
                procs: []
            )
            return Entry(id: Self.projectIDBase + index, rule: rule, paths: project.paths, sizes: measured[index], methods: project.methods)
        }
    }

    private final class Measurements: @unchecked Sendable {
        private let lock = NSLock()
        private var sizes: [[Int]]
        /// Each list's walks until its last path is in; then the list is sized and they go.
        private var walks: [[CleanDevMacEngine.Usage]]
        private var pending: [Int]
        private var done = 0

        init(_ counts: [Int]) {
            sizes = counts.map { [Int](repeating: 0, count: $0) }
            walks = counts.map { [CleanDevMacEngine.Usage](repeating: CleanDevMacEngine.Usage(), count: $0) }
            pending = counts
        }

        /// Stores one path's walk, sizes its list once the list is complete, and returns
        /// how many paths are measured in all.
        func record(_ walk: CleanDevMacEngine.Usage, list: Int, path: Int) -> Int {
            lock.lock()
            defer { lock.unlock() }
            walks[list][path] = walk
            pending[list] -= 1
            if pending[list] == 0 {
                sizes[list] = CleanDevMacEngine.allocatedKB(walks[list])
                walks[list] = []
            }
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
            for (index, path) in entry.paths.enumerated() {
                let size = entry.sizes[index]
                let method = entry.methods[index]
                let shown = CleanDevMacEngine.displayPath(path, home: home)
                let outcome = CleanDevMacEngine.delete(path, method: method, home: home,
                                                       physicalHome: physicalHome, trash: environment.moveToTrash)
                switch outcome {
                case .alreadyGone:
                    break
                case .deleted:
                    switch method {
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
                    let verb = method == .trash ? "trash" : "delete"
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
