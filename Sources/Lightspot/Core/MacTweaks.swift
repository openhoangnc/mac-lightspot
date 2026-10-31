import Foundation
import Darwin

// MARK: - macOS Tweaks
//
// The `defaults write` one-liners developers keep in a dotfiles README, as quick actions.
// Every setting but the Dock's icons is a toggle that reads the current value and flips it, so
// the same row turns it back. Clear Dock Icons saves the Dock's icons first and Restore Dock
// Icons puts them back (`MacTweaksDock`, through cfprefsd). Nothing here needs an
// administrator password.

enum MacTweaks {
    /// A shell toggle for boolean preferences. `defaultValue` is what macOS uses while the
    /// first key is unset; every key in `keys` is written to the opposite of the first's
    /// current value. `restart` names a process to relaunch so the change shows at once.
    static func toggleScript(domain: String, keys: [String], defaultValue: Bool, restart: String? = nil) -> String {
        let current = "$(defaults read \(domain) \(keys[0]) 2>/dev/null || echo \(defaultValue ? 1 : 0))"
        func write(_ value: Bool) -> String {
            keys.map { "defaults write \(domain) \($0) -bool \(value)" }.joined(separator: "; ")
        }
        var script = "case \"\(current)\" in 1|[Yy][Ee][Ss]|[Tt][Rr][Uu][Ee]) \(write(false));; *) \(write(true));; esac"
        if let restart { script += "; killall \(restart)" }
        return script
    }

    /// Instant Dock auto-hide (no delay, a quick slide) while the delay key is set; back to
    /// macOS's own timing by deleting both keys.
    static func instantDockScript(domain: String = "com.apple.dock", restart: String? = "Dock") -> String {
        var script = "if defaults read \(domain) autohide-delay >/dev/null 2>&1; "
            + "then defaults delete \(domain) autohide-delay; defaults delete \(domain) autohide-time-modifier 2>/dev/null; "
            + "else defaults write \(domain) autohide-delay -float 0; defaults write \(domain) autohide-time-modifier -float 0.15; fi"
        if let restart { script += "; killall \(restart)" }
        return script
    }

