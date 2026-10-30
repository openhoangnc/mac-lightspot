import AppKit
import Foundation

@MainActor
enum SpotlightManager {
    // MARK: - Cached State
    //
    // Probing the real state costs ~66 ms per call: `launchctl print-disabled` and
    // `mdutil -s /` are spawned as subprocesses and waited on. SwiftUI re-evaluates
    // `Menu` content on every body pass, so reading them live blocked the main thread
    // on every keystroke. The menus read this snapshot instead; it is only ever
    // refreshed off the main thread.

    struct State: Equatable, Sendable {
        var shortcutEnabled: Bool = true
        var serviceDisabled: Bool = false
        var indexingEnabled: Bool = true
    }

    /// What `disableAll` / `enableAll` actually managed to change. The shortcut and
    /// service flags are verified against the system afterwards rather than assumed,
    /// so the alerts can stop claiming success when nothing moved.
    struct ApplyResult: Sendable {
        var shortcut: Bool = false
        var service: Bool = false
        /// `nil` when indexing was not part of the request.
        var indexing: Bool?
    }

    // The first refresh takes ~200 ms to land, during which the menus would otherwise
    // show hardcoded defaults that may contradict reality. Persist the last known
    // snapshot so a relaunch paints the correct labels immediately.
    private nonisolated static let stateDefaultsKey = "lightspot_spotlight_state"

    private static var cachedState = loadPersistedState()
    private static var isRefreshing = false

    private nonisolated static func loadPersistedState() -> State {
        guard let raw = UserDefaults.standard.dictionary(forKey: stateDefaultsKey) else { return State() }
        var state = State()
        if let v = raw["shortcutEnabled"] as? Bool { state.shortcutEnabled = v }
        if let v = raw["serviceDisabled"] as? Bool { state.serviceDisabled = v }
        if let v = raw["indexingEnabled"] as? Bool { state.indexingEnabled = v }
        return state
    }

    private static func persist(_ state: State) {
        UserDefaults.standard.set([
            "shortcutEnabled": state.shortcutEnabled,
            "serviceDisabled": state.serviceDisabled,
            "indexingEnabled": state.indexingEnabled,
        ], forKey: stateDefaultsKey)
    }

    /// Instant, non-blocking reads of the last known state.
    static func isShortcutEnabled() -> Bool { cachedState.shortcutEnabled }
    static func isServiceDisabled() -> Bool { cachedState.serviceDisabled }
    static func isIndexingEnabled() -> Bool { cachedState.indexingEnabled }

    /// Re-probes the real system state on a background queue.
    /// `onChange` runs on the main actor only when the snapshot actually changed,
    /// so callers can rebuild menus without redrawing on every refresh.
    static func refreshState(onChange: (@Sendable @MainActor () -> Void)? = nil) {
        guard !isRefreshing else { return }
        isRefreshing = true

        DispatchQueue.global(qos: .utility).async {
            let probed = State(
                shortcutEnabled: probeShortcutEnabled(),
                serviceDisabled: probeServiceDisabled(),
                indexingEnabled: probeIndexingEnabled()
            )
            Task { @MainActor in
                let changed = probed != cachedState
                cachedState = probed
                isRefreshing = false
                if changed {
                    persist(probed)
                    onChange?()
                }
            }
        }
    }

    // MARK: - 1. Spotlight Shortcut (⌘Space)
    //
    // Three things make this harder than writing a plist key, and getting any of them
    // wrong looks identical from the outside — "Lightspot says Disabled, ⌘Space still
    // opens Spotlight":
    //
    //  1. The preference has to go through `cfprefsd`. This used to shell out to
    //     PlistBuddy against ~/Library/Preferences/com.apple.symbolichotkeys.plist,
    //     but that file is the daemon's backing store, not the API: cfprefsd holds its
    //     own copy, serves reads from it and flushes it back on its own schedule, so a
    //     direct file write is read back stale and can be overwritten wholesale.
    //     `defaults read` does not "sync" it either — it is a read, and if anything it
    //     re-caches the value we were trying to replace.
    //  2. A missing entry has to be created, not set. PlistBuddy `Set` fails outright
    //     with "Does Not Exist" on a Mac where the user never customised the Spotlight
    //     shortcut, and the failure was swallowed (`try?`, exit status ignored) while
    //     the cached state optimistically flipped to "disabled".
    //  3. The window server caches symbolic hotkeys at login. Without `activateSettings
    //     -u` the new value sits in the preference domain doing nothing until the next
    //     logout, which is the single most common way this appears broken.

