import AppKit

// MARK: - Mac Tweaks Provider
//
// The "Mac Tweaks" search row and the state behind its overlay: one section per job
// (Free Up Space, Apple Intelligence and Settings now; Background Items in a later release),
// each with an engine that scans and applies. Scans and applies run on the
// provider's own queue and publish snapshots, so `search()` and the overlay only ever
// read memory (invariant 0). Nothing runs until the user opens Mac Tweaks: at launch
// and on every keystroke the row is static text plus the last scan's total.
//
// A later section adds a case to `MacTweaksSection.built`, an engine conforming to
// `MacTweaksSectionEngine` returned by `MacTweaksProvider.engine(for:)`, and whatever its
// engine needs in `Environment`. Rows, plans, progress and receipts are shared types, so
// the overlay, the model and the key routing take a new section as it is.

/// The overlay's sections, in tab order.
enum MacTweaksSection: String, CaseIterable, Sendable {
    case freeUpSpace = "free-up-space"
    case appleIntelligence = "apple-intelligence"
    case settings
    case backgroundItems = "background-items"

    var title: String {
        switch self {
        case .freeUpSpace: return "Free Up Space"
        case .appleIntelligence: return "Apple Intelligence"
        case .settings: return "Settings"
        case .backgroundItems: return "Background Items"
        }
    }

    var symbol: String {
        switch self {
        case .freeUpSpace: return "internaldrive"
        case .appleIntelligence: return "brain"
        case .settings: return "gearshape"
        case .backgroundItems: return "gearshape.2"
        }
    }

    /// What the overlay says while the section's scan starts.
    var scanningTitle: String {
        switch self {
        case .freeUpSpace: return "Looking for space to free…"
        case .appleIntelligence: return "Checking Apple Intelligence…"
        case .settings: return "Reading your settings…"
        case .backgroundItems: return "Looking at background items…"
        }
    }

    /// The sections this build has, in tab order. Only these are shown, scanned or reachable
    /// with ⇥. Apple Intelligence only where it exists: Apple silicon, and a macOS with at least
    /// one of its features (none before 15.1). Settings everywhere: macOS 13 has most of its
    /// tweaks.
    static let built: [MacTweaksSection] =
        sections(appleIntelligence: Catalog.hasAppleSilicon && !Catalog.availableFeatures.isEmpty)

    static func sections(appleIntelligence: Bool) -> [MacTweaksSection] {
        (appleIntelligence ? [.freeUpSpace, .appleIntelligence] : [.freeUpSpace]) + [.settings]
    }

    /// Its position in `allCases`: per-section state is kept in arrays, not in dictionaries
    /// keyed by the section, whose generic code costs binary size for nothing at four keys.
    var index: Int {
        switch self {
        case .freeUpSpace: return 0
        case .appleIntelligence: return 1
        case .settings: return 2
        case .backgroundItems: return 3
        }
    }
}

/// Where a link row's ↵ goes. The overlay hands it to the view model, which owns the panel.
enum MacTweaksLink: Sendable, Equatable {
    /// The Clean Dev Mac overlay.
    case cleanDevMac
    /// A System Settings pane.
    case settings(deepLink: String)
    /// Another Mac Tweaks section (Free Up Space's "Apple Intelligence models" row).
    case section(MacTweaksSection)
}

/// One thing a row acts on.
struct MacTweaksItem: Sendable, Equatable {
    /// A path, or for a snapshot its date.
    let target: String
    /// Allocated bytes, as `du` counts them; 0 where macOS can't say.
    var bytes: Int64 = 0
    /// Another user owns it, so moving it takes the administrator batch.
    var isForeign = false
}