    static let actions: [QuickAction] = [
        QuickAction(
            name: "Clear Dock Icons",
            keywords: ["clear dock", "clear dock icons", "empty dock", "remove dock icons", "remove dock apps"],
            sfSymbol: "dock.rectangle",
            subtitle: "Remove every app pinned to the Dock, then restart it. Restore Dock Icons puts them back",
            script: MacTweaksDock.clearScript,
            usesOsascript: false
        ),
        QuickAction(
            name: "Restore Dock Icons",
            keywords: ["restore dock", "restore dock icons", "undo clear dock", "put back dock icons", "dock icons back"],
            sfSymbol: "dock.arrow.up.rectangle",
            subtitle: "Put back the apps Clear Dock Icons removed, then restart the Dock",
            script: MacTweaksDock.restoreScript,
            usesOsascript: false
        ),
        QuickAction(
            name: "Restart Dock",
            keywords: ["restart dock", "reload dock", "relaunch dock", "fix dock"],
            sfSymbol: "arrow.triangle.2.circlepath",
            subtitle: "Relaunch the Dock, Launchpad and Mission Control",
            script: "killall Dock",
            usesOsascript: false
        ),
        QuickAction(
            name: "Toggle Dock Auto-Hide",
            keywords: ["dock autohide", "auto hide dock", "autohide", "hide dock", "show dock"],
            sfSymbol: "dock.arrow.down.rectangle",
            subtitle: "Hide the Dock until the pointer reaches it, or keep it shown",
            script: #"tell application "System Events" to tell dock preferences to set autohide to not autohide"#,
            usesOsascript: true
        ),
        QuickAction(
            name: "Toggle Instant Dock Auto-Hide",
            keywords: ["instant dock", "fast dock", "dock delay", "dock animation", "dock speed", "autohide delay"],
            sfSymbol: "hare.fill",
            subtitle: "Show an auto-hidden Dock with no delay, or go back to macOS's timing",
            script: instantDockScript(),
            usesOsascript: false
        ),
        QuickAction(
            name: "Toggle Dock Recent Apps",
            keywords: ["dock recents", "recent apps in dock", "show recents", "suggested apps"],
            sfSymbol: "clock.arrow.circlepath",
            subtitle: "Show or hide recent and suggested apps in the Dock",
            script: toggleScript(domain: "com.apple.dock", keys: ["show-recents"], defaultValue: true, restart: "Dock"),
            usesOsascript: false
        ),
        QuickAction(
            name: "Toggle Hidden Files in Finder",
            keywords: ["hidden files", "show hidden files", "hide hidden files", "dotfiles", "show dotfiles"],
            sfSymbol: "eye.slash",
            subtitle: "Show or hide dotfiles and hidden folders in Finder (relaunches Finder)",
            script: toggleScript(domain: "com.apple.finder", keys: ["AppleShowAllFiles"], defaultValue: false, restart: "Finder"),
            usesOsascript: false
        ),
        QuickAction(
            name: "Toggle File Extensions in Finder",
            keywords: ["file extensions", "show extensions", "show file extensions", "hide extensions"],
            sfSymbol: "doc.text.magnifyingglass",
            subtitle: "Always show or hide filename extensions (relaunches Finder)",
            script: toggleScript(domain: "NSGlobalDomain", keys: ["AppleShowAllExtensions"], defaultValue: false, restart: "Finder"),
            usesOsascript: false
        ),
        QuickAction(
            name: "Toggle Finder Path Bar",
            keywords: ["path bar", "finder path", "show path bar"],
            sfSymbol: "folder.badge.gearshape",
            subtitle: "Show or hide the folder path at the bottom of Finder windows",
            script: toggleScript(domain: "com.apple.finder", keys: ["ShowPathbar"], defaultValue: false, restart: "Finder"),
            usesOsascript: false
        ),
        QuickAction(
            name: "Toggle Desktop Icons",
            keywords: ["desktop icons", "hide desktop icons", "show desktop icons", "presentation mode"],
            sfSymbol: "rectangle.on.rectangle.slash",
            subtitle: "Hide or show the files on the desktop, e.g. for a screen share (relaunches Finder)",
            script: toggleScript(domain: "com.apple.finder", keys: ["CreateDesktop"], defaultValue: true, restart: "Finder"),
            usesOsascript: false
        ),
        QuickAction(
            name: "Restart Finder",
            keywords: ["restart finder", "relaunch finder", "reload finder", "fix finder"],
            sfSymbol: "arrow.clockwise.circle",
            subtitle: "Relaunch Finder; its windows come back",
            script: "killall Finder",
            usesOsascript: false
        ),
        QuickAction(
            name: "Toggle Screenshot Shadows",
            keywords: ["screenshot shadow", "window shadow", "screenshot shadows"],
            sfSymbol: "camera.on.rectangle",
            subtitle: "Turn the drop shadow on window screenshots off or on",
            script: toggleScript(domain: "com.apple.screencapture", keys: ["disable-shadow"], defaultValue: false, restart: "SystemUIServer"),
            usesOsascript: false
        ),
        QuickAction(
            name: "Toggle .DS_Store on Network & USB Drives",
            keywords: [".ds_store", "ds_store", "dsstore", "ds store", "network drives", "usb drives"],
            sfSymbol: "externaldrive.badge.xmark",
            subtitle: "Stop or resume Finder writing .DS_Store files to network and USB volumes",
            script: toggleScript(domain: "com.apple.desktopservices", keys: ["DSDontWriteNetworkStores", "DSDontWriteUSBStores"],
                                 defaultValue: false, restart: "Finder"),
            usesOsascript: false
        ),
        QuickAction(
            name: "Toggle Press-and-Hold Accents",
            keywords: ["key repeat", "press and hold", "accent menu", "hold to repeat", "vim key repeat"],
            sfSymbol: "keyboard",
            subtitle: "Holding a key repeats it instead of showing accents, or back (relaunch apps to apply)",
            script: toggleScript(domain: "NSGlobalDomain", keys: ["ApplePressAndHoldEnabled"], defaultValue: true),
            usesOsascript: false
        ),
        QuickAction(
            name: "Toggle Smart Quotes & Dashes",
            keywords: ["smart quotes", "curly quotes", "smart dashes", "auto quotes", "straight quotes"],
            sfSymbol: "quote.opening",
            subtitle: "Stop or resume macOS turning \" into “ ” and -- into — as you type",
            script: toggleScript(domain: "NSGlobalDomain", keys: ["NSAutomaticQuoteSubstitutionEnabled", "NSAutomaticDashSubstitutionEnabled"],
                                 defaultValue: true),
            usesOsascript: false
        ),
    ]
}

