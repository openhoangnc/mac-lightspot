import AppKit
import SwiftUI

@main
struct LightspotApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: SpotlightPanel!
    private var hotkeyManager: HotkeyManager!
    private var menuBarController: MenuBarController!
    private var viewModel: SearchViewModel!
    private var hostingView: NSHostingView<SpotlightView>!

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            setup()
        }
    }

    private func setup() {
        // Setup standard main menu for text editing shortcuts (Cmd+A, Cmd+C, Cmd+V, Cmd+X, Cmd+Z)
        setupMainMenu()

        // Start background app scan
        AppScanner.shared.startScanning()

        // Parse the zsh history file off the main thread
        ShellHistoryProvider.shared.startLoading()

        // Discover and load recent VS Code projects off the main thread
        VSCodeProjectsProvider.shared.startLoading()

        // Create the view model
        viewModel = SearchViewModel()
        viewModel.onHide = { [weak self] in
            self?.hidePanel()
        }

        // Create and configure the panel
        panel = SpotlightPanel()

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
        menuBarController.setup(hotkeyManager: hotkeyManager)

        // Inject dependencies into view model
        viewModel.hotkeyManager = hotkeyManager
        viewModel.menuBarController = menuBarController

        // Prime the cached system-state snapshots off the main thread. Menus read
        // the cache; probing live would block the UI (see SpotlightManager).
        refreshSystemState()
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
        VSCodeProjectsProvider.shared.refreshIfNeeded()
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
        appMenu.addItem(withTitle: "About Lightspot", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
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
}