/// One row of a section: what it is, what it holds and what applying it does. Engines fill
/// these in; the overlay only displays them.
struct MacTweaksRow: Sendable, Equatable, Identifiable {
    /// Stable across scans: the catalog's ID.
    let id: String
    let symbol: String
    let title: String
    let detail: String
    /// Shown in the warning color.
    var caveat: String?
    var items: [MacTweaksItem] = []
    /// What it frees; nil when macOS can't say (snapshots).
    var bytes: Int64?
    /// Shown instead of a size: "4 snapshots".
    var countLabel: String?
    var isDefault = false
    /// Capsules beside the size: "Deleted right away", "May ask for password".
    var tags: [String] = []
    /// What applying does to it, as the plan says it: "Moved to the Trash".
    var outcome = ""
    /// ↵ opens this instead; never ticked.
    var link: MacTweaksLink?
    /// ⌥↵: shows its first item in Finder.
    var revealsInFinder = false
    /// Shown with a lock instead of a checkbox; Space does nothing (a feature another profile
    /// sets, or one Lightspot's own profile already locks off).
    var readOnly = false
    /// Applied on its own: ticking it unticks every other row, and ticking another unticks it
    /// (Apple Intelligence's turn-on and finish rows, Settings' Undo everything).
    var exclusive = false
    /// The header of the group it belongs to (Settings): the list draws it above the first row of
    /// each group.
    var group: String?
    /// Ticking it undoes something (Settings' On rows): the box shows an undo arrow.
    var undoes = false
    /// A preset: Space ticks these rows, or unticks them when they all are. Never applied itself.
    var ticks: [String]?

    var isLink: Bool { link != nil }
    var isPreset: Bool { ticks != nil }

    /// The right-hand column.
    var value: String {
        if let countLabel { return countLabel }
        return bytes.map(MacTweaksProvider.size) ?? ""
    }
}

/// What an apply did, as the overlay shows it and the log records it.
struct MacTweaksReceipt: Sendable, Equatable {
    var headline: String
    var lines: [String] = []
    /// What stayed and why, in the warning color.
    var problems: [String] = []
    var notes: [String] = []
    /// What ⌥↵ shows in Finder from the receipt: an app macOS wouldn't let go.
    var reveal: String?
    /// It did what was asked: the receipt shows the green check only then.
    var isSuccess = true
}

/// Which rows are ticked: each row's default after a scan, and Space's change. Pure, so it is
/// tested; the overlay's model applies it.
enum MacTweaksTicks {
    /// A row Space can tick: not a link, not read-only.
    static func isTickable(_ row: MacTweaksRow?) -> Bool {
        guard let row else { return false }
        return !row.isLink && !row.readOnly
    }

    static func hasTickable(_ rows: [MacTweaksRow]) -> Bool { rows.contains { isTickable($0) } }

    /// The rows ticked after a scan: those that default to it, an exclusive one alone.
    static func defaults(_ rows: [MacTweaksRow]) -> Set<String> {
        let ticked = rows.filter { $0.isDefault && isTickable($0) }
        if let exclusive = ticked.first(where: \.exclusive) { return [exclusive.id] }
        return Set(ticked.map(\.id))
    }

    /// Space on `id`: ticks or unticks it. An exclusive row is applied alone, so ticking it
    /// unticks the rest, and ticking any other row unticks the exclusive ones. A preset ticks the
    /// rows it names that Space can tick (unticking them when they all are already), and is never
    /// ticked itself.
    static func toggled(_ ticks: Set<String>, _ id: String, in rows: [MacTweaksRow]) -> Set<String> {
        guard let row = rows.first(where: { $0.id == id }), isTickable(row) else { return ticks }
        if let named = row.ticks {
            let targets = presetTargets(named, in: rows)
            guard !targets.isEmpty else { return ticks }
            if targets.allSatisfy(ticks.contains) { return ticks.subtracting(targets) }
            return ticks.subtracting(rows.filter(\.exclusive).map(\.id)).union(targets)
        }
        if ticks.contains(id) { return ticks.subtracting([id]) }
        if row.exclusive { return [id] }
        return ticks.subtracting(rows.filter(\.exclusive).map(\.id)).union([id])
    }

    /// The rows a preset can tick: those it names that are tickable, neither presets nor exclusive.
    static func presetTargets(_ named: [String], in rows: [MacTweaksRow]) -> [String] {
        named.filter { id in rows.first { $0.id == id }.map { isTickable($0) && !$0.isPreset && !$0.exclusive } ?? false }
    }

    /// The rows an apply gets: ticked, and neither links nor presets.
    static func ticked(_ rows: [MacTweaksRow], _ ticks: Set<String>) -> [MacTweaksRow] {
        rows.filter { !$0.isLink && !$0.isPreset && ticks.contains($0.id) }
    }