    // Held as `String`, not `CFString`: a non-Sendable CFString cannot be a static
    // property under Swift 6 strict concurrency (same constraint as invariant 2).
    private nonisolated static let hotkeyDomain = "com.apple.symbolichotkeys"
    private nonisolated static let hotkeyRootKey = "AppleSymbolicHotKeys"

    /// The `AppleSymbolicHotKeys` entries macOS reserves for Spotlight: 64 is
    /// "Show Spotlight search" (⌘Space by default) and 65 is "Show Finder search
    /// window" (⌥⌘Space). Only 64 used to be touched, which left half the shortcut
    /// registered and kept the key combination out of reach for other apps.
    nonisolated static let spotlightHotkeyIDs = [64, 65]

    /// Apple's factory binding for an entry, written when one is missing so a restore
    /// produces a working shortcut instead of an inert `enabled`-only stub.
    /// `parameters` is `[character code, virtual keycode, Cocoa modifier mask]`:
    /// space is 32 / `kVK_Space` 49, ⌘ is 1048576 and ⌥⌘ is 1572864.
    nonisolated static func defaultHotkeyParameters(for id: Int) -> [Int] {
        id == 65 ? [32, 49, 1_572_864] : [32, 49, 1_048_576]
    }

    /// The whole `AppleSymbolicHotKeys` dictionary, read through the daemon.
    /// Not private: `SystemShortcutConflicts` reads the same root to spot a system
    /// shortcut sitting on Lightspot's key combination, and both must see what the
    /// system will act on rather than the plist file's stale copy.
    nonisolated static func readHotkeyRoot() -> [String: Any] {
        CFPreferencesCopyValue(hotkeyRootKey as CFString, hotkeyDomain as CFString,
                               kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String: Any] ?? [:]
    }

    /// `enabled` is a CFBoolean when System Settings writes it and a CFNumber when
    /// `defaults write -int` does, and both bridge in here.
    nonisolated static func isHotkeyEntryEnabled(_ entry: Any?) -> Bool {
        // A missing entry means the factory default, and Spotlight ships enabled.
        guard let entry = entry as? [String: Any] else { return true }
        guard let raw = entry["enabled"] else { return true }
        if let flag = raw as? Bool { return flag }
        if let number = raw as? NSNumber { return number.boolValue }
        return true
    }

    /// Builds the replacement root dictionary for a given target state, preserving
    /// each entry's existing key binding and filling in the default when absent.
    nonisolated static func hotkeyRoot(_ root: [String: Any], settingEnabled enabled: Bool) -> [String: Any] {
        var updated = root
        for id in spotlightHotkeyIDs {
            let key = String(id)
            var entry = updated[key] as? [String: Any] ?? [:]
            entry["enabled"] = enabled
            if entry["value"] == nil {
                entry["value"] = [
                    "type": "standard",
                    "parameters": defaultHotkeyParameters(for: id),
                ] as [String: Any]
            }
            updated[key] = entry
        }
        return updated
    }

    /// Reads whether either Spotlight shortcut is still live, through cfprefsd rather
    /// than the plist file so the answer matches what the system will act on.
    private nonisolated static func probeShortcutEnabled() -> Bool {
        let root = readHotkeyRoot()
        return spotlightHotkeyIDs.contains { isHotkeyEntryEnabled(root[String($0)]) }
    }

