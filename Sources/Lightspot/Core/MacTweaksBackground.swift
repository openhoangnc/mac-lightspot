import AppKit
import Darwin

// MARK: - Mac Tweaks: Background Items
//
// The launch agents and daemons other apps installed: updaters, helpers and agents that run
// whether or not their app is open. Ported from RemoveMacAI's BackgroundItems.swift (MIT, see
// THIRD-PARTY-NOTICES.md): its three folders, its verdicts (owner, updater, leftover) and its
// launchctl verbs. Lightspot's own: the state also reads whether launchd has the job loaded; user
// agents change as the user and every daemon in one administrator batch; everything is judged by
// reading launchd again; a turn-off is journaled before it runs; and root only ever acts on a
// plist the scan found, never on what the journal (the user's own file) says. All of it blocks, so
// it runs on MacTweaksProvider's queue, and only once the user opens the section.

enum MacTweaksBackground {
    typealias ProviderEnvironment = MacTweaksProvider.Environment

    // MARK: Items

    /// Where an item lives, and so the launchd domain it belongs to.
    enum Place: Sendable, Equatable {
        /// `~/Library/LaunchAgents`: this user's agents, in `gui/<uid>`.
        case userAgents
        /// `/Library/LaunchAgents`: agents every account loads, each into its own `gui/<uid>`.
        case allUsersAgents
        /// `/Library/LaunchDaemons`: daemons for the whole Mac, in `system`.
        case daemons

        var isSystem: Bool { self == .daemons }
    }

    /// One plist the scan found: what launchd would run, and where.
    struct Item: Sendable, Equatable {
        let label: String
        let plist: String
        let place: Place
        /// `Program`, else `ProgramArguments[0]`, else "" (RemoveMacAI's).
        let program: String
        let arguments: [String]
        let associatedIDs: [String]
        /// The plist's own `Disabled` key: launchd keeps such a job off unless an override says
        /// otherwise.
        let plistDisabled: Bool
        /// The plist is a symlink: listed and switched like any other, never moved.
        let isLink: Bool
        let ownerUID: uid_t?
        /// Other plists with the same label in the same domain (one in each agent folder):
        /// launchd runs only one of them, so neither file is ever moved.
        var alsoAt: [String] = []

        var system: Bool { place.isSystem }
        /// The row's ID and the journal's key.
        var id: String { MacTweaksBackground.key(label: label, system: system) }
    }

    /// "background:gui/<label>" or "background:system/<label>": no uid, so the key of an account
    /// that moved to another Mac still matches.
    static func key(label: String, system: Bool) -> String {
        "background:" + (system ? "system/" : "gui/") + label
    }

    /// The label and domain a key names, or nil for any other key.
    static func parse(key: String) -> (label: String, system: Bool)? {
        for (prefix, system) in [("background:gui/", false), ("background:system/", true)] where key.hasPrefix(prefix) {
            return (String(key.dropFirst(prefix.count)), system)
        }
        return nil
    }

    static func domain(system: Bool, userID: uid_t) -> String { system ? "system" : "gui/\(userID)" }

    static func target(_ label: String, system: Bool, userID: uid_t) -> String {
        domain(system: system, userID: userID) + "/" + label
    }