    /// How a row's box is drawn.
    enum Box: Sendable, Equatable {
        case link, locked, unticked, ticked, undo
        /// A preset with some, not all, of its rows ticked.
        case mixed
    }

    static func box(_ row: MacTweaksRow, _ ticks: Set<String>, in rows: [MacTweaksRow]) -> Box {
        if row.isLink { return .link }
        if row.readOnly { return .locked }
        if let named = row.ticks {
            let targets = presetTargets(named, in: rows)
            let on = targets.filter(ticks.contains).count
            return targets.isEmpty || on == 0 ? .unticked : (on == targets.count ? .ticked : .mixed)
        }
        guard ticks.contains(row.id) else { return .unticked }
        return row.undoes ? .undo : .ticked
    }
}

/// One section's engine. Both calls block: the provider runs them on its queue.
protocol MacTweaksSectionEngine: Sendable {
    /// What the section offers now, in display order; `only` limits it to those row IDs
    /// (the verify pass after an apply).
    func scan(only: Set<String>?, progress: (@Sendable (String) -> Void)?) -> [MacTweaksRow]
    /// Applies `rows`, ticked from the last scan, one progress line per step; ends by
    /// scanning them again. Returns the receipt and those rows as they are now.
    func apply(_ rows: [MacTweaksRow], progress: (@Sendable (String) -> Void)?) -> (receipt: MacTweaksReceipt, rescanned: [MacTweaksRow])
    /// The plan's closing sentences for `rows`.
    func planNotes(for rows: [MacTweaksRow]) -> [String]
}

final class MacTweaksProvider: @unchecked Sendable {
    static let shared = MacTweaksProvider()

    // MARK: Search row

    static let resultID = "action-mac-tweaks"
    /// The row's action. A sentinel like the cleaner's: `SearchAction` is persisted in search
    /// history, and the view model opens the overlay on it.
    static let openScript = "internal:mac-tweaks"
    static let title = "Mac Tweaks"
    /// The subtitle before a scan, and the one search history stores.
    static let fixedSubtitle = "Free up space and tidy macOS"
    static let symbol = "slider.horizontal.3"

    /// Phrases only: a bare word another row answers to ("clean", "dock", "storage", an
    /// app's name) stays with that row.
    static let keywords = [
        "mac tweaks", "tweaks", "debloat", "free up space", "free space", "disk space", "reclaim space",
        "remove garageband", "delete garageband", "remove imovie", "delete imovie", "remove keynote",
        "remove numbers", "remove pages", "macos installers", "old macos installer", "time machine snapshots",
        "local snapshots", "unavailable simulators", "ipsw", "iphone updates", "aerial videos", "app caches",
    ]
    private static let lowercaseTitle = title.lowercased()

    /// The row that opens Mac Tweaks on its Settings section, for a few high-intent phrases.
    static let settingsResultID = "action-mac-tweaks-settings"
    static let openSettingsScript = "internal:mac-tweaks:settings"
    static let settingsTitle = "Mac Tweaks: Settings"
    static let settingsSubtitle = "Turn off analytics and ads, stop Music opening, tidy Finder and the Dock, with undo"
    /// Phrases only, matched exactly or by prefix: a word from inside one ("analytics", "music",
    /// "library") never brings the row up, so it stays with the row that answers to it.
    /// "restore dock icons" is the quick action's own name.
    static let settingsKeywords = [
        "stop music from opening", "turn off apple music", "turn off mac analytics", "turn off personalized ads",
        "show the library folder", "show library folder",
    ]

    /// The row that opens Mac Tweaks on its Apple Intelligence section.
    static let intelligenceResultID = "action-mac-tweaks-apple-intelligence"
    static let openIntelligenceScript = "internal:mac-tweaks:apple-intelligence"
    static let intelligenceTitle = "Mac Tweaks: Apple Intelligence"
    static let intelligenceSubtitle = "Turn Apple Intelligence off for every account and remove its models"
    /// Its phrases and their weights. A bare "apple intelligence" weighs under the 0.95 System
    /// Settings gives its own keywords, so the "Apple Intelligence & Siri" pane stays first for it.
    static let intelligenceKeywords: [(phrase: String, weight: Double)] = [
        ("apple intelligence", 0.9),
        ("turn off apple intelligence", 0.95),
        ("remove apple intelligence", 0.95),
        ("delete apple intelligence models", 0.95),
    ]

