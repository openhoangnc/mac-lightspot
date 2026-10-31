import AppKit
import SwiftUI

// MARK: - Clean Dev Mac Window

/// Clean Dev Mac's own window (`ToolWindowController`): the cleaner's list, plan and receipt, as
/// the panel's overlay drew them, in a window that stays open while Finder, a terminal running
/// cdm or a password prompt takes the focus. Made on first open; the model with it, kept from
/// then on (a standing scan's ticks survive a close, as the overlay's did); the window and its
/// hosting view made at each open and released at each close. A scan or a clean lives in
/// `CleanDevMacProvider`, so it keeps running with the window closed, and reopening shows it.
@MainActor
final class CleanDevMacWindowController: ToolWindowController {
    /// The size the view is laid out for: the panel's width, the overlay's height.
    static let size = NSSize(width: 740, height: 450)

    let model: CleanDevMacModel
    /// ⌘↵ and the "cdm in Terminal" button: cdm itself, in the preferred terminal.
    var onOpenInTerminal: (() -> Void)?

    init(model: CleanDevMacModel, placement: Placement = .remembered) {
        self.model = model
        super.init(title: CleanDevMacProvider.title, frameName: "CleanDevMac", contentSize: Self.size, placement: placement)
    }

    /// Opens the window and measures unless a recent scan stands, or brings the open one to the
    /// front, leaving the list, the plan or a running clean as it is.
    func show() {
        if open() { model.open() }
    }

    override var closeHelp: String? { "Close. A running scan or clean keeps going." }

    override func makeContent() -> NSView {
        let hosting = NSHostingView(rootView: CleanDevMacView(model: model, onOpenInTerminal: { [weak self] in self?.openInTerminal() }))
        // The window sets the size; the view fills whatever it is given.
        hosting.sizingOptions = []
        return hosting
    }

    /// The overlay's keys, now the window's: ↑↓ select, Space ticks, ↵ reviews, cleans or
    /// rescans, ⇥ scans the code repos when offered, ⌥↵ shows the category in Finder, ⌘↵ runs
    /// cdm in the terminal, Esc backs out of the plan, else closes, as ⌘W does.
    override func handleKey(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        switch event.keyCode {
        case 53: // Esc
            if !model.cancelConfirmation() { close() }
        case 36, 76: // Return, Enter
            if flags.contains(.option) {
                model.revealCursorInFinder()
            } else if flags.contains(.command) {
                openInTerminal()
            } else if flags.isEmpty {
                model.primaryAction()
            } else {
                return false
            }
        case 48 where flags.isEmpty: // Tab: cdm's "Also scan your code repos?"
            model.scanRepos()
        case 125 where flags.isEmpty: // ↓
            model.moveDown()
        case 126 where flags.isEmpty: // ↑
            model.moveUp()
        case 49 where flags.isEmpty: // Space
            model.toggleCursor()
        default:
            return false
        }
        return true
    }

    private func openInTerminal() {
        onOpenInTerminal?()
    }
}