// MARK: - The Dock's icons

/// The Dock's pinned apps (`com.apple.dock` `persistent-apps`), read and written through
/// cfprefsd (invariant 8): Clear Dock Icons with its backup, Restore Dock Icons, and the Settings
/// section's "Remove unused Apple apps from the Dock", which journals the tiles it takes out.
/// Each read-modify-write holds one lock: the quick actions run on a global queue, the Settings
/// tweak on Mac Tweaks' queue.
enum MacTweaksDock {
    static let domain = "com.apple.dock"
    static let key = "persistent-apps"
    static let clearScript = "internal:clear-dock"
    static let restoreScript = "internal:restore-dock"
    /// What Clear Dock Icons ran up to 1.3.9. Search history keeps a row's action, so an old
    /// history entry still holds it; `QuickActionsProvider.execute` runs the new action for it.
    static let legacyClearScript = "defaults write com.apple.dock persistent-apps -array && killall Dock"
    private static let lock = NSLock()

    enum Action: Sendable, Equatable { case clear, restore }

    /// The Dock action a quick action's script names, the 1.3.x one-liner included.
    static func action(forScript script: String) -> Action? {
        switch script {
        case clearScript, legacyClearScript: return .clear
        case restoreScript: return .restore
        default: return nil
        }
    }

    /// `~/Library/Application Support/Lightspot/dock-backup.plist`: the icons Clear Dock Icons
    /// removed, until Restore Dock Icons puts them back.
    static func backupURL(home: String) -> URL {
        URL(fileURLWithPath: home + "/Library/Application Support/Lightspot/dock-backup.plist")
    }

    /// The tiles in a stored `persistent-apps`, in order.
    static func tiles(_ value: PreferenceValue?) -> [Any] { value?.object as? [Any] ?? [] }

    static func bundleID(_ tile: Any) -> String? {
        ((tile as? [String: Any])?["tile-data"] as? [String: Any])?["bundle-identifier"] as? String
    }

    /// The name the Dock shows for a tile.
    static func label(_ tile: Any) -> String {
        ((tile as? [String: Any])?["tile-data"] as? [String: Any])?["file-label"] as? String ?? bundleID(tile) ?? "a Dock item"
    }

    static func encode(_ tile: Any) -> Data? {
        try? PropertyListSerialization.data(fromPropertyList: tile, format: .binary, options: 0)
    }

    static func decode(_ data: Data) -> Any? {
        try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    }

    /// The app a journaled tile is for.
    static func appID(_ tile: MacTweaksJournal.Tile) -> String? { decode(tile.plist).flatMap(bundleID) }

    /// `tiles`, then each of `more` for an app not among them yet: an app keeps the first place
    /// recorded for it, so removing it, dragging it back and removing it again journals it once.
    static func adding(_ more: [MacTweaksJournal.Tile], to tiles: [MacTweaksJournal.Tile]) -> [MacTweaksJournal.Tile] {
        var seen = Set(tiles.compactMap(appID))
        return tiles + more.filter { tile in appID(tile).map { seen.insert($0).inserted } ?? true }
    }

    /// The tiles of `current` with `tiles` put back at their old positions (RemoveMacAI's
    /// reinsertion): each app once, so one already in the Dock, or put back by an earlier tile,
    /// is skipped; a tile without a bundle ID (a spacer) goes back only into an empty Dock.
    static func reinserted(_ tiles: [MacTweaksJournal.Tile], into current: [Any]) -> [Any] {
        var result = current
        var present = Set(current.compactMap(bundleID))
        let empty = current.isEmpty
        for tile in tiles.sorted(by: { $0.index < $1.index }) {
            guard let object = decode(tile.plist) else { continue }
            if let id = bundleID(object) {
                guard present.insert(id).inserted else { continue }
            } else if !empty {
                continue
            }
            result.insert(object, at: min(tile.index, result.count))
        }
        return result
    }