    /// Whether a quick action's script opens Mac Tweaks, and on which section (nil: as left).
    static func isOpenScript(_ script: String) -> Bool {
        script == openScript || script == openIntelligenceScript || script == openSettingsScript
    }
    static func section(forScript script: String) -> MacTweaksSection? {
        switch script {
        case openIntelligenceScript: return .appleIntelligence
        case openSettingsScript: return .settings
        default: return nil
        }
    }

    /// Pure in-memory: static keywords and the last scan's total.
    func search(_ query: SearchQuery) -> [SearchResult] {
        guard !query.isEmpty else { return [] }
        var results: [SearchResult] = []
        var best = FuzzyMatcher.score(query: query, targetLower: Self.lowercaseTitle, targetTokens: [], targetInitials: nil)
        for keyword in Self.keywords {
            if let score = FuzzyMatcher.score(query: query, targetLower: keyword, targetTokens: [], targetInitials: nil) {
                best = max(best ?? 0, score * 0.95)
            }
        }
        if let score = best {
            lock.lock()
            let freeable = state.freeableBytes
            lock.unlock()
            results.append(SearchResult(
                id: Self.resultID,
                title: Self.title,
                subtitle: Self.subtitle(freeableBytes: freeable),
                iconType: .systemSymbol(name: Self.symbol),
                category: .quickActions,
                score: score,
                action: .runQuickAction(script: Self.openScript, usesOsascript: false)
            ))
        }
        if MacTweaksSection.built.contains(.settings) {
            var settings: Double?
            for keyword in Self.settingsKeywords {
                if let score = FuzzyMatcher.score(query: query, targetLower: keyword, targetTokens: [], targetInitials: nil), score >= 95 {
                    settings = max(settings ?? 0, score * 0.95)
                }
            }
            if let score = settings {
                results.append(SearchResult(
                    id: Self.settingsResultID,
                    title: Self.settingsTitle,
                    subtitle: Self.settingsSubtitle,
                    iconType: .systemSymbol(name: MacTweaksSection.settings.symbol),
                    category: .quickActions,
                    score: score,
                    action: .runQuickAction(script: Self.openSettingsScript, usesOsascript: false)
                ))
            }
        }
        if MacTweaksSection.built.contains(.appleIntelligence) {
            var intelligence: Double?
            for keyword in Self.intelligenceKeywords {
                if let score = FuzzyMatcher.score(query: query, targetLower: keyword.phrase, targetTokens: [], targetInitials: nil) {
                    intelligence = max(intelligence ?? 0, score * keyword.weight)
                }
            }
            if let score = intelligence {
                results.append(SearchResult(
                    id: Self.intelligenceResultID,
                    title: Self.intelligenceTitle,
                    subtitle: Self.intelligenceSubtitle,
                    iconType: .systemSymbol(name: MacTweaksSection.appleIntelligence.symbol),
                    category: .quickActions,
                    score: score,
                    action: .runQuickAction(script: Self.openIntelligenceScript, usesOsascript: false)
                ))
            }
        }
        return results
    }

    // MARK: Overlay copy that depends on where a section stands

    /// The steps view's line while an apply runs, and while it waits for System Settings.
    static let workingNote = "This keeps running if you close the panel. Reopen Mac Tweaks to see the result."
    static let waitNote = "Lightspot checks every second for 10 minutes. Esc stops waiting; the profile stays in System Settings."
    /// The overlay's close button: it closes the panel and leaves a running apply or wait going.
    static let closeHelp = "Close. A running apply, or a wait for System Settings, keeps going."

    /// The footer's Esc while an apply runs: it stops a wait for System Settings, else closes.
    static func escapeLabel(_ state: SectionState) -> String {
        if case .applying = state.phase, state.waiting { return "Stop waiting" }
        return "Close"
    }