    /// Reloads the window server's cached keyboard settings so the change takes effect
    /// now instead of at the next login. Blocking (~0.4 s) — background queues only.
    private nonisolated static func activateKeyboardSettings() {
        let path = "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
        guard FileManager.default.isExecutableFile(atPath: path) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-u"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            NSLog("SpotlightManager: activateSettings failed to launch: %@", error.localizedDescription)
            return
        }
        process.waitUntilExit()
    }

    /// Writes both Spotlight hotkey entries and verifies the result. Blocking.
    @discardableResult
    private nonisolated static func writeShortcut(enabled: Bool) -> Bool {
        let root = hotkeyRoot(readHotkeyRoot(), settingEnabled: enabled)
        CFPreferencesSetValue(hotkeyRootKey as CFString, root as CFDictionary, hotkeyDomain as CFString,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)

        guard CFPreferencesAppSynchronize(hotkeyDomain as CFString) else {
            NSLog("SpotlightManager: cfprefsd refused to synchronize %@", hotkeyDomain)
            return false
        }

        activateKeyboardSettings()

        // Read back through the daemon: this is the only honest success signal.
        let applied = probeShortcutEnabled() == enabled
        if !applied {
            NSLog("SpotlightManager: Spotlight shortcut did not reach enabled=%@", enabled ? "true" : "false")
        }
        return applied
    }

    /// Toggles the macOS Spotlight shortcuts (hotkey IDs 64 and 65).
    /// `completion` reports whether the system actually ended up in the requested
    /// state, so callers can tell the user the truth.
    static func setShortcut(enabled: Bool, completion: (@Sendable @MainActor (Bool) -> Void)? = nil) {
        cachedState.shortcutEnabled = enabled // optimistic; reconciled below

        DispatchQueue.global(qos: .userInitiated).async {
            let success = writeShortcut(enabled: enabled)
            let actual = probeShortcutEnabled()
            Task { @MainActor in
                cachedState.shortcutEnabled = actual
                persist(cachedState)
                completion?(success)
            }
        }
    }

    // MARK: - 2. Spotlight Background Service / Process (launchctl)

    nonisolated static let serviceLabel = "com.apple.Spotlight"
    nonisolated static let servicePlistPath = "/System/Library/LaunchAgents/com.apple.Spotlight.plist"

    /// The `launchctl` invocations that turn the agent off or back on, in order.
    ///
    /// `enable` on its own only clears the override. launchd skips a disabled agent at
    /// login, so after a logout or restart with Spotlight disabled the agent is not
    /// loaded at all, and it stays absent after `enable` (`kickstart` then fails with
    /// "Could not find service") until the next login. `bootstrap` loads it and
    /// `kickstart` starts it now, as uninstall.sh does. `bootstrap` fails when the
    /// agent is already loaded, which is the usual case, so only the first command's
    /// exit status counts and the outcome is verified by probing afterwards.
    nonisolated static func serviceCommands(enabled: Bool, uid: uid_t) -> [[String]] {
        let target = "gui/\(uid)/\(serviceLabel)"
        guard enabled else { return [["disable", target]] }
        return [
            ["enable", target],
            ["bootstrap", "gui/\(uid)", servicePlistPath],
            ["kickstart", target],
        ]
    }

    /// Runs `/bin/launchctl` with its output discarded. Blocking.
    @discardableResult
    private nonisolated static func runLaunchctl(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            NSLog("SpotlightManager: launchctl %@ failed to launch: %@", arguments.first ?? "", error.localizedDescription)
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// Whether launchd has the agent loaded in this login session. Blocking.
    private nonisolated static func probeServiceLoaded() -> Bool {
        runLaunchctl(["print", "gui/\(getuid())/\(serviceLabel)"])
    }

    /// Reads whether the Spotlight launchd service is disabled for the current user. Blocking (~66 ms).
    private nonisolated static func probeServiceDisabled() -> Bool {
        let uid = getuid()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print-disabled", "gui/\(uid)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            NSLog("SpotlightManager: launchctl print-disabled failed to launch: %@", error.localizedDescription)
            return false
        }

        // Drain before waiting: `print-disabled` output can exceed the pipe buffer
        // and would otherwise deadlock against waitUntilExit().
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""
        return output.contains("\"\(serviceLabel)\" => disabled")
    }

    /// Enables or disables the Spotlight launchd background process; enabling also
    /// loads and starts it (see `serviceCommands`). `completion` reports the verified
    /// outcome.
    static func setService(enabled: Bool, completion: (@Sendable @MainActor (Bool) -> Void)? = nil) {
        cachedState.serviceDisabled = !enabled // optimistic; reconciled below

        DispatchQueue.global(qos: .userInitiated).async {
            let commands = serviceCommands(enabled: enabled, uid: getuid())
            let launched = runLaunchctl(commands[0])
            for arguments in commands.dropFirst() {
                runLaunchctl(arguments)
            }

            if !enabled {
                let kill = Process()
                kill.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
                kill.arguments = ["Spotlight"]
                kill.standardOutput = FileHandle.nullDevice
                kill.standardError = FileHandle.nullDevice
                try? kill.run()
                kill.waitUntilExit()
            }

            let disabled = probeServiceDisabled()
            // Re-enabled but not loaded is the bug this guards: the flag reads right
            // and Spotlight is still gone until the next login.
            let success = launched && (disabled == !enabled) && (!enabled || probeServiceLoaded())
            Task { @MainActor in
                cachedState.serviceDisabled = disabled
                persist(cachedState)
                completion?(success)
            }
        }
    }

    /// Kills any active Spotlight GUI process
    static func killSpotlightProcess() {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            process.arguments = ["Spotlight"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
        }
    }

    // MARK: - 3. Spotlight File Indexing (mdutil)

    /// Reads whether filesystem indexing is enabled on the main volume. Blocking (~66 ms).
    private nonisolated static func probeIndexingEnabled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdutil")
        process.arguments = ["-s", "/"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            NSLog("SpotlightManager: mdutil failed to launch: %@", error.localizedDescription)
            return true
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""
        return output.localizedCaseInsensitiveContains("Indexing enabled")
    }

    /// Turns Spotlight file indexing on/off across all volumes (requires Admin / Touch ID)
    static func setIndexing(enabled: Bool, completion: @escaping @Sendable @MainActor (Bool) -> Void) {
        let flag = enabled ? "on" : "off"
        let script = "do shell script \"mdutil -a -i \(flag)\" with administrator privileges"

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            let success: Bool
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
                success = (error == nil)
            } else {
                success = false
            }
            Task { @MainActor in
                if success { cachedState.indexingEnabled = enabled }
                completion(success)
                refreshState()
            }
        }
    }

    // MARK: - 4. Master Control

    /// Overall status summary
    static var isSpotlightFullyDisabled: Bool {
        !isShortcutEnabled() && isServiceDisabled() && !isIndexingEnabled()
    }

    /// Disables shortcut, launchd service, and optionally file indexing.
    static func disableAll(includeIndexing: Bool, completion: (@Sendable @MainActor (ApplyResult) -> Void)? = nil) {
        apply(enabled: false, includeIndexing: includeIndexing, completion: completion)
    }

    /// Re-enables shortcut, launchd service, and optionally file indexing.
    static func enableAll(includeIndexing: Bool, completion: (@Sendable @MainActor (ApplyResult) -> Void)? = nil) {
        apply(enabled: true, includeIndexing: includeIndexing, completion: completion)
    }

    /// Runs the three toggles and reports each one's verified outcome once they have
    /// all landed. The shortcut and service writes run concurrently on their own
    /// queues; indexing is last because it raises an admin prompt.
    private static func apply(enabled: Bool,
                              includeIndexing: Bool,
                              completion: (@Sendable @MainActor (ApplyResult) -> Void)?) {
        let box = ResultBox()

        setShortcut(enabled: enabled) { success in
            box.shortcut = success
            finish(box, includeIndexing: includeIndexing, enabled: enabled, completion: completion)
        }
        setService(enabled: enabled) { success in
            box.service = success
            finish(box, includeIndexing: includeIndexing, enabled: enabled, completion: completion)
        }
    }

    /// Mutable only on the main actor, so the two completions above cannot race.
    @MainActor
    private final class ResultBox {
        var shortcut: Bool?
        var service: Bool?
        var indexingStarted = false
    }

    @MainActor
    private static func finish(_ box: ResultBox,
                               includeIndexing: Bool,
                               enabled: Bool,
                               completion: (@Sendable @MainActor (ApplyResult) -> Void)?) {
        guard let shortcut = box.shortcut, let service = box.service else { return }

        guard includeIndexing else {
            completion?(ApplyResult(shortcut: shortcut, service: service, indexing: nil))
            return
        }

        guard !box.indexingStarted else { return }
        box.indexingStarted = true
        setIndexing(enabled: enabled) { indexing in
            completion?(ApplyResult(shortcut: shortcut, service: service, indexing: indexing))
        }
    }

    /// Opens macOS System Settings -> Keyboard Shortcuts
    static func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            SystemSettingsOpener.open(url)
        }
    }
}
