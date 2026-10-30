import AppKit
import SwiftUI

@main
struct LightspotApp {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--cleanup-login-item") ||
           CommandLine.arguments.contains("--uninstall-login-item") ||
           CommandLine.arguments.contains("--uninstall") {
            _ = AutoStartManager.setEnabled(false)
            exit(0)
        }

        let delegate = AppDelegate()

        // One Lightspot per user; see SingleInstanceGuard. Checked after the helper
        // flags above, which the uninstaller runs while a copy may still be up.
        if let bundleIdentifier = Bundle.main.bundleIdentifier,
           let executablePath = Bundle.main.executablePath {
            let claim = AppDelegate.InstanceClaim(
                bundleIdentifier: bundleIdentifier,
                lockPath: SingleInstanceGuard.lockFilePath(bundleIdentifier: bundleIdentifier),
                build: SingleInstanceGuard.buildIdentity(executablePath: executablePath),
                replacedPID: SingleInstanceGuard.replacedPID(arguments: CommandLine.arguments)
            )
            if claim.replacedPID != nil {
                // Started by an update. The old copy quits only once this one has
                // finished launching, so the lock is claimed after that, in the delegate.
                delegate.pendingClaim = claim
            } else {
                proceed(with: SingleInstanceGuard.claim(
                    bundleIdentifier: claim.bundleIdentifier,
                    lockPath: claim.lockPath,
                    build: claim.build
                ), bundleIdentifier: bundleIdentifier)
            }
        }

        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }

    /// Exits unless the decision is to run.
    static func proceed(with decision: SingleInstanceGuard.LaunchDecision, bundleIdentifier: String) {
        switch decision {
        case .run:
            // The lock descriptor stays open until the process exits. Any older
            // build has quit by now, so nothing still writes the HTTP cache and
            // cookie store that versions up to 1.2.0 left behind; delete them.
            LegacyNetworkStores.removeInBackground(bundleIdentifier: bundleIdentifier)
        case .handedOff:
            exit(0)
        case .holderDidNotQuit(let pid):
            NSLog("Lightspot: another build (pid %d) is running and did not quit; exiting.", pid ?? -1)
            exit(1)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: SpotlightPanel!
    private var hotkeyManager: HotkeyManager!
    private var menuBarController: MenuBarController!
    private var viewModel: SearchViewModel!
    private var hostingView: NSHostingView<SpotlightView>!
    private var instanceRequests: SingleInstanceGuard.RequestListener?
    private let launchedAt = Date()

    struct InstanceClaim {
        let bundleIdentifier: String
        let lockPath: String
        let build: String
        let replacedPID: pid_t?
    }

    /// Set when an update started this copy to replace another: the lock is claimed,
    /// and anything shown, only once that copy has quit.
    var pendingClaim: InstanceClaim?
    /// Fires the moment the replaced copy exits, so the gap between its menu bar item
    /// going and ours appearing is only `setup()`. The 0.1 s poll stays as the fallback.
    private var replacedExitSource: DispatchSourceProcess?

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            if let claim = pendingClaim, let replacedPID = claim.replacedPID {
                // Finishing launching is the old copy's cue to quit. Until it has, it
                // owns the menu bar item and the hotkey, and showing ours would put two
                // Lightspots on screen.
                let deadline = Date().addingTimeInterval(SingleInstanceGuard.replacingTimeout)
                let source = DispatchSource.makeProcessSource(identifier: replacedPID, eventMask: .exit, queue: .main)
                source.setEventHandler { [weak self] in
                    MainActor.assumeIsolated {
                        self?.awaitReplacedCopy(replacedPID, claim: claim, until: deadline)
                    }
                }
                source.resume()
                replacedExitSource = source
                awaitReplacedCopy(replacedPID, claim: claim, until: deadline)
            } else {
                setup()
            }
        }
    }

    private func awaitReplacedCopy(_ replacedPID: pid_t, claim: InstanceClaim, until deadline: Date) {
        // The exit source and the poll can both land after the claim was made.
        guard pendingClaim != nil else { return }
        let decision = Date() < deadline
            ? SingleInstanceGuard.claimReplacing(replacedPID,
                                                 bundleIdentifier: claim.bundleIdentifier,
                                                 lockPath: claim.lockPath,
                                                 build: claim.build)
            : SingleInstanceGuard.claim(bundleIdentifier: claim.bundleIdentifier,
                                        lockPath: claim.lockPath,
                                        build: claim.build)
        guard let decision else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                MainActor.assumeIsolated {
                    self?.awaitReplacedCopy(replacedPID, claim: claim, until: deadline)
                }
            }
            return
        }
        pendingClaim = nil
        replacedExitSource?.cancel()
        replacedExitSource = nil
        NSLog("Lightspot: taking over from pid %d", replacedPID)
        LightspotApp.proceed(with: decision, bundleIdentifier: claim.bundleIdentifier)
        setup()
    }

    /// Opening Lightspot.app while it runs (Finder, `open`) reopens this instance
    /// instead of starting another: treat it like a second launch's hand-off.
    nonisolated func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated {
            handleShowRequest()
        }
        return false
    }

    private func setup() {
        // Setup standard main menu for text editing shortcuts (Cmd+A, Cmd+C, Cmd+V, Cmd+X, Cmd+Z)
        setupMainMenu()

        // Start background app scan
        AppScanner.shared.startScanning()

        // Parse the zsh history file off the main thread
        ShellHistoryProvider.shared.startLoading()

        // Discover and load recent projects (VS Code, Cursor, Zed, JetBrains, Sublime) off the main thread
        RecentProjectsProvider.shared.startLoading()

        // Read System Settings' own search terms for every pane off the main thread
        SettingsProvider.shared.startLoadingSearchTerms()

        // Start in-memory ephemeral clipboard history monitoring
        ClipboardHistoryManager.shared.startMonitoring()

        // Create the view model
        viewModel = SearchViewModel()
        viewModel.onHide = { [weak self] in
            self?.hidePanel()
        }

        // Create and configure the panel
        panel = SpotlightPanel()
        panel.onDismiss = { [weak self] in
            self?.hidePanel()
        }

        // Hook up dynamic height animation from view model
        viewModel.onHeightChange = { [weak self] targetHeight in
            self?.panel.updateHeight(targetHeight)
        }

        // Create SwiftUI view with view model
        let spotlightView = SpotlightView(viewModel: viewModel)
        hostingView = NSHostingView(rootView: spotlightView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        if let contentView = panel.contentView {
            contentView.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.topAnchor.constraint(equalTo: contentView.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                hostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            ])
        }

        // Wire up panel keyboard callbacks directly to the reactive view model
        panel.onMoveUp = { [weak self] in
            self?.viewModel.moveUp()
        }
        panel.onMoveDown = { [weak self] in
            self?.viewModel.moveDown()
        }
        panel.onMoveLeft = { [weak self] in
            self?.viewModel.moveLeft()
        }
        panel.onMoveRight = { [weak self] in
            self?.viewModel.moveRight()
        }
        panel.onNextTab = { [weak self] in
            self?.viewModel.nextCategory()
        }
        panel.onPrevTab = { [weak self] in
            self?.viewModel.previousCategory()
        }
        panel.onSubmit = { [weak self] in
            self?.viewModel.activateSelected()
        }
        panel.onSecondarySubmit = { [weak self] in
            self?.viewModel.activateSecondary()
        }
        panel.onOpenInFinder = { [weak self] in
            self?.viewModel.activateFinder()
        }
        panel.onCancel = { [weak self] in
            self?.viewModel.handleCancel()
        }
        panel.onTogglePin = { [weak self] in
            self?.viewModel.togglePinForSelection()
        }
        panel.onManagePins = { [weak self] in
            self?.viewModel.togglePinManager()
        }
        panel.onManageHistory = { [weak self] in
            self?.viewModel.toggleHistoryManager()
        }
        panel.onManageCustomCommands = { [weak self] in
            self?.viewModel.toggleCustomCommandManager()
        }
        panel.onDeleteKey = { [weak self] in
            self?.viewModel.handleDeleteKey() ?? false
        }
        panel.onSpaceKey = { [weak self] in
            self?.viewModel.handleSpaceKey() ?? false
        }

        // Set up hotkey
        hotkeyManager = HotkeyManager()
        hotkeyManager.onToggle = { [weak self] in
            MainActor.assumeIsolated {
                self?.togglePanel()
            }
        }
        hotkeyManager.register()

        // Set up menu bar
        menuBarController = MenuBarController()
        menuBarController.onShowToggle = { [weak self] in
            self?.togglePanel()
        }
        menuBarController.onManageCustomCommands = { [weak self] in
            guard let self = self else { return }
            if !self.panel.isVisible {
                self.showPanel()
            }
            self.viewModel.showCustomCommandManager()
        }
        menuBarController.onManagePins = { [weak self] in
            guard let self = self else { return }
            if !self.panel.isVisible {
                // showPanel() resets the view model, so open the manager afterwards.
                self.showPanel()
            }
            self.viewModel.showPinManager()
        }
        menuBarController.onManageHistory = { [weak self] in
            guard let self = self else { return }
            if !self.panel.isVisible {
                self.showPanel()
            }
            self.viewModel.showHistoryManager()
        }
        menuBarController.onOpenCleaner = { [weak self] in
            guard let self = self else { return }
            if !self.panel.isVisible {
                self.showPanel()
            }
            self.viewModel.showCleaner()
        }
        menuBarController.onOpenTweaks = { [weak self] in
            guard let self = self else { return }
            if !self.panel.isVisible {
                // showPanel() resets the view model, so open Mac Tweaks afterwards.
                self.showPanel()
            }
            self.viewModel.showTweaks()
        }
        menuBarController.onEnsurePanelVisible = { [weak self] in
            guard let self = self else { return false }
            if !self.panel.isVisible {
                self.showPanel()
            }
            return true
        }
        menuBarController.setup(hotkeyManager: hotkeyManager)

        // Inject dependencies into view model
        viewModel.hotkeyManager = hotkeyManager
        viewModel.menuBarController = menuBarController
        menuBarController.viewModel = viewModel

        // Inject dependencies into settings backup controller
        SettingsBackupController.shared.hotkeyManager = hotkeyManager
        SettingsBackupController.shared.menuBarController = menuBarController
        SettingsBackupController.shared.viewModel = viewModel

        // Prime the cached system-state snapshots off the main thread. Menus read
        // the cache; probing live would block the UI (see SpotlightManager).
        refreshSystemState()

        // Handle first-run onboarding (auto-enable launch at login & suggest disabling Spotlight)
        FirstRunManager.handleFirstRunIfNeeded(delegate: menuBarController)

        // Carbon hands a key combination to one owner. If Lightspot lost the race at
        // launch the panel would silently never open, so say so instead — after the
        // Spotlight state snapshot has landed, which decides what the alert offers.
        if !hotkeyManager.isRegistered {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                MainActor.assumeIsolated {
                    self?.menuBarController?.presentHotkeyConflictIfNeeded()
                }
            }
        }

        // Look for a new release in the background. Deliberately delayed: it is
        // network work and nothing at launch depends on the answer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            MainActor.assumeIsolated {
                UpdateManager.shared.checkAutomaticallyIfDue { release in
                    MainActor.assumeIsolated {
                        guard UpdateManager.shared.hasPromptableUpdate else { return }
                        self?.menuBarController?.rebuildMenu()
                        self?.menuBarController?.presentUpdatePrompt(for: release)
                    }
                }
            }
        }
        // Answer later launches: show the panel for a second copy of this build,
        // quit when a different build (reinstalled, rebuilt, updated) takes over.
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            instanceRequests = SingleInstanceGuard.RequestListener(
                bundleIdentifier: bundleIdentifier,
                onShowPanel: { [weak self] in
                    MainActor.assumeIsolated {
                        self?.handleShowRequest()
                    }
                },
                onQuit: {
                    MainActor.assumeIsolated {
                        NSApp.terminate(nil)
                    }
                }
            )
        }
    }

    private func handleShowRequest() {
        guard panel != nil, !panel.isVisible,
              SingleInstanceGuard.shouldHonorShowRequest(launchedAt: launchedAt) else { return }
        showPanel()
    }

    /// Re-probes macOS Spotlight / login-item state in the background and rebuilds
    /// the menus only if something actually changed.
    private func refreshSystemState() {
        SpotlightManager.refreshState { [weak self] in
            MainActor.assumeIsolated {
                self?.menuBarController?.rebuildMenu()
                self?.viewModel?.objectWillChange.send()
            }
        }
        AutoStartManager.refreshState { [weak self] in
            MainActor.assumeIsolated {
                self?.menuBarController?.rebuildMenu()
                self?.viewModel?.objectWillChange.send()
            }
        }
    }

    private func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        AppScanner.shared.refreshIfNeeded()
        ShellHistoryProvider.shared.refreshIfNeeded()
        RecentProjectsProvider.shared.refreshIfNeeded()
        // Prime bookmarks and the open-tab list here so the first keystroke has data
        // to match against; both return immediately and refresh in the background.
        BrowserIntegrationProvider.shared.warmUp()
        ProcessKillerProvider.shared.warmUp()
        ToolInstallersProvider.shared.warmUp()
        refreshSystemState()
        viewModel.reset()

        // Set frame size to default expanded launcher size
        panel.setFrame(NSRect(
            x: panel.frame.origin.x,
            y: panel.frame.origin.y,
            width: SpotlightPanel.panelWidth,
            height: SpotlightPanel.defaultHeight
        ), display: false)

        panel.showPanel()

        // Focus the text field
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated {
                if let panel = self?.panel {
                    panel.makeKey()
                    if let textField = self?.findTextField(in: panel.contentView) {
                        panel.makeFirstResponder(textField)
                    }
                }
            }
        }
    }

    private func hidePanel() {
        panel.hidePanel()
        
        // Reclaim memory actively when hiding
        viewModel.reclaimMemory()
        AppScanner.shared.reclaimMemory()
        ShellHistoryProvider.shared.reclaimMemory()
        RecentAppsManager.shared.reclaimMemory()
        malloc_zone_pressure_relief(nil, 0)
    }

    private func findTextField(in view: NSView?) -> NSTextField? {
        guard let view = view else { return nil }
        if let textField = view as? NSTextField, textField.isEditable {
            return textField
        }
        for subview in view.subviews {
            if let found = findTextField(in: subview) {
                return found
            }
        }
        return nil
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let aboutMenuItem = NSMenuItem(title: "About Lightspot", action: #selector(aboutAction), keyEquivalent: "")
        aboutMenuItem.target = self
        appMenu.addItem(aboutMenuItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Lightspot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit Menu (crucial for standard text field shortcuts: Cmd+A, Cmd+C, Cmd+V, Cmd+X, Cmd+Z)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func aboutAction() {
        menuBarController?.showAbout()
    }
}