    static func subtitle(freeableBytes: Int64?) -> String {
        guard let bytes = freeableBytes, bytes > 0 else { return fixedSubtitle }
        return "\(size(bytes)) you can free"
    }

    /// Sizes as Finder shows them: decimal units, "14.2 GB", "640 MB". Always a "." whatever
    /// the locale, like the rest of the overlay.
    static func size(_ bytes: Int64) -> String {
        if bytes >= 999_500_000 { return String(format: "%.1f GB", Double(bytes) / 1e9) }
        if bytes >= 999_500 { return String(format: "%.0f MB", Double(bytes) / 1e6) }
        return String(format: "%.0f KB", max(1, Double(bytes) / 1e3))
    }

    // MARK: State

    enum Phase: Sendable, Equatable {
        case idle
        /// The latest progress line.
        case scanning(String)
        case ready
        /// One line per step so far; the last is running.
        case applying([String])
        case finished

        var isBusy: Bool {
            switch self {
            case .scanning, .applying: return true
            case .idle, .ready, .finished: return false
            }
        }
    }

    struct SectionState: Sendable {
        var phase: Phase = .idle
        var rows: [MacTweaksRow] = []
        var scannedAt: Date?
        var receipt: MacTweaksReceipt?
        var finishedAt: Date?
        /// Bumped by every completed scan, so the overlay resets its ticks to the defaults.
        var generation = 0
        /// The apply is waiting for System Settings (the profile's approval or removal): Esc
        /// stops that wait, and the footer says so.
        var waiting = false
    }

    struct Snapshot: Sendable {
        /// Bumped by every change, so the overlay can tell a new snapshot from the one it has
        /// without comparing them field by field.
        var revision = 0
        /// One per section, by `MacTweaksSection.index`.
        var sections = MacTweaksSection.allCases.map { _ in SectionState() }
        /// What Free Up Space offered at its last scan: the row's subtitle. It outlives the
        /// rows, which closing the overlay drops.
        var freeableBytes: Int64?
        /// What Apple Intelligence's last scan (or an apply's rescan) read: the inventory and the
        /// markers. The summary, the plan and Free Up Space's link row are built from it, so none
        /// of them reads anything. Kept like `freeableBytes`: it is small and outlives the rows.
        var appleIntelligenceScan: MacTweaksIntelligence.ScanContext?
        /// What Settings' last scan (or an apply's rescan) read, for its summary and plan.
        var settingsScan: MacTweaksSettings.Reading?

        subscript(section: MacTweaksSection) -> SectionState {
            get { sections[section.index] }
            set { sections[section.index] = newValue }
        }
    }

    /// Everything Mac Tweaks reads or changes on the system, so tests can point it at a temp
    /// folder and fakes. `live` builds closures only: nothing here runs at launch.
    struct Environment: Sendable {
        var home: String
        /// "/" on a real Mac, where /Applications and /Library hang off it.
        var systemRoot = "/"
        var userID: uid_t = getuid()
        /// The user that owns a path (lstat), or nil when it can't be read.
        var ownerOf: @Sendable (String) -> uid_t? = { MacTweaksStorage.owner(of: $0) }
        /// Whether LaunchServices knows an app with this bundle identifier, on any disk.
        var isAppInstalled: @Sendable (String) -> Bool = { !NSWorkspace.shared.urlsForApplications(withBundleIdentifier: $0).isEmpty }
        /// Runs a program and returns its status and stdout (-1 when it failed to start or
        /// ran past the timeout). Never a shell.
        var run: @Sendable (_ executable: String, _ arguments: [String], _ timeout: TimeInterval) -> (status: Int32, output: String) = {
            CleanDevMacEngine.run($0, $1, timeout: $2)
        }
        var xcodeSelect = "/usr/bin/xcode-select"
        var tmutil = "/usr/bin/tmutil"
        var moveToTrash: @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
        /// Runs one script Lightspot built as root, after at most one prompt, never twice.
        var runAdmin: @Sendable (String) -> QuickActionsProvider.PrivilegedRun = { QuickActionsProvider.runPrivilegedScript($0) }
        /// Clean Dev Mac's rules, whose caches App caches leaves to the cleaner: the ones it
        /// holds in memory, else cdm's local folder, else the app's own copy. Never fetched.
        var cleanDevMacRules: @Sendable (_ home: String) -> CleanDevMacRuleSet? = { MacTweaksStorage.cleanDevMacRules(home: $0) }
        var now: @Sendable () -> Date = { Date() }
        /// Everything the Apple Intelligence section reads or changes, injected the same way.
        /// `.inert` so Free Up Space tests that build `Environment(home:)` need nothing more.
        var intelligence = MacTweaksIntelligence.Environment.inert
        /// Apple Intelligence's models on disk, for Free Up Space's link row. The provider sets
        /// it to the last Apple Intelligence scan's total; nil (no row) everywhere else.
        var appleIntelligenceModelBytes: @Sendable () -> Int64? = { nil }
        /// Everything the Settings section reads or changes besides the profile (which it shares
        /// with Apple Intelligence through `intelligence`). `.inert` here, as for Apple Intelligence.
        var settings = MacTweaksSettings.Environment.inert