    private static func write(_ tiles: [Any], _ store: PreferenceStore) -> Bool {
        guard let value = PreferenceValue(tiles as NSArray), store.write(domain, key, value) else { return false }
        store.synchronize(domain)
        return true
    }

    private static func current(_ store: PreferenceStore) -> [Any] {
        store.synchronize(domain)
        return tiles(store.read(domain, key))
    }

    /// The apps in the Dock now, read through cfprefsd.
    static func appIDs(_ store: PreferenceStore) -> Set<String> { Set(current(store).compactMap(bundleID)) }

    /// What a check compares: each tile's app, or for a tile without one (a spacer) its kind, in
    /// order. The Dock may rewrite a tile's other fields (its dates, its GUID) as it loads it.
    static func signature(_ tiles: [Any]) -> [String] {
        tiles.map { tile in
            bundleID(tile) ?? ((tile as? [String: Any])?["tile-type"] as? String).map { "(\($0))" } ?? "(tile)"
        }
    }

    // MARK: Writing around the Dock's restart

    /// This user's running Dock: its PID and when it started.
    struct Running: Sendable, Equatable {
        var pid: Int32
        var started: Date
    }

    /// The Dock's executable, which `runningDock` looks for in the process table.
    static let executable = "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock"

    /// This user's Dock in the process table (`proc_pidpath`, and `proc_pidinfo`'s start); the
    /// newest when a killed one is still on its way out. About a millisecond.
    static func runningDock() -> Running? {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 32)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        // PROC_PIDPATHINFO_MAXSIZE, a macro Swift does not import.
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let uid = getuid()
        var newest: Running?
        for pid in pids.prefix(Int(max(count, 0))) where pid > 0 {
            var info = proc_bsdinfo()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_uid == uid,
                  proc_pidpath(pid, &path, UInt32(path.count)) > 0, String(cString: path) == executable else { continue }
            let started = Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1e6)
            if newest.map({ started > $0.started }) ?? true { newest = Running(pid: pid, started: started) }
        }
        return newest
    }

    /// A Dock restart that can be checked: the restart, a look at the Dock that runs, a clock and
    /// a pause, injected so tests drive them with fakes.
    struct Restarter: Sendable {
        /// `killall Dock`: launchd starts a new one.
        var restart: @Sendable () -> Void
        /// This user's running Dock, nil while none runs. Nil itself where processes can't be seen
        /// (tests that don't drive it): then nothing waits, and the read-back right after the
        /// restart is the check.
        var running: (@Sendable () -> Running?)?
        var now: @Sendable () -> Date
        var pause: @Sendable (TimeInterval) -> Void
    }

    /// A Dock younger than this may still be starting, and a Dock killed while it starts writes
    /// the icons it started with over a change made meanwhile: 1.4.0's QA ran Restore 4 s after
    /// Clear and the Dock came back empty, the backup already gone. Measured here (27.2): Docks
    /// killed 3.9 and 4.0 s after their start wrote their icons; none killed at 0.5, 1.9, 2.9,
    /// 4.3, 4.9, 6.0 or 10 s did. Twice the danger, for slower Macs.
    static let settleAge: TimeInterval = 8
    /// The Dock a restart brings up is checked once it has run this long: the killed one writes
    /// as it quits, before launchd starts the next.
    static let checkAge: TimeInterval = 1
    /// Two reads of the icons this far apart must agree before the Dock counts as settled.
    static let stableGap: TimeInterval = 0.5
    /// The longest any wait for the Dock lasts.
    static let upTimeout: TimeInterval = 20

    /// Waits until a Dock other than `old` has run `age` and its icons read the same twice
    /// `stableGap` apart. False when none does within `upTimeout`; true at once when processes
    /// can't be seen.
    static func waitForDock(_ store: PreferenceStore, _ restarter: Restarter, age: TimeInterval, notPID old: Int32? = nil) -> Bool {
        guard let running = restarter.running else { return true }
        let deadline = restarter.now().addingTimeInterval(upTimeout)
        var last: [String]?
        while true {
            if let dock = running(), dock.pid != old, restarter.now().timeIntervalSince(dock.started) >= age {
                let icons = signature(current(store))
                if icons == last { return true }
                last = icons
            } else {
                last = nil
            }
            guard restarter.now() < deadline else { return false }
            restarter.pause(stableGap)
        }
    }

    /// How a write that restarts the Dock ended.
    enum Restarted: Sendable, Equatable {
        /// The Dock that came up shows the icons written.
        case verified
        /// cfprefsd didn't take the write: nothing changed.
        case notWritten
        /// The Dock came back with other icons, after a second try too.
        case overwritten
        /// No Dock came up and settled within `upTimeout`, before the write or after the restart.
        case noDock
    }

    /// Waits for any Dock that just restarted to settle, writes the icons `target` makes of the
    /// Dock's own, restarts the Dock and checks the Dock that comes up shows them; once more when
    /// that restart lost them. Returns the icons before and after the last write. Callers hold
    /// `lock`.
    private static func writeAndRestart(_ store: PreferenceStore, _ restarter: Restarter,
                                        target: ([Any]) -> [Any]) -> (Restarted, before: [Any], written: [Any]) {
        var before: [Any] = []
        var written: [Any] = []
        for _ in 0..<2 {
            guard waitForDock(store, restarter, age: settleAge) else { return (.noDock, before, written) }
            before = current(store)
            written = target(before)
            guard write(written, store), signature(current(store)) == signature(written) else { return (.notWritten, before, written) }
            let old = restarter.running?()?.pid
            restarter.restart()
            guard waitForDock(store, restarter, age: checkAge, notPID: old) else { return (.noDock, before, written) }
            if signature(current(store)) == signature(written) { return (.verified, before, written) }
        }
        return (.overwritten, before, written)
    }

    /// Settings' Dock-removal tweak again after a restart lost it: these apps out, the rest kept,
    /// nothing journaled (the first removal's entry stands). True when cfprefsd took it.
    static func removeAgain(_ ids: Set<String>, store: PreferenceStore) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return write(current(store).filter { bundleID($0).map(ids.contains) != true }, store)
    }

    enum RemoveOutcome: Sendable, Equatable {
        case removed([String])
        case nothingToDo
        /// `record` couldn't journal the tiles: nothing changed.
        case notSaved
        case failed
    }

    /// Takes these apps' tiles out of the Dock, keeping the rest in order. `record` journals what
    /// goes (position, name, tile) before anything changes, and returns false when it couldn't.
    static func removeApps(_ ids: Set<String>, store: PreferenceStore, record: ([MacTweaksJournal.Tile]) -> Bool) -> RemoveOutcome {
        lock.lock()
        defer { lock.unlock() }
        var kept: [Any] = []
        var removed: [MacTweaksJournal.Tile] = []
        for (index, tile) in current(store).enumerated() {
            if let id = bundleID(tile), ids.contains(id), let data = encode(tile) {
                removed.append(MacTweaksJournal.Tile(index: index, label: label(tile), plist: data))
            } else {
                kept.append(tile)
            }
        }
        guard !removed.isEmpty else { return .nothingToDo }
        guard record(removed) else { return .notSaved }
        guard write(kept, store) else { return .failed }
        return current(store).contains { bundleID($0).map(ids.contains) == true } ? .failed : .removed(removed.map(\.label))
    }

    /// Puts journaled tiles back; true when every app among them is in the Dock again.
    static func putBack(_ tiles: [MacTweaksJournal.Tile], store: PreferenceStore) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let merged = reinserted(tiles, into: current(store))
        guard write(merged, store) else { return false }
        let present = Set(current(store).compactMap(bundleID))
        return tiles.allSatisfy { tile in decode(tile.plist).flatMap(bundleID).map(present.contains) ?? true }
    }

    // MARK: Clear and Restore Dock Icons

    struct Environment: Sendable {
        var preferences = PreferenceStore.inert
        var fileSystem = MacTweaksJournal.FileSystem.inert
        var backupURL: URL
        var restartDock: @Sendable () -> Void = {}
        var now: @Sendable () -> Date = { Date() }
        /// This user's running Dock (`runningDock`); nil where processes can't be seen, and then
        /// nothing waits for the Dock (`Restarter.running`).
        var runningDock: (@Sendable () -> Running?)? = nil
        var pause: @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }

        var restarter: Restarter { Restarter(restart: restartDock, running: runningDock, now: now, pause: pause) }

        static func live(home: String = NSHomeDirectory()) -> Environment {
            Environment(preferences: .live(), fileSystem: .live, backupURL: MacTweaksDock.backupURL(home: home),
                        restartDock: { _ = CleanDevMacEngine.run("/usr/bin/killall", ["Dock"], timeout: 10) },
                        runningDock: { MacTweaksDock.runningDock() })
        }
    }

    enum Outcome: Sendable, Equatable {
        /// This many icons were saved, then removed.
        case cleared(Int)
        /// The Dock has no icons: nothing changes, and an earlier backup stays.
        case alreadyEmpty
        /// The backup couldn't be written, so nothing was cleared.
        case backupFailed(String)
        /// cfprefsd didn't take the change.
        case notWritten
        /// The Dock restarted with other icons than the ones written, twice: a Dock killed while
        /// it starts writes its own over them. The backup stays.
        case overwritten
        /// No Dock came up and settled to write to or check: the backup stays.
        case noDock
        /// This many icons came back.
        case restored(Int)
        case nothingToRestore
    }

    /// The backup's icons and when the first Clear saved them; nil without a backup, or with one
    /// that can't be read.
    private static func backup(_ env: Environment) -> (tiles: [Any], date: Date?)? {
        guard env.fileSystem.exists(env.backupURL), let data = env.fileSystem.read(env.backupURL),
              let backup = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let tiles = backup[key] as? [Any] else { return nil }
        return (tiles, backup["date"] as? Date)
    }

    /// Clear Dock Icons: saves `persistent-apps` to the backup, then empties it and restarts the
    /// Dock, once any Dock that just restarted has settled, and checks the Dock that comes up is
    /// empty (`writeAndRestart`). Nothing is cleared without the backup written first. A backup an
    /// earlier Clear left keeps its icons and gains only the apps it lacks, so clearing again
    /// before a Restore loses nothing; a spacer it already has a place for isn't added twice. One
    /// that can't be read is replaced: Restore can't use it either.
    @discardableResult
    static func clear(_ env: Environment) -> Outcome {
        lock.lock()
        defer { lock.unlock() }
        let store = env.preferences
        let tiles = current(store)
        guard !tiles.isEmpty else { return .alreadyEmpty }
        var saved = tiles
        var date = env.now()
        if let earlier = backup(env) {
            var seen = Set(earlier.tiles.compactMap(bundleID))
            saved = earlier.tiles + tiles.filter { tile in bundleID(tile).map { seen.insert($0).inserted } ?? false }
            date = earlier.date ?? date
        }
        let file: [String: Any] = ["version": 1, "date": date, key: saved]
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: file, format: .xml, options: 0)
            try env.fileSystem.write(env.backupURL, data)
        } catch {
            return .backupFailed(error.localizedDescription)
        }
        switch writeAndRestart(store, env.restarter, target: { _ in [] }).0 {
        case .verified: return .cleared(tiles.count)
        case .notWritten: return .notWritten
        case .overwritten: return .overwritten
        case .noDock: return .noDock
        }
    }

    /// The backup's icons merged into the Dock's own: into an empty Dock exactly as they were;
    /// otherwise the missing apps at their old positions, keeping icons added since.
    static func merged(_ saved: [Any], into now: [Any]) -> [Any] {
        guard !now.isEmpty else { return saved }
        let tiles = saved.enumerated().compactMap { index, tile in
            encode(tile).map { MacTweaksJournal.Tile(index: index, label: label(tile), plist: $0) }
        }
        return reinserted(tiles, into: now)
    }

    /// Restore Dock Icons: puts the backup's icons back (`merged`), once any Dock that just
    /// restarted has settled, restarts the Dock and checks the Dock that comes up shows them, once
    /// more if that restart lost them (`writeAndRestart`). The backup goes only once they are
    /// checked, so a later Restore can't bring back icons removed on purpose, and a Restore the
    /// Dock lost keeps it.
    @discardableResult
    static func restore(_ env: Environment) -> Outcome {
        lock.lock()
        defer { lock.unlock() }
        let store = env.preferences
        guard let saved = backup(env)?.tiles else { return .nothingToRestore }
        // Every app already back: nothing to write or restart.
        guard merged(saved, into: current(store)).count > current(store).count else {
            try? env.fileSystem.remove(env.backupURL)
            return .restored(0)
        }
        let (result, before, written) = writeAndRestart(store, env.restarter, target: { merged(saved, into: $0) })
        switch result {
        case .verified:
            try? env.fileSystem.remove(env.backupURL)
            return .restored(written.count - before.count)
        case .notWritten: return .notWritten
        case .overwritten: return .overwritten
        case .noDock: return .noDock
        }
    }

    /// Runs a Dock quick action (on QuickActionsProvider's global queue) and keeps what it found
    /// for the two rows' subtitles.
    static func run(_ action: Action, env: Environment = .live(), status: Status = .shared) {
        status.record(action == .clear ? clear(env) : restore(env), for: action)
    }

    // MARK: What the two rows say before ↵

    /// Restore Dock Icons with no backup changes nothing: every 1.3.x user who cleared the Dock
    /// before updating has none.
    static let noBackupSubtitle = "No Dock backup to restore. Lightspot 1.3.9 and older didn't save one"

    /// What a row says after a Clear or Restore that changed nothing because something failed;
    /// nil after one that worked, or found nothing to do (which the rows say before ↵).
    static func problem(_ outcome: Outcome, for action: Action) -> String? {
        switch outcome {
        case .backupFailed(let reason):
            return "Last time Lightspot couldn't save the icons first, so it cleared nothing (\(reason))"
        case .notWritten:
            return action == .clear ? "Last time the Dock didn't take the change, so its icons stayed"
                                    : "Last time the Dock didn't take its icons back. The backup is kept"
        case .overwritten:
            return action == .clear ? "Last time the Dock restarted with its icons still there, twice. The backup is kept"
                                    : "Last time the Dock restarted without the restored icons, twice. The backup is kept"
        case .noDock:
            return "Last time the Dock didn't come up within \(Int(upTimeout)) seconds, so Lightspot couldn't check its icons. The backup is kept"
        case .cleared, .alreadyEmpty, .restored, .nothingToRestore:
            return nil
        }
    }

    /// The rows' subtitles without blocking the keystroke path (invariant 0): whether a backup
    /// waits, read on a background queue behind a staleness check and an in-flight flag, and
    /// after each Clear or Restore with what it ran into. Nothing is read until a search shows
    /// one of the two rows.
    final class Status: @unchecked Sendable {
        static let shared = Status { FileManager.default.fileExists(atPath: MacTweaksDock.backupURL(home: NSHomeDirectory()).path) }
        private static let staleAfter: TimeInterval = 5

        private let backupExists: @Sendable () -> Bool
        private let lock = NSLock()
        private let queue = DispatchQueue(label: "com.lightspot.dock-status")
        private var backup: Bool?
        private var problems: [Action: String] = [:]
        private var lastRead = Date.distantPast
        private var refreshing = false

        init(backupExists: @escaping @Sendable () -> Bool) {
            self.backupExists = backupExists
        }

        /// The row's subtitle when it differs from its usual one. Never blocks: before the first
        /// read it is nil, and a stale snapshot schedules a read.
        func subtitle(for action: Action) -> String? {
            lock.lock()
            let known = backup
            let problem = problems[action]
            let stale = Date().timeIntervalSince(lastRead) > Self.staleAfter
            lock.unlock()
            if stale { scheduleRefresh() }
            if let problem { return problem }
            return action == .restore && known == false ? MacTweaksDock.noBackupSubtitle : nil
        }

        /// After a Clear or Restore, off the main thread: the backup read again, and what went
        /// wrong kept for that row until it runs again.
        func record(_ outcome: Outcome, for action: Action) {
            let exists = backupExists()
            lock.lock()
            backup = exists
            problems[action] = MacTweaksDock.problem(outcome, for: action)
            lastRead = Date()
            lock.unlock()
        }

        /// Blocking: reads whether the backup exists now (tests, and the background refresh).
        func refreshNow() {
            let exists = backupExists()
            lock.lock()
            backup = exists
            lastRead = Date()
            refreshing = false
            lock.unlock()
        }

        private func scheduleRefresh() {
            lock.lock()
            guard !refreshing else { lock.unlock(); return }
            refreshing = true
            lock.unlock()
            queue.async { [self] in refreshNow() }
        }
    }
}
