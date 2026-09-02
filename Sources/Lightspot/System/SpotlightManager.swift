import AppKit
import Foundation

@MainActor
enum SpotlightManager {
    private nonisolated static let plistPath = ("~/Library/Preferences/com.apple.symbolichotkeys.plist" as NSString).expandingTildeInPath

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

    /// Reads whether the default macOS Spotlight shortcut (hotkey ID 64) is enabled. Blocking.
    private nonisolated static func probeShortcutEnabled() -> Bool {
        guard let dict = NSDictionary(contentsOfFile: plistPath) as? [String: Any],
              let hotkeys = dict["AppleSymbolicHotKeys"] as? [String: Any],
              let entry64 = hotkeys["64"] as? [String: Any],
              let enabled = entry64["enabled"] as? Bool else {
            return true
        }
        return enabled
    }

    /// Toggles the default macOS Spotlight shortcut (hotkey ID 64)
    static func setShortcut(enabled: Bool) {
        cachedState.shortcutEnabled = enabled // optimistic; refreshState() reconciles

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/libexec/PlistBuddy")
            process.arguments = ["-c", "Set :AppleSymbolicHotKeys:64:enabled \(enabled)", plistPath]
            try? process.run()
            process.waitUntilExit()

            // Sync defaults so macOS picks up preference changes
            let syncProcess = Process()
            syncProcess.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            syncProcess.arguments = ["read", "com.apple.symbolichotkeys"]
            try? syncProcess.run()
            syncProcess.waitUntilExit()
        }
    }

    // MARK: - 2. Spotlight Background Service / Process (launchctl)

    /// Reads whether the Spotlight launchd service is disabled for the current user. Blocking (~66 ms).
    private nonisolated static func probeServiceDisabled() -> Bool {
        let uid = getuid()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print-disabled", "gui/\(uid)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()

        // Drain before waiting: `print-disabled` output can exceed the pipe buffer
        // and would otherwise deadlock against waitUntilExit().
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""
        return output.contains("\"com.apple.Spotlight\" => disabled")
    }

    /// Enables or disables the Spotlight launchd background process
    static func setService(enabled: Bool) {
        cachedState.serviceDisabled = !enabled // optimistic; refreshState() reconciles

        DispatchQueue.global(qos: .userInitiated).async {
            let uid = getuid()
            let action = enabled ? "enable" : "disable"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = [action, "gui/\(uid)/com.apple.Spotlight"]
            try? process.run()
            process.waitUntilExit()

            if !enabled {
                let kill = Process()
                kill.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
                kill.arguments = ["Spotlight"]
                try? kill.run()
            }
        }
    }

    /// Kills any active Spotlight GUI process
    static func killSpotlightProcess() {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            process.arguments = ["Spotlight"]
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
        try? process.run()

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

    /// Disables shortcut, launchd service, and optionally initiates indexing disable
    static func disableAll(includeIndexing: Bool, completion: (@Sendable @MainActor (Bool) -> Void)? = nil) {
        setShortcut(enabled: false)
        setService(enabled: false)

        if includeIndexing {
            setIndexing(enabled: false) { success in
                completion?(success)
            }
        } else {
            completion?(true)
        }
    }

    /// Re-enables shortcut, launchd service, and optionally indexing
    static func enableAll(includeIndexing: Bool, completion: (@Sendable @MainActor (Bool) -> Void)? = nil) {
        setShortcut(enabled: true)
        setService(enabled: true)

        if includeIndexing {
            setIndexing(enabled: true) { success in
                completion?(success)
            }
        } else {
            completion?(true)
        }
    }

    /// Opens macOS System Settings -> Keyboard Shortcuts
    static func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
