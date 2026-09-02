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

        shortcutMenu.addItem(NSMenuItem.separator())
        let sysPrefItem = NSMenuItem(title: "Disable macOS Spotlight Shortcut...", action: #selector(openKeyboardSettingsAction), keyEquivalent: "")
        sysPrefItem.target = self
        shortcutMenu.addItem(sysPrefItem)

        let shortcutParentItem = NSMenuItem(title: "Shortcut", action: nil, keyEquivalent: "")
        shortcutParentItem.submenu = shortcutMenu
        menu.addItem(shortcutParentItem)

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

        if option == .commandSpace {
            promptSpotlightDisablingGuide()
        }
    }

    @objc private func openKeyboardSettingsAction() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func promptSpotlightDisablingGuide() {
        let alert = NSAlert()
        alert.messageText = "Using ⌘Space as Lightspot Shortcut"
        alert.informativeText = "To use Command+Space for Lightspot, make sure to disable or rebind the default macOS Spotlight shortcut in:\n\nSystem Settings → Keyboard → Keyboard Shortcuts → Spotlight → Uncheck 'Show Spotlight search'."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Keyboard Settings")
        alert.addButton(withTitle: "OK")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openKeyboardSettingsAction()
        }
    }

    @objc private func aboutAction() {
        let currentOption = hotkeyManager?.currentOption.shortLabel ?? "⌘Space"
        let alert = NSAlert()
        alert.messageText = "Lightspot"
        alert.informativeText = "A lightweight Spotlight replacement for macOS.\n\nVersion 1.0.0\n\nCurrent Hotkey: \(currentOption)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
}
