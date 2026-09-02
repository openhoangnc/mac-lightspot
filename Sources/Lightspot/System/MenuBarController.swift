import AppKit

@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem?
    private weak var hotkeyManager: HotkeyManager?
    var onShowToggle: (() -> Void)?

    func setup(hotkeyManager: HotkeyManager) {
        self.hotkeyManager = hotkeyManager
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "magnifyingglass",
                                   accessibilityDescription: "Lightspot")
            button.image?.size = NSSize(width: 16, height: 16)
        }

        rebuildMenu()
    }

    func rebuildMenu() {
        guard let hotkeyManager = hotkeyManager else { return }
        let currentOption = hotkeyManager.currentOption

        let menu = NSMenu()

        let showItem = NSMenuItem(title: "Show Lightspot (\(currentOption.shortLabel))", action: #selector(showAction), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(NSMenuItem.separator())

        // Shortcut submenu
        let shortcutMenu = NSMenu()
        for option in HotkeyOption.allCases {
            let item = NSMenuItem(title: option.displayName, action: #selector(selectHotkeyAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option
            item.state = (option == currentOption) ? .on : .off
            shortcutMenu.addItem(item)
        }

        let shortcutParentItem = NSMenuItem(title: "Shortcut", action: nil, keyEquivalent: "")
        shortcutParentItem.submenu = shortcutMenu
        menu.addItem(shortcutParentItem)

        // System Spotlight Management submenu
        let spotlightMenu = NSMenu()
        let isShortcutOn = SpotlightManager.isShortcutEnabled()
        let isServiceDisabled = SpotlightManager.isServiceDisabled()
        let isIndexingOn = SpotlightManager.isIndexingEnabled()

        // 1. Shortcut toggle
        let shortcutToggle = NSMenuItem(
            title: isShortcutOn ? "Disable Spotlight Shortcut (⌘Space)" : "Enable Spotlight Shortcut (⌘Space)",
            action: #selector(toggleShortcutAction),
            keyEquivalent: ""
        )
        shortcutToggle.target = self
        spotlightMenu.addItem(shortcutToggle)

        // 2. Process / Service toggle
        let serviceToggle = NSMenuItem(
            title: isServiceDisabled ? "Enable Spotlight Process (launchctl)" : "Disable Spotlight Process (launchctl)",
            action: #selector(toggleServiceAction),
            keyEquivalent: ""
        )
        serviceToggle.target = self
        spotlightMenu.addItem(serviceToggle)

        // 3. File Indexing toggle
        let indexingToggle = NSMenuItem(
            title: isIndexingOn ? "Disable File Indexing (mdutil)..." : "Enable File Indexing (mdutil)...",
            action: #selector(toggleIndexingAction),
            keyEquivalent: ""
        )
        indexingToggle.target = self
        spotlightMenu.addItem(indexingToggle)

        spotlightMenu.addItem(NSMenuItem.separator())

        // Status Summary Item
        let statusTitle = "Status: Shortcut " + (isShortcutOn ? "ON" : "OFF") +
                          ", Process " + (isServiceDisabled ? "OFF" : "ON") +
                          ", Indexing " + (isIndexingOn ? "ON" : "OFF")
        let statusSummary = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusSummary.isEnabled = false
        spotlightMenu.addItem(statusSummary)

        spotlightMenu.addItem(NSMenuItem.separator())

        // 4. Master actions
        let disableAllItem = NSMenuItem(
            title: "Disable Everything (Shortcut + Process + Indexing)...",
            action: #selector(disableAllAction),
            keyEquivalent: ""
        )
        disableAllItem.target = self
        spotlightMenu.addItem(disableAllItem)

        let enableAllItem = NSMenuItem(
            title: "Restore Default Spotlight...",
            action: #selector(enableAllAction),
            keyEquivalent: ""
        )
        enableAllItem.target = self
        spotlightMenu.addItem(enableAllItem)

        spotlightMenu.addItem(NSMenuItem.separator())
        let sysPrefItem = NSMenuItem(title: "Open Keyboard Shortcuts Settings...", action: #selector(openKeyboardSettingsAction), keyEquivalent: "")
        sysPrefItem.target = self
        spotlightMenu.addItem(sysPrefItem)

        let spotlightParentItem = NSMenuItem(title: "System Spotlight", action: nil, keyEquivalent: "")
        spotlightParentItem.submenu = spotlightMenu
        menu.addItem(spotlightParentItem)

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: "About Lightspot", action: #selector(aboutAction), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Lightspot", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func showAction() {
        onShowToggle?()
    }

    @objc private func selectHotkeyAction(_ sender: NSMenuItem) {
        guard let option = sender.representedObject as? HotkeyOption,
              let hotkeyManager = hotkeyManager else { return }
        hotkeyManager.currentOption = option
        rebuildMenu()

        if option == .commandSpace && SpotlightManager.isShortcutEnabled() {
            promptSpotlightDisablingGuide()
        }
    }

    @objc private func toggleShortcutAction() {
        let currentlyEnabled = SpotlightManager.isShortcutEnabled()
        SpotlightManager.setShortcut(enabled: !currentlyEnabled)
        rebuildMenu()

        showAlert(
            title: !currentlyEnabled ? "Spotlight Shortcut Enabled" : "Spotlight Shortcut Disabled",
            message: !currentlyEnabled
                ? "The macOS built-in Spotlight shortcut (⌘Space) has been re-enabled."
                : "The macOS built-in Spotlight shortcut (⌘Space) has been disabled. ⌘Space is now reserved for Lightspot!"
        )
    }

    @objc private func toggleServiceAction() {
        let isCurrentlyDisabled = SpotlightManager.isServiceDisabled()
        SpotlightManager.setService(enabled: isCurrentlyDisabled)
        rebuildMenu()

        showAlert(
            title: isCurrentlyDisabled ? "Spotlight Process Enabled" : "Spotlight Process Disabled",
            message: isCurrentlyDisabled
                ? "The Spotlight launchd background process has been re-enabled."
                : "The Spotlight launchd background process has been disabled and terminated."
        )
    }

    @objc private func toggleIndexingAction() {
        let isCurrentlyOn = SpotlightManager.isIndexingEnabled()
        let targetState = !isCurrentlyOn

        SpotlightManager.setIndexing(enabled: targetState) { [weak self] success in
            self?.rebuildMenu()
            if success {
                self?.showAlert(
                    title: targetState ? "Spotlight Indexing Enabled" : "Spotlight Indexing Disabled",
                    message: targetState
                        ? "Spotlight filesystem indexing has been turned back on."
                        : "Spotlight filesystem indexing (mdutil) has been turned off across all volumes, freeing background CPU and disk resources."
                )
            } else {
                self?.showAlert(
                    title: "Authentication Required",
                    message: "Changing Spotlight indexing requires administrator privileges."
                )
            }
        }
    }

    @objc private func disableAllAction() {
        SpotlightManager.disableAll(includeIndexing: true) { [weak self] success in
            self?.rebuildMenu()
            self?.showAlert(
                title: "Spotlight Fully Disabled",
                message: "1. ⌘Space Shortcut: Disabled\n2. Background Process: Terminated & Disabled\n3. File Indexing: " + (success ? "Disabled" : "Unchanged (Admin canceled)") + "\n\nLightspot is now your primary launcher!"
            )
        }
    }

    @objc private func enableAllAction() {
        SpotlightManager.enableAll(includeIndexing: true) { [weak self] _ in
            self?.rebuildMenu()
            self?.showAlert(
                title: "Spotlight Restored",
                message: "Default macOS Spotlight shortcut, background service, and file indexing have been re-enabled."
            )
        }
    }

    @objc private func openKeyboardSettingsAction() {
        SpotlightManager.openKeyboardSettings()
    }

    private func promptSpotlightDisablingGuide() {
        let alert = NSAlert()
        alert.messageText = "Using ⌘Space as Lightspot Shortcut"
        alert.informativeText = "System Spotlight is currently enabled. Would you like Lightspot to disable the system Spotlight shortcut for you?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Disable System Spotlight")
        alert.addButton(withTitle: "Open Keyboard Settings")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            SpotlightManager.setShortcut(enabled: false)
            rebuildMenu()
        } else if response == .alertSecondButtonReturn {
            openKeyboardSettingsAction()
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func aboutAction() {
        let currentOption = hotkeyManager?.currentOption.shortLabel ?? "⌘Space"
        let shortcutStatus = SpotlightManager.isShortcutEnabled() ? "Active" : "Disabled"
        let indexingStatus = SpotlightManager.isIndexingEnabled() ? "Active" : "Disabled"
        let processStatus = SpotlightManager.isServiceDisabled() ? "Disabled" : "Active"

        let alert = NSAlert()
        alert.messageText = "Lightspot"
        alert.informativeText = """
        A lightweight Spotlight replacement for macOS.

        Version: 1.0.0
        Hotkey: \(currentOption)

        macOS Spotlight Status:
        • Shortcut (⌘Space): \(shortcutStatus)
        • Background Process: \(processStatus)
        • File Indexing: \(indexingStatus)
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
}
