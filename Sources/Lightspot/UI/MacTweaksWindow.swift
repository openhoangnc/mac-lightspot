import AppKit
import SwiftUI

// MARK: - Mac Tweaks Window

/// Mac Tweaks' own window: titled, movable, closable, resizable from 740 × 450 pt. It is an
/// `NSWindow`, not an `NSPanel`, so it never hides when Lightspot loses focus (an apply sends the
/// user to System Settings and to the Touch ID prompt), and it never follows the Spotlight panel
/// out. It closes only with its close button, ⌘W, or Esc with no plan or wait open.
///
/// Every key Mac Tweaks answers to is taken here, before any view sees it (`onKey`): there is no
/// text field in the window, and a focused SwiftUI button (Full Keyboard Access) would otherwise
/// take Space and Return.
@MainActor
final class MacTweaksWindow: NSWindow {
    /// True when Mac Tweaks took the key.
    var onKey: ((NSEvent) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true { return }
        super.sendEvent(event)
    }

    /// ⌘W (there is no File menu to hold it), and whatever AppKit offers as a key equivalent
    /// first. Only while this window is key: AppKit may offer the main window a key equivalent
    /// typed in the Spotlight panel.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isKeyWindow, onKey?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// Opens, focuses and closes the Mac Tweaks window. Made on first open (`AppDelegate`), never at
/// launch. The model stays from then on, as it did for the overlay (a scan's ticks and cursor
/// survive a close while the scan stands); the window and its hosting view are made at each open
/// and released at each close, and the close drops the scan details as `overlayClosed()` does.
/// A running apply lives in `MacTweaksProvider`, so it keeps running with the window closed and
/// reopening shows its steps, then its receipt.
@MainActor
final class MacTweaksWindowController: NSObject, NSWindowDelegate {
    enum Placement {
        /// The app's: the frame remembered under `frameName`, the app activated, the window key.
        case remembered
        /// overlay_check's: at this origin, off every screen; no frame saved, the app never
        /// activated.
        case offscreen(NSPoint)
    }

    /// The frame is kept in Lightspot's defaults as "NSWindow Frame MacTweaks".
    static let frameName = "MacTweaks"
    /// The size the view is laid out for: the panel's width, the overlay's height.
    static let contentSize = NSSize(width: 740, height: 450)
    /// The window is dark in both appearances: the card's colours (white text at opacities, yellow
    /// caveats, red buttons) are drawn for a dark ground, as all of Lightspot is. The title bar is
    /// transparent over this colour, so the window reads as one dark card.
    static let background = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.118, alpha: 1)

    let model: MacTweaksModel
    private let placement: Placement
    private(set) var window: MacTweaksWindow?

    /// ↵ on a link row that leaves Mac Tweaks: Clean Dev Mac (the panel's overlay) and System
    /// Settings. A switch to another section stays in the window.
    var onLink: ((MacTweaksLink) -> Void)?
    /// The window became key: the owner hides the Spotlight panel, as a click outside it does.
    var onBecomeKey: (() -> Void)?

    init(model: MacTweaksModel, placement: Placement = .remembered) {
        self.model = model
        self.placement = placement
        super.init()
        model.onLink = { [weak self] link in self?.open(link) }
    }

    var isOpen: Bool { window != nil }

    /// Opens the window on `section` (nil: where it was left), or, when it is open, brings it to
    /// the front and switches to `section`, leaving a plan on show alone when it is already there.
    func show(_ section: MacTweaksSection? = nil) {
        if let window {
            if let section { model.select(section) }
            bringToFront(window)
            return
        }
        let window = Self.makeWindow(model: model)
        window.delegate = self
        window.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        switch placement {
        case .remembered:
            if !window.setFrameUsingName(Self.frameName) { window.center() }
            window.setFrameAutosaveName(Self.frameName)
        case .offscreen(let origin):
            window.setFrameOrigin(origin)
        }
        self.window = window
        if let section { model.show(section) } else { model.open() }
        bringToFront(window)
    }

    /// The close button, ⌘W and Esc.
    func close() {
        window?.performClose(nil)
    }

    /// The window and its hosting view, as the app and overlay_check build them.
    static func makeWindow(model: MacTweaksModel) -> MacTweaksWindow {
        let window = MacTweaksWindow(contentRect: NSRect(origin: .zero, size: contentSize),
                                     styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                     backing: .buffered, defer: true)
        window.title = MacTweaksProvider.title
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = background
        window.contentMinSize = contentSize
        // Reopened from another Space, or over a full-screen app, it comes to where the user is.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.standardWindowButton(.closeButton)?.toolTip = MacTweaksProvider.closeHelp
        let hosting = NSHostingView(rootView: MacTweaksView(model: model))
        // The window sets the size; the view fills whatever it is given.
        hosting.sizingOptions = []
        window.contentView = hosting
        return window
    }

    private func bringToFront(_ window: MacTweaksWindow) {
        if window.isMiniaturized { window.deminiaturize(nil) }
        switch placement {
        case .remembered:
            // An LSUIElement agent: the panel never activates Lightspot, so a window needs it.
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        case .offscreen:
            window.orderFrontRegardless()
        }
    }

    private func open(_ link: MacTweaksLink) {
        if case .section(let section) = link {
            model.select(section)
        } else {
            onLink?(link)
        }
    }

    // MARK: Keys

    /// The overlay's keys, now the window's: ↑↓ select, Space ticks, ⌫ marks a row for deletion
    /// (Background Items), ↵ reviews, applies or opens a link, ⌥↵ shows the row in Finder, ⇥ / ⇧⇥ switch sections, Esc backs out of the plan or
    /// stops a wait for System Settings, else closes, as ⌘W does. True when the key was taken.
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        if flags == .command {
            guard event.charactersIgnoringModifiers?.lowercased() == "w" else { return false }
            close()
            return true
        }
        guard event.type == .keyDown else { return false }
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

    // MARK: NSWindowDelegate

    nonisolated func windowDidBecomeKey(_ notification: Notification) {
        MainActor.assumeIsolated { onBecomeKey?() }
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated { closed() }
    }

    /// The provider drops what no longer needs to be in memory (`overlayClosed()`), and the
    /// window and its hosting view go: the SwiftUI graph is released once AppKit is done closing.
    private func closed() {
        guard let window else { return }
        model.close()
        if case .remembered = placement {
            window.saveFrame(usingName: Self.frameName)
            // The next open's window takes the name; two windows can't share it.
            window.setFrameAutosaveName("")
        }
        window.onKey = nil
        window.delegate = nil
        self.window = nil
        DispatchQueue.main.async { window.contentView = nil }
    }
}
