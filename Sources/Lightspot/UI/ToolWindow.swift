import AppKit
import SwiftUI

// MARK: - Tool windows (Mac Tweaks, Clean Dev Mac)

/// The window Mac Tweaks and Clean Dev Mac each open in: titled, movable, closable, resizable
/// from its controller's `contentSize`. It is an `NSWindow`, not an `NSPanel`, so it never hides
/// when Lightspot loses focus (an apply or a clean sends the user to System Settings, a password
/// prompt or Finder), and it never follows the Spotlight panel out. It closes only with its close
/// button, ⌘W, or the Esc its controller allows.
///
/// Every key the tool answers to is taken here, before any view sees it (`onKey`): there is no
/// text field in the window, and a focused SwiftUI button (Full Keyboard Access) would otherwise
/// take Space and Return.
@MainActor
final class ToolWindow: NSWindow {
    /// The dark card both tools draw, in both appearances: their colours (white text at
    /// opacities, yellow caveats, red buttons) are made for a dark ground, as all of Lightspot is.
    /// The title bar is transparent over it, so the window reads as one card.
    static let background = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.118, alpha: 1)

    /// True when the tool took the key.
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

/// What both tool windows share: made on first open by `AppDelegate`, never at launch; the window
/// and its hosting view made at each open (`makeContent`) and released at each close, after
/// `didClose`; the frame remembered under `frameName`; the app activated and the window made key
/// on open (Lightspot is an `LSUIElement` agent whose panel never activates it); ⌘W closing it.
/// A subclass gives the content, its keys (`handleKey`) and what a close drops (`didClose`).
@MainActor
class ToolWindowController: NSObject, NSWindowDelegate {
    enum Placement {
        /// The app's: the frame remembered under `frameName`, the app activated, the window key.
        case remembered
        /// overlay_check's: at this origin, off every screen; no frame saved, the app never
        /// activated.
        case offscreen(NSPoint)
    }

    let title: String
    /// Kept in Lightspot's defaults as "NSWindow Frame <frameName>".
    let frameName: String
    /// The size the content is laid out for, and the window's minimum.
    let contentSize: NSSize
    let placement: Placement
    private(set) var window: ToolWindow?

    /// The window became key: the owner hides the Spotlight panel, as a click outside it does.
    var onBecomeKey: (() -> Void)?

    init(title: String, frameName: String, contentSize: NSSize, placement: Placement) {
        self.title = title
        self.frameName = frameName
        self.contentSize = contentSize
        self.placement = placement
        super.init()
    }

    var isOpen: Bool { window != nil }

    /// The hosting view, made at each open.
    func makeContent() -> NSView { NSView() }
    /// The close button's tooltip.
    var closeHelp: String? { nil }
    /// The tool's keys; true when it took the key. ⌘W is handled before this.
    func handleKey(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool { false }
    /// The window closed: the tool drops what no longer needs to be in memory.
    func didClose() {}

    /// Opens the window, or brings the open one to the front. True when it opened.
    @discardableResult
    func open() -> Bool {
        if let window {
            bringToFront(window)
            return false
        }
        let window = makeWindow()
        window.delegate = self
        window.onKey = { [weak self] event in self?.key(event) ?? false }
        switch placement {
        case .remembered:
            if !window.setFrameUsingName(frameName) { window.center() }
            window.setFrameAutosaveName(frameName)
        case .offscreen(let origin):
            window.setFrameOrigin(origin)
        }
        self.window = window
        bringToFront(window)
        return true
    }

    /// The close button, ⌘W and Esc.
    func close() {
        window?.performClose(nil)
    }

    /// The window and its hosting view, as the app and overlay_check build them.
    func makeWindow() -> ToolWindow {
        let window = ToolWindow(contentRect: NSRect(origin: .zero, size: contentSize),
                                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                backing: .buffered, defer: true)
        window.title = title
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = ToolWindow.background
        window.contentMinSize = contentSize
        // Reopened from another Space, or over a full-screen app, it comes to where the user is.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.standardWindowButton(.closeButton)?.toolTip = closeHelp
        window.contentView = makeContent()
        return window
    }

    func bringToFront(_ window: ToolWindow) {
        if window.isMiniaturized { window.deminiaturize(nil) }
        switch placement {
        case .remembered:
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        case .offscreen:
            window.orderFrontRegardless()
        }
    }

    private func key(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
            close()
            return true
        }
        guard event.type == .keyDown else { return false }
        return handleKey(event, flags: flags)
    }

    // MARK: NSWindowDelegate

    nonisolated func windowDidBecomeKey(_ notification: Notification) {
        MainActor.assumeIsolated { onBecomeKey?() }
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated { closed() }
    }

    /// The tool drops what it should (`didClose`), and the window and its hosting view go: the
    /// SwiftUI graph is released once AppKit is done closing.
    private func closed() {
        guard let window else { return }
        didClose()
        if case .remembered = placement {
            window.saveFrame(usingName: frameName)
            // The next open's window takes the name; two windows can't share it.
            window.setFrameAutosaveName("")
        }
        window.onKey = nil
        window.delegate = nil
        self.window = nil
        DispatchQueue.main.async { window.contentView = nil }
    }
}
