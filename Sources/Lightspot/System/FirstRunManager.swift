import AppKit
import Foundation

@MainActor
public protocol FirstRunDelegate: AnyObject {
    func rebuildMenu()
    func showAlert(title: String, message: String)
    /// Claims ⌘Space once the system Spotlight shortcut has let go of it.
    func reclaimHotkeyIfFreed()
}

@MainActor
enum FirstRunManager {
    nonisolated static let userDefaultsKey = "lightspot_first_run_completed"

    /// Checks if this is the first run of the application.
    static var isFirstRun: Bool {
        !UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    /// Marks the first run as completed.
    static func markFirstRunCompleted() {
        UserDefaults.standard.set(true, forKey: userDefaultsKey)
    }

    /// Resets the first-run flag (useful for testing).
    static func resetFirstRunForTesting() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    /// Performs first-run onboarding if needed:
    /// 1. Auto-enables Launch at Login immediately.
    /// 2. Schedules a prompt suggesting the user disable Everything of system Spotlight.
    static func handleFirstRunIfNeeded(delegate: (any FirstRunDelegate)? = nil, promptDelay: TimeInterval = 0.3) {
        guard isFirstRun else { return }
        markFirstRunCompleted()

        // 1. Auto enable launch at login
        _ = AutoStartManager.setEnabled(true)
        delegate?.rebuildMenu()

        // 2. Suggest user disable Everything of system spotlight shortly after launch
        if promptDelay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + promptDelay) {
                promptDisableSpotlight(delegate: delegate)
            }
        } else if promptDelay == 0 {
            promptDisableSpotlight(delegate: delegate)
        }
    }

    /// Prompts the user with an alert suggesting to disable Everything of system Spotlight.
    static func promptDisableSpotlight(delegate: (any FirstRunDelegate)? = nil) {
        // Skip prompt if Spotlight is already fully disabled
        guard !SpotlightManager.isSpotlightFullyDisabled else { return }

        let alert = NSAlert()
        alert.messageText = "Disable System Spotlight?"
        alert.informativeText = """
        Lightspot works best when replacing Apple's built-in Spotlight (⌘Space).

        Would you like to "Disable Everything" (Spotlight ⌘Space shortcut, background service, and file indexing)?

        This reclaims CPU, RAM, and disk space, and reserves ⌘Space exclusively for Lightspot. You can restore default Spotlight settings at any time from the Lightspot menu bar.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Disable Everything")
        alert.addButton(withTitle: "Keep Spotlight")
        alert.window.level = .floating
        alert.window.center()
        alert.window.orderFrontRegardless()

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            SpotlightManager.disableAll(includeIndexing: true) { result in
                delegate?.reclaimHotkeyIfFreed()
                delegate?.rebuildMenu()
                let title = result.shortcut ? "Spotlight Fully Disabled" : "Spotlight Partially Disabled"
                let summaryMessage = summary(for: result)
                if let del = delegate {
                    del.showAlert(title: title, message: summaryMessage)
                } else {
                    let doneAlert = NSAlert()
                    doneAlert.messageText = title
                    doneAlert.informativeText = summaryMessage
                    doneAlert.alertStyle = .informational
                    doneAlert.addButton(withTitle: "OK")
                    doneAlert.window.level = .floating
                    doneAlert.window.center()
                    doneAlert.window.orderFrontRegardless()
                    doneAlert.runModal()
                }
            }
        }
    }

    /// Per-toggle outcome of the onboarding "Disable Everything" choice. Each flag is
    /// verified against the system, so a write macOS refused is reported as such
    /// instead of being announced as a success.
    nonisolated static func summary(for result: SpotlightManager.ApplyResult) -> String {
        var lines = [
            "1. \u{2318}Space Shortcut: " + (result.shortcut ? "Disabled" : "Unchanged (macOS refused)"),
            "2. Background Process: " + (result.service ? "Terminated & Disabled" : "Unchanged (launchctl refused)"),
        ]
        if let indexing = result.indexing {
            lines.append("3. File Indexing: " + (indexing ? "Disabled" : "Unchanged (Admin canceled)"))
        }
        let allDone = result.shortcut && result.service && (result.indexing ?? true)
        lines.append(allDone
            ? "\nLightspot is now your primary launcher!"
            : "\nYou can finish up by hand in Keyboard Shortcuts Settings.")
        return lines.joined(separator: "\n")
    }
}
