import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate, NSMenuItemValidation {
    private var statusItem: NSStatusItem?
    private weak var hotkeyManager: HotkeyManager?
    weak var viewModel: SearchViewModel?
    var onShowToggle: (() -> Void)?
    var onManageCustomCommands: (() -> Void)?
    var onManagePins: (() -> Void)?
    var onManageHistory: (() -> Void)?
    var onEnsurePanelVisible: (() -> Bool)?

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        return menuItem.isEnabled
    }

    /// The status menu reads SpotlightManager's cached snapshot, which is refreshed
    /// off the main thread. Kick a refresh as the menu opens so it self-corrects if
    /// the user changed Spotlight elsewhere; the rebuild lands a moment later.
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            SpotlightManager.refreshState { [weak self] in
                MainActor.assumeIsolated { self?.rebuildMenu() }
            }
            AutoStartManager.refreshState { [weak self] in
                MainActor.assumeIsolated { self?.rebuildMenu() }
            }
        }
    }

    func setup(hotkeyManager: HotkeyManager) {
        self.hotkeyManager = hotkeyManager
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "magnifyingglass",
                                   accessibilityDescription: "Lightspot")
            button.image?.size = NSSize(width: 16, height: 16)
        }

        updateStatusItemVisibility()
        rebuildMenu()
    }

    func rebuildMenu() {
        guard let menu = buildMenu() else { return }
        menu.delegate = self
        statusItem?.menu = menu
        viewModel?.objectWillChange.send()
    }

    func buildMenu(isForModal: Bool = false) -> NSMenu? {
        guard let hotkeyManager = hotkeyManager else { return nil }
        let currentOption = hotkeyManager.currentOption

        let menu = NSMenu()

        // 1. Show Lightspot (menu bar only)
        if !isForModal {
            let showItem = NSMenuItem(title: "Show Lightspot (\(currentOption.shortLabel))", action: #selector(showAction), keyEquivalent: "")
            showItem.target = self
            menu.addItem(showItem)
        }

        // 2. Category Navigation (modal only)
        if isForModal {
            let nextCatItem = NSMenuItem(title: "Next Category (Tab)", action: #selector(nextCategoryAction), keyEquivalent: "")
            nextCatItem.target = self
            menu.addItem(nextCatItem)

            let prevCatItem = NSMenuItem(title: "Previous Category (⇧Tab)", action: #selector(prevCategoryAction), keyEquivalent: "")
            prevCatItem.target = self
            menu.addItem(prevCatItem)
        }

        menu.addItem(NSMenuItem.separator())

        // 3. Custom Commands
        let customCommandsItem = NSMenuItem(title: "Custom Commands... (⌘⇧C)", action: #selector(manageCustomCommandsAction), keyEquivalent: "")
        customCommandsItem.target = self
        menu.addItem(customCommandsItem)

        menu.addItem(NSMenuItem.separator())

        // 4. Pinned Commands
        let pinnedItem = NSMenuItem(title: "Pinned Commands... (⌘⇧P)", action: #selector(managePinsAction), keyEquivalent: "")
        pinnedItem.target = self
        menu.addItem(pinnedItem)

        if isForModal {
            let pinTitle: String
            let pinEnabled: Bool
            if viewModel?.isPinManagerPresented == true {
                pinTitle = "Unpin Selected Command (⌘P)"
                pinEnabled = !(viewModel?.pinnedCommands.isEmpty ?? true)
            } else if let command = viewModel?.selectedCommand {
                let isPinned = PinnedCommandsStore.shared.isPinned(command)
                pinTitle = isPinned ? "Unpin Selected Command (⌘P)" : "Pin Selected Command (⌘P)"
                pinEnabled = true
            } else {
                pinTitle = "Pin / Unpin Selected Command (⌘P)"
                pinEnabled = false
            }
            let pinToggleItem = NSMenuItem(title: pinTitle, action: #selector(togglePinAction), keyEquivalent: "")
            pinToggleItem.target = self
            pinToggleItem.isEnabled = pinEnabled
            menu.addItem(pinToggleItem)
        }

        menu.addItem(NSMenuItem.separator())

        // 5. Search History
        let historyItem = NSMenuItem(title: "Search History... (⌘⇧H)", action: #selector(manageHistoryAction), keyEquivalent: "")
        historyItem.target = self
        menu.addItem(historyItem)

        let clearHistoryItem = NSMenuItem(title: "Clear Search History", action: #selector(clearHistoryAction), keyEquivalent: "")
        clearHistoryItem.target = self
        menu.addItem(clearHistoryItem)

        menu.addItem(NSMenuItem.separator())

        // 6. Shortcut submenu
        let shortcutMenu = NSMenu()
        for option in HotkeyOption.allCases {
            let item = NSMenuItem(title: option.displayName, action: #selector(selectHotkeyAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option
            item.state = (option == currentOption) ? .on : .off
            shortcutMenu.addItem(item)
        }

        let shortcutParentItem = NSMenuItem(title: "Shortcut (\(currentOption.shortLabel))", action: nil, keyEquivalent: "")
        shortcutParentItem.submenu = shortcutMenu
        menu.addItem(shortcutParentItem)

        // 7. Search Engine submenu
        let searchEngineMenu = NSMenu()
        let currentEngine = WebSearchProvider.shared.defaultEngine
        for option in SearchEngineOption.allCases {
            let item = NSMenuItem(title: option.displayName, action: #selector(selectSearchEngineAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option
            item.state = (option == currentEngine) ? .on : .off
            searchEngineMenu.addItem(item)
        }

        let searchEngineParentItem = NSMenuItem(title: "Search Engine", action: nil, keyEquivalent: "")
        searchEngineParentItem.submenu = searchEngineMenu
        menu.addItem(searchEngineParentItem)

        // 8. Browser History submenu
        let browserHistoryMenu = NSMenu()
        let currentHistoryLimit = BrowserIntegrationProvider.shared.historyLimitDays
        for option in BrowserHistoryDays.allCases {
            let item = NSMenuItem(title: option.displayName, action: #selector(selectBrowserHistoryAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option
            item.state = (option == currentHistoryLimit) ? .on : .off
            browserHistoryMenu.addItem(item)
        }

        let browserHistoryParentItem = NSMenuItem(title: "Browser History", action: nil, keyEquivalent: "")
        browserHistoryParentItem.submenu = browserHistoryMenu
        menu.addItem(browserHistoryParentItem)

        // 9. Terminal App submenu
        let terminalMenu = NSMenu()
        let currentTerminal = TerminalLauncher.currentTerminal
        for option in TerminalAppOption.installedOptions {
            let item = NSMenuItem(title: option.displayName, action: #selector(selectTerminalAppAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option
            item.state = (option == currentTerminal) ? .on : .off
            terminalMenu.addItem(item)
        }

        let terminalParentItem = NSMenuItem(title: "Terminal App", action: nil, keyEquivalent: "")
        terminalParentItem.submenu = terminalMenu
        menu.addItem(terminalParentItem)

        // 10. System Spotlight Management submenu
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

        // 11. Auto-start / Launch at Login toggle
        let isAutoStartOn = AutoStartManager.isEnabled
        let autoStartItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleAutoStartAction),
            keyEquivalent: ""
        )
        autoStartItem.target = self
        autoStartItem.state = isAutoStartOn ? .on : .off
        menu.addItem(autoStartItem)

        // 12. Hide Menu Bar Icon toggle
        let hideIconItem = NSMenuItem(
            title: isMenuBarIconHidden ? "Show Menu Bar Icon" : "Hide Menu Bar Icon",
            action: #selector(toggleHideMenuBarIconAction),
            keyEquivalent: ""
        )
        hideIconItem.target = self
        menu.addItem(hideIconItem)

        menu.addItem(NSMenuItem.separator())

        // 13. Export Settings...
        let exportItem = NSMenuItem(title: "Export Settings...", action: #selector(exportSettingsAction), keyEquivalent: "")
        exportItem.target = self
        menu.addItem(exportItem)

        // 14. Import Settings...
        let importItem = NSMenuItem(title: "Import Settings...", action: #selector(importSettingsAction), keyEquivalent: "")
        importItem.target = self
        menu.addItem(importItem)

        // 15. Clear Clipboard History
        let clearClipItem = NSMenuItem(title: "Clear Clipboard History", action: #selector(clearClipboardAction), keyEquivalent: "")
        clearClipItem.target = self
        menu.addItem(clearClipItem)

        menu.addItem(NSMenuItem.separator())

        if isForModal {
            let clearSearchItem = NSMenuItem(title: "Clear Search (Esc)", action: #selector(clearSearchAction), keyEquivalent: "")
            clearSearchItem.target = self
            clearSearchItem.isEnabled = !(viewModel?.query.isEmpty ?? true)
            menu.addItem(clearSearchItem)

            let closeItem = NSMenuItem(title: "Close Lightspot", action: #selector(closeAction), keyEquivalent: "")
            closeItem.target = self
            menu.addItem(closeItem)

            menu.addItem(NSMenuItem.separator())
        }

        // About Lightspot
        let aboutItem = NSMenuItem(title: "About Lightspot", action: #selector(aboutAction), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        // Quit Lightspot
        let quitItem = NSMenuItem(title: "Quit Lightspot", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private let hideIconDefaultsKey = "lightspot_hide_menubar_icon"

    var isMenuBarIconHidden: Bool {
        get { UserDefaults.standard.bool(forKey: hideIconDefaultsKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: hideIconDefaultsKey)
            updateStatusItemVisibility()
        }
    }

    func updateStatusItemVisibility() {
        statusItem?.isVisible = !isMenuBarIconHidden
    }

    @objc func toggleHideMenuBarIconAction() {
        isMenuBarIconHidden.toggle()
        rebuildMenu()
    }

    @objc private func toggleAutoStartAction() {
        _ = AutoStartManager.toggle()
        rebuildMenu()
    }

    @objc private func showAction() {
        onShowToggle?()
    }

    @objc private func closeAction() {
        viewModel?.onHide?()
    }

    @objc private func nextCategoryAction() {
        if onEnsurePanelVisible?() != true {
            onShowToggle?()
        }
        viewModel?.nextCategory()
    }

    @objc private func prevCategoryAction() {
        if onEnsurePanelVisible?() != true {
            onShowToggle?()
        }
        viewModel?.previousCategory()
    }

    @objc private func togglePinAction() {
        viewModel?.togglePinForSelection()
    }

    @objc private func clearHistoryAction() {
        viewModel?.clearAllHistory()
    }

    @objc private func clearSearchAction() {
        viewModel?.clearSearch()
    }
    @objc private func manageCustomCommandsAction() {
        onManageCustomCommands?()
    }

    @objc private func managePinsAction() {
        onManagePins?()
    }

    @objc private func manageHistoryAction() {
        onManageHistory?()
    }

    @objc private func exportSettingsAction() {
        SettingsBackupController.shared.exportSettings()
    }

    @objc private func importSettingsAction() {
        SettingsBackupController.shared.importSettings()
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

    @objc private func selectSearchEngineAction(_ sender: NSMenuItem) {
        guard let option = sender.representedObject as? SearchEngineOption else { return }
        WebSearchProvider.shared.defaultEngine = option
        rebuildMenu()
    }

    @objc private func selectBrowserHistoryAction(_ sender: NSMenuItem) {
        guard let option = sender.representedObject as? BrowserHistoryDays else { return }
        BrowserIntegrationProvider.shared.historyLimitDays = option
        rebuildMenu()
    }

    @objc private func selectTerminalAppAction(_ sender: NSMenuItem) {
        guard let option = sender.representedObject as? TerminalAppOption else { return }
        TerminalLauncher.currentTerminal = option
        rebuildMenu()
    }

    @objc private func clearClipboardAction() {
        ClipboardHistoryManager.shared.clearHistory()
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
        alert.window.level = .floating
        alert.window.center()
        alert.window.orderFrontRegardless()

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            SpotlightManager.setShortcut(enabled: false)
            rebuildMenu()
        } else if response == .alertSecondButtonReturn {
            openKeyboardSettingsAction()
        }
    }

    func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.window.level = .floating
        alert.window.center()
        alert.window.orderFrontRegardless()
        alert.runModal()
    }

    @objc func aboutAction() {
        showAbout()
    }

    func showAbout() {
        NSApp.activate(ignoringOtherApps: true)

        let currentOption = hotkeyManager?.currentOption.shortLabel ?? "⌘Space"
        let shortcutStatus = SpotlightManager.isShortcutEnabled() ? "Active" : "Disabled"
        let indexingStatus = SpotlightManager.isIndexingEnabled() ? "Active" : "Disabled"
        let processStatus = SpotlightManager.isServiceDisabled() ? "Disabled" : "Active"

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

        let alert = NSAlert()
        alert.messageText = "Lightspot"
        alert.informativeText = """
        A lightweight Spotlight replacement for macOS.

        Version: \(appVersion)
        Hotkey: \(currentOption)

        macOS Spotlight Status:
        • Shortcut (⌘Space): \(shortcutStatus)
        • Background Process: \(processStatus)
        • File Indexing: \(indexingStatus)
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.window.level = .floating
        alert.window.center()
        alert.window.orderFrontRegardless()
        alert.runModal()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
}

extension MenuBarController: FirstRunDelegate {}

