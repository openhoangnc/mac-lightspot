import Foundation
import Darwin

// MARK: - Mac Tweaks: Settings
//
// The tweaks in `MacTweaksSettings.catalog`, each with its state, a tick that changes it, and an
// undo journal so everything Lightspot changed can go back as it was. Ported from RemoveMacAI's
// Engine.swift, Prefs.swift and MusicLaunch.swift (MIT). Local settings go through cfprefsd
// (invariant 8), launchctl for Music's launch entry and the media keys, the Dock's tiles and
// `~/Library`'s flag, each journaled before it changes; the profile-backed ones go in the Mac
// Tweaks profile through the same approval as Apple Intelligence, keeping what that profile
// holds for Apple Intelligence. Scans and applies block, so they run on MacTweaksProvider's
// queue, only once the user opens the section; the summary and the plan are built from what the
// scan read, and read nothing.

extension MacTweaksSettings {
    typealias ProviderEnvironment = MacTweaksProvider.Environment

    /// Where a tweak stands on this Mac.
    enum State: Sendable, Equatable {
        case on, off, partly
        /// Another configuration profile sets one of its keys: Lightspot leaves it alone.
        case managed
        case notOnThisMacOS

        var label: String {
            switch self {
            case .on: return "On"
            case .off: return "Off"
            case .partly: return "Partly"
            case .managed: return "Managed"
            case .notOnThisMacOS: return "Not on this macOS"
            }
        }
    }

    static let undoEverythingID = "undo-everything"
    static let undoEverythingTitle = "Undo everything Lightspot changed"
    /// The tag on a row that goes in the profile, drawn with a lock.
    static let profileTag = "Profile"
    static let presetsGroup = "Presets"
    static let undoGroup = "Undo"
    static let musicPrefix = "application.com.apple.Music."
    static let managedCaveat = "Another configuration profile sets this, so Lightspot leaves it alone."
    static let alreadyOffCaveat = "Already off in your own settings, but not locked."
    static let sharedProfileNote = "This profile applies to every account on this Mac: changing it here changes it for them too."
    static let reopenNote = "Apps you have open pick up these changes when you reopen them."
    static let undoLaterNote = "Undo them here later, one by one or with Undo everything Lightspot changed."
    static let trashNote = "Files Free Up Space moved to the Trash stay there."
    static let backgroundForEveryoneNote = "Background items for all users come back on for every account on this Mac."

    // MARK: The environment

    /// What became of one of Background Items' journal entries in Undo everything.
    enum BackgroundOutcome: Sendable, Equatable {
        /// Back as it was before Lightspot: its entry goes. `line` says how, when the count alone
        /// can't (one that was off before Lightspot stays off).
        case undone(line: String?)
        /// Nothing left to undo (its plist is gone): nothing ran, its entry goes, and `line`
        /// says so.
        case dropped(line: String)
        /// It stays, and so does its entry. `problem` says why, unless the receipt already does
        /// (a prompt cancelled or refused).
        case kept(problem: String?)
    }

    /// What background items Lightspot turned off contribute to Undo everything (Background
    /// Items' hook): root steps for the one administrator batch, steps as this user, and what
    /// became of each journal key once both have run.
    struct BackgroundUndo: Sendable {
        var adminCommands: [String] = []
        /// The journal key each of `adminCommands` undoes, in order.
        var adminKeys: [String] = []
        /// As this user; returns problem lines.
        var userSteps: @Sendable () -> [String] = { [] }
        /// After the batch and the user steps: a key's outcome, given its administrator step's
        /// status and output (nil when it has none, or the batch didn't run).
        var outcome: @Sendable (String, (status: Int32, output: String)?) -> BackgroundOutcome = { _, _ in .kept(problem: nil) }
        /// Keys it keeps without trying: entries it can't read, and entries naming what Lightspot
        /// never changes. The receipt notes both.
        var unreadable: [String] = []
        var refused: [String] = []
        /// What it ran as this user, for the receipts log.
        var log: @Sendable () -> [String] = { [] }
    }

    /// Everything the section reads or changes, injected so tests use fakes and scratch domains,
    /// and deep_verify reads only. `.inert` is the safe default; `.live` wires the real system.
    struct Environment: Sendable {
        var preferences = PreferenceStore.inert
        /// `/bin/launchctl` with these arguments: its status and what it printed, stderr included.
        var launchctl: @Sendable ([String]) -> (status: Int32, output: String) = { _ in (-1, "") }
        /// A path's inode (lstat), for Music's launch label.
        var inode: @Sendable (String) -> UInt64? = { _ in nil }
        var isHidden: @Sendable (String) -> Bool? = { _ in nil }
        var setHidden: @Sendable (String, Bool) -> Bool = { _, _ in false }
        /// `killall <name>` for Finder, the Dock and SystemUIServer, which read these settings
        /// only at launch.
        var restart: @Sendable (String) -> Bool = { _ in false }
        /// This user's running Dock (`MacTweaksDock.runningDock`), so a Dock that just restarted
        /// settles before a change it reads, and the one a restart brings up is checked
        /// (`restartDock`). Nil where processes can't be seen: nothing waits then.
        var runningDock: (@Sendable () -> MacTweaksDock.Running?)? = nil
        var pause: @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
        var fileSystem = MacTweaksJournal.FileSystem.inert
        var osVersion: @Sendable () -> (Int, Int) = { Catalog.currentOS }
        /// Background Items' part of Undo everything: nil when this build has none, and then its
        /// journal entries stay.
        var background: (@Sendable ([(key: String, json: Data)]) -> BackgroundUndo)? = nil
        /// The plan's line for each of its entries, by key, built once per scan.
        var backgroundPlanLines: (@Sendable ([(key: String, json: Data)]) -> [String: String])? = nil

        static let inert = Environment()

        static var live: Environment {
            var env = Environment()
            env.preferences = .live()
            env.launchctl = { CleanDevMacEngine.run("/bin/launchctl", $0, timeout: 10, mergeErrors: true) }
            env.inode = { path in
                var info = stat()
                return lstat(path, &info) == 0 ? UInt64(info.st_ino) : nil
            }
            env.isHidden = { path in
                var url = URL(fileURLWithPath: path)
                url.removeAllCachedResourceValues()
                return (try? url.resourceValues(forKeys: [.isHiddenKey]))?.isHidden
            }
            env.setHidden = { path, hidden in
                var url = URL(fileURLWithPath: path)
                var values = URLResourceValues()
                values.isHidden = hidden
                return (try? url.setResourceValues(values)) != nil
            }
            env.restart = { CleanDevMacEngine.run("/usr/bin/killall", [$0], timeout: 10).status == 0 }
            env.runningDock = { MacTweaksDock.runningDock() }
            env.fileSystem = .live
            return env
        }
    }

    static func journalURL(_ env: ProviderEnvironment) -> URL { MacTweaksJournal.url(home: env.home) }
    static func libraryPath(_ env: ProviderEnvironment) -> String { env.home + "/Library" }
    static func musicApp(_ env: ProviderEnvironment) -> String { root(env) + "System/Applications/Music.app" }
    static func rcdPlist(_ env: ProviderEnvironment) -> String { root(env) + "System/Library/LaunchAgents/com.apple.rcd.plist" }
    /// rcd's plist as launchctl takes it (`rcdPlist` is where a scan looks for it).
    static let rcdPlistPath = "/System/Library/LaunchAgents/com.apple.rcd.plist"
    private static func root(_ env: ProviderEnvironment) -> String { env.systemRoot.hasSuffix("/") ? env.systemRoot : env.systemRoot + "/" }

    /// Music's application job: `application.com.apple.Music.<inode of Music.app>.<inode of its
    /// executable>`, the form launchd uses (platform report D). Inodes are 19 digits here.
    static func musicLabel(_ env: ProviderEnvironment) -> String? {
        let app = musicApp(env)
        guard let bundle = env.settings.inode(app), let executable = env.settings.inode(app + "/Contents/MacOS/Music") else { return nil }
        return musicPrefix + String(bundle) + "." + String(executable)
    }

