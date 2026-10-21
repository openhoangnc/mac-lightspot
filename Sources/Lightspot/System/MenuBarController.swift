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
    var onOpenCleaner: (() -> Void)?
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
            UpdateManager.shared.checkAutomaticallyIfDue { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuildMenu() }
            }
            SystemShortcutConflicts.refresh { [weak self] in
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
        SystemShortcutConflicts.refresh { [weak self] in
            MainActor.assumeIsolated { self?.rebuildMenu() }
        }
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

        // 6. Clean Dev Mac (cdm)
        let cleanerItem = NSMenuItem(title: "Clean Dev Mac...", action: #selector(openCleanerAction), keyEquivalent: "")
        cleanerItem.target = self
        menu.addItem(cleanerItem)

        menu.addItem(NSMenuItem.separator())

        // 7. Shortcut submenu
        //
        // A combination macOS already binds still registers and still opens the panel,
        // so the only symptom is the system shortcut firing too (⌃Space switches the
        // input source). The titles carry that, read from a cached snapshot because
        // menu content is rebuilt on every body pass.
        let shortcutMenu = NSMenu()
        for option in HotkeyOption.allCases {
            let title = SystemShortcutConflicts.cachedConflict(for: option)
                .map { "\(option.displayName) — \($0.note)" } ?? option.displayName
            let item = NSMenuItem(title: title, action: #selector(selectHotkeyAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option
            item.state = (option == currentOption) ? .on : .off
            shortcutMenu.addItem(item)
        }

        let activeConflict = SystemShortcutConflicts.cachedConflict(for: currentOption)
        if let conflict = activeConflict {
            shortcutMenu.addItem(NSMenuItem.separator())
            let noteItem = NSMenuItem(title: "macOS also uses \(currentOption.shortLabel) for “\(conflict.name)”",
                                      action: nil, keyEquivalent: "")
            noteItem.isEnabled = false
            shortcutMenu.addItem(noteItem)

            let settingsItem = NSMenuItem(title: "Open Keyboard Shortcuts Settings...",
                                          action: #selector(openKeyboardSettingsAction), keyEquivalent: "")
            settingsItem.target = self
            shortcutMenu.addItem(settingsItem)
        }

        let shortcutTitle = activeConflict == nil
            ? "Shortcut (\(currentOption.shortLabel))"
            : "Shortcut (\(currentOption.shortLabel)) ⚠︎"
        let shortcutParentItem = NSMenuItem(title: shortcutTitle, action: nil, keyEquivalent: "")
        shortcutParentItem.submenu = shortcutMenu
        menu.addItem(shortcutParentItem)

        // 8. Search Engine submenu
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

        // 9. Browser History submenu
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

        // 10. Terminal App submenu
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

        // 11. System Spotlight Management submenu
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

        // 12. Auto-start / Launch at Login toggle
        let isAutoStartOn = AutoStartManager.isEnabled
        let autoStartItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleAutoStartAction),
            keyEquivalent: ""
        )
        autoStartItem.target = self
        autoStartItem.state = isAutoStartOn ? .on : .off
        menu.addItem(autoStartItem)

        // 13. Hide Menu Bar Icon toggle
        let hideIconItem = NSMenuItem(
            title: isMenuBarIconHidden ? "Show Menu Bar Icon" : "Hide Menu Bar Icon",
            action: #selector(toggleHideMenuBarIconAction),
            keyEquivalent: ""
        )
        hideIconItem.target = self
        menu.addItem(hideIconItem)

        menu.addItem(NSMenuItem.separator())

        // 14. Export Settings...
        let exportItem = NSMenuItem(title: "Export Settings...", action: #selector(exportSettingsAction), keyEquivalent: "")
        exportItem.target = self
        menu.addItem(exportItem)

        // 15. Import Settings...
        let importItem = NSMenuItem(title: "Import Settings...", action: #selector(importSettingsAction), keyEquivalent: "")
        importItem.target = self
        menu.addItem(importItem)

        // 16. Clear Clipboard History
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

        // 17. Software Update
        let updater = UpdateManager.shared
        if updater.hasPromptableUpdate, let pending = updater.availableUpdate {
            let updateItem = NSMenuItem(title: "Update to \(pending.displayVersion)...",
                                        action: #selector(installUpdateAction),
                                        keyEquivalent: "")
            updateItem.target = self
            menu.addItem(updateItem)
        }

        let checkUpdateItem = NSMenuItem(
            title: updater.isChecking ? "Checking for Updates..." : "Check for Updates...",
            action: #selector(checkForUpdatesAction),
            keyEquivalent: ""
        )
        checkUpdateItem.target = self
        checkUpdateItem.isEnabled = !updater.isChecking && !updater.isInstalling
        menu.addItem(checkUpdateItem)

        let autoUpdateItem = NSMenuItem(title: "Automatically Check for Updates",
                                        action: #selector(toggleAutoUpdateAction),
                                        keyEquivalent: "")
        autoUpdateItem.target = self
        autoUpdateItem.state = updater.isAutomaticEnabled ? .on : .off
        menu.addItem(autoUpdateItem)

        menu.addItem(NSMenuItem.separator())

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

    @objc private func openCleanerAction() {
        onOpenCleaner?()
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
        let target = !SpotlightManager.isShortcutEnabled()

        SpotlightManager.setShortcut(enabled: target) { [weak self] success in
            guard let self = self else { return }
            self.reclaimHotkeyIfFreed()
            self.rebuildMenu()

            guard success else {
                self.showAlert(title: "Could Not Change Spotlight Shortcut",
                               message: Self.shortcutFailureMessage)
                return
            }

            self.showAlert(
                title: target ? "Spotlight Shortcut Enabled" : "Spotlight Shortcut Disabled",
                message: target
                    ? "The macOS built-in Spotlight shortcut (⌘Space and ⌥⌘Space) has been re-enabled."
                    : "The macOS built-in Spotlight shortcut (⌘Space and ⌥⌘Space) has been disabled. ⌘Space is now reserved for Lightspot!"
            )
        }
    }

    /// Shown whenever a shortcut write does not survive its read-back. The write goes
    /// through cfprefsd and is verified, so a failure here is a real refusal rather
    /// than the silent no-op this used to report as success.
    private static let shortcutFailureMessage = """
    macOS did not accept the change to its Spotlight shortcut.

    Open Keyboard Shortcuts Settings and clear "Show Spotlight search" and "Show Finder search window" under Spotlight by hand, then choose ⌘Space again here.
    """

    /// Carbon grants a key combination to one owner. If Lightspot lost ⌘Space at launch
    /// because the system Spotlight shortcut still held it, claim it now that it is free.
    func reclaimHotkeyIfFreed() {
        guard let hotkeyManager = hotkeyManager, !hotkeyManager.isRegistered else { return }
        guard !SpotlightManager.isShortcutEnabled() else { return }
        hotkeyManager.reRegisterIfNeeded()
    }

    @objc private func toggleServiceAction() {
        let target = SpotlightManager.isServiceDisabled()

        SpotlightManager.setService(enabled: target) { [weak self] success in
            guard let self = self else { return }
            self.rebuildMenu()

            guard success else {
                self.showAlert(
                    title: "Could Not Change Spotlight Process",
                    message: target
                        ? "launchctl could not enable and start com.apple.Spotlight for this user."
                        : "launchctl refused to disable com.apple.Spotlight for this user."
                )
                return
            }

            self.showAlert(
                title: target ? "Spotlight Process Enabled" : "Spotlight Process Disabled",
                message: target
                    ? "The Spotlight launchd background process has been re-enabled and started."
                    : "The Spotlight launchd background process has been disabled and terminated."
            )
        }
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
        SpotlightManager.disableAll(includeIndexing: true) { [weak self] result in
            guard let self = self else { return }
            self.reclaimHotkeyIfFreed()
            self.rebuildMenu()
            self.showAlert(
                title: result.shortcut ? "Spotlight Fully Disabled" : "Spotlight Partially Disabled",
                message: Self.summary(for: result, disabling: true)
            )
        }
    }

    @objc private func enableAllAction() {
        SpotlightManager.enableAll(includeIndexing: true) { [weak self] result in
            guard let self = self else { return }
            self.rebuildMenu()
            self.showAlert(
                title: result.shortcut ? "Spotlight Restored" : "Spotlight Partially Restored",
                message: Self.summary(for: result, disabling: false)
            )
        }
    }

    /// Reports each toggle's verified outcome. The old copy claimed all three had
    /// changed whenever the indexing prompt was accepted, which hid a shortcut write
    /// that never landed.
    static func summary(for result: SpotlightManager.ApplyResult, disabling: Bool) -> String {
        let done = disabling ? "Disabled" : "Enabled"
        var lines = [
            "1. ⌘Space Shortcut: " + (result.shortcut ? done : "Unchanged (macOS refused)"),
            "2. Background Process: " + (result.service ? done : "Unchanged (launchctl refused)"),
        ]
        if let indexing = result.indexing {
            lines.append("3. File Indexing: " + (indexing ? done : "Unchanged (Admin canceled)"))
        }

        let allDone = result.shortcut && result.service && (result.indexing ?? true)
        if disabling {
            lines.append(allDone
                ? "\nLightspot is now your primary launcher!"
                : "\n" + shortcutFailureMessage)
        } else {
            lines.append(allDone
                ? "\nDefault macOS Spotlight behaviour has been restored."
                : "\nSome settings could not be restored automatically — check Keyboard Shortcuts Settings.")
        }
        return lines.joined(separator: "\n")
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
            SpotlightManager.setShortcut(enabled: false) { [weak self] success in
                guard let self = self else { return }
                self.reclaimHotkeyIfFreed()
                self.rebuildMenu()
                if !success {
                    self.showAlert(title: "Could Not Change Spotlight Shortcut",
                                   message: Self.shortcutFailureMessage)
                }
            }
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

    /// Called shortly after launch when Carbon refused the key combination. Something
    /// else already owns it — on a stock Mac that is the system Spotlight shortcut,
    /// and the symptom is simply that the panel never opens.
    func presentHotkeyConflictIfNeeded() {
        guard let hotkeyManager = hotkeyManager else { return }

        // The owner may have gone away since launch; a retry is free.
        if hotkeyManager.reRegisterIfNeeded() {
            rebuildMenu()
            return
        }

        let combination = hotkeyManager.currentOption.shortLabel
        let spotlightHoldsIt = SpotlightManager.isShortcutEnabled()

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "\(combination) Is Already Taken"
        alert.informativeText = spotlightHoldsIt
            ? "macOS still has its own Spotlight shortcut registered, so Lightspot could not claim \(combination).\n\nDisable the system Spotlight shortcut to hand \(combination) to Lightspot."
            : "Another app has registered \(combination), so Lightspot could not claim it.\n\nQuit that app or pick a different shortcut from the Lightspot menu."
        alert.alertStyle = .warning
        if spotlightHoldsIt {
            alert.addButton(withTitle: "Disable System Spotlight Shortcut")
        }
        alert.addButton(withTitle: "Open Keyboard Shortcuts Settings")
        alert.addButton(withTitle: "Later")
        alert.window.level = .floating
        alert.window.center()
        alert.window.orderFrontRegardless()

        let response = alert.runModal()
        if spotlightHoldsIt, response == .alertFirstButtonReturn {
            SpotlightManager.setShortcut(enabled: false) { [weak self] success in
                guard let self = self else { return }
                let claimed = self.hotkeyManager?.reRegisterIfNeeded() ?? false
                self.rebuildMenu()
                if !success {
                    self.showAlert(title: "Could Not Change Spotlight Shortcut",
                                   message: Self.shortcutFailureMessage)
                } else if !claimed {
                    self.showAlert(
                        title: "\(combination) Still Unavailable",
                        message: "The system Spotlight shortcut is off, but another app is holding \(combination). Pick a different shortcut from the Lightspot menu."
                    )
                }
            }
        } else if response == (spotlightHoldsIt ? .alertSecondButtonReturn : .alertFirstButtonReturn) {
            openKeyboardSettingsAction()
        }
    }

    // MARK: - Software Update

    @objc private func toggleAutoUpdateAction() {
        let updater = UpdateManager.shared
        updater.isAutomaticEnabled.toggle()
        rebuildMenu()
        if updater.isAutomaticEnabled {
            updater.checkAutomaticallyIfDue { [weak self] _ in
                self?.rebuildMenu()
            }
        }
    }

    @objc private func checkForUpdatesAction() {
        let updater = UpdateManager.shared
        rebuildMenu() // paint "Checking for Updates..." right away

        updater.checkForUpdates(userInitiated: true) { [weak self] outcome in
            guard let self = self else { return }
            self.rebuildMenu()

            switch outcome {
            case .available(let release):
                self.presentUpdatePrompt(for: release)
            case .upToDate(let current):
                self.showAlert(title: "You're Up to Date",
                               message: "Lightspot \(current) is the latest version.")
            case .failed(let message):
                self.showAlert(title: "Could Not Check for Updates", message: message)
            }
        }
    }

    @objc private func installUpdateAction() {
        guard let release = UpdateManager.shared.availableUpdate else { return }
        presentUpdatePrompt(for: release)
    }

    /// Offers the update. "Install and Relaunch" replaces the bundle and restarts;
    /// "Skip This Version" silences this one release without turning checks off.
    func presentUpdatePrompt(for release: ReleaseInfo) {
        let updater = UpdateManager.shared

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Lightspot \(release.displayVersion) is available"
        var details = "You are running \(updater.currentVersion)."
        if let size = release.assetSize {
            let formatted = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            details += " The download is \(formatted)."
        }
        if let notes = release.notes, !notes.isEmpty {
            details += "\n\n" + String(notes.prefix(600))
        }
        details += "\n\nLightspot keeps running until the new version has started, then hands over to it."
        alert.informativeText = details
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Release Notes")
        alert.addButton(withTitle: "Skip This Version")
        alert.addButton(withTitle: "Later")
        alert.window.level = .floating
        alert.window.center()
        alert.window.orderFrontRegardless()

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            beginInstall(release)
        case .alertSecondButtonReturn:
            if let page = release.pageURL { NSWorkspace.shared.open(page) }
        case .alertThirdButtonReturn:
            updater.skip(release)
            rebuildMenu()
        default:
            break
        }
    }

    private func beginInstall(_ release: ReleaseInfo) {
        rebuildMenu()
        UpdateManager.shared.install(release) { [weak self] outcome in
            switch outcome {
            case .relaunching:
                // The new build has finished launching and is waiting for this
                // process to exit before it shows its menu bar item.
                NSApp.terminate(nil)
            case .failed(let message):
                self?.rebuildMenu()
                self?.showAlert(title: "Update Failed", message: message)
            }
        }
    }

    @objc func aboutAction() {
        showAbout()
    }

    func showAbout() {
        NSApp.activate(ignoringOtherApps: true)

        let option = hotkeyManager?.currentOption
        let conflictNote = option
            .flatMap { SystemShortcutConflicts.cachedConflict(for: $0) }
            .map { " — macOS also uses it for “\($0.name)”" } ?? ""
        let currentOption = (option?.shortLabel ?? "⌘Space") + conflictNote
        let shortcutStatus = SpotlightManager.isShortcutEnabled() ? "Active" : "Disabled"
        let indexingStatus = SpotlightManager.isIndexingEnabled() ? "Active" : "Disabled"
        let processStatus = SpotlightManager.isServiceDisabled() ? "Disabled" : "Active"

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let updateSuffix = UpdateManager.shared.availableUpdate
            .map { " (\($0.displayVersion) available)" } ?? ""

        let alert = NSAlert()
        alert.messageText = "Lightspot"
        alert.informativeText = """
        A lightweight Spotlight replacement for macOS.

        Version: \(appVersion)\(updateSuffix)
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

