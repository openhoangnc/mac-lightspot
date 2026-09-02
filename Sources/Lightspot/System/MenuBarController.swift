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
        let isSystemSpotlightOn = SpotlightManager.isSystemSpotlightShortcutEnabled()

        let toggleItem = NSMenuItem(
            title: isSystemSpotlightOn ? "Disable System Spotlight Shortcut (⌘Space)" : "Enable System Spotlight Shortcut (⌘Space)",
            action: #selector(toggleSystemSpotlightAction),
            keyEquivalent: ""
        )
        toggleItem.target = self
        spotlightMenu.addItem(toggleItem)

        let statusItemDesc = NSMenuItem(
            title: "Status: " + (isSystemSpotlightOn ? "Enabled" : "Disabled (Lightspot Ready)"),
            action: nil,
            keyEquivalent: ""
        )
        statusItemDesc.isEnabled = false
        spotlightMenu.addItem(statusItemDesc)

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

        if option == .commandSpace && SpotlightManager.isSystemSpotlightShortcutEnabled() {
            promptSpotlightDisablingGuide()
        }
    }

    @objc private func toggleSystemSpotlightAction() {
        let currentlyEnabled = SpotlightManager.isSystemSpotlightShortcutEnabled()
        SpotlightManager.setSystemSpotlightShortcut(enabled: !currentlyEnabled)
        rebuildMenu()

        let alert = NSAlert()
        alert.messageText = !currentlyEnabled ? "System Spotlight Shortcut Enabled" : "System Spotlight Shortcut Disabled"
        alert.informativeText = !currentlyEnabled
            ? "The macOS built-in Spotlight shortcut (⌘Space) has been re-enabled."
            : "The macOS built-in Spotlight shortcut (⌘Space) has been disabled. ⌘Space is now exclusively reserved for Lightspot!"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
            SpotlightManager.setSystemSpotlightShortcut(enabled: false)
            rebuildMenu()
        } else if response == .alertSecondButtonReturn {
            openKeyboardSettingsAction()
        }
    }

    @objc private func aboutAction() {
        let currentOption = hotkeyManager?.currentOption.shortLabel ?? "⌘Space"
        let isSystemSpotlightOn = SpotlightManager.isSystemSpotlightShortcutEnabled()
        let spotlightStatus = isSystemSpotlightOn ? "Enabled" : "Disabled"

        let alert = NSAlert()
        alert.messageText = "Lightspot"
        alert.informativeText = "A lightweight Spotlight replacement for macOS.\n\nVersion 1.0.0\n\nCurrent Hotkey: \(currentOption)\nSystem Spotlight: \(spotlightStatus)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
}
