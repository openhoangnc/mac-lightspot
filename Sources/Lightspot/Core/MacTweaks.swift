import Foundation

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

        static func live(home: String = NSHomeDirectory()) -> Environment {
            Environment(preferences: .live(), fileSystem: .live, backupURL: MacTweaksDock.backupURL(home: home),
                        restartDock: { _ = CleanDevMacEngine.run("/usr/bin/killall", ["Dock"], timeout: 10) })
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
    /// Dock. Nothing is cleared without the backup written first. A backup an earlier Clear left
    /// keeps its icons and gains only the apps it lacks, so clearing again before a Restore loses
    /// nothing; a spacer it already has a place for isn't added twice. One that can't be read is
    /// replaced: Restore can't use it either.
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
        guard write([], store), current(store).isEmpty else { return .notWritten }
        env.restartDock()
        return .cleared(tiles.count)
    }

    /// Restore Dock Icons: puts the backup's icons back. Into an empty Dock exactly as they were;
    /// otherwise the missing apps at their old positions, keeping icons added since. The backup
    /// goes once its icons are back, so a later Restore can't bring back icons removed on purpose.
    @discardableResult
    static func restore(_ env: Environment) -> Outcome {
        lock.lock()
        defer { lock.unlock() }
        let store = env.preferences
        guard let saved = backup(env)?.tiles else { return .nothingToRestore }
        let now = current(store)
        let merged: [Any]
        if now.isEmpty {
            merged = saved
        } else {
            let tiles = saved.enumerated().compactMap { index, tile in
                encode(tile).map { MacTweaksJournal.Tile(index: index, label: label(tile), plist: $0) }
            }
            merged = reinserted(tiles, into: now)
        }
        let added = merged.count - now.count
        if added > 0 {
            guard write(merged, store) else { return .notWritten }
            let present = Set(current(store).compactMap(bundleID))
            guard saved.compactMap(bundleID).allSatisfy(present.contains) else { return .notWritten }
        }
        try? env.fileSystem.remove(env.backupURL)
        if added > 0 { env.restartDock() }
        return .restored(added)
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