        static var live: Environment {
            var environment = Environment(home: NSHomeDirectory())
            environment.intelligence = .live(home: environment.home)
            environment.settings = .live
            return environment
        }

        /// The receipts log, capped like cdm's clean.log.
        var logURL: URL { URL(fileURLWithPath: home + "/Library/Application Support/Lightspot/mac-tweaks.log") }
    }

    /// A finished scan, and a receipt, stand this long before opening scans again.
    static let rescanAfter: TimeInterval = 5 * 60

    let environment: Environment
    private let lock = NSLock()
    private var state = Snapshot()
    private var observer: (@Sendable () -> Void)?
    private var lastProgressReport = Date.distantPast
    /// Per section: Esc stopped its wait for System Settings. Set by `cancelWait` only while that
    /// section waits (`SectionState.waiting`), reset when a wait starts, so an Esc elsewhere, or
    /// before the wait, never stops one. Panel hiding never sets it.
    private var waitCancelled = MacTweaksSection.allCases.map { _ in false }
    private let queue = DispatchQueue(label: "com.lightspot.mactweaks", qos: .userInitiated)

    init(environment: Environment = .live) {
        self.environment = environment
    }

    /// The engine behind each built section. A later section adds its case here.
    static func engine(for section: MacTweaksSection, environment: Environment) -> MacTweaksSectionEngine? {
        switch section {
        case .freeUpSpace: return MacTweaksStorage.Engine(environment: environment)
        case .appleIntelligence: return MacTweaksIntelligence.Engine(environment: environment)
        case .settings: return MacTweaksSettings.Engine(environment: environment)
        case .backgroundItems: return nil
        }
    }

    /// The engine for a section, with what the provider knows: Free Up Space gets the last Apple
    /// Intelligence scan's model total (its link row); Apple Intelligence and Settings get the scan
    /// on show (so their plans read nothing) and their own wait and cancel flag, for the profile's
    /// approval.
    func makeEngine(for section: MacTweaksSection) -> MacTweaksSectionEngine? {
        var env = environment
        let current = snapshot
        switch section {
        case .freeUpSpace:
            let bytes = MacTweaksIntelligence.modelBytes(current.appleIntelligenceScan?.inventory)
            env.appleIntelligenceModelBytes = { bytes }
            return Self.engine(for: section, environment: env)
        case .appleIntelligence:
            env.intelligence.waiting = { [weak self] on in self?.setWaiting(section, on) }
            env.intelligence.isCancelled = { [weak self] in self?.isWaitCancelled(section) ?? false }
            return MacTweaksIntelligence.Engine(environment: env, shown: current[section].rows,
                                                scanned: current.appleIntelligenceScan)
        case .settings:
            env.intelligence.waiting = { [weak self] on in self?.setWaiting(section, on) }
            env.intelligence.isCancelled = { [weak self] in self?.isWaitCancelled(section) ?? false }
            return MacTweaksSettings.Engine(environment: env, scanned: current.settingsScan)
        case .backgroundItems:
            return Self.engine(for: section, environment: env)
        }
    }

    // MARK: Waiting for System Settings

