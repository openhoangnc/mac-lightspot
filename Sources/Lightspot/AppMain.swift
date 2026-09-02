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
        // Start background app scan
        AppScanner.shared.startScanning()

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
            self?.viewModel.moveSelectionUp()
        }
        panel.onMoveDown = { [weak self] in
            self?.viewModel.moveSelectionDown()
        }
        panel.onSubmit = { [weak self] in
            self?.viewModel.activateSelected()
        }
        panel.onCancel = { [weak self] in
            self?.viewModel.handleCancel()
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
        menuBarController.setup(hotkeyManager: hotkeyManager)
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
        viewModel.reset()

        // Reset to compact height
        panel.setFrame(NSRect(
            x: panel.frame.origin.x,
            y: panel.frame.origin.y,
            width: 680,
            height: 60
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
}
