import AppKit
import SwiftUI

// MARK: - Mac Tweaks Window

/// Mac Tweaks' own window (`ToolWindowController`): the sections, as the panel's overlay drew
/// them, in a window that stays open while System Settings or the Touch ID prompt takes the
/// focus. Made on first open (`AppDelegate`), never at launch. The model stays from then on, as
/// it did for the overlay (a scan's ticks and cursor survive a close while the scan stands); the
/// window and its hosting view are made at each open and released at each close, and the close
/// drops the scan details as `overlayClosed()` does. A running apply lives in
/// `MacTweaksProvider`, so it keeps running with the window closed and reopening shows its steps,
/// then its receipt.
@MainActor
final class MacTweaksWindowController: ToolWindowController {
    /// The frame is kept in Lightspot's defaults as "NSWindow Frame MacTweaks".
    static let frameName = "MacTweaks"
    /// The size the view is laid out for: the panel's width, the overlay's height.
    static let contentSize = NSSize(width: 740, height: 450)

    let model: MacTweaksModel

    /// ↵ on a link row that leaves Mac Tweaks: Clean Dev Mac (its own window) and System
    /// Settings. A switch to another section stays in the window.
    var onLink: ((MacTweaksLink) -> Void)?

    init(model: MacTweaksModel, placement: Placement = .remembered) {
        self.model = model
        super.init(title: MacTweaksProvider.title, frameName: Self.frameName, contentSize: Self.contentSize, placement: placement)
        model.onLink = { [weak self] link in self?.follow(link) }
    }

    /// Opens the window on `section` (nil: where it was left), or, when it is open, brings it to
    /// the front and switches to `section`, leaving a plan on show alone when it is already there.
    func show(_ section: MacTweaksSection? = nil) {
        if isOpen {
            if let section { model.select(section) }
            open()
            return
        }
        open()
        if let section { model.show(section) } else { model.open() }
    }

    override var closeHelp: String? { MacTweaksProvider.closeHelp }

    override func makeContent() -> NSView {
        let hosting = NSHostingView(rootView: MacTweaksView(model: model))
        // The window sets the size; the view fills whatever it is given.
        hosting.sizingOptions = []
        return hosting
    }

    /// The provider drops what no longer needs to be in memory (`overlayClosed()`).
    override func didClose() {
        model.close()
    }

    private func follow(_ link: MacTweaksLink) {
        if case .section(let section) = link {
            model.select(section)
        } else {
            onLink?(link)
        }
    }

    // MARK: Keys

    /// The overlay's keys, now the window's: ↑↓ select, Space ticks, ⌫ marks a row for deletion
    /// (Background Items), ↵ reviews, applies or opens a link, ⌥↵ shows the row in Finder, ⇥ / ⇧⇥
    /// switch sections, Esc backs out of the plan or stops a wait for System Settings, else
    /// closes, as ⌘W does. True when the key was taken.
    override func handleKey(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        switch event.keyCode {
        case 53: // Esc
            escape()
        case 36, 76: // Return, Enter
            if flags.contains(.option) {
                reveal()
            } else if flags.contains(.command) {
                // ⌘↵ means nothing in Mac Tweaks.
            } else if flags.isEmpty {
                model.primaryAction()
            } else {
                return false
            }
        case 48: // Tab
            if flags == .shift {
                model.previousSection()
            } else if flags.isEmpty {
                model.nextSection()
            } else {
                return false
            }
        case 125 where flags.isEmpty: // ↓
            model.moveDown()
        case 126 where flags.isEmpty: // ↑
            model.moveUp()
        case 49 where flags.isEmpty: // Space
            model.toggleCursor()
        case 51 where flags.isEmpty, 117 where flags.isEmpty: // ⌫, ⌦
            model.toggleDeletion()
        default:
            return false
        }
        return true
    }

    /// Esc backs out of the plan, or stops the section's wait for System Settings (the profile
    /// stays there, and the window shows the wait end), else closes the window.
    private func escape() {
        if model.cancelConfirmation() { return }
        if model.isWaiting {
            model.requestCancel()
            return
        }
        close()
    }

    /// ⌥↵: the row's file in Finder, or on a receipt the app macOS kept. The window stays.
    private func reveal() {
        guard let path = model.revealPath else { return }
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
}