    /// A section's wait starts or ends: a new wait is never already cancelled.
    private func setWaiting(_ section: MacTweaksSection, _ on: Bool) {
        lock.lock()
        if on { waitCancelled[section.index] = false }
        state[section].waiting = on
        state.revision += 1
        lock.unlock()
        notify()
    }

    /// Esc on a section that waits for System Settings: stop that wait. Nothing otherwise, so an
    /// Esc before the wait starts, or while another section works, changes nothing. The pending
    /// profile stays in System Settings; the next open continues if it got installed meanwhile.
    func cancelWait(_ section: MacTweaksSection) {
        lock.lock()
        if state[section].waiting { waitCancelled[section.index] = true }
        lock.unlock()
    }

    /// Whether Esc stopped the section's running wait, read by the wait on the queue.
    func isWaitCancelled(_ section: MacTweaksSection) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return state[section].waiting && waitCancelled[section.index]
    }

    /// Non-blocking: the latest state, for the overlay.
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
        state.revision += 1
        lock.unlock()
        notify()
    }

    /// Scan progress is reported at most ten times a second: every report is a SwiftUI pass.
    private func reportScanProgress(_ section: MacTweaksSection, _ line: String) {
        lock.lock()
        guard case .scanning = state[section].phase else {
            lock.unlock()
            return
        }
        state[section].phase = .scanning(line)
        state.revision += 1
        let now = Date()
        let due = now.timeIntervalSince(lastProgressReport) >= 0.1
        if due { lastProgressReport = now }
        lock.unlock()
        if due { notify() }
    }

    /// What the row's subtitle shows: the bytes Free Up Space's rows offer.
    static func freeableBytes(_ rows: [MacTweaksRow]) -> Int64 {
        rows.filter { !$0.isLink }.reduce(0) { $0 + ($1.bytes ?? 0) }
    }

    private func isFresh(_ date: Date?) -> Bool {
        date.map { environment.now().timeIntervalSince($0) < Self.rescanAfter } == true
    }

    // MARK: Opening and closing

    /// Opening a section scans it, unless it is busy (the overlay shows the progress), a
    /// recent scan stands, or a recent apply's receipt is still to be read.
    func open(_ section: MacTweaksSection) {
        lock.lock()
        let current = state[section]
        let keep: Bool
        switch current.phase {
        case .scanning, .applying: keep = true
        case .ready: keep = isFresh(current.scannedAt)
        case .finished: keep = isFresh(current.finishedAt)
        case .idle: keep = false
        }
        lock.unlock()
        if !keep { startScan(section, force: true) }
    }

    /// The overlay closed. A scan that still stands is kept, so reopening within five
    /// minutes shows it again; anything older, and the rows behind a receipt, are dropped,
    /// keeping only the total the search row shows. A scan or an apply keeps running.
    func overlayClosed() {
        lock.lock()
        var changed = false
        for section in MacTweaksSection.built {
            var current = state[section]
            switch current.phase {
            case .ready where !isFresh(current.scannedAt):
                current = SectionState(generation: current.generation)
            case .finished where !isFresh(current.finishedAt):
                current = SectionState(generation: current.generation)
            case .finished where !current.rows.isEmpty:
                // The receipt is what reopening shows; ↵ on it scans again.
                current.rows = []
            default:
                continue
            }
            state[section] = current
            // What Settings' scan read goes with its rows (Apple Intelligence's stays: Free Up
            // Space's link row reads it).
            if section == .settings { state.settingsScan = nil }
            changed = true
        }
        if changed { state.revision += 1 }
        lock.unlock()
        if changed { notify() }
    }

    // MARK: Scanning

    /// Starts a scan unless one is running or (without `force`) a recent one stands.
    func startScan(_ section: MacTweaksSection, force: Bool = false) {
        guard let engine = makeEngine(for: section) else { return }
        lock.lock()
        let current = state[section]
        guard !current.phase.isBusy, force || !(current.phase == .ready && isFresh(current.scannedAt)) else {
            lock.unlock()
            return
        }
        // The old rows go now, not when the new ones arrive.
        state[section] = SectionState(phase: .scanning(section.scanningTitle), generation: current.generation)
        state.revision += 1
        lock.unlock()
        notify()

        queue.async { [self] in
            let rows = engine.scan(only: nil) { line in
                self.reportScanProgress(section, line)
            }
            let now = environment.now()
            // What the Apple Intelligence scan read, for the summary, the plan and Free Up
            // Space's link row.
            let context = (engine as? MacTweaksIntelligence.Engine)?.lastContext
            let reading = (engine as? MacTweaksSettings.Engine)?.lastContext
            update { state in
                state[section].phase = .ready
                state[section].rows = rows
                state[section].scannedAt = now
                state[section].generation += 1
                if section == .freeUpSpace { state.freeableBytes = Self.freeableBytes(rows) }
                if let context { state.appleIntelligenceScan = context }
                if let reading { state.settingsScan = reading }
            }
        }
    }

    // MARK: Applying

    /// Applies the rows of the current scan whose IDs are given. Only from `.ready`: the
    /// overlay shows the plan first, and the rows must be the ones it showed.
    func apply(_ section: MacTweaksSection, ids: Set<String>) {
        guard let engine = makeEngine(for: section) else { return }
        lock.lock()
        let selected = MacTweaksTicks.ticked(state[section].rows, ids)
        guard state[section].phase == .ready, !selected.isEmpty else {
            lock.unlock()
            return
        }
        state[section].phase = .applying([])
        state.revision += 1
        lock.unlock()
        notify()

        queue.async { [self] in
            let result = engine.apply(selected) { line in
                self.update { state in
                    if case .applying(let steps) = state[section].phase {
                        state[section].phase = .applying(steps + [line])
                    }
                }
            }
            let applied = Set(selected.map(\.id))
            let now = environment.now()
            update { state in
                var rows: [MacTweaksRow] = []
                if result.rescanned.contains(where: { !applied.contains($0.id) }) {
                    // A full rescan (Apple Intelligence, Settings): every row as it is now.
                    rows = result.rescanned
                } else {
                    for row in state[section].rows {
                        if !applied.contains(row.id) {
                            rows.append(row)
                        } else if let again = result.rescanned.first(where: { $0.id == row.id }) {
                            rows.append(again)
                        }
                    }
                }
                state[section].rows = rows
                state[section].phase = .finished
                state[section].receipt = result.receipt
                state[section].finishedAt = now
                state[section].waiting = false
                if section == .freeUpSpace { state.freeableBytes = Self.freeableBytes(rows) }
                // An apply's rescan, with its own inventory's availability.
                if let context = (engine as? MacTweaksIntelligence.Engine)?.lastContext { state.appleIntelligenceScan = context }
                if let reading = (engine as? MacTweaksSettings.Engine)?.lastContext { state.settingsScan = reading }
                // Apple Intelligence and Settings share one profile: the other one's scan no
                // longer stands, so opening it scans again.
                if let sibling = Self.profileSibling(section), state[sibling].phase == .ready { state[sibling].scannedAt = nil }
            }
        }
    }

    /// The section that shares the profile with this one.
    static func profileSibling(_ section: MacTweaksSection) -> MacTweaksSection? {
        switch section {
        case .appleIntelligence: return .settings
        case .settings: return .appleIntelligence
        case .freeUpSpace, .backgroundItems: return nil
        }
    }

    /// The plan's closing sentences for the ticked rows of `section`.
    func planNotes(_ section: MacTweaksSection, rows: [MacTweaksRow]) -> [String] {
        makeEngine(for: section)?.planNotes(for: rows) ?? []
    }

    // MARK: Receipts

    /// Appends one apply's lines to the receipts log, rotating first: past 1 MiB it keeps the
    /// newest 256 KiB, as cdm's clean.log does. Best effort.
    static func appendReceipt(section: MacTweaksSection, lines: [String], environment: Environment, started: Date) {
        let rule = String(repeating: "=", count: 50)
        var text = "\(rule)\nMac Tweaks run (Lightspot): \(CleanDevMacEngine.logDate(started))\n\(rule)\n▸ \(section.title)\n"
        for line in lines { text += "  \(line)\n" }
        text += "\(rule)\nFinished: \(CleanDevMacEngine.logDate(environment.now()))\n\(rule)\n"
        CleanDevMacEngine.appendToLog(text, url: environment.logURL, now: environment.now())
    }
}
