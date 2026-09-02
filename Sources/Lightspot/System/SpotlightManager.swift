import AppKit
import Foundation

@MainActor
enum SpotlightManager {
    private static let plistPath = ("~/Library/Preferences/com.apple.symbolichotkeys.plist" as NSString).expandingTildeInPath

    // MARK: - 1. Spotlight Shortcut (⌘Space)

    /// Checks if the default macOS Spotlight shortcut (hotkey ID 64) is enabled
    static func isShortcutEnabled() -> Bool {
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

    // MARK: - 2. Spotlight Background Service / Process (launchctl)

    /// Checks if the Spotlight launchd service is disabled for current user
    static func isServiceDisabled() -> Bool {
        let uid = getuid()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print-disabled", "gui/\(uid)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.contains("\"com.apple.Spotlight\" => disabled")
    }

    /// Enables or disables the Spotlight launchd background process
    static func setService(enabled: Bool) {
        let uid = getuid()
        let action = enabled ? "enable" : "disable"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = [action, "gui/\(uid)/com.apple.Spotlight"]
        try? process.run()
        process.waitUntilExit()

        if !enabled {
            killSpotlightProcess()
        }
    }

    /// Kills any active Spotlight GUI process
    static func killSpotlightProcess() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Spotlight"]
        try? process.run()
    }

    // MARK: - 3. Spotlight File Indexing (mdutil)

    /// Checks if filesystem indexing is enabled on the main volume
    static func isIndexingEnabled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdutil")
        process.arguments = ["-s", "/"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
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
                completion(success)
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