    /// Whether launchctl can be handed this label: `gui/501/a/b` names service `a`, and an empty
    /// label names the whole domain, which `print` reports as there (status 0). A quote or a
    /// control character would also make `print-disabled`'s list ambiguous. Printable ASCII only:
    /// Foundation hands a child process its arguments decomposed (NFD; measured: é arrives as
    /// e + U+0301), the batch included, and launchd compares labels byte for byte, so an accented
    /// label would reach launchctl spelled differently from the one it has.
    static func isActionable(_ label: String) -> Bool {
        !label.isEmpty && label.utf8.count <= 512 && !label.contains("/") && !label.contains("\"")
            && label.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value < 0x7F }
    }

    // MARK: Verdicts (RemoveMacAI's)

    static let interpreters: Set<String> = ["sh", "bash", "zsh", "python3", "python", "node", "osascript", "perl", "ruby"]

    /// Whether it only keeps its app up to date, by its label and the name of what it runs.
    /// Anything else (a VPN, Docker's socket, a sync helper) can be what makes its app work.
    static func isUpdater(label: String, program: String) -> Bool {
        [label, (program as NSString).lastPathComponent].contains { $0.lowercased().contains("update") }
    }

    /// The path the leftover verdict judges: the program, or the script an interpreter runs; nil
    /// for an interpreter given inline code (`-c`, `-e`, `-lc`…) or no script, which is never judged.
    static func judgedPath(program: String, arguments: [String]) -> String? {
        guard interpreters.contains((program as NSString).lastPathComponent) else { return program }
        let rest = arguments.dropFirst()
        let inline = rest.contains { $0.hasPrefix("-") && !$0.hasPrefix("--") && ($0.contains("c") || $0.contains("e")) }
        guard !inline else { return nil }
        return rest.first { !$0.hasPrefix("-") }
    }

    /// What a path leads to, as `lookUp` finds it.
    enum Lookup: Sendable, Equatable {
        /// It exists: where, with every symlink resolved, and whether it is a regular file.
        case found(String, regularFile: Bool)
        /// macOS says it doesn't exist: ENOENT, or ENOTDIR (a file where a folder should be).
        case missing
        /// It can't be told: inside a folder macOS guards, through too many links, or no access.
        case unknown
    }

    /// Where Lightspot never looks (`lookUp`): the folders macOS guards (`Roots.neverTouched`:
    /// Documents, Desktop…, where even an `lstat` can raise its privacy prompt), other disks
    /// (`/Volumes`: what sits on one that isn't mounted would read as gone) and cloud folders
    /// (`~/Library/CloudStorage`: a file there may only arrive when it is opened).
    static func guardedFolders(_ env: ProviderEnvironment) -> [String] {
        let roots = MacTweaksStorage.Roots(env)
        let cloud = roots.inHome("Library/CloudStorage")
        return roots.neverTouched + ["/Volumes", cloud.lexical, cloud.physical]
    }

    /// A spelling the disk would take for the same name: APFS here ignores case and Unicode
    /// normalization, so `~/documents` is `~/Documents`.
    static func folded(_ path: String) -> String { path.precomposedStringWithCanonicalMapping.lowercased() }

    /// Looks a path up one component at a time, so that nothing inside a guarded folder
    /// (`guardedFolders`) is ever touched: each step is checked before it is looked at, in any
    /// case and normalization, and a symlink on the way is followed by its text, at most 16 of
    /// them. So a link that leads into Documents, directly or through another link, is refused
    /// before it gets there.
    static func lookUp(_ path: String, guarded: [String] = []) -> Lookup {
        guard path.hasPrefix("/") else { return .unknown }
        let refused = guarded.map(folded)
        var pending = path.split(separator: "/").map(String.init)
        var current = ""
        var links = 0
        while !pending.isEmpty {
            let part = pending.removeFirst()
            if part == "." { continue }
            if part == ".." {
                current = (current as NSString).deletingLastPathComponent
                if current == "/" { current = "" }
                continue
            }
            let next = current + "/" + part
            let spelled = folded(next)
            if refused.contains(where: { MacTweaksStorage.isInside(spelled, $0) }) { return .unknown }
            var info = stat()
            guard lstat(next, &info) == 0 else { return errno == ENOENT || errno == ENOTDIR ? .missing : .unknown }
            let kind = info.st_mode & S_IFMT
            if kind == S_IFLNK {
                links += 1
                guard links <= 16, let text = try? FileManager.default.destinationOfSymbolicLink(atPath: next), !text.isEmpty else { return .unknown }
                if text.hasPrefix("/") { current = "" }
                pending = text.split(separator: "/").map(String.init) + pending
            } else if pending.isEmpty {
                return .found(next, regularFile: kind == S_IFREG)
            } else if kind == S_IFDIR {
                current = next
            } else {
                return .missing
            }
        }
        return current.isEmpty ? .unknown : .found(current, regularFile: false)
    }

    /// True only when macOS says the path doesn't exist (ENOENT or ENOTDIR), not when it can't look.
    static func confirmedMissing(_ path: String, guarded: [String] = []) -> Bool {
        lookUp(path, guarded: guarded) == .missing
    }

    /// Left over from a deleted app: what it runs is confirmed gone, so it can't run. A path in a
    /// guarded folder (`guardedFolders`) is never looked at, so never judged.
    static func isLeftover(_ item: Item, guarded: [String] = []) -> Bool {
        judgedPath(program: item.program, arguments: item.arguments).map { confirmedMissing($0, guarded: guarded) } ?? false
    }

    /// The app or program it runs, as people know it. When RemoveMacAI's rule falls back to the
    /// label, the app its plist names (`appName`, LaunchServices) is used first: Lightspot's
    /// addition, so `com.docker.vmnetd` reads "Docker" rather than "vmnetd".
    static func owner(label: String, program: String, arguments: [String], appName: () -> String?) -> String {
        if let app = program.split(separator: "/").first(where: { $0.hasSuffix(".app") }) {
            return String(app.dropLast(4))
        }
        var name = (program as NSString).lastPathComponent
        if interpreters.contains(name), let script = arguments.dropFirst().first(where: { $0.contains("/") }) {
            name = (script as NSString).lastPathComponent
        }
        if name.isEmpty || name == label {
            if let app = appName() { return app }
            let parts = label.split(separator: ".")
            return parts.count >= 3 ? String(parts[2]) : label
        }
        return name
    }

    /// What a scan concludes about an item.
    struct Verdict: Sendable, Equatable {
        let owner: String
        let isUpdater: Bool
        let isLeftover: Bool
        /// Its plist names the apps it came with, and LaunchServices knows none of them.
        let appMissing: Bool
    }

    static func verdict(_ item: Item, _ env: ProviderEnvironment) -> Verdict {
        let names = item.associatedIDs.map { env.backgroundItems.appName($0) }
        return Verdict(
            owner: owner(label: item.label, program: item.program, arguments: item.arguments) { names.lazy.compactMap { $0 }.first },
            isUpdater: isUpdater(label: item.label, program: item.program),
            isLeftover: isLeftover(item, guarded: guardedFolders(env)),
            appMissing: !names.isEmpty && names.allSatisfy { $0 == nil })
    }

    // MARK: The folders

    /// The three folders, fixed in code, as written and where they must resolve.
    static func folders(_ env: ProviderEnvironment) -> [(place: Place, lexical: String, physical: String)] {
        let roots = MacTweaksStorage.Roots(env)
        let user = roots.inHome("Library/LaunchAgents")
        let agents = roots.inSystem("Library/LaunchAgents")
        let daemons = roots.inSystem("Library/LaunchDaemons")
        return [(.userAgents, user.lexical, user.physical), (.allUsersAgents, agents.lexical, agents.physical),
                (.daemons, daemons.lexical, daemons.physical)]
    }

    /// Bigger than any launchd plist by far (they are a few hundred bytes): past this a file is
    /// skipped unread, so a planted one can't swell the scan.
    static let maxPlistBytes = 1 << 20

    /// Where a plist must be to be acted on: a direct child of its fixed folder, as written and
    /// with the folder resolved (no symlink on the way leads elsewhere), named `*.plist`.
    static func isAllowed(_ plist: String, _ place: Place, _ env: ProviderEnvironment) -> Bool {
        guard let folder = folders(env).first(where: { $0.place == place }) else { return false }
        let parent = (plist as NSString).deletingLastPathComponent
        let name = (plist as NSString).lastPathComponent
        return MacTweaksStorage.isPlainAbsolute(plist) && parent == folder.lexical && name.hasSuffix(".plist")
            && !name.hasPrefix(".") && MacTweaksStorage.resolved(parent) == folder.physical
    }

    /// Where a symlinked plist leads, when Lightspot may read it there: a regular file reached
    /// without touching any guarded folder (`lookUp`; a dotfiles link into `~/Documents` would
    /// otherwise raise macOS's privacy prompt). nil for any other link.
    static func linkTarget(_ path: String, _ env: ProviderEnvironment) -> String? {
        if case .found(let resolved, regularFile: true) = lookUp(path, guarded: guardedFolders(env)) { return resolved }
        return nil
    }

    /// A plist's dictionary: opened without following a link (`linkTarget` vets one first) and
    /// without blocking (a FIFO named `x.plist` can't hang the scan), a regular file once open, at
    /// most `maxPlistBytes`.
    static func readPlist(_ path: String) -> [String: Any]? {
        let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size <= maxPlistBytes,
              let data = try? handle.read(upToCount: maxPlistBytes + 1), data.count <= maxPlistBytes else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    /// The item a plist describes, or nil: not `*.plist`, a dot file, a link Lightspot may not
    /// follow, not a readable dictionary, no `Label` (Google's empty Keystone stubs), or one of
    /// macOS's own (`com.apple.`).
    static func item(at path: String, place: Place, _ env: ProviderEnvironment) -> Item? {
        let name = (path as NSString).lastPathComponent
        guard name.hasSuffix(".plist"), !name.hasPrefix(".") else { return nil }
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        let source = info.st_mode & S_IFMT == S_IFLNK ? linkTarget(path, env) : path
        guard let source, let dict = readPlist(source),
              let label = dict["Label"] as? String, !label.isEmpty, !label.hasPrefix("com.apple.") else { return nil }
        let arguments = dict["ProgramArguments"] as? [String] ?? []
        let associated = dict["AssociatedBundleIdentifiers"]
        return Item(label: label, plist: path, place: place,
                    program: dict["Program"] as? String ?? arguments.first ?? "",
                    arguments: arguments,
                    associatedIDs: (associated as? [String]) ?? (associated as? String).map { [$0] } ?? [],
                    plistDisabled: dict["Disabled"] as? Bool ?? false,
                    isLink: info.st_mode & S_IFMT == S_IFLNK,
                    ownerUID: env.ownerOf(path))
    }

    /// Every item in the three folders, in folder order and by name. A label's first plist in its
    /// domain makes the row, as launchd loads only one; the others are named on it (`alsoAt`).
    static func items(_ env: ProviderEnvironment) -> [Item] {
        var found: [Item] = []
        var position: [String: Int] = [:]
        for folder in folders(env) {
            for path in MacTweaksStorage.children(of: folder.lexical) {
                guard let item = item(at: path, place: folder.place, env) else { continue }
                if let first = position[item.id] {
                    found[first].alsoAt.append(path)
                } else {
                    position[item.id] = found.count
                    found.append(item)
                }
            }
        }
        return found
    }

    // MARK: launchd

    /// `launchctl print-disabled`'s list: label → true for `disabled` (or `true`, older systems),
    /// false for an explicit `enabled` (or `false`). Each line is `"<label>" => <value>`; the split
    /// is at the last `" => `, so a label holding "=>" still reads right.
    static func overrides(_ output: String) -> [String: Bool] {
        var list: [String: Bool] = [:]
        for line in output.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix("\""), let arrow = text.range(of: "\" => ", options: .backwards),
                  arrow.lowerBound > text.startIndex else { continue }
            let label = String(text[text.index(after: text.startIndex)..<arrow.lowerBound])
            switch text[arrow.upperBound...] {
            case "disabled", "true": list[label] = true
            case "enabled", "false": list[label] = false
            default: continue
            }
        }
        return list
    }

    enum Loaded: Sendable, Equatable {
        case yes, no, unknown

        /// `launchctl print <target>`'s exit status: 0 loaded, 113 not; anything else (112, no such
        /// domain; a timeout) says nothing.
        init(status: Int32) {
            self = status == 0 ? .yes : status == 113 ? .no : .unknown
        }
    }

    /// What launchd says about some items, read once per scan, apply or undo.
    struct Launchd: Sendable {
        /// Per domain; nil when its list couldn't be read.
        var gui: [String: Bool]?
        var system: [String: Bool]?
        /// By item ID.
        var loaded: [String: Loaded] = [:]

        /// Off by launchd's override, else by the plist's own `Disabled`; nil when unread.
        func isDisabled(_ item: Item) -> Bool? {
            guard let list = item.system ? system : gui else { return nil }
            return list[item.label] ?? item.plistDisabled
        }

        func isLoaded(_ item: Item) -> Loaded { loaded[item.id] ?? .unknown }
    }

    /// Reads the override lists the items need and, for each, whether its job is loaded. Only
    /// `print`'s exit status is kept: its output lists the job's environment.
    static func read(_ items: [Item], _ env: ProviderEnvironment) -> Launchd {
        let launchctl = env.backgroundItems.launchctl
        var reading = Launchd()
        if items.contains(where: { !$0.system }) {
            let listed = launchctl(["print-disabled", domain(system: false, userID: env.userID)])
            reading.gui = listed.status == 0 ? overrides(listed.output) : nil
        }
        if items.contains(where: \.system) {
            let listed = launchctl(["print-disabled", "system"])
            reading.system = listed.status == 0 ? overrides(listed.output) : nil
        }
        for item in items where isActionable(item.label) {
            reading.loaded[item.id] = Loaded(status: launchctl(["print", target(item.label, system: item.system, userID: env.userID)]).status)
        }
        return reading
    }

    // MARK: State and what Space ticks

    enum State: Sendable, Equatable {
        case on, off, notLoaded, unknown

        /// The right-hand column.
        var label: String {
            switch self {
            case .on: return "On"
            case .off: return "Off"
            case .notLoaded: return "Not loaded"
            case .unknown: return "Unknown"
            }
        }
    }

    static func state(disabled: Bool?, loaded: Loaded) -> State {
        guard let disabled else { return .unknown }
        if disabled { return .off }
        switch loaded {
        case .yes: return .on
        case .no: return .notLoaded
        case .unknown: return .unknown
        }
    }

    enum Change: Sendable, Equatable { case turnOff, turnOn, trash }

    /// A leftover goes to the Trash, unless its file is a link or another plist has its label
    /// (stopping this one would stop that one's job); an Off item is turned back on; anything else
    /// is turned off.
    static func change(_ item: Item, state: State, leftover: Bool) -> Change {
        if leftover && !item.isLink && item.alsoAt.isEmpty { return .trash }
        return state == .off ? .turnOn : .turnOff
    }

    // The row's outcome names its change; the engine reads it back from these constants.
    static let turnOffOutcome = "Turned off: it stops now and stays off after a restart"
    static let turnOffIdleOutcome = "Turned off: it stays off, even if Login Items switches it on again"
    static let turnOnOutcome = "Turned back on: launchd loads it again"
    static let trashOutcome = "Stopped, then its file goes to the Trash"

    static func change(of row: MacTweaksRow) -> Change? {
        switch row.outcome {
        case turnOffOutcome, turnOffIdleOutcome: return .turnOff
        case turnOnOutcome: return .turnOn
        case trashOutcome: return .trash
        default: return nil
        }
    }

    // MARK: Rows

    static let updaterTag = "Updater"
    static let leftoverTag = "Leftover"
    static let allUsersTag = "For all users"
    static let loginItemsRowID = "login-items"
    /// System Settings' Login Items & Extensions, the pane SettingsProvider's Login Items row opens.
    static let loginItemsLink = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
    static let symbols = ["gearshape", "gearshape.2", "arrow.triangle.2.circlepath", "questionmark.folder",
                          "person.crop.circle.badge.checkmark"]
    static let appleNote = "macOS's own aren't listed."
    /// How a blocked journal's reason starts (`MacTweaksJournal.blockedReason`): every row then
    /// leads with that reason, and the summary says what it means.
    static let blockedPrefix = "Lightspot can't read or move its undo journal"
    static let blockedSummary = "Lightspot changes nothing here until its undo journal can be read."
    static let unreadNote = "launchd didn't say whether it's switched off, so Lightspot leaves it alone."
    static let unsafeLabelNote = "Its label can't be passed to launchctl safely, so Lightspot leaves it alone."
    static let elsewhereNote = "A link on the way to its folder leads somewhere else, so Lightspot leaves it alone."

    /// A daemon runs until the Mac restarts; an agent until its user logs out.
    static func untilRestart(system: Bool) -> String { system ? "until you restart" : "until you log out or restart" }
    static let notLoadedNote = "Not loaded now. Login Items & Extensions in System Settings may have it switched off."
    static let unreadableJournalNote = "Lightspot's undo journal can't be read: turning this off keeps it aside, and starts a new one."

    static func warning(_ owner: String) -> String { "Not an updater. Turning it off can stop \(owner) working." }

    /// What a row's detail says it runs: the program, or an interpreter and its script; never
    /// other arguments, which can hold tokens.
    static func runs(_ item: Item, home: String) -> String {
        let shown = { CleanDevMacEngine.displayPath($0, home: home) }
        if interpreters.contains((item.program as NSString).lastPathComponent),
           let script = judgedPath(program: item.program, arguments: item.arguments), script != item.program {
            return shown(item.program) + " " + shown(script)
        }
        return shown(item.program)
    }

    /// The launchctl commands a change runs, as the plan shows them.
    static func commands(_ item: Item, _ change: Change, loaded: Loaded, env: ProviderEnvironment) -> [String] {
        let target = target(item.label, system: item.system, userID: env.userID)
        switch change {
        case .turnOff:
            return ["launchctl disable \(target)"] + (loaded == .no ? [] : ["launchctl bootout \(target)"])
        case .turnOn:
            let plist = CleanDevMacEngine.displayPath(item.plist, home: env.home)
            return ["launchctl enable \(target)"]
                + (loaded == .yes ? [] : ["launchctl bootstrap \(domain(system: item.system, userID: env.userID)) \(plist)"])
        case .trash:
            return loaded == .no ? [] : ["launchctl bootout \(target)"]
        }
    }

    static func row(_ item: Item, _ launchd: Launchd, journal: JournalStatus, recorded: Set<String>,
                    _ env: ProviderEnvironment) -> MacTweaksRow {
        let verdict = verdict(item, env)
        let disabled = launchd.isDisabled(item)
        let loaded = launchd.isLoaded(item)
        let state = state(disabled: disabled, loaded: loaded)
        let change = change(item, state: state, leftover: verdict.isLeftover)

        // Read-only first, with why: what apply would refuse is never offered.
        var notes: [String] = []
        if case .blocked(let reason) = journal {
            notes.append(reason)
        } else if !isActionable(item.label) {
            notes.append(unsafeLabelNote)
        } else if !isAllowed(item.plist, item.place, env) {
            notes.append(elsewhereNote)
        } else if disabled == nil {
            notes.append(unreadNote)
        }
        let readOnly = !notes.isEmpty
        switch state {
        case .off where loaded == .yes:
            notes.append("Off, but still running \(untilRestart(system: item.system)).")
        case .off:
            let byOverride = (item.system ? launchd.system : launchd.gui)?[item.label] != nil
            if !byOverride { notes.append("Its own file keeps it off.") }
        case .notLoaded:
            notes.append(notLoadedNote)
        case .unknown where disabled != nil && isActionable(item.label):
            notes.append("launchd didn't say whether it's loaded.")
        default:
            break
        }
        if recorded.contains(item.id) && state == .off { notes.append("Lightspot turned it off.") }
        if verdict.appMissing {
            notes.append("The app it came with (\(item.associatedIDs.joined(separator: ", "))) isn't installed.")
        }
        // An agent every account loads: switching it is for this account; its file is everyone's.
        if item.place == .allUsersAgents {
            switch change {
            case .turnOff: notes.append("Installed for every account. Turning it off here is for your account only.")
            case .turnOn: notes.append("Installed for every account. Turning it back on here is for your account only.")
            case .trash: notes.append("Installed for every account: its file goes to the Trash for all of them.")
            }
        }
        if !item.alsoAt.isEmpty {
            let others = item.alsoAt.map { CleanDevMacEngine.displayPath($0, home: env.home) }.joined(separator: ", ")
            notes.append("Another copy is installed at \(others), and launchd runs only one of them"
                         + (verdict.isLeftover ? ", so Lightspot moves neither file." : "."))
        }
        if change == .turnOff, case .unreadable = journal { notes.append(unreadableJournalNote) }
        if verdict.isLeftover {
            if !item.alsoAt.isEmpty {
                notes.append("What this copy runs is gone.")
            } else {
                notes.append(item.isLink ? "What it runs is gone. Its file is a link, so Lightspot doesn't move it."
                                         : "What it runs is gone, so it can't run.")
            }
        } else if !verdict.isUpdater {
            notes.append(warning(verdict.owner))
        }

        var tags: [String] = []
        if verdict.isUpdater { tags.append(updaterTag) }
        if verdict.isLeftover { tags.append(leftoverTag) }
        // Moving a file out of /Library/LaunchAgents removes it for every account, as a daemon's
        // change is for every account.
        if item.system || (item.place == .allUsersAgents && change == .trash) { tags.append(allUsersTag) }
        let foreign = item.ownerUID != env.userID
        // Root moves a leftover another account owns, or one out of the folder every account
        // shares (root's, whoever owns the file).
        if item.system || (change == .trash && (foreign || item.place == .allUsersAgents)) {
            tags.append(MacTweaksStorage.passwordTag)
        }

        let symbol = verdict.isLeftover ? "questionmark.folder" : verdict.isUpdater ? "arrow.triangle.2.circlepath"
            : item.system ? "gearshape.2" : "gearshape"
        let program = runs(item, home: env.home)
        let outcome: String
        switch change {
        case .turnOff: outcome = loaded == .yes ? turnOffOutcome : turnOffIdleOutcome
        case .turnOn: outcome = turnOnOutcome
        case .trash: outcome = trashOutcome
        }
        return MacTweaksRow(
            id: item.id, symbol: symbol, title: verdict.owner,
            detail: program.isEmpty ? item.label : item.label + " · " + program,
            caveat: notes.isEmpty ? nil : notes.joined(separator: " "),
            // A read-only row runs nothing, so it lists no commands.
            items: [MacTweaksItem(target: item.plist, isForeign: foreign)]
                + (readOnly ? [] : commands(item, change, loaded: loaded, env: env).map { MacTweaksItem(target: $0) }),
            countLabel: state.label,
            isDefault: change == .trash,
            tags: tags,
            outcome: outcome,
            revealsInFinder: true,
            readOnly: readOnly)
    }

    /// The last row: Login Items & Extensions, where macOS keeps its own switches for these.
    static var loginItemsRow: MacTweaksRow {
        MacTweaksRow(id: loginItemsRowID, symbol: "person.crop.circle.badge.checkmark", title: "Login Items in System Settings",
                     detail: "Apps that open at login, and the switches macOS keeps for background items.",
                     link: .settings(deepLink: loginItemsLink))
    }

    // MARK: Scanning

    /// Blocking: one row per item, then the Login Items link. `only` limits it to those row IDs
    /// (the verify pass), without the link.
    /// `progress` is optional rather than defaulted: a closure argument makes the compiler copy
    /// the whole function once per closure it is called with.
    static func scan(_ env: ProviderEnvironment, only: Set<String>? = nil,
                     progress: (@Sendable (String) -> Void)? = nil) -> [MacTweaksRow] {
        progress?(MacTweaksSection.backgroundItems.scanningTitle)
        let found = items(env).filter { only?.contains($0.id) ?? true }
        let launchd = read(found, env)
        let journal = Self.journal(env)
        let status = journal.status()
        var recorded = Set<String>()
        if case .blocked = status {} else { recorded = Set(journal.entries().map(\.key)) }
        var rows = found.map { row($0, launchd, journal: status, recorded: recorded, env) }
        if only == nil { rows.append(loginItemsRow) }
        return rows
    }

    // MARK: Summary and plan (read nothing)

    private static func count(_ number: Int, _ singular: String, _ plural: String) -> String {
        "\(number) \(number == 1 ? singular : plural)"
    }

    static func summary(rows: [MacTweaksRow], ticked: [MacTweaksRow]) -> String {
        let items = rows.filter { !$0.isLink }
        guard !items.isEmpty else { return "No background items from other apps. " + appleNote }
        var parts: [String] = []
        for state in [State.on, .off, .notLoaded, .unknown] {
            let number = items.filter { $0.countLabel == state.label }.count
            if number > 0 { parts.append("\(number) \(state.label.lowercased())") }
        }
        let leftovers = items.filter { $0.tags.contains(leftoverTag) }.count
        if leftovers > 0 { parts.append(count(leftovers, "leftover", "leftovers")) }
        var line = "Found \(count(items.count, "background item", "background items")) from other apps: " + parts.joined(separator: ", ")
        if !ticked.isEmpty { line += " · \(ticked.count) ticked" }
        // A blocked journal: the rows say why; the summary says what it means.
        if items.contains(where: { $0.caveat?.hasPrefix(blockedPrefix) == true }) { return line + ". " + blockedSummary }
        return line + ". " + appleNote
    }

    static func applyTitle(ticked rows: [MacTweaksRow]) -> String {
        let changes = rows.compactMap(change(of:))
        let number = changes.count
        switch Set(changes) {
        case [.turnOff]: return "Turn off " + count(number, "item", "items")
        case [.turnOn]: return "Turn " + count(number, "item", "items") + " back on"
        case [.trash]: return "Move " + count(number, "leftover", "leftovers") + " to the Trash"
        default: return "Apply " + count(number, "change", "changes")
        }
    }

    /// The administrator runs a daemon's change, and the move of a leftover the user can't move:
    /// another account's, or one in `/Library/LaunchAgents` (For all users on a leftover).
    static func needsAdministrator(_ row: MacTweaksRow) -> Bool {
        row.id.hasPrefix("background:system/")
            || (change(of: row) == .trash && (row.items.first?.isForeign == true || row.tags.contains(allUsersTag)))
    }

    static let turnedOffNote = "Turned-off items stay off after a restart, until you turn them back on here "
        + "or with Undo everything Lightspot changed, in Settings."

    static func planNotes(_ rows: [MacTweaksRow]) -> [String] {
        let changes = rows.compactMap(change(of:))
        var notes: [String] = []
        if changes.contains(.turnOff) { notes.append(turnedOffNote) }
        if rows.contains(where: { $0.tags.contains(allUsersTag) }) { notes.append("Items for all users change for every account on this Mac.") }
        if rows.contains(where: needsAdministrator) { notes.append(MacTweaksStorage.passwordNote) }
        if changes.contains(.trash) { notes.append("Leftover files go to the Trash.") }
        return notes
    }

    // MARK: The administrator batch's steps

    /// `disable`, then `bootout` only while loaded: a failed disable stops nothing, since stopping
    /// it now without the override would bring it back at the next boot.
    static func turnOffCommand(_ launchctl: String, _ target: String) -> String {
        let (l, t) = (MacTweaksStorage.shellQuote(launchctl), MacTweaksStorage.shellQuote(target))
        return "\(l) disable \(t) && if \(l) print \(t) >/dev/null 2>&1; then \(l) bootout \(t); fi"
    }

    /// `enable`, then `bootstrap` only while not loaded (and only when asked: Undo everything
    /// starts only what was loaded before).
    static func turnOnCommand(_ launchctl: String, _ target: String, domain: String, plist: String, bootstrap: Bool = true) -> String {
        let (l, t) = (MacTweaksStorage.shellQuote(launchctl), MacTweaksStorage.shellQuote(target))
        guard bootstrap else { return "\(l) enable \(t)" }
        return "\(l) enable \(t) && if ! \(l) print \(t) >/dev/null 2>&1; then \(l) bootstrap "
            + "\(MacTweaksStorage.shellQuote(domain)) \(MacTweaksStorage.shellQuote(plist)); fi"
    }

    /// A leftover root moves: stopped if loaded, refused if still loaded, then the guarded move.
    static func stopAndTrashCommand(_ launchctl: String, _ target: String, move: String) -> String {
        let (l, t) = (MacTweaksStorage.shellQuote(launchctl), MacTweaksStorage.shellQuote(target))
        return "if \(l) print \(t) >/dev/null 2>&1; then \(l) bootout \(t); fi; "
            + "if \(l) print \(t) >/dev/null 2>&1; then echo 'Lightspot: still running after bootout'; exit 1; fi; " + move
    }

    // MARK: Applying

    /// One ticked item, as the fresh read finds it.
    private struct Step {
        let item: Item
        let change: Change
        let owner: String
        let disabled: Bool
        let loaded: Loaded
        /// What launchctl, or the batch step, last said when something failed.
        var said = ""
        /// Its administrator step, by 1-based position in the batch.
        var adminStep: Int?
        /// For a leftover: moved by the user, or where root moves it to.
        var trashedByUser = false
        var trashDestination: String?
        var stillRunning = false
        var refusedMove: String?
    }

    /// Blocking: changes `rows` and looks again. User agents first, as this user; then every
    /// daemon's change, and every leftover root must move, in one administrator batch; then launchd
    /// is read again and only what it confirms counts. A turn-off is journaled before anything runs.
    static func apply(_ rows: [MacTweaksRow], env: ProviderEnvironment,
                      progress: (@Sendable (String) -> Void)? = nil) -> (receipt: MacTweaksReceipt, rescanned: [MacTweaksRow]) {
        let started = env.now()
        let background = env.backgroundItems
        let launchctl = background.launchctl
        func shown(_ path: String) -> String { CleanDevMacEngine.displayPath(path, home: env.home) }
        var log: [String] = []
        var tally = Tally()
        var problems: [String] = []
        var notes: [String] = []
        let ticked = rows.filter { !$0.isLink && change(of: $0) != nil }

        // 1. Read again: the plist still there, through the gate, with the same label; launchd now.
        progress?("Reading launchd again…")
        let current = items(env)
        var found: [(item: Item, change: Change, owner: String)] = []
        for row in ticked {
            guard let change = change(of: row) else { continue }
            let plist = row.items.first?.target ?? ""
            if let item = current.first(where: { $0.id == row.id }), item.plist == plist {
                guard isAllowed(plist, item.place, env) else {
                    problems.append("\(row.title) stays as it is: a link on the way to its folder leads somewhere else.")
                    log.append("folder resolves elsewhere: \(shown(plist))")
                    continue
                }
                found.append((item, change, row.title))
            } else if !MacTweaksStorage.exists(plist) {
                tally.gone.append(row.title)
                log.append("gone already: \(shown(plist))")
            } else {
                problems.append("\(row.title) changed since the scan, so Lightspot left it alone.")
                log.append("changed since the scan: \(shown(plist))")
            }
        }
        let before = read(found.map(\.item), env)
        let guarded = guardedFolders(env)
        var steps: [Step] = []
        for (item, change, owner) in found {
            guard isActionable(item.label) else {
                problems.append("\(owner) stays as it is: its label can't be passed to launchctl safely.")
                continue
            }
            guard let disabled = before.isDisabled(item) else {
                problems.append("\(owner) stays as it is: launchd didn't say whether it's switched off.")
                continue
            }
            let loaded = before.isLoaded(item)
            switch change {
            case .turnOff where disabled:
                tally.alreadyOff.append(owner)
                continue
            case .turnOn where !disabled && loaded == .yes:
                tally.alreadyOn.append(owner)
                continue
            case .trash where !isLeftover(item, guarded: guarded):
                problems.append("\(owner) stays: what it runs is back.")
                log.append("not a leftover any more: \(shown(item.plist))")
                continue
            case .trash where item.isLink:
                problems.append("\(owner) stays: its file is a link now, and Lightspot doesn't move links.")
                continue
            case .trash where !item.alsoAt.isEmpty:
                problems.append("\(owner) stays: another copy has its label now, and launchd runs only one of them.")
                continue
            default:
                break
            }
            steps.append(Step(item: item, change: change, owner: owner, disabled: disabled, loaded: loaded))
        }

        // 2. The journal: nothing changes when it is blocked; turn-offs are recorded first.
        let journal = Self.journal(env)
        if case .blocked(let reason) = journal.status() {
            let receipt = MacTweaksReceipt(headline: "Nothing changed.", lines: tally.lines, problems: problems + [reason], isSuccess: false)
            MacTweaksProvider.appendReceipt(section: .backgroundItems, lines: log + ["journal blocked: \(reason)", receipt.headline],
                                            environment: env, started: started)
            return (receipt, scan(env, only: Set(ticked.map(\.id))))
        }
        var recordedNow = Set<String>()
        let offs = steps.filter { $0.change == .turnOff }
        if !offs.isEmpty {
            let entries = offs.map { Entry(item: $0.item, owner: $0.owner, wasDisabled: $0.disabled, wasLoaded: $0.loaded == .yes, date: started) }
            let aside: String?
            switch journal.recordAhead(entries) {
            case .saved(let added, let movedAside):
                recordedNow = added
                aside = movedAside
            case .failed(let reason, let movedAside):
                for step in offs { problems.append("Lightspot couldn't record what \(step.owner) was, so it left it on: \(reason)") }
                log.append("journal not saved: \(reason)")
                steps.removeAll { $0.change == .turnOff }
                aside = movedAside
            }
            if let aside {
                // Settings' words, for the same thing.
                notes.append("Lightspot couldn't read its undo journal, so it kept it as \(aside). Undo can't put back what that file recorded.")
                log.append("unreadable journal kept as \(aside)")
            }
        }

        // 3. User agents, as this user.
        let uid = env.userID
        var forAdministrator: [Int] = []
        if steps.contains(where: { !$0.item.system }) { progress?("Changing your background items…") }
        for index in steps.indices where !steps[index].item.system {
            let item = steps[index].item
            let target = target(item.label, system: false, userID: uid)
            func run(_ arguments: [String]) -> Bool {
                let result = launchctl(arguments)
                log.append("launchctl \(arguments.joined(separator: " ")): status \(result.status)")
                if result.status != 0 { steps[index].said = result.output }
                return result.status == 0
            }
            switch steps[index].change {
            case .turnOff:
                if run(["disable", target]), launchctl(["print", target]).status == 0 { _ = run(["bootout", target]) }
            case .turnOn:
                if run(["enable", target]), launchctl(["print", target]).status != 0 {
                    _ = run(["bootstrap", domain(system: false, userID: uid), item.plist])
                }
            case .trash:
                if launchctl(["print", target]).status == 0 { _ = run(["bootout", target]) }
                guard launchctl(["print", target]).status != 0 else {
                    steps[index].stillRunning = true
                    continue
                }
                guard isAllowed(item.plist, item.place, env), isRegularFile(item.plist) else {
                    steps[index].refusedMove = "it no longer passes Mac Tweaks' checks"
                    continue
                }
                do {
                    try env.moveToTrash(URL(fileURLWithPath: item.plist))
                    steps[index].trashedByUser = true
                    log.append("trashed: \(shown(item.plist))")
                } catch {
                    // Phase 1's rules: a folder's permissions (EACCES) or another owner, the
                    // administrator; macOS refusing the user's own file, or any other error, stays.
                    if !MacTweaksStorage.exists(item.plist) {
                        continue
                    } else if MacTweaksStorage.isPermissionError(error)
                                && (MacTweaksStorage.isAccessDenied(error) || item.ownerUID != uid) {
                        forAdministrator.append(index)
                    } else if MacTweaksStorage.isPermissionError(error) {
                        steps[index].refusedMove = "macOS didn't let Lightspot move it (\(error.localizedDescription))"
                    } else {
                        steps[index].refusedMove = error.localizedDescription
                    }
                }
            }
        }

        // 4. The administrator batch: daemons, and leftovers only root can move. Trash names are
        //    reserved only now, after every move of the user's own.
        let roots = MacTweaksStorage.Roots(env)
        let path = background.launchctlPath
        var commands: [String] = []
        var taken = Set<String>()
        func rootMove(_ index: Int) {
            let item = steps[index].item
            guard isAllowed(item.plist, item.place, env), isRegularFile(item.plist),
                  let physical = MacTweaksStorage.resolved((item.plist as NSString).deletingLastPathComponent) else {
                steps[index].refusedMove = "it no longer passes Mac Tweaks' checks"
                return
            }
            let destination = roots.trash + "/" + MacTweaksStorage.uniqueTrashName((item.plist as NSString).lastPathComponent,
                                                                                 in: roots.trash, taken: &taken)
            let move = MacTweaksStorage.guardedMove(item.plist, to: destination, trash: roots.trash, physicalParent: physical)
            commands.append(stopAndTrashCommand(path, target(item.label, system: item.system, userID: uid), move: move))
            steps[index].trashDestination = destination
            steps[index].adminStep = commands.count
        }
        for index in steps.indices where steps[index].item.system {
            let item = steps[index].item
            let target = target(item.label, system: true, userID: uid)
            switch steps[index].change {
            case .turnOff:
                commands.append(turnOffCommand(path, target))
                steps[index].adminStep = commands.count
            case .turnOn:
                commands.append(turnOnCommand(path, target, domain: "system", plist: item.plist))
                steps[index].adminStep = commands.count
            case .trash:
                rootMove(index)
            }
        }
        for index in forAdministrator { rootMove(index) }
        var adminRun: QuickActionsProvider.PrivilegedRun?
        var results: [Int: (status: Int32, output: String)] = [:]
        if !commands.isEmpty {
            progress?(MacTweaksStorage.passwordNote)
            let tag = "__LS_" + UUID().uuidString.prefix(8)
            let run = env.runAdmin(MacTweaksStorage.adminScript(commands, tag: tag))
            adminRun = run
            switch run {
            case .ran(let status, let output):
                results = MacTweaksStorage.batchResults(output, tag: tag)
                log.append("administrator batch (\(count(commands.count, "step", "steps"))): ran (status \(status))")
            case .cancelled:
                log.append("administrator batch: the prompt was cancelled")
            case .refused(let message):
                log.append("administrator batch: not authorized (\(message))")
            }
        }
        /// Why a step did nothing: the prompt, or the reason launchctl (or the batch step) printed.
        func why(_ step: Step) -> String {
            var printed = step.said
            if let index = step.adminStep {
                switch adminRun {
                case .cancelled?: return "it needs Touch ID or your password, and the prompt was cancelled"
                case .refused?: return "it needs Touch ID or your password, and macOS didn't accept it"
                case .ran?, nil:
                    guard let result = results[index] else { return "the administrator batch stopped before it" }
                    printed = result.output
                }
            }
            let reason = MacTweaksStorage.reason(printed)
            return reason.isEmpty ? "launchctl reported no error" : reason
        }

        // 5. Look again.
        progress?("Checking launchd…")
        let after = read(steps.map(\.item), env)
        var unconfirmed = 0
        var forget = Set<String>()
        for step in steps {
            let item = step.item
            switch step.change {
            case .turnOff:
                // Only what launchd confirms counts, either way: when its list can't be read, the
                // entry written ahead stays, so Undo everything can still turn the item back on.
                switch after.isDisabled(item) {
                case true?:
                    tally.turnedOff.append(step.owner)
                    if step.loaded == .no { log.append("off, and it wasn't loaded: \(step.owner)") }
                    if after.isLoaded(item) == .yes {
                        problems.append("\(step.owner) is off, but still running \(untilRestart(system: item.system)) (\(why(step))).")
                    }
                case false?:
                    problems.append("\(step.owner) is still on (\(why(step))).")
                    if recordedNow.contains(item.id) { forget.insert(item.id) }
                case nil:
                    unconfirmed += 1
                    problems.append("\(step.owner): launchd didn't say whether it's off now. Lightspot kept its record, "
                                    + "so Undo everything can still turn it back on.")
                }
            case .turnOn:
                switch after.isDisabled(item) {
                case false?:
                    tally.turnedOn.append(step.owner)
                    forget.insert(item.id)
                    if after.isLoaded(item) != .yes {
                        problems.append("\(step.owner) is on again, but it didn't load (\(why(step))). "
                                        + "Login Items & Extensions in System Settings may have it switched off.")
                    }
                case true?:
                    problems.append("\(step.owner) is still off (\(why(step))).")
                case nil:
                    unconfirmed += 1
                    problems.append("\(step.owner): launchd didn't say whether it's on now. Lightspot kept its record.")
                }
            case .trash:
                let gone = !MacTweaksStorage.exists(item.plist)
                var batchMoved = false
                if let destination = step.trashDestination, let index = step.adminStep, case .ran? = adminRun {
                    batchMoved = gone && MacTweaksStorage.exists(destination) && (results[index]?.status ?? 0) == 0
                }
                if gone && (step.trashedByUser || batchMoved) {
                    tally.trashed.append(step.owner)
                    forget.insert(item.id)
                } else if gone {
                    forget.insert(item.id)
                    problems.append("\(step.owner): it was gone before Lightspot moved it.")
                } else if step.stillRunning {
                    problems.append("\(step.owner) stays: it was still running after Lightspot stopped it.")
                } else if let refused = step.refusedMove {
                    // macOS's own words may already end the sentence.
                    problems.append("\(step.owner) stays: \(refused)" + (refused.hasSuffix(".") ? "" : "."))
                } else {
                    problems.append("\(step.owner) stays (\(why(step))).")
                }
            }
        }
        if !forget.isEmpty, let failure = journal.remove(forget) {
            problems.append("Lightspot couldn't update its journal: \(failure)")
        }

        if !tally.turnedOff.isEmpty { notes.append(turnBackOnNote(tally.turnedOff.count)) }
        let receipt = MacTweaksReceipt(headline: tally.headline(unconfirmed: unconfirmed), lines: tally.lines, problems: problems,
                                       notes: notes, isSuccess: problems.isEmpty && tally.changed > 0)
        MacTweaksProvider.appendReceipt(section: .backgroundItems, lines: log + [receipt.headline] + receipt.lines + problems,
                                        environment: env, started: started)
        return (receipt, scan(env, only: Set(ticked.map(\.id))))
    }

    static func turnBackOnNote(_ number: Int) -> String {
        "Turn \(number == 1 ? "it" : "them") back on here, or with Undo everything Lightspot changed, in Settings."
    }

    /// What an apply did, by kind: the receipt has one wrapped line per kind, as Settings' does
    /// ("Turned off: Docker, GoogleUpdater."), under a headline short enough for one line.
    struct Tally: Sendable, Equatable {
        var turnedOff: [String] = []
        var turnedOn: [String] = []
        var trashed: [String] = []
        var alreadyOff: [String] = []
        var alreadyOn: [String] = []
        /// Their files were gone before the apply.
        var gone: [String] = []

        var changed: Int { turnedOff.count + turnedOn.count + trashed.count }

        var lines: [String] {
            [("Turned off", turnedOff), ("Turned back on", turnedOn), ("Moved to the Trash", trashed),
             ("Already off", alreadyOff), ("Already on", alreadyOn), ("Already gone", gone)]
                .filter { !$0.1.isEmpty }
                .map { $0.0 + ": " + $0.1.joined(separator: ", ") + "." }
        }

        func headline(unconfirmed: Int) -> String {
            let kinds = [turnedOff, turnedOn, trashed].filter { !$0.isEmpty }.count
            switch kinds {
            case 0: return unconfirmed > 0 ? "launchd didn't confirm what changed." : "Nothing changed."
            case 1 where !turnedOff.isEmpty: return "Turned off " + MacTweaksBackground.count(changed, "item", "items") + "."
            case 1 where !turnedOn.isEmpty: return "Turned " + MacTweaksBackground.count(changed, "item", "items") + " back on."
            case 1: return "Moved " + MacTweaksBackground.count(changed, "leftover", "leftovers") + " to the Trash."
            default: return "Changed " + MacTweaksBackground.count(changed, "background item", "background items") + "."
            }
        }
    }

    /// A regular file, not a link: the only thing a leftover's move takes.
    static func isRegularFile(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFREG
    }

    // MARK: The journal

    /// `MacTweaksJournal`'s status of `tweaks-journal.json`, as a scan reads it: ready (or no
    /// file yet); unreadable (the first write keeps it aside); blocked (it can't be read or kept
    /// aside: nothing changes, every row is read-only).
    typealias JournalStatus = MacTweaksJournal.Status

    enum JournalWrite: Sendable, Equatable {
        /// Saved; the keys this call added (entries already there are never touched), and the
        /// name an unreadable file was kept aside as first.
        case saved(added: Set<String>, movedAside: String? = nil)
        /// Not saved, and why; an unreadable file may have been kept aside before the save failed.
        case failed(String, movedAside: String? = nil)
    }

    /// Settings' `tweaks-journal.json` (`MacTweaksJournal`), narrowed to `background:` entries:
    /// the section needs only these four calls. `file` is the real one; tests give an in-memory
    /// one.
    struct Journal: Sendable {
        /// Read only: never moves or writes anything (a scan).
        var status: @Sendable () -> JournalStatus
        /// Every `background:` entry it holds that decodes.
        var entries: @Sendable () -> [Entry]
        /// Adds the entries it lacks (the first previous state wins), keeping an unreadable file
        /// aside first, and saves before the caller changes anything.
        var recordAhead: @Sendable ([Entry]) -> JournalWrite
        /// Removes these keys and saves; nil, or why it couldn't.
        var remove: @Sendable (Set<String>) -> String?

        /// The journal file through `MacTweaksJournal`, its rules and all: a scan reads its
        /// status and entries and moves nothing; a write starts from `loadForWriting` (an
        /// unreadable file kept aside first, nothing written when it can't be) and saves ahead,
        /// atomically. Every other entry, of Settings or of a kind this version doesn't know, is
        /// written back as it was read. Runs on the provider's queue, as Settings' writes do.
        static func file(url: URL, home: String, fileSystem: MacTweaksJournal.FileSystem,
                         now: @escaping @Sendable () -> Date) -> Journal {
            Journal(
                status: { MacTweaksJournal.status(url: url, home: home, fileSystem: fileSystem) },
                entries: {
                    (MacTweaksJournal.load(url: url, fileSystem: fileSystem).journal?.entries(kind: Entry.kind) ?? [])
                        .compactMap { Entry(key: $0.key, json: $0.json) }
                },
                recordAhead: { entries in
                    let access = MacTweaksJournal.loadForWriting(url: url, now: now(), home: home, fileSystem: fileSystem)
                    guard var journal = access.journal else { return .failed(access.blockedReason ?? "it can't be read") }
                    var added = Set<String>()
                    for entry in entries where journal.recordIfAbsent(entry.key, entry.json) { added.insert(entry.key) }
                    guard !added.isEmpty || access.movedAside != nil else { return .saved(added: []) }
                    do {
                        try journal.saveAhead(url: url, fileSystem: fileSystem)
                    } catch {
                        return .failed(error.localizedDescription, movedAside: access.movedAside)
                    }
                    return .saved(added: added, movedAside: access.movedAside)
                },
                remove: { keys in
                    // Nothing to take out of a file that isn't there or can't be read: an
                    // unreadable one is kept aside by the next write that records something.
                    guard case .loaded(let current) = MacTweaksJournal.load(url: url, fileSystem: fileSystem),
                          keys.contains(where: { current.json($0) != nil }) else { return nil }
                    var journal = current
                    for key in keys { journal.remove(key) }
                    do {
                        try journal.saveAhead(url: url, fileSystem: fileSystem)
                    } catch {
                        return error.localizedDescription
                    }
                    return nil
                })
        }
    }

    /// The section's journal: the environment's, else the journal file, through Settings' file
    /// system, so what forbids Settings' writes (deep_verify) forbids these too.
    static func journal(_ env: ProviderEnvironment) -> Journal {
        env.backgroundItems.journal ?? .file(url: MacTweaksJournal.url(home: env.home), home: env.home,
                                             fileSystem: env.settings.fileSystem, now: env.now)
    }

    /// One entry: what an item was before Lightspot first turned it off. Its JSON is this type's
    /// own; `MacTweaksJournal` keeps the object as it is.
    struct Entry: Sendable, Equatable {
        static let kind = "background"
        let key: String
        let label: String
        let system: Bool
        let plist: String
        /// For the plan and the receipt, when the file is gone.
        let owner: String
        let wasDisabled: Bool
        /// Lightspot's: Undo everything starts only what was loaded before.
        let wasLoaded: Bool
        let date: Date

        init(item: Item, owner: String, wasDisabled: Bool, wasLoaded: Bool, date: Date) {
            key = item.id
            label = item.label
            system = item.system
            plist = item.plist
            self.owner = owner
            self.wasDisabled = wasDisabled
            self.wasLoaded = wasLoaded
            // ISO 8601 keeps whole seconds; so does the entry, so it round-trips equal.
            self.date = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
        }

        private struct Stored: Codable {
            var kind: String?
            var tweak: String?
            var label: String?
            var domain: String?
            var plist: String?
            var owner: String?
            var wasDisabled: Bool
            var wasLoaded: Bool?
            var date: Date?
        }

        /// From the journal: nil for another kind, or fields that contradict the key. Fields an
        /// older writer left out come from the key (`wasLoaded` then reads as loaded, which starts
        /// the item again as RemoveMacAI's undo does).
        init?(key: String, json: Data) {
            guard let named = MacTweaksBackground.parse(key: key) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let stored = try? decoder.decode(Stored.self, from: json), (stored.kind ?? Self.kind) == Self.kind,
                  (stored.tweak ?? key) == key, (stored.label ?? named.label) == named.label,
                  (stored.domain ?? (named.system ? "system" : "gui")) == (named.system ? "system" : "gui") else { return nil }
            self.key = key
            label = named.label
            system = named.system
            plist = stored.plist ?? ""
            owner = stored.owner ?? named.label
            wasDisabled = stored.wasDisabled
            wasLoaded = stored.wasLoaded ?? true
            date = stored.date ?? Date(timeIntervalSince1970: 0)
        }

        /// The object the journal stores: kind, tweak (the key), label, domain, plist, owner,
        /// wasDisabled, wasLoaded and date, ISO 8601 as the rest of the file.
        var json: Data {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let stored = Stored(kind: Self.kind, tweak: key, label: label, domain: system ? "system" : "gui", plist: plist,
                                owner: owner, wasDisabled: wasDisabled, wasLoaded: wasLoaded, date: date)
            return (try? encoder.encode(stored)) ?? Data()
        }
    }

    // MARK: Undo everything's hook

    /// What Undo everything runs for the journal's `background:` entries: Settings' hook type,
    /// built on the provider's queue from a fresh scan.
    typealias Undo = MacTweaksSettings.BackgroundUndo

    /// Reads launchd once, the first time it's asked, for `outcome`.
    private final class OnceReading: @unchecked Sendable {
        private let lock = NSLock()
        private var reading: Launchd?
        private let make: @Sendable () -> Launchd
        init(_ make: @escaping @Sendable () -> Launchd) { self.make = make }
        var value: Launchd {
            lock.lock()
            defer { lock.unlock() }
            if let reading { return reading }
            let fresh = make()
            reading = fresh
            return fresh
        }
    }

    /// What the agents' steps did: each refused `enable`'s output, and the log's lines.
    private final class UndoRecord: @unchecked Sendable {
        private let lock = NSLock()
        private var refusals: [String: String] = [:]
        private var lines: [String] = []
        func refused(_ key: String, _ output: String) { lock.lock(); refusals[key] = output; lock.unlock() }
        func refusal(_ key: String) -> String? { lock.lock(); defer { lock.unlock() }; return refusals[key] }
        func log(_ line: String) { lock.lock(); lines.append(line); lock.unlock() }
        var log: [String] { lock.lock(); defer { lock.unlock() }; return lines }
    }

    /// Each entry by its own fields, checked against what is on disk now. The plist used is always
    /// the scan's: the journal is the user's own file, so nothing it says alone makes root act.
    /// Only what was loaded before is started again; an entry whose plist is gone has nothing to
    /// turn back on, so nothing runs and it is dropped; one that contradicts itself, or names a
    /// label Lightspot never changes, stays (`refused`), as do the keys in `unreadable`.
    static func undo(_ entries: [Entry], unreadable: [String] = [], environment env: ProviderEnvironment) -> Undo {
        let found = Dictionary(items(env).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let uid = env.userID
        let path = env.backgroundItems.launchctlPath
        var admin: [String] = []
        var adminKeys: [String] = []
        var agents: [(key: String, item: Item, owner: String, bootstrap: Bool)] = []
        var decided: [String: MacTweaksSettings.BackgroundOutcome] = [:]
        var refused: [String] = []
        var watchedItems: [String: (item: Item, owner: String)] = [:]
        for entry in entries {
            guard entry.key == key(label: entry.label, system: entry.system), isActionable(entry.label),
                  !entry.label.hasPrefix("com.apple.") else {
                refused.append(entry.key)
                continue
            }
            if entry.wasDisabled {
                decided[entry.key] = .undone(line: "\(entry.owner): left off, as it was before Lightspot.")
                continue
            }
            guard let item = found[entry.key] else {
                decided[entry.key] = .dropped(line: "\(entry.owner): its plist is gone, so Lightspot ran nothing and dropped its entry; "
                                                  + "launchd keeps its switch off.")
                continue
            }
            watchedItems[entry.key] = (item, entry.owner)
            if item.system {
                admin.append(turnOnCommand(path, target(item.label, system: true, userID: uid), domain: "system",
                                           plist: item.plist, bootstrap: entry.wasLoaded))
                adminKeys.append(entry.key)
            } else {
                agents.append((entry.key, item, entry.owner, entry.wasLoaded))
            }
        }
        let launchctl = env.backgroundItems.launchctl
        let home = env.home
        let record = UndoRecord()
        let toStart = agents
        let settled = decided
        let watched = watchedItems
        let reading = OnceReading { read(watched.values.map(\.item), env) }
        return Undo(
            adminCommands: admin,
            adminKeys: adminKeys,
            userSteps: {
                var problems: [String] = []
                for agent in toStart {
                    let target = target(agent.item.label, system: false, userID: uid)
                    let enabled = launchctl(["enable", target])
                    record.log("launchctl enable \(target): status \(enabled.status)")
                    guard enabled.status == 0 else {
                        record.refused(agent.key, enabled.output)
                        continue
                    }
                    guard agent.bootstrap, launchctl(["print", target]).status != 0 else { continue }
                    let gui = domain(system: false, userID: uid)
                    let loaded = launchctl(["bootstrap", gui, agent.item.plist])
                    record.log("launchctl bootstrap \(gui) \(CleanDevMacEngine.displayPath(agent.item.plist, home: home)): status \(loaded.status)")
                    if loaded.status != 0 {
                        problems.append("\(agent.owner) is on again, but it didn't load\(because(loaded.output)). "
                                        + "Login Items & Extensions in System Settings may have it switched off.")
                    }
                }
                return problems
            },
            outcome: { key, step in
                if let outcome = settled[key] { return outcome }
                guard let watchedItem = watched[key] else { return .kept(problem: nil) }
                let owner = watchedItem.owner
                switch reading.value.isDisabled(watchedItem.item) {
                case false?:
                    return .undone(line: nil)
                case nil:
                    return .kept(problem: "\(owner): launchd didn't say whether it's on now, so Lightspot keeps its record.")
                case true?:
                    if watchedItem.item.system {
                        // No step result: the batch didn't run, and the receipt says why for every daemon.
                        guard let step else { return .kept(problem: nil) }
                        return .kept(problem: stillOff(owner, refused: step.status != 0, output: step.output))
                    }
                    let refusal = record.refusal(key)
                    return .kept(problem: stillOff(owner, refused: refusal != nil, output: refusal ?? ""))
                }
            },
            unreadable: unreadable,
            refused: refused,
            log: { record.log })
    }

    /// "<owner>: still off (why).", in launchctl's words when it refused; when it said nothing,
    /// no brackets; when it reported no error, that.
    static func stillOff(_ owner: String, refused: Bool, output: String) -> String {
        guard refused else { return "\(owner): still off (launchctl reported no error)." }
        let reason = MacTweaksStorage.reason(output)
        return reason.isEmpty ? "\(owner): still off." : "\(owner): still off (\(reason))."
    }

    /// What launchctl printed when it refused, as " (reason)", or nothing when it said nothing.
    static func because(_ output: String) -> String {
        let reason = MacTweaksStorage.reason(output)
        return reason.isEmpty ? "" : " (\(reason))"
    }

    /// Undo everything's plan line for an entry, from its own fields and whether a scan finds its
    /// plist (`found`). It promises only what `undo` would do: an entry `undo` keeps or drops
    /// says so, and the journal's plist path is never shown (`undo` uses the one the scan finds).
    static func undoPlanLine(_ entry: Entry, userID: uid_t, found: Bool = true) -> String {
        guard entry.key == key(label: entry.label, system: entry.system), isActionable(entry.label),
              !entry.label.hasPrefix("com.apple.") else {
            return "\(entry.label): kept: Lightspot can't undo this entry."
        }
        if entry.wasDisabled { return "\(entry.owner): it was off before Lightspot, so it stays off." }
        guard found else { return "\(entry.owner): its plist is gone, so Lightspot runs nothing and drops its entry; launchd keeps its switch off." }
        let target = target(entry.label, system: entry.system, userID: userID)
        if entry.wasLoaded {
            return "\(entry.owner): back on and started again (launchctl enable \(target), then launchctl bootstrap)."
        }
        return "\(entry.owner): launchd's switch back on; it wasn't loaded before (launchctl enable \(target))."
    }

    /// The plan lines for every entry at once, by key: one look for the plists (`items`), and
    /// only when an entry needs it. An entry that doesn't decode is kept, and its line says so.
    static func undoPlanLines(_ pairs: [(key: String, json: Data)], environment env: ProviderEnvironment) -> [String: String] {
        let entries = pairs.map { (key: $0.key, entry: Entry(key: $0.key, json: $0.json)) }
        let needsScan = entries.contains { $0.entry.map { !$0.wasDisabled && isActionable($0.label) } ?? false }
        let found = needsScan ? Set(items(env).map(\.id)) : []
        var lines: [String: String] = [:]
        for (key, entry) in entries {
            guard let entry else {
                lines[key] = "\(key): kept, its journal entry can't be read, so Lightspot can't tell what to put back"
                continue
            }
            lines[key] = undoPlanLine(entry, userID: env.userID, found: found.contains(entry.key))
        }
        return lines
    }

    /// Connects Settings' Undo everything to this section (`MacTweaksProvider.settingsEnvironment`):
    /// the journal's `background:` entries go to `undo`, whose root steps join Settings' one
    /// administrator batch, profile or no profile, and their plan lines come from `undoPlanLines`.
    static func connectUndoEverything(_ env: inout ProviderEnvironment) {
        let base = env
        env.settings.background = { pairs in
            let entries = pairs.compactMap { Entry(key: $0.key, json: $0.json) }
            let decoded = Set(entries.map(\.key))
            return MacTweaksBackground.undo(entries, unreadable: pairs.map(\.key).filter { !decoded.contains($0) }, environment: base)
        }
        env.settings.backgroundPlanLines = { pairs in undoPlanLines(pairs, environment: base) }
    }

    // MARK: Environment

    /// Everything the section reads or changes beyond the provider's environment, injected so tests
    /// run against a fake launchctl and a fake journal. `.inert` reads nothing.
    struct Environment: Sendable {
        /// launchctl as the administrator batch names it: absolute, since the batch runs as root.
        var launchctlPath = "/bin/launchctl"
        /// launchctl as this user: its status and everything it printed (the reason is on stderr).
        var launchctl: @Sendable ([String]) -> (status: Int32, output: String) = { _ in (-1, "") }
        /// The app LaunchServices knows by a bundle identifier, as its file name without ".app".
        var appName: @Sendable (String) -> String? = { _ in nil }
        /// nil for the journal file, read and written through Settings' file system
        /// (`journal(_:)`): `.inert`'s writes nothing, so an inert apply records, and changes,
        /// nothing. Tests set an in-memory one.
        var journal: Journal? = nil

        static let inert = Environment()

        /// Closures only: nothing runs until the section scans.
        static var live: Environment {
            var environment = Environment()
            let path = environment.launchctlPath
            environment.launchctl = { MacTweaksBackground.run(path, $0) }
            environment.appName = { id in
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { ($0.lastPathComponent as NSString).deletingPathExtension }
            }
            return environment
        }
    }

    /// The child, for the timeout's closure: Process isn't Sendable, and only `terminate()` is
    /// called from there.
    private final class Child: @unchecked Sendable {
        let process = Process()
    }

    /// Runs a program directly, never through a shell, with stdin from /dev/null and stdout and
    /// stderr on one pipe, which is read before waiting (invariant 1). Stopped past `timeout`
    /// (status -1). Keeps the first 64 KiB of what it printed.
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 10) -> (status: Int32, output: String) {
        let child = Child()
        let process = child.process
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return (-1, "")
        }
        let stop = DispatchWorkItem { if child.process.isRunning { child.process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: stop)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        stop.cancel()
        let stopped = process.terminationReason == .uncaughtSignal && process.terminationStatus == SIGTERM
        return (stopped ? -1 : process.terminationStatus, String(decoding: data.prefix(65_536), as: UTF8.self))
    }

    // MARK: Engine

    /// Background Items as a Mac Tweaks section.
    struct Engine: MacTweaksSectionEngine {
        let environment: ProviderEnvironment

        func scan(only: Set<String>?, progress: (@Sendable (String) -> Void)?) -> [MacTweaksRow] {
            MacTweaksBackground.scan(environment, only: only, progress: progress)
        }

        func apply(_ rows: [MacTweaksRow], progress: (@Sendable (String) -> Void)?) -> (receipt: MacTweaksReceipt, rescanned: [MacTweaksRow]) {
            MacTweaksBackground.apply(rows, env: environment, progress: progress)
        }

        func planNotes(for rows: [MacTweaksRow]) -> [String] {
            MacTweaksBackground.planNotes(rows)
        }
    }
}