    /// The labels in `launchctl print-disabled`'s output that are disabled (`=> disabled`, or
    /// `true` on older systems; report E3).
    static func disabledLabels(_ output: String) -> Set<String> {
        var labels = Set<String>()
        for line in output.split(separator: "\n") {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            guard value == "disabled" || value == "true" else { continue }
            labels.insert(parts[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
        }
        return labels
    }

    // MARK: What a scan reads

    /// One Dock tile, as the plan names it.
    struct DockTile: Sendable, Equatable {
        var bundleID: String?
        var label: String
    }

    /// What the Mac looks like, read once per scan or apply. The provider keeps the scan's, so the
    /// summary and the plan read nothing.
    struct Reading: Sendable {
        var os: (Int, Int) = Catalog.currentOS
        var userID: uid_t = 0
        var installed = MacTweaksProfile.Installed()
        var disabled: Set<String> = []
        /// Disabled labels launchd still has loaded (asked only for those).
        var loaded: Set<String> = []
        var musicLabel: String?
        var dock: [DockTile] = []
        var libraryHidden: Bool?
        /// By "domain|key": what apps see, the user's own, and the forced keys.
        var values: [String: PreferenceValue] = [:]
        var userValues: [String: PreferenceValue] = [:]
        var forced: Set<String> = []
        var journal = MacTweaksJournal()
        var journalStatus = MacTweaksJournal.Status.ready
        var rcdPlistExists = false
        var dockBackupExists = false
        /// The home folder: which deleted background plists go back into this user's own folder.
        var home = NSHomeDirectory()

        static func slot(_ domain: String, _ key: String) -> String { domain + "|" + key }
        func value(_ domain: String, _ key: String) -> PreferenceValue? { values[Self.slot(domain, key)] }
        func userValue(_ domain: String, _ key: String) -> PreferenceValue? { userValues[Self.slot(domain, key)] }
        func isForced(_ domain: String, _ key: String) -> Bool { forced.contains(Self.slot(domain, key)) }
    }

    /// Every (domain, key) the catalog reads.
    static let readKeys: [(domain: String, key: String)] = catalog.flatMap { tweak in
        tweak.changes.compactMap { change -> (domain: String, key: String)? in
            switch change {
            case .restriction(let key): return (restriction, key)
            case .forced(let domain, let key, _), .pref(let domain, let key, _): return (domain, key)
            default: return nil
            }
        }
    }

    /// Blocking: the marker, launchd's disabled list (and whether a disabled rcd or Music job is
    /// still loaded), Music's inodes, the Dock's tiles, `~/Library`'s flag, every catalog key
    /// through cfprefsd (each domain synchronized once) and the journal (read, never moved).
    /// `journal` replaces the file's when an apply already holds one.
    static func read(_ env: ProviderEnvironment, journal: MacTweaksJournal? = nil) -> Reading {
        let settings = env.settings
        var r = Reading()
        r.os = settings.osVersion()
        r.userID = env.userID
        r.home = env.home
        r.installed = env.intelligence.profileInstalled()
        let url = journalURL(env)
        if let journal {
            r.journal = journal
        } else {
            r.journalStatus = MacTweaksJournal.status(url: url, home: env.home, fileSystem: settings.fileSystem)
            r.journal = MacTweaksJournal.load(url: url, fileSystem: settings.fileSystem).journal ?? MacTweaksJournal()
        }
        r.disabled = disabledLabels(settings.launchctl(["print-disabled", "gui/\(env.userID)"]).output)
        r.musicLabel = musicLabel(env)
        for label in [rcdLabel, r.musicLabel].compactMap({ $0 }) where r.disabled.contains(label) {
            if isLoaded(label, env) { r.loaded.insert(label) }
        }
        let store = settings.preferences
        store.synchronize(dock)
        r.dock = MacTweaksDock.tiles(store.read(dock, MacTweaksDock.key)).map {
            DockTile(bundleID: MacTweaksDock.bundleID($0), label: MacTweaksDock.label($0))
        }
        r.libraryHidden = settings.isHidden(libraryPath(env))
        var synchronized = Set<String>()
        for (domain, key) in readKeys {
            if synchronized.insert(domain).inserted { store.synchronize(domain) }
            let slot = Reading.slot(domain, key)
            r.values[slot] = store.read(domain, key)
            r.userValues[slot] = store.userValue(domain, key)
            if store.isForced(domain, key) { r.forced.insert(slot) }
        }
        r.rcdPlistExists = settings.fileSystem.exists(URL(fileURLWithPath: rcdPlist(env)))
        r.dockBackupExists = settings.fileSystem.exists(MacTweaksDock.backupURL(home: env.home))
        return r
    }

    /// Whether launchd has the job loaded: `launchctl print` exits 0, 113 when it doesn't.
    static func isLoaded(_ label: String, _ env: ProviderEnvironment) -> Bool {
        env.settings.launchctl(["print", "gui/\(env.userID)/\(label)"]).status == 0
    }

    // MARK: State

    /// Whether one change is in effect.
    static func applied(_ change: Change, _ r: Reading) -> Bool {
        switch change {
        case .restriction(let key):
            return r.isForced(restriction, key) && PreferenceValue.bool(false).matches(r.value(restriction, key))
        case .forced(let domain, let key, let value):
            return r.isForced(domain, key) && value.matches(r.value(domain, key))
        case .pref(let domain, let key, let value):
            return value.matches(r.value(domain, key))
        case .service(let label):
            return r.disabled.contains(label)
        case .musicLaunches:
            return musicState(r) == .on
        case .dockRemove(let ids):
            return !r.dock.contains { $0.bundleID.map(ids.contains) == true }
        case .showLibrary:
            return r.libraryHidden == false
        }
    }

    /// A setting forced by something other than Lightspot's profile can't be changed here: a
    /// profile key forced by another profile, or any forced key of a user preference, which a
    /// write of the user's own value can't beat (RemoveMacAI's `managedElsewhere`).
    static func managedElsewhere(_ change: Change, ours: Bool, _ r: Reading) -> Bool {
        switch change {
        case .restriction(let key): return !ours && r.isForced(restriction, key)
        case .forced(let domain, let key, _): return !ours && r.isForced(domain, key)
        case .pref(let domain, let key, _): return r.isForced(domain, key)
        default: return false
        }
    }

    /// Music's launch entry (RemoveMacAI's `MusicLaunch.state`): on while its current label is
    /// disabled and not loaded; partly while it is still loaded (Music took 64 s to quit here) or
    /// only an older label is disabled (after a macOS update replaced Music); else off.
    static func musicState(_ r: Reading) -> State {
        if let label = r.musicLabel, r.disabled.contains(label) { return r.loaded.contains(label) ? .partly : .on }
        return r.disabled.contains { $0.hasPrefix(musicPrefix) } ? .partly : .off
    }

    static func state(_ tweak: Tweak, _ r: Reading) -> State {
        guard tweak.isSupported(on: r.os) else { return .notOnThisMacOS }
        let ours = r.installed.on && r.installed.tweaks.contains(tweak.id)
        if tweak.changes.contains(where: { managedElsewhere($0, ours: ours, r) }) { return .managed }
        if tweak.changes == [.musicLaunches] { return musicState(r) }
        let done = tweak.changes.filter { applied($0, r) }.count
        if done == tweak.changes.count {
            // A job switched off but still loaded is only partly done until it stops.
            for case .service(let label) in tweak.changes where r.loaded.contains(label) { return .partly }
            return .on
        }
        return done == 0 ? .off : .partly
    }

    /// A tweak locked by a profile whose every key already reads that way in the user's own
    /// settings, but isn't forced: it counts as off, and its row says so. Never for restrictions
    /// (a user value there does nothing) or the domains judged by their forced value only.
    static func alreadyOffButNotLocked(_ tweak: Tweak, _ r: Reading) -> Bool {
        let forced = tweak.changes.compactMap { change -> (String, String, PreferenceValue)? in
            if case .forced(let domain, let key, let value) = change { return (domain, key, value) }
            return nil
        }
        guard !forced.isEmpty, forced.count == tweak.changes.count else { return false }
        return forced.allSatisfy { domain, key, value in
            !MacTweaksIntelligence.unreadableDomains.contains(domain) && !domain.hasPrefix("group.")
                && !r.isForced(domain, key) && value.matches(r.userValue(domain, key))
        }
    }

    /// Whether ticking an On tweak can undo anything: the Dock tweak only with the tiles Lightspot
    /// took out; the rest always (back to the value before Lightspot, or to macOS's default).
    static func canUndo(_ tweak: Tweak, _ r: Reading) -> Bool {
        for case .dockRemove(let ids) in tweak.changes {
            return r.journal.entry(Change.dockRemove(ids).key)?.tiles?.isEmpty == false
        }
        return true
    }

    // MARK: Rows

    static func rows(_ r: Reading, backgroundLines: (@Sendable ([(key: String, json: Data)]) -> [String: String])? = nil) -> [MacTweaksRow] {
        let blocked = r.journalStatus.isBlocked
        var states: [String: State] = [:]
        var tweakRows: [MacTweaksRow] = []
        for tweak in catalog {
            let state = state(tweak, r)
            states[tweak.id] = state
            tweakRows.append(row(tweak, state, r, blocked: blocked))
        }
        var rows = Preset.allCases.map { preset -> MacTweaksRow in
            let targets = tweaks(in: preset).filter { tweak in
                (states[tweak.id] == .off || states[tweak.id] == .partly)
                    && tweakRows.first { $0.id == tweak.id }.map { !$0.readOnly } == true
            }.map(\.id)
            var row = MacTweaksRow(id: preset.id, symbol: preset.symbol, title: preset.title, detail: preset.detail)
            row.group = presetsGroup
            row.ticks = targets
            row.countLabel = targets.isEmpty ? "All on" : "\(targets.count) to change"
            row.outcome = "Ticks its settings"
            row.readOnly = blocked
            return row
        }
        rows += tweakRows
        if let undo = undoEverythingRow(r, backgroundLines: backgroundLines) { rows.append(undo) }
        return rows
    }

    static func row(_ tweak: Tweak, _ state: State, _ r: Reading, blocked: Bool) -> MacTweaksRow {
        var row = MacTweaksRow(id: tweak.id, symbol: tweak.symbol, title: tweak.title, detail: tweak.detail)
        row.group = tweak.group.title
        row.countLabel = state.label
        if tweak.inProfile { row.tags = [profileTag] }
        var notes: [String] = []
        var readOnly = blocked
        var replaced: String?
        switch state {
        case .managed:
            readOnly = true
            replaced = managedCaveat
        case .notOnThisMacOS:
            readOnly = true
            replaced = "Needs macOS \(tweak.since.0)\(tweak.since.1 > 0 ? ".\(tweak.since.1)" : "") or later."
        case .on:
            row.undoes = true
            if !canUndo(tweak, r) {
                readOnly = true
                notes.append("None of these apps are in your Dock.")
            }
        case .partly:
            notes.append(partlyNote(tweak, r))
        case .off:
            if alreadyOffButNotLocked(tweak, r) { notes.append(alreadyOffCaveat) }
        }
        if tweak.changes.contains(.musicLaunches), r.musicLabel == nil, state != .notOnThisMacOS {
            readOnly = true
            notes.append("Lightspot couldn't find Music's app.")
        }
        if blocked, let reason = r.journalStatus.reason { replaced = reason }
        row.readOnly = readOnly
        row.caveat = replaced ?? (notes + [tweak.caveat].compactMap { $0 }).joined(separator: " ").nilIfEmpty
        row.items = commands(tweak, undoing: row.undoes, r).map { MacTweaksItem(target: $0) }
        row.outcome = outcome(tweak, state, r)
        return row
    }

    static func partlyNote(_ tweak: Tweak, _ r: Reading) -> String {
        if tweak.changes == [.musicLaunches] {
            if let label = r.musicLabel, r.disabled.contains(label) { return "Music is still open. Tick it to close it." }
            return "macOS updated Music, so it can open again. Tick it to stop it again."
        }
        for case .service(let label) in tweak.changes where r.disabled.contains(label) && r.loaded.contains(label) {
            return "Off from your next login: macOS didn't let Lightspot stop it now. Tick it to try again."
        }
        return "Part of it is already set. Ticking it finishes it."
    }

    /// What the plan says applying will do to the row, by its state now: the plan shows it before
    /// anything runs, so never "Applied" (the receipt's word).
    static func outcome(_ tweak: Tweak, _ state: State, _ r: Reading) -> String {
        switch state {
        case .off: return tweak.inProfile ? "Turns on, locked by Lightspot's profile" : "Turns on"
        case .partly: return "Finishes"
        case .on:
            if tweak.inProfile { return "Turns off: it comes out of Lightspot's profile" }
            if keptOffOnUndo(tweak, r) { return "Leaves it as it was: it was off before Lightspot" }
            let keys = journalKeys(tweak, r)
            let recorded = keys.filter { r.journal.json($0) != nil }
            if recorded.isEmpty { return "Undoes: back to macOS's default (Lightspot didn't make this change)" }
            return recorded.count == keys.count ? "Undoes: back to your setting from before Lightspot" : "Undoes"
        case .managed, .notOnThisMacOS: return ""
        }
    }

    /// A tweak of jobs only, each journaled as off before Lightspot: undoing it leaves them off
    /// and drops their entries, so the Mac stays as it is.
    static func keptOffOnUndo(_ tweak: Tweak, _ r: Reading) -> Bool {
        var labels: [String] = []
        for change in tweak.changes {
            switch change {
            case .service(let label): labels.append(label)
            case .musicLaunches: labels += musicLabelsToRestore(tweak, r)
            default: return false
            }
        }
        return !labels.isEmpty && labels.allSatisfy { r.journal.entry("service:" + $0)?.wasDisabled == true }
    }

    /// The journal keys a tweak's local changes use now (Music's: its current label's).
    static func journalKeys(_ tweak: Tweak, _ r: Reading) -> [String] {
        tweak.changes.compactMap { change in
            switch change {
            case .restriction, .forced: return nil
            case .musicLaunches: return r.musicLabel.map { "service:" + $0 }
            default: return change.key
            }
        }
    }

    /// The equivalent command of each change, as `defaults`, `launchctl` and `chflags` would take
    /// them; "profile: …" for what the profile sets.
    static func commands(_ tweak: Tweak, undoing: Bool, _ r: Reading) -> [String] {
        let gui = "gui/\(r.userID)"
        var lines: [String] = []
        for change in tweak.changes {
            switch change {
            case .restriction(let key):
                lines.append("profile: \(restriction) \(key) = false" + (undoing ? " removed" : ""))
            case .forced(let domain, let key, let value):
                lines.append("profile: \(domain) \(shellWord(key)) = \(value.shown)" + (undoing ? " removed" : " (locked)"))
            case .pref(let domain, let key, let value):
                if undoing {
                    if let entry = r.journal.entry(change.key) {
                        lines.append(restoreCommand(domain, key, entry.previous))
                    } else if value.matches(r.value(domain, key)) {
                        lines.append("defaults delete \(domain) \(shellWord(key))")
                    }
                } else if !value.matches(r.value(domain, key)) {
                    lines.append("defaults write \(domain) \(shellWord(key)) \(value.defaultsArguments ?? value.shown)")
                }
            case .service(let label):
                lines += undoing ? restoreCommands(label, entry: r.journal.entry("service:" + label),
                                                   plist: label == rcdLabel && r.rcdPlistExists ? rcdPlistPath : nil, gui: gui)
                                 : stopCommands(label, gui: gui)
            case .musicLaunches:
                if undoing {
                    for label in musicLabelsToRestore(tweak, r) { lines += restoreCommands(label, entry: r.journal.entry("service:" + label), plist: nil, gui: gui) }
                } else if let label = r.musicLabel {
                    lines += stopCommands(label, gui: gui)
                }
            case .dockRemove(let ids):
                if undoing {
                    let tiles = r.journal.entry(change.key)?.tiles ?? []
                    if !tiles.isEmpty { lines.append("put back in the Dock: " + tiles.map { "\($0.label) (\(ordinal($0.index + 1)))" }.joined(separator: ", ")) }
                } else {
                    let present = r.dock.filter { $0.bundleID.map(ids.contains) == true }.map(\.label)
                    if !present.isEmpty { lines.append("remove from the Dock: " + present.joined(separator: ", ")) }
                }
            case .showLibrary:
                let hidden = r.journal.entry(change.key)?.wasHidden ?? true
                lines.append(undoing ? "chflags \(hidden ? "hidden" : "nohidden") ~/Library" : "chflags nohidden ~/Library")
            }
        }
        return lines
    }

    static func restoreCommand(_ domain: String, _ key: String, _ previous: PreferenceValue?) -> String {
        guard let previous else { return "defaults delete \(domain) \(shellWord(key))" }
        if let arguments = previous.defaultsArguments { return "defaults write \(domain) \(shellWord(key)) \(arguments)" }
        return "defaults write \(domain) \(shellWord(key)) (puts back \(previous.shown))"
    }

    /// Turning a job off, one command per item so neither is cut short: Music's label is long.
    static func stopCommands(_ label: String, gui: String) -> [String] {
        ["launchctl disable \(gui)/\(label)", "launchctl bootout \(gui)/\(label)"]
    }

    /// Putting a job back: enable, then bootstrap when it has a plist (rcd), one item each; for one
    /// that was off before Lightspot, that it stays off.
    static func restoreCommands(_ label: String, entry: MacTweaksJournal.Entry?, plist: String?, gui: String) -> [String] {
        if entry?.wasDisabled == true { return ["\(label) was off before Lightspot: it stays off"] }
        return ["launchctl enable \(gui)/\(label)"] + (plist.map { ["launchctl bootstrap \(gui) \($0)"] } ?? [])
    }

    static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 10, n % 100) {
        case (_, 11...13): suffix = "th"
        case (1, _): suffix = "st"
        case (2, _): suffix = "nd"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }

    /// The Music labels an undo enables: every one this tweak recorded (RemoveMacAI's
    /// `recordedLabels`); else, as a row's undo turns the tweak off even when Lightspot recorded
    /// nothing, the current label when it is disabled; else the older labels still disabled. That
    /// last case is a row that turned Partly between the scan and the apply, after a macOS update
    /// replaced Music that another tool had stopped: those labels name a Music that is gone, so
    /// enabling them changes only launchd's list, and the row reads Off again.
    static func musicLabelsToRestore(_ tweak: Tweak, _ r: Reading) -> [String] {
        let recorded = r.journal.entries.filter { $0.key.hasPrefix("service:" + musicPrefix) && $0.entry.tweak == tweak.id }
            .compactMap(\.entry.label)
        if !recorded.isEmpty { return recorded.sorted() }
        if let label = r.musicLabel, r.disabled.contains(label) { return [label] }
        return r.disabled.filter { $0.hasPrefix(musicPrefix) }.sorted()
    }

    // MARK: Undo everything's row

    static func undoEverythingRow(_ r: Reading, backgroundLines: (@Sendable ([(key: String, json: Data)]) -> [String: String])? = nil) -> MacTweaksRow? {
        let profile = r.installed.on
        guard profile || !r.journal.isEmpty else { return nil }
        var detail = "Puts back every setting Lightspot changed on this Mac as it was"
        if profile {
            detail += ", and removes Lightspot's profile" + (r.installed.ai ? ", which turns Apple Intelligence back on" : "")
        }
        detail += ". Files in the Trash stay there."
        var row = MacTweaksRow(id: undoEverythingID, symbol: "arrow.uturn.backward.circle", title: undoEverythingTitle, detail: detail)
        row.group = undoGroup
        row.exclusive = true
        row.undoes = true
        row.items = undoEverythingLines(r, background: backgroundLines).map { MacTweaksItem(target: $0) }
        let count = r.journal.keys.count + (profile ? 1 : 0)
        row.countLabel = "\(count) \(count == 1 ? "change" : "changes")"
        row.outcome = "Puts everything back as it was before Lightspot"
        row.readOnly = r.journalStatus.isBlocked
        if case .unreadable(let reason) = r.journalStatus { row.caveat = reason }
        return row
    }

    /// One line per journal entry (a job's two commands on two) and one for the profile: what
    /// Undo everything does to each.
    static func undoEverythingLines(_ r: Reading, background: (@Sendable ([(key: String, json: Data)]) -> [String: String])? = nil) -> [String] {
        let gui = "gui/\(r.userID)"
        var lines: [String] = []
        if r.installed.on {
            // Every setting the profile locks, those this version doesn't know included.
            let locked = r.installed.tweaks.count
            var what: [String] = []
            if r.installed.ai { what.append("Apple Intelligence comes back on") }
            if locked > 0 { what.append("\(locked) locked \(locked == 1 ? "setting goes" : "settings go") back to your own") }
            lines.append("Lightspot's profile: \(MacTweaksProfile.removeCommand())" + (what.isEmpty ? "" : " (\(what.joined(separator: "; ")))"))
        }
        // Background Items' lines come all at once: its hook looks for their plists once.
        let backgroundEntries = r.journal.entries(kind: "background")
        let backgroundLines = backgroundEntries.isEmpty ? [:] : background?(backgroundEntries) ?? [:]
        for key in r.journal.keys {
            if let entry = r.journal.entry(key) {
                lines += undoLines(entry, gui: gui)
            } else if r.journal.kind(key) == "background" {
                lines.append(backgroundLines[key] ?? "\(key): kept, Background Items isn't part of this build")
            } else if isUnreadable(key, r.journal) {
                lines.append("\(key): kept, its journal entry can't be read, so Lightspot can't tell what to put back")
            } else {
                lines.append("\(key): kept, this version of Lightspot can't undo it")
            }
        }
        return lines
    }

    /// An entry of a kind this version reads that doesn't decode (damaged, or written by hand).
    static func isUnreadable(_ key: String, _ journal: MacTweaksJournal) -> Bool {
        journal.kind(key).map(MacTweaksJournal.typedKinds.contains) == true && journal.entry(key) == nil
    }

    static func undoLines(_ entry: MacTweaksJournal.Entry, gui: String) -> [String] {
        let title = tweak(entry.tweak)?.title
        func named(_ text: String) -> String { title.map { "\($0): \(text)" } ?? text }
        switch entry.kind {
        case "pref":
            let domain = entry.domain ?? "?", key = entry.key ?? "?"
            return [named(restoreCommand(domain, key, entry.previous))]
        case "service":
            return restoreCommands(entry.label ?? "?", entry: entry, plist: entry.plist, gui: gui).map(named)
        case "dock":
            let tiles = entry.tiles ?? []
            return [named("put back in the Dock: " + tiles.map { "\($0.label) (\(ordinal($0.index + 1)))" }.joined(separator: ", "))]
        case "hidden":
            return [named("chflags \(entry.wasHidden ?? true ? "hidden" : "nohidden") ~/\(entry.path ?? "Library")")]
        default:
            return [named("kept, this version of Lightspot can't undo it")]
        }
    }

    // MARK: The plan

    /// What one apply does.
    struct Plan: Sendable, Equatable {
        /// Tweaks turned on or finished, then undone, in catalog order.
        var apply: [String] = []
        var undo: [String] = []
        /// "Title: why", for ticked rows left as they are.
        var skipped: [String] = []
        /// The profile to install, or to remove when empty; nil to leave it.
        var profile: MacTweaksProfile.Contents?
        /// The tweak IDs the installed profile holds that this version doesn't know (after a
        /// downgrade): changing the profile drops them, as their keys can't be built.
        var dropped: [String] = []
        /// Finder, the Dock, SystemUIServer: each once, for the local changes.
        var restarts: [String] = []
        var undoEverything = false
    }

    /// The tweak IDs Lightspot's installed profile holds that this version doesn't know.
    static func unknownTweaks(_ installed: MacTweaksProfile.Installed) -> [String] {
        installed.on ? installed.tweaks.subtracting(profileTweakIDs(installed.tweaks)).sorted() : []
    }

    /// What a plan that changes the profile says about the IDs it drops; nil when there are none.
    static func droppedNote(_ ids: [String]) -> String? {
        guard !ids.isEmpty else { return nil }
        let one = ids.count == 1
        return "Lightspot's profile also locks \(one ? "a setting" : "\(ids.count) settings") this version doesn't know "
            + "(\(ids.joined(separator: ", "))). This version can't keep \(one ? "it" : "them") in the profile, so \(one ? "it goes" : "they go") back to your own."
    }

    /// Apple Intelligence exactly as Lightspot's profile has it in force, so a Settings change
    /// keeps it: nil when the profile doesn't turn it off; for a profile made on an older macOS,
    /// the features it didn't know stay on (kept), as they are now.
    static func aiInForce(_ installed: MacTweaksProfile.Installed, os: (Int, Int)) -> Set<String>? {
        guard installed.on && installed.ai else { return nil }
        guard let features = installed.features else { return installed.kept }
        let added = Set(Catalog.availableFeatures(os: os).map(\.id)).subtracting(features)
        return installed.kept.union(added)
    }

    /// The plan for the ticked rows, against a reading. Pure: the plan view builds it from the
    /// scan, the apply from a fresh reading. A row ticked to undo is undone only while it is still
    /// on, one ticked to turn on only while it isn't; a managed or unsupported one never changes.
    static func plan(_ ticked: [MacTweaksRow], _ r: Reading) -> Plan {
        var plan = Plan()
        if ticked.contains(where: { $0.id == undoEverythingID }) {
            plan.undoEverything = true
            return plan
        }
        let ids = Set(ticked.map(\.id))
        let undoIDs = Set(ticked.filter(\.undoes).map(\.id))
        for tweak in catalog where ids.contains(tweak.id) {
            let state = state(tweak, r)
            switch state {
            case .managed: plan.skipped.append("\(tweak.title): another configuration profile sets it now.")
            case .notOnThisMacOS: plan.skipped.append("\(tweak.title): not on this version of macOS.")
            case .on, .off, .partly:
                if undoIDs.contains(tweak.id) {
                    if state == .off {
                        plan.skipped.append("\(tweak.title): already off.")
                    } else if state == .on && !canUndo(tweak, r) {
                        plan.skipped.append("\(tweak.title): nothing Lightspot can put back.")
                    } else {
                        plan.undo.append(tweak.id)
                    }
                } else if state == .on {
                    plan.skipped.append("\(tweak.title): already on.")
                } else {
                    plan.apply.append(tweak.id)
                }
            }
        }
        let held = heldTweaks(r.installed)
        let applying = profileTweakIDs(Set(plan.apply))
        for id in applying.intersection(held) {
            plan.apply.removeAll { $0 == id }
            plan.skipped.append("\(tweak(id)?.title ?? id): already in Lightspot's profile.")
        }
        let target = held.union(applying).subtracting(profileTweakIDs(Set(plan.undo)))
        if target != held {
            plan.profile = MacTweaksProfile.Contents(ai: aiInForce(r.installed, os: r.os), tweaks: target)
            plan.dropped = unknownTweaks(r.installed)
        }
        let local = Set((plan.apply + plan.undo).compactMap { tweak($0) }.filter { !$0.inProfile }.flatMap(\.restart))
        plan.restarts = restartOrder.filter(local.contains)
        return plan
    }

    // MARK: The summary, the plan's notes and its button

    static func summary(rows: [MacTweaksRow], ticked: [MacTweaksRow], context: Reading?) -> String {
        let tweakRows = rows.filter { tweak($0.id) != nil }
        let shown = tweakRows.filter { $0.countLabel != State.notOnThisMacOS.label }
        let on = shown.filter { $0.countLabel == State.on.label }.count
        let partly = shown.filter { $0.countLabel == State.partly.label }.count
        var parts = ["\(on) of \(shown.count) on"]
        if partly > 0 { parts.append("\(partly) partly") }
        if ticked.contains(where: { $0.id == undoEverythingID }) {
            parts.append("Undo everything ticked")
        } else if !ticked.isEmpty {
            parts.append("\(ticked.count) to change")
        }
        var text = parts.joined(separator: " · ") + "."
        if let reason = context?.journalStatus.reason { text += " " + reason }
        return text
    }

    static func applyTitle(ticked rows: [MacTweaksRow]) -> String {
        if rows.contains(where: { $0.id == undoEverythingID }) { return "Undo everything" }
        let n = rows.count
        return "Apply \(n) \(n == 1 ? "change" : "changes")"
    }

    /// "Finder", "Finder and the Dock", "Finder, the Dock and SystemUIServer".
    static func spokenList(_ names: [String]) -> String {
        let shown = names.map { $0 == "Dock" ? "the Dock" : $0 }
        guard let last = shown.last else { return "" }
        return shown.count == 1 ? last : shown.dropLast().joined(separator: ", ") + " and " + last
    }

    static func restartSentence(_ names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        let list = spokenList(names)
        var text = "\(list.prefix(1).uppercased() + list.dropFirst()) \(names.count == 1 ? "restarts" : "restart once each") ("
            + names.map { "killall \($0)" }.joined(separator: "; ") + ")."
        if names.contains("Finder") { text += " Finder's windows come back." }
        return text
    }

    /// What `launchctl enable` leaves behind, said wherever Lightspot runs it (a job's undo, Undo
    /// everything, Background Items' turn-on): launchd keeps the job's override as "enabled", where
    /// there may have been none, and no launchctl verb removes an override; only root can, in
    /// launchd's own database. Said, not changed: the job runs as asked.
    static let enabledRecordPlanNote = "Turning a job back on runs launchctl enable, and launchd keeps an \"enabled\" record for it "
        + "from then on (launchctl print-disabled lists it). Only an administrator can remove that record."
    static let enabledRecordReceiptNote = "launchd keeps an \"enabled\" record for each job Lightspot turned back on "
        + "(launchctl print-disabled lists it). Only an administrator can remove that record."

    /// Whether undoing the tweak runs `launchctl enable`: it has a job, and not every one of them
    /// was off before Lightspot.
    static func undoRunsEnable(_ tweak: Tweak, _ r: Reading) -> Bool {
        tweak.changes.contains { if case .service = $0 { return true }; return $0 == .musicLaunches } && !keptOffOnUndo(tweak, r)
    }

    /// The plan's closing sentences, from the scan on show. Reads nothing (invariant 0).
    static func planNotes(ticked: [MacTweaksRow], context: Reading?) -> [String] {
        guard let r = context else { return [] }
        let plan = plan(ticked, r)
        if plan.undoEverything { return undoEverythingNotes(r) }
        var notes: [String] = []
        if let restart = restartSentence(plan.restarts) { notes.append(restart) }
        let local = (plan.apply + plan.undo).compactMap { tweak($0) }.filter { !$0.inProfile }
        if local.contains(where: { $0.changes.contains { if case .pref(global, _, _) = $0 { return true }; return false } }) {
            notes.append(reopenNote)
        }
        if plan.undo.compactMap({ tweak($0) }).contains(where: { undoRunsEnable($0, r) }) { notes.append(enabledRecordPlanNote) }
        if plan.apply.contains("music-launches") { notes.append("Music quits if it's open.") }
        if plan.apply.contains("media-keys") {
            notes.append("The play, pause and skip keys may keep working until you log out: macOS may not let Lightspot stop their service now.")
        }
        if let profile = plan.profile {
            if profile.isEmpty {
                notes.append("Lightspot asks for your administrator password to remove its profile.")
            } else {
                notes.append("System Settings asks you to approve one profile." + (r.installed.on && r.installed.ai ? " Apple Intelligence stays as it is." : ""))
            }
            if let dropped = droppedNote(plan.dropped) { notes.append(dropped) }
            notes.append(sharedProfileNote)
        }
        if !plan.skipped.isEmpty { notes.append("Left as it is: " + plan.skipped.joined(separator: " ")) }
        if case .unreadable = r.journalStatus { notes.append("Lightspot's undo journal can't be read: applying keeps it aside.") }
        // Only what is turned on can be undone later.
        if !plan.apply.isEmpty { notes.append(undoLaterNote) }
        return notes
    }

    static func undoEverythingNotes(_ r: Reading) -> [String] {
        var notes: [String] = []
        let entries = r.journal.entries
        if !entries.isEmpty {
            notes.append("Puts back \(entries.count) \(entries.count == 1 ? "setting" : "settings") as \(entries.count == 1 ? "it was" : "they were") before Lightspot changed \(entries.count == 1 ? "it" : "them").")
        }
        let backgroundPairs = r.journal.entries(kind: "background")
        let background = backgroundPairs.map(\.key)
        if !background.isEmpty {
            notes.append("Puts back \(background.count) background \(background.count == 1 ? "item" : "items") Lightspot turned off or deleted.")
        }
        let restarts = restartOrder.filter { name in entries.contains { $0.entry.restart?.contains(name) == true } }
        if let restart = restartSentence(restarts) { notes.append(restart) }
        // Daemons go back on, and root's deleted plists back in place, in the administrator batch,
        // with the profile's removal or alone.
        let daemons = MacTweaksBackground.undoNeedsAdministrator(backgroundPairs, home: r.home)
        if r.installed.on {
            notes.append(daemons ? "Lightspot asks for your administrator password to remove its profile and turn background items "
                                   + "for every account back on."
                                 : "Lightspot asks for your administrator password to remove its profile.")
            if r.installed.ai {
                notes.append("Apple Intelligence comes back on, and macOS downloads its models again when you next turn a feature on.")
            }
            notes.append(sharedProfileNote)
        } else if daemons {
            notes.append(MacTweaksStorage.passwordNote)
        }
        if daemons { notes.append(backgroundForEveryoneNote) }
        if !background.isEmpty || entries.contains(where: { $0.entry.kind == "service" && $0.entry.wasDisabled != true }) {
            notes.append(enabledRecordPlanNote)
        }
        if case .unreadable = r.journalStatus { notes.append("Lightspot's undo journal can't be read: applying keeps it aside, so only the profile can be undone.") }
        notes.append(trashNote)
        if r.dockBackupExists { notes.append("Restore Dock Icons puts back what Clear Dock Icons removed.") }
        return notes
    }

    // MARK: Applying

    typealias ApplyResult = (receipt: MacTweaksReceipt, rescanned: [MacTweaksRow], context: Reading?)

    /// Changes the ticked rows: local changes first, each journaled before it is made, then the
    /// restarts they need, then the profile when a profile-backed tweak changed. Or, for the Undo
    /// everything row, puts back everything the journal holds and removes the profile. Blocking:
    /// the provider runs it on its queue.
    static func apply(_ rows: [MacTweaksRow], env: ProviderEnvironment,
                      progress: (@Sendable (String) -> Void)? = nil) -> ApplyResult {
        let started = env.now()
        let settings = env.settings
        let url = journalURL(env)
        let access = MacTweaksJournal.loadForWriting(url: url, now: started, home: env.home, fileSystem: settings.fileSystem)
        guard var journal = access.journal else {
            return finish(MacTweaksReceipt(headline: "Nothing changed.", problems: [access.blockedReason ?? ""], isSuccess: false),
                          env: env, started: started, log: ["journal blocked: nothing changed"])
        }
        var work = Work()
        if let aside = access.movedAside {
            work.notes.append("Lightspot couldn't read its undo journal, so it kept it as \(aside). Undo can't put back what that file recorded.")
            work.log.append("unreadable journal kept as \(aside)")
        }
        if rows.contains(where: { $0.id == undoEverythingID }) {
            return undoEverything(env: env, journal: &journal, work: work, started: started, progress: progress)
        }
        let r = read(env, journal: journal)
        let plan = plan(rows, r)
        work.notes += plan.skipped
        work.log += plan.skipped.map { "left: " + $0 }

        let undoing = plan.undo.compactMap { tweak($0) }.filter { !$0.inProfile }
        let applying = plan.apply.compactMap { tweak($0) }.filter { !$0.inProfile }
        if (undoing + applying).contains(where: { $0.restart.contains("Dock") }) { waitForDock(env, progress: progress) }
        if !undoing.isEmpty { progress?("Undoing \(undoing.count) \(undoing.count == 1 ? "setting" : "settings")…") }
        var changedLocal: [Tweak] = []
        for tweak in undoing where revert(tweak, r, journal: &journal, env: env, work: &work) { changedLocal.append(tweak) }
        if !applying.isEmpty { progress?("Changing \(applying.count) \(applying.count == 1 ? "setting" : "settings")…") }
        for tweak in applying where turnOn(tweak, r, journal: &journal, env: env, work: &work) { changedLocal.append(tweak) }

        let restarts = restartOrder.filter { name in changedLocal.contains { $0.restart.contains(name) } }
        if !restarts.isEmpty {
            progress?("Restarting \(spokenList(restarts))…")
            for name in restarts {
                if name == "Dock" {
                    for check in restartDock(env, checks: work.dockChecks, work: &work) {
                        rollBack(check, journal: &journal, env: env, work: &work)
                        if let id = check.tweak {
                            work.failed.insert(id)
                            work.applied.removeAll { $0 == check.title }
                            work.finished.removeAll { $0 == check.title }
                            work.undone.removeAll { $0 == check.title }
                        }
                    }
                } else {
                    _ = settings.restart(name)
                    work.log.append("killall \(name)")
                }
            }
            work.lines.append("Restarted \(spokenList(restarts)).")
        }

        var profileDone = true
        var profileWaiting = false
        if let target = plan.profile {
            let change = MacTweaksProfile.change(to: target, env: env, progress: progress, log: &work.log)
            switch change {
            case .alreadyMatches: break
            case .installed:
                let added = profileTweaks(target.tweaks.subtracting(heldTweaks(r.installed))).map(\.title)
                let removed = profileTweaks(heldTweaks(r.installed).subtracting(target.tweaks)).map(\.title) + plan.dropped
                if !added.isEmpty { work.lines.append("Locked by Lightspot's profile: \(added.joined(separator: ", ")).") }
                if !removed.isEmpty { work.lines.append("Taken out of Lightspot's profile: \(removed.joined(separator: ", ")).") }
            case .removed:
                work.lines.append("Lightspot's profile is removed: these settings are your own again.")
            case .notApproved:
                profileDone = false
                profileWaiting = true
                work.notes.append("The profile isn't installed yet. Approve it in System Settings › General › Device Management, then open Mac Tweaks again.")
            case .notRemoved:
                profileDone = false
                profileWaiting = true
                work.notes.append(MacTweaksIntelligence.removalInstruction + " Then open Mac Tweaks again.")
            case .promptCancelled:
                profileDone = false
                work.problems.append("The administrator prompt was cancelled, so Lightspot's profile stays installed.")
            case .promptRefused:
                profileDone = false
                work.problems.append("macOS didn't accept the administrator password, so Lightspot's profile stays installed.")
            case .writeFailed(let message):
                profileDone = false
                work.problems.append("Lightspot couldn't write the profile: \(message)")
            }
        }

        // Verify by reading the Mac again.
        progress?("Checking the settings again…")
        let after = read(env)
        let uncounted = work.failed.union(work.leftAsItWas)
        for id in plan.apply + plan.undo {
            guard let tweak = tweak(id), !uncounted.contains(id) else { continue }
            if tweak.inProfile && !profileDone { continue }
            let now = state(tweak, after)
            let undoing = plan.undo.contains(id)
            // An undo may leave it Partly (an older Music label, a key the owner set); a job off from
            // the next login reads Partly until then.
            if now != (undoing ? State.off : State.on) && !(now == .partly && (undoing || work.nextLogin.contains(id))) {
                work.problems.append("\(tweak.title): still \(now.label.lowercased()).")
            }
        }
        let changed = plan.apply.filter { !uncounted.contains($0) && (tweak($0).map { !$0.inProfile || profileDone } ?? false) }.count
        let undone = plan.undo.filter { !uncounted.contains($0) && (tweak($0).map { !$0.inProfile || profileDone } ?? false) }.count
        var headline: String
        switch (changed, undone) {
        case (0, 0): headline = "Nothing changed."
        case (_, 0): headline = "Changed \(changed) \(changed == 1 ? "setting" : "settings")."
        case (0, _): headline = "Undid \(undone) \(undone == 1 ? "setting" : "settings")."
        default: headline = "Changed \(changed) \(changed == 1 ? "setting" : "settings") and undid \(undone)."
        }
        if profileWaiting { headline += " The profile is waiting for you." }
        if changedLocal.contains(where: { $0.changes.contains { if case .pref(global, _, _) = $0 { return true }; return false } }) {
            work.notes.append(reopenNote)
        }
        if work.enabledJobs { work.notes.append(enabledRecordReceiptNote) }
        // Only what was turned on can be undone later; an undo has nothing left to undo.
        if changed > 0 { work.notes.append(undoLaterNote) }
        let receipt = MacTweaksReceipt(headline: headline, lines: work.receiptLines, problems: work.problems, notes: work.notes,
                                       isSuccess: work.problems.isEmpty && profileDone && (changed + undone > 0 || plan.skipped.isEmpty))
        return finish(receipt, env: env, started: started, log: work.log, reading: after)
    }

    /// What an apply did so far.
    struct Work: Sendable {
        /// Titles by what happened to them: the receipt has one wrapped line per kind.
        var applied: [String] = []
        var finished: [String] = []
        var undone: [String] = []
        /// What a title alone can't say: a job off from the next login, one left as it was, the
        /// restarts, the profile.
        var lines: [String] = []
        var problems: [String] = []
        var notes: [String] = []
        var log: [String] = []
        /// Tweaks that failed, so the verify pass doesn't report them twice.
        var failed: Set<String> = []
        /// Tweaks whose job is off but still running until the next login: they read Partly.
        var nextLogin: Set<String> = []
        /// Tweaks an undo left as they were (their jobs were off before Lightspot).
        var leftAsItWas: Set<String> = []
        /// The Dock tiles this apply changed, checked in the Dock its restart brings up.
        var dockChecks: [DockCheck] = []
        /// `launchctl enable` ran: the receipt says launchd keeps an "enabled" record.
        var enabledJobs = false

        /// The receipt's lines: one per kind of change, then the rest.
        var receiptLines: [String] {
            var grouped: [String] = []
            if !applied.isEmpty { grouped.append("Applied: " + applied.joined(separator: ", ") + ".") }
            if !finished.isEmpty { grouped.append("Finished: " + finished.joined(separator: ", ") + ".") }
            if !undone.isEmpty { grouped.append("Undone: " + undone.joined(separator: ", ") + ".") }
            return grouped + lines
        }
    }

    /// Saves the journal before the change it records. False (and the tweak skipped) when it
    /// can't be saved: nothing of the tweak changes then.
    private static func saveAhead(_ journal: MacTweaksJournal, _ tweak: Tweak, env: ProviderEnvironment, work: inout Work) -> Bool {
        do {
            try journal.saveAhead(url: journalURL(env), fileSystem: env.settings.fileSystem)
            return true
        } catch {
            work.problems.append("\(tweak.title): Lightspot couldn't save its undo journal (\(error.localizedDescription)), so it changed nothing.")
            work.failed.insert(tweak.id)
            return false
        }
    }

    /// Turns a local tweak on, or finishes it: every change journaled first. True when something
    /// changed (its restarts are due).
    @discardableResult
    static func turnOn(_ tweak: Tweak, _ r: Reading, journal: inout MacTweaksJournal, env: ProviderEnvironment, work: inout Work) -> Bool {
        let settings = env.settings
        let store = settings.preferences
        let date = env.now()
        var problems: [String] = []
        var changed = false
        // A job macOS wouldn't stop now: what the receipt says instead of "Applied".
        var later: String?
        for change in tweak.changes {
            switch change {
            case .restriction, .forced:
                continue
            case .pref(let domain, let key, let value):
                guard !value.matches(r.value(domain, key)) else { continue }
                let previous = r.userValue(domain, key)
                let added = journal.recordIfAbsent(change.key, .pref(tweak: tweak.id, date: date, domain: domain, key: key,
                                                                      previous: previous, restart: tweak.restart))
                guard saveAhead(journal, tweak, env: env, work: &work) else {
                    if added { journal.remove(change.key) }
                    return changed
                }
                _ = store.write(domain, key, value)
                store.synchronize(domain)
                if value.matches(store.read(domain, key)) {
                    changed = true
                    work.log.append("defaults write \(domain) \(shellWord(key)) \(value.defaultsArguments ?? value.shown)")
                } else {
                    problems.append("\(domain) \(key) didn't change.")
                    if added && store.userValue(domain, key) == previous {
                        journal.remove(change.key)
                        _ = try? journal.saveAhead(url: journalURL(env), fileSystem: settings.fileSystem)
                    }
                }
            case .showLibrary:
                guard r.libraryHidden != false else { continue }
                let added = journal.recordIfAbsent(change.key, .hidden(tweak: tweak.id, date: date, path: "Library", wasHidden: r.libraryHidden ?? true))
                guard saveAhead(journal, tweak, env: env, work: &work) else {
                    if added { journal.remove(change.key) }
                    return changed
                }
                let path = libraryPath(env)
                if settings.setHidden(path, false) && settings.isHidden(path) == false {
                    changed = true
                    work.log.append("chflags nohidden ~/Library")
                } else {
                    problems.append("macOS didn't let Lightspot show ~/Library.")
                    // Only the entry this apply made, and only while the folder is still hidden.
                    if added && settings.isHidden(path) == true {
                        journal.remove(change.key)
                        _ = try? journal.saveAhead(url: journalURL(env), fileSystem: settings.fileSystem)
                    }
                }
            case .dockRemove(let ids):
                // The entry as it was, put back when the tiles can't be saved or the Dock refuses.
                let before = journal.json(change.key)
                var taking: [MacTweaksJournal.Tile] = []
                let outcome = MacTweaksDock.removeApps(Set(ids), store: store) { removed in
                    taking = removed
                    let earlier = journal.entry(change.key)
                    journal.replace(change.key, .dock(tweak: tweak.id, date: earlier?.date ?? date,
                                                      tiles: MacTweaksDock.adding(removed, to: earlier?.tiles ?? []), restart: tweak.restart))
                    guard saveAhead(journal, tweak, env: env, work: &work) else {
                        journal.reset(change.key, to: before)
                        return false
                    }
                    return true
                }
                switch outcome {
                case .removed(let names):
                    changed = true
                    work.log.append("removed from the Dock: \(names.joined(separator: ", "))")
                    work.dockChecks.append(DockCheck(kind: .removed(Set(taking.compactMap(MacTweaksDock.appID))), key: change.key,
                                                     before: before, tweak: tweak.id, title: tweak.title))
                case .nothingToDo: break
                case .notSaved: return changed
                case .failed:
                    problems.append("The Dock didn't take the change.")
                    // Back as it was while every app it meant to take out is still in the Dock.
                    store.synchronize(MacTweaksDock.domain)
                    let present = Set(MacTweaksDock.tiles(store.read(MacTweaksDock.domain, MacTweaksDock.key)).compactMap(MacTweaksDock.bundleID))
                    if taking.allSatisfy({ MacTweaksDock.appID($0).map(present.contains) ?? true }) {
                        journal.reset(change.key, to: before)
                        _ = try? journal.saveAhead(url: journalURL(env), fileSystem: settings.fileSystem)
                    }
                }
            case .service(let label):
                if turnOff(label, tweak: tweak, r: r, journal: &journal, env: env, work: &work, problems: &problems, later: &later) { changed = true }
                if work.failed.contains(tweak.id) { return changed }
            case .musicLaunches:
                guard let label = musicLabel(env) else {
                    problems.append("Lightspot couldn't find Music's app, so it changed nothing.")
                    continue
                }
                if turnOff(label, tweak: tweak, r: r, journal: &journal, env: env, work: &work, problems: &problems, later: &later) { changed = true }
                if work.failed.contains(tweak.id) { return changed }
            }
        }
        if !problems.isEmpty {
            work.problems += problems.map { "\(tweak.title): \($0)" }
            work.failed.insert(tweak.id)
        } else if changed {
            if let later {
                work.lines.append("\(tweak.title): \(later)")
                work.nextLogin.insert(tweak.id)
            } else if state(tweak, r) == .partly {
                work.finished.append(tweak.title)
            } else {
                work.applied.append(tweak.title)
            }
        }
        return changed
    }

    /// `launchctl disable`, then `bootout` while it is loaded, journaled first. True when the job
    /// is now disabled. A bootout macOS refuses isn't a failure: the job is off, still running
    /// until the next login (Music: until it quits), and `later` says so; the row reads Partly
    /// until then.
    private static func turnOff(_ label: String, tweak: Tweak, r: Reading, journal: inout MacTweaksJournal, env: ProviderEnvironment,
                                work: inout Work, problems: inout [String], later: inout String?) -> Bool {
        let launchctl = env.settings.launchctl
        let target = "gui/\(env.userID)/\(label)"
        let wasDisabled = r.disabled.contains(label)
        let plist = label == rcdLabel && r.rcdPlistExists ? rcdPlistPath : nil
        let added = journal.recordIfAbsent("service:" + label, .service(tweak: tweak.id, date: env.now(), label: label,
                                                                        wasDisabled: wasDisabled, plist: plist))
        guard saveAhead(journal, tweak, env: env, work: &work) else {
            if added { journal.remove("service:" + label) }
            return false
        }
        let disable = launchctl(["disable", target])
        guard disable.status == 0 else {
            problems.append("launchctl couldn't switch it off (\(firstLine(disable.output))).")
            if added && !wasDisabled {
                journal.remove("service:" + label)
                _ = try? journal.saveAhead(url: journalURL(env), fileSystem: env.settings.fileSystem)
            }
            return false
        }
        work.log.append("launchctl disable \(target)")
        if launchctl(["print", target]).status == 0 {
            let bootout = launchctl(["bootout", target])
            work.log.append("launchctl bootout \(target): status \(bootout.status)")
            if bootout.status != 0 {
                let why = firstLine(bootout.output)
                later = label.hasPrefix(musicPrefix)
                    ? "Music can't open again once you quit it. macOS didn't let Lightspot close it now (\(why))."
                    : "off from your next login. macOS didn't let Lightspot stop it now (\(why))."
            }
        }
        return true
    }

    static func firstLine(_ text: String) -> String {
        let line = text.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return line.isEmpty ? "no message" : line
    }

    /// Undoes a local tweak: what the journal recorded goes back; a key it has no entry for that
    /// still reads the tweak's way goes back to macOS's default (RemoveMacAI's revert). True when
    /// something changed.
    @discardableResult
    static func revert(_ tweak: Tweak, _ r: Reading, journal: inout MacTweaksJournal, env: ProviderEnvironment, work: inout Work) -> Bool {
        let settings = env.settings
        let store = settings.preferences
        var problems: [String] = []
        var changed = false
        var jobs: [JobRestore] = []
        for change in tweak.changes {
            switch change {
            case .restriction, .forced:
                continue
            case .pref(let domain, let key, let value):
                let entry = journal.entry(change.key)
                guard entry != nil || value.matches(r.value(domain, key)) else { continue }
                let target = entry?.previous
                if restorePref(domain, key, to: target, store: store) {
                    changed = true
                    work.log.append(restoreCommand(domain, key, target))
                    if entry != nil { journal.remove(change.key) }
                } else {
                    problems.append("\(domain) \(key) didn't go back.")
                }
            case .showLibrary:
                let entry = journal.entry(change.key)
                let hidden = entry?.wasHidden ?? true
                let path = libraryPath(env)
                if settings.setHidden(path, hidden) && settings.isHidden(path) == hidden {
                    changed = true
                    work.log.append("chflags \(hidden ? "hidden" : "nohidden") ~/Library")
                    if entry != nil { journal.remove(change.key) }
                } else {
                    problems.append("macOS didn't let Lightspot change ~/Library back.")
                }
            case .dockRemove:
                guard let entry = journal.entry(change.key), let tiles = entry.tiles, !tiles.isEmpty else { continue }
                let before = journal.json(change.key)
                if MacTweaksDock.putBack(tiles, store: store) {
                    changed = true
                    journal.remove(change.key)
                    work.dockChecks.append(DockCheck(kind: .putBack(tiles), key: change.key, before: before, tweak: tweak.id, title: tweak.title))
                    work.log.append("put back in the Dock: \(tiles.map(\.label).joined(separator: ", "))")
                } else {
                    problems.append("The Dock didn't take its icons back.")
                }
            case .service(let label):
                jobs.append(restoreService(label, entry: journal.entry("service:" + label), journal: &journal, env: env, work: &work, problems: &problems))
            case .musicLaunches:
                for label in musicLabelsToRestore(tweak, r) {
                    jobs.append(restoreService(label, entry: journal.entry("service:" + label), journal: &journal, env: env, work: &work, problems: &problems))
                }
            }
        }
        var nextLogin: String?
        for job in jobs {
            switch job {
            case .enabled: changed = true
            case .fromNextLogin(let why): changed = true; nextLogin = why
            case .keptOff, .failed: break
            }
        }
        do { try journal.saveAhead(url: journalURL(env), fileSystem: settings.fileSystem) } catch {
            problems.append("Lightspot couldn't save its undo journal (\(error.localizedDescription)); undoing again is safe.")
        }
        if !problems.isEmpty {
            work.problems += problems.map { "\(tweak.title): \($0)" }
            work.failed.insert(tweak.id)
        } else if changed {
            if let why = nextLogin {
                work.lines.append("\(tweak.title): undone, back from your next login. macOS didn't let Lightspot start it again now (\(why)).")
            } else {
                work.undone.append(tweak.title)
            }
        } else if !jobs.isEmpty && jobs.allSatisfy({ $0 == .keptOff }) {
            // Its jobs were off before Lightspot: undo leaves them so, and the check expects that.
            work.leftAsItWas.insert(tweak.id)
            work.lines.append("\(tweak.title): left as it was, since it was off before Lightspot. Tick it again to undo it anyway.")
        }
        return changed
    }

    /// Writes a preference back (nil deletes it) and checks the user's own value now reads so.
    static func restorePref(_ domain: String, _ key: String, to value: PreferenceValue?, store: PreferenceStore) -> Bool {
        _ = store.write(domain, key, value)
        store.synchronize(domain)
        let now = store.userValue(domain, key)
        guard let value else { return now == nil }
        return now.map(value.isSameValue) ?? false
    }

    /// What putting one job back did.
    enum JobRestore: Sendable, Equatable {
        case enabled
        /// Enabled, but macOS didn't let Lightspot start it now: it runs again from the next login.
        case fromNextLogin(String)
        /// It was off before Lightspot: left off, its entry gone.
        case keptOff
        case failed
    }

    /// Enables a job Lightspot disabled, and bootstraps its plist again when it has one and isn't
    /// loaded (rcd). A job that was off before Lightspot stays off. Its entry goes once the job is
    /// enabled, so a failed enable keeps it and undoing again retries (RemoveMacAI's
    /// `restoreService`); a bootstrap macOS refuses only delays it to the next login.
    private static func restoreService(_ label: String, entry: MacTweaksJournal.Entry?, journal: inout MacTweaksJournal, env: ProviderEnvironment,
                                       work: inout Work, problems: inout [String]) -> JobRestore {
        let key = "service:" + label
        if entry?.wasDisabled == true {
            journal.remove(key)
            work.log.append("\(label) was off before Lightspot: left off")
            return .keptOff
        }
        let launchctl = env.settings.launchctl
        let target = "gui/\(env.userID)/\(label)"
        let enable = launchctl(["enable", target])
        guard enable.status == 0 else {
            problems.append("launchctl couldn't switch \(label) back on (\(firstLine(enable.output))).")
            return .failed
        }
        work.log.append("launchctl enable \(target)")
        work.enabledJobs = true
        journal.remove(key)
        let plist = entry?.plist ?? (label == rcdLabel ? rcdPlistPath : nil)
        if let plist, env.settings.fileSystem.exists(URL(fileURLWithPath: label == rcdLabel ? rcdPlist(env) : plist)),
           launchctl(["print", target]).status != 0 {
            let bootstrap = launchctl(["bootstrap", "gui/\(env.userID)", plist])
            work.log.append("launchctl bootstrap gui/\(env.userID) \(plist): status \(bootstrap.status)")
            if bootstrap.status != 0 { return .fromNextLogin(firstLine(bootstrap.output)) }
        }
        return .enabled
    }

    // MARK: The Dock's restart

    /// A Dock tile change this apply made, checked in the Dock its restart brings up.
    struct DockCheck: Sendable {
        enum Kind: Sendable {
            /// These apps were taken out.
            case removed(Set<String>)
            /// These tiles were put back.
            case putBack([MacTweaksJournal.Tile])
        }
        let kind: Kind
        /// The journal key, and its entry before this apply changed it: what a rollback restores.
        let key: String
        let before: Data?
        /// The tweak whose row made it; nil for Undo everything.
        let tweak: String?
        let title: String

        /// The Dock shows the change now.
        func holds(_ store: PreferenceStore) -> Bool {
            let present = MacTweaksDock.appIDs(store)
            switch kind {
            case .removed(let ids): return present.isDisjoint(with: ids)
            case .putBack(let tiles): return tiles.allSatisfy { MacTweaksDock.appID($0).map(present.contains) ?? true }
            }
        }

        /// Makes it again, nothing journaled: the first try's entry stands.
        func redo(_ store: PreferenceStore) {
            switch kind {
            case .removed(let ids): _ = MacTweaksDock.removeAgain(ids, store: store)
            case .putBack(let tiles): _ = MacTweaksDock.putBack(tiles, store: store)
            }
        }
    }

    /// The Dock's restarts as `MacTweaksDock` checks its own: through `restart`, seen through
    /// `runningDock`.
    static func dockRestarter(_ env: ProviderEnvironment) -> MacTweaksDock.Restarter {
        let settings = env.settings
        return MacTweaksDock.Restarter(restart: { _ = settings.restart("Dock") }, running: settings.runningDock,
                                       now: env.now, pause: settings.pause)
    }

    /// Before a change the Dock reads: a Dock that just restarted (a Clear Dock Icons a moment
    /// ago) settles first, since one killed while it starts writes its icons over the change.
    static func waitForDock(_ env: ProviderEnvironment, progress: (@Sendable (String) -> Void)?) {
        let restarter = dockRestarter(env)
        if let dock = restarter.running?(), restarter.now().timeIntervalSince(dock.started) < MacTweaksDock.settleAge {
            progress?("Waiting for the Dock to finish starting…")
        }
        _ = MacTweaksDock.waitForDock(env.settings.preferences, restarter, age: MacTweaksDock.settleAge)
    }

    /// Restarts the Dock and waits for the one that comes up, so the check after it reads what
    /// that Dock shows, then checks there the tiles this apply changed: made again and the Dock
    /// restarted once more when the restart lost them. Returns the changes still lost after that.
    static func restartDock(_ env: ProviderEnvironment, checks: [DockCheck], work: inout Work) -> [DockCheck] {
        let store = env.settings.preferences
        let restarter = dockRestarter(env)
        func restartAndWait() {
            let old = restarter.running?()?.pid
            restarter.restart()
            work.log.append("killall Dock")
            if !MacTweaksDock.waitForDock(store, restarter, age: MacTweaksDock.checkAge, notPID: old) {
                work.log.append("the Dock didn't come up within \(Int(MacTweaksDock.upTimeout)) s")
            }
        }
        restartAndWait()
        var lost = checks.filter { !$0.holds(store) }
        guard !lost.isEmpty else { return [] }
        work.log.append("the Dock restarted without the change to " + lost.map(\.title).joined(separator: ", ") + ": once more")
        _ = MacTweaksDock.waitForDock(store, restarter, age: MacTweaksDock.settleAge)
        for check in lost { check.redo(store) }
        restartAndWait()
        lost = checks.filter { !$0.holds(store) }
        return lost
    }

    /// A Dock change its restart lost twice: the journal goes back to what the Dock shows (a
    /// removal's entry as it was while every app is back; a put-back's entry kept, so undoing
    /// again retries), and the receipt says so.
    static func rollBack(_ check: DockCheck, journal: inout MacTweaksJournal, env: ProviderEnvironment, work: inout Work) {
        switch check.kind {
        case .removed(let ids):
            if ids.isSubset(of: MacTweaksDock.appIDs(env.settings.preferences)) { journal.reset(check.key, to: check.before) }
            work.problems.append("\(check.title): the Dock restarted with these icons still in it, twice.")
        case .putBack:
            journal.reset(check.key, to: check.before)
            work.problems.append("\(check.title): the Dock restarted without the icons put back, twice. Lightspot keeps their record, so undoing again retries.")
        }
        work.log.append("\(check.key): the Dock lost the change twice; journal entry as the Dock is")
        do { try journal.saveAhead(url: journalURL(env), fileSystem: env.settings.fileSystem) } catch {
            work.problems.append("Lightspot couldn't save its undo journal (\(error.localizedDescription)).")
        }
    }

    // MARK: Undo everything

    private static func undoEverything(env: ProviderEnvironment, journal: inout MacTweaksJournal, work: Work, started: Date,
                                       progress: (@Sendable (String) -> Void)?) -> ApplyResult {
        var work = work
        let settings = env.settings
        let store = settings.preferences
        let r = read(env, journal: journal)
        let url = journalURL(env)
        if journal.entries.contains(where: { $0.entry.restart?.contains("Dock") == true }) { waitForDock(env, progress: progress) }
        progress?("Undoing what Lightspot changed…")
        var undone = 0, kept = 0
        var restarts = Set<String>()
        // Settings, the Library folder and the Dock first, then the jobs.
        let order = ["pref": 0, "hidden": 1, "dock": 2, "service": 3]
        let typed = journal.entries.sorted { (order[$0.entry.kind] ?? 9, $0.key) < (order[$1.entry.kind] ?? 9, $1.key) }
        for (key, entry) in typed {
            var problems: [String] = []
            var ok = false
            let title = tweak(entry.tweak)?.title ?? key
            switch entry.kind {
            case "pref":
                guard let domain = entry.domain, let name = entry.key else { break }
                ok = restorePref(domain, name, to: entry.previous, store: store)
                if ok { journal.remove(key); work.log.append(restoreCommand(domain, name, entry.previous)) }
                else { problems.append("\(domain) \(name) didn't go back.") }
            case "hidden":
                let path = env.home + "/" + (entry.path ?? "Library")
                let hidden = entry.wasHidden ?? true
                ok = settings.setHidden(path, hidden) && settings.isHidden(path) == hidden
                if ok { journal.remove(key); work.log.append("chflags \(hidden ? "hidden" : "nohidden") ~/\(entry.path ?? "Library")") }
                else { problems.append("macOS didn't let Lightspot change ~/\(entry.path ?? "Library") back.") }
            case "dock":
                let tiles = entry.tiles ?? []
                let before = journal.json(key)
                ok = tiles.isEmpty || MacTweaksDock.putBack(tiles, store: store)
                if ok {
                    journal.remove(key)
                    work.log.append("put back in the Dock: \(tiles.map(\.label).joined(separator: ", "))")
                    if !tiles.isEmpty { work.dockChecks.append(DockCheck(kind: .putBack(tiles), key: key, before: before, tweak: nil, title: title)) }
                } else {
                    problems.append("The Dock didn't take its icons back.")
                }
            case "service":
                guard let label = entry.label else { break }
                switch restoreService(label, entry: entry, journal: &journal, env: env, work: &work, problems: &problems) {
                case .enabled:
                    ok = true
                case .fromNextLogin(let why):
                    ok = true
                    work.lines.append("\(title): back from your next login. macOS didn't let Lightspot start it again now (\(why)).")
                case .keptOff:
                    work.lines.append("\(title): left as it was. It was off before Lightspot.")
                case .failed:
                    break
                }
            default:
                break
            }
            if ok {
                undone += 1
                restarts.formUnion(entry.restart ?? [])
            }
            work.problems += problems.map { "\(title): \($0)" }
            do { try journal.saveAhead(url: url, fileSystem: settings.fileSystem) } catch {
                work.problems.append("Lightspot couldn't save its undo journal (\(error.localizedDescription)); undoing again is safe.")
            }
        }

        // Background items, through their own section's hook.
        let background = journal.entries(kind: "background")
        var backgroundUndo: BackgroundUndo?
        if !background.isEmpty {
            if let hook = settings.background {
                let undo = hook(background)
                backgroundUndo = undo
                work.problems += undo.userSteps()
                work.log += undo.log()
            } else {
                kept += background.count
                work.notes.append("Background items Lightspot turned off stay as they are: Background Items isn't part of this build.")
            }
        }
        let unknown = journal.keys.filter { key in
            guard let kind = journal.kind(key) else { return true }
            return !MacTweaksJournal.typedKinds.contains(kind) && kind != "background"
        }
        if !unknown.isEmpty {
            kept += unknown.count
            work.notes.append("Kept: \(unknown.count) \(unknown.count == 1 ? "change" : "changes") this version of Lightspot can't undo.")
        }
        let unreadable = journal.keys.filter { isUnreadable($0, journal) }
        if !unreadable.isEmpty {
            let one = unreadable.count == 1
            kept += unreadable.count
            work.notes.append("Kept: \(unreadable.count) \(one ? "change" : "changes") whose journal \(one ? "entry" : "entries") can't be read, "
                              + "so Lightspot can't tell what to put back (\(unreadable.joined(separator: ", "))).")
        }

        let restartList = restartOrder.filter(restarts.contains)
        if !restartList.isEmpty {
            progress?("Restarting \(spokenList(restartList))…")
            for name in restartList {
                if name == "Dock" {
                    for check in restartDock(env, checks: work.dockChecks, work: &work) {
                        rollBack(check, journal: &journal, env: env, work: &work)
                        undone -= 1
                        kept += 1
                    }
                } else {
                    _ = settings.restart(name)
                    work.log.append("killall \(name)")
                }
            }
        }

        // One administrator batch: the profile's removal, then Background Items' root steps, which
        // run in it even when there is no profile (or it went since the reading).
        let adminCommands = backgroundUndo?.adminCommands ?? []
        var profileGone = !r.installed.on
        var steps: [Int: (status: Int32, output: String)] = [:]
        if r.installed.on || !adminCommands.isEmpty {
            let change = MacTweaksProfile.change(to: MacTweaksProfile.Contents(ai: nil, tweaks: []), env: env,
                                                 alsoAsAdministrator: adminCommands, progress: progress, log: &work.log,
                                                 extraResults: { steps = $0 })
            let staying = [r.installed.on ? "Lightspot's profile stays installed" : nil,
                           adminCommands.isEmpty ? nil : "background items for every account stay off"].compactMap { $0 }.joined(separator: " and ")
            switch change {
            case .removed, .alreadyMatches:
                profileGone = true
                if r.installed.on { work.lines.append("Lightspot's profile is removed" + (r.installed.ai ? ": Apple Intelligence is back on." : ".")) }
            case .notRemoved:
                work.notes.append(MacTweaksIntelligence.removalInstruction + " Then open Mac Tweaks again.")
            case .promptCancelled:
                work.problems.append("The administrator prompt was cancelled, so \(staying).")
            case .promptRefused:
                work.problems.append("macOS didn't accept the administrator password, so \(staying).")
            case .installed, .notApproved, .writeFailed:
                break
            }
        }
        var dropped = 0
        if let undo = backgroundUndo {
            for (key, _) in background {
                let step = undo.adminKeys.firstIndex(of: key).flatMap { steps[$0] }
                switch undo.outcome(key, step) {
                case .undone(let line):
                    journal.remove(key)
                    undone += 1
                    work.enabledJobs = true
                    if let line { work.lines.append(line) }
                    work.log.append("\(key): back as it was")
                case .dropped(let line):
                    journal.remove(key)
                    dropped += 1
                    work.lines.append(line)
                    work.log.append("\(key): its plist is gone; entry dropped, nothing ran")
                case .kept(let problem):
                    kept += 1
                    if let problem { work.problems.append(problem) }
                    work.log.append("\(key): kept" + (problem.map { " (\($0))" } ?? ""))
                }
            }
            if !undo.unreadable.isEmpty {
                let one = undo.unreadable.count == 1
                work.notes.append("Kept: \(undo.unreadable.count) background \(one ? "item whose journal entry" : "items whose journal entries") "
                                  + "can't be read, so Lightspot can't tell what to put back (\(undo.unreadable.joined(separator: ", "))).")
            }
            if !undo.refused.isEmpty {
                let one = undo.refused.count == 1
                work.notes.append("Kept: \(undo.refused.count) background \(one ? "item" : "items") Lightspot never changes, "
                                  + "so it doesn't undo \(one ? "it" : "them") (\(undo.refused.joined(separator: ", "))).")
            }
            do { try journal.saveAhead(url: url, fileSystem: settings.fileSystem) } catch {
                work.problems.append("Lightspot couldn't save its undo journal (\(error.localizedDescription)).")
            }
        }
        if undone > 0 { work.lines.insert("Put back \(undone) \(undone == 1 ? "change" : "changes").", at: 0) }
        if work.enabledJobs { work.notes.append(enabledRecordReceiptNote) }
        if !restartList.isEmpty { work.lines.append("Restarted \(spokenList(restartList)).") }

        // An entry dropped because its plist is gone ran nothing: never "everything is back".
        let complete = work.problems.isEmpty && profileGone && kept == 0 && dropped == 0 && journal.isEmpty
        let headline: String
        if complete {
            headline = "Everything Lightspot changed is back."
        } else if undone == 0 && !(profileGone && r.installed.on) {
            headline = "Nothing changed."
        } else {
            headline = "Some changes couldn't be undone."
        }
        let receipt = MacTweaksReceipt(headline: headline, lines: work.receiptLines, problems: work.problems, notes: work.notes, isSuccess: complete)
        return finish(receipt, env: env, started: started, log: work.log)
    }

    /// Writes the receipt to the log and reads the Mac again for the rows.
    private static func finish(_ receipt: MacTweaksReceipt, env: ProviderEnvironment, started: Date, log: [String],
                               reading: Reading? = nil) -> ApplyResult {
        MacTweaksProvider.appendReceipt(section: .settings, lines: log + [receipt.headline] + receipt.lines + receipt.problems,
                                        environment: env, started: started)
        let r = reading ?? read(env)
        return (receipt, rows(r, backgroundLines: env.settings.backgroundPlanLines), r)
    }

    // MARK: The section

    /// Settings as a Mac Tweaks section. A class so the provider can read what the last scan or the
    /// apply's rescan read; it carries the scan on show, so building the plan reads nothing.
    final class Engine: MacTweaksSectionEngine, @unchecked Sendable {
        let environment: ProviderEnvironment
        let scanned: Reading?
        private let lock = NSLock()
        private var _lastContext: Reading?

        init(environment: ProviderEnvironment, scanned: Reading? = nil) {
            self.environment = environment
            self.scanned = scanned
        }

        var lastContext: Reading? { lock.lock(); defer { lock.unlock() }; return _lastContext }

        private func remember(_ context: Reading?) {
            guard let context else { return }
            lock.lock(); _lastContext = context; lock.unlock()
        }

        func scan(only: Set<String>?, progress: (@Sendable (String) -> Void)?) -> [MacTweaksRow] {
            progress?("Reading your settings…")
            let reading = MacTweaksSettings.read(environment)
            // The profile file is needed only until the profile is installed. Apple Intelligence's
            // scan removes it too, but that section isn't on every Mac (Intel, macOS 13 to 15.0).
            if reading.installed.on { environment.intelligence.removeProfileFile() }
            remember(reading)
            return MacTweaksSettings.rows(reading, backgroundLines: environment.settings.backgroundPlanLines)
        }

        func apply(_ rows: [MacTweaksRow], progress: (@Sendable (String) -> Void)?) -> (receipt: MacTweaksReceipt, rescanned: [MacTweaksRow]) {
            let result = MacTweaksSettings.apply(rows, env: environment, progress: progress)
            remember(result.context)
            return (result.receipt, result.rescanned)
        }

        func planNotes(for rows: [MacTweaksRow]) -> [String] {
            MacTweaksSettings.planNotes(ticked: rows, context: scanned)
        }
    }
}

extension String {
    /// Nil for an empty string.
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
