import AppKit
import Foundation

enum SpotlightManager {
    private static let plistPath = ("~/Library/Preferences/com.apple.symbolichotkeys.plist" as NSString).expandingTildeInPath

    /// Checks if the default macOS Spotlight shortcut (hotkey ID 64) is enabled
    static func isSystemSpotlightShortcutEnabled() -> Bool {
        guard let dict = NSDictionary(contentsOfFile: plistPath) as? [String: Any],
              let hotkeys = dict["AppleSymbolicHotKeys"] as? [String: Any],
              let entry64 = hotkeys["64"] as? [String: Any],
              let enabled = entry64["enabled"] as? Bool else {
            return true
        }
        return enabled
    }

    /// Toggles the default macOS Spotlight shortcut (hotkey ID 64)
    static func setSystemSpotlightShortcut(enabled: Bool) {
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

    /// Opens macOS System Settings -> Keyboard Shortcuts
    static func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
