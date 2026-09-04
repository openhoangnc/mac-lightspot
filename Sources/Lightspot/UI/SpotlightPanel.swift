import AppKit
import SwiftUI

// MARK: - Custom Field Editor (intercepts arrow & tab keys for grid and result navigation)

@MainActor
final class SpotlightFieldEditor: NSTextView {
    var onMoveUp: (@MainActor () -> Void)?
    var onMoveDown: (@MainActor () -> Void)?
    var onMoveLeft: (@MainActor () -> Void)?
    var onMoveRight: (@MainActor () -> Void)?
    var onNextTab: (@MainActor () -> Void)?
    var onPrevTab: (@MainActor () -> Void)?
    var onSubmit: (@MainActor () -> Void)?
    var onSecondarySubmit: (@MainActor () -> Void)?
    var onOpenInFinder: (@MainActor () -> Void)?
    var onCancel: (@MainActor () -> Void)?
    var onTogglePin: (@MainActor () -> Void)?
    var onManagePins: (@MainActor () -> Void)?
    var onManageHistory: (@MainActor () -> Void)?
    var onManageCustomCommands: (@MainActor () -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.option) {
                onSecondarySubmit?()
                return
            } else if flags.contains(.command) {
                onOpenInFinder?()
                return
            } else if flags.isEmpty || flags == .capsLock {
                onSubmit?()
                return
            }
        }
        super.keyDown(with: event)
    }

    override func insertNewlineIgnoringFieldEditor(_ sender: Any?) {
        onSecondarySubmit?()
    }

    override func insertLineBreak(_ sender: Any?) {
        onSecondarySubmit?()
    }

    override func insertParagraphSeparator(_ sender: Any?) {
        onSecondarySubmit?()
    }

    override func doCommand(by selector: Selector) {
        if selector == #selector(NSResponder.moveUp(_:)) {
            onMoveUp?()
        } else if selector == #selector(NSResponder.moveDown(_:)) {
            onMoveDown?()
        } else if selector == #selector(NSResponder.moveLeft(_:)) && selectedRange().location == 0 {
            onMoveLeft?()
        } else if selector == #selector(NSResponder.moveRight(_:)) && selectedRange().location == string.count {
            onMoveRight?()
        } else if selector == #selector(NSResponder.insertTab(_:)) {
            onNextTab?()
        } else if selector == #selector(NSResponder.insertBacktab(_:)) {
            onPrevTab?()
        } else if selector == #selector(NSResponder.insertNewline(_:)) ||
                   selector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) ||
                   selector == #selector(NSResponder.insertLineBreak(_:)) ||
                   selector == #selector(NSResponder.insertParagraphSeparator(_:)) {
            if let event = NSApp.currentEvent {
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if flags.contains(.option) {
                    onSecondarySubmit?()
                } else if flags.contains(.command) {
                    onOpenInFinder?()
                } else {
                    onSubmit?()
                }
            } else {
                onSubmit?()
            }
        } else if selector == #selector(NSResponder.cancelOperation(_:)) {
            onCancel?()
        } else {
            super.doCommand(by: selector)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .option {
            if let chars = event.charactersIgnoringModifiers, (chars == "\r" || chars == "\n") {
                onSecondarySubmit?()
                return true
            }
        } else if flags == .command {
            guard let chars = event.charactersIgnoringModifiers?.lowercased() else {
                return super.performKeyEquivalent(with: event)
            }
            switch chars {
            case "\r", "\n", "r":
                onOpenInFinder?()
                return true
            case "a":
                selectAll(nil)
                return true
            case "c":
                copy(nil)
                return true
            case "v":
                paste(nil)
                return true
            case "x":
                cut(nil)
                return true
            case "z":
                undoManager?.undo()
                return true
            case "p":
                // ⌘P pins / unpins the selected Terminal History result. A
                // .nonactivatingPanel never becomes main, so this is the only place
                // the key can be caught.
                onTogglePin?()
                return true
            case "y":
                // ⌘Y opens the search history manager
                onManageHistory?()
                return true
            default:
                break
            }
        } else if flags == [.command, .shift] {
            guard let chars = event.charactersIgnoringModifiers?.lowercased() else {
                return super.performKeyEquivalent(with: event)
            }
            switch chars {
            case "z":
                undoManager?.redo()
                return true
            case "p":
                onManagePins?()
                return true
            case "h":
                // ⌘⇧H opens the search history manager
                onManageHistory?()
                return true
            case "c":
                // ⌘⇧C opens custom commands manager
                onManageCustomCommands?()
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn: Bool) {
        guard turnedOn else { return }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        let cursorWidth: CGFloat = 2.5
        let cursorRect = NSRect(
            x: rect.origin.x,
            y: rect.origin.y + 1,
            width: cursorWidth,
            height: max(rect.height - 2, 20)
        )

        // Outer Siri / Apple Intelligence cyan glow shadow
        let glow = NSShadow()
        glow.shadowColor = NSColor(red: 0.25, green: 0.8, blue: 1.0, alpha: 0.9)
        glow.shadowBlurRadius = 7.0
        glow.shadowOffset = .zero
        glow.set()

        // Glowing rounded cursor
        let path = NSBezierPath(roundedRect: cursorRect, xRadius: 1.25, yRadius: 1.25)
        let coreColor = NSColor(red: 0.92, green: 0.97, blue: 1.0, alpha: 1.0)
        coreColor.setFill()
        path.fill()

        // Inner bright white highlight
        let innerRect = cursorRect.insetBy(dx: 0.3, dy: 0.3)
        let innerPath = NSBezierPath(roundedRect: innerRect, xRadius: 0.8, yRadius: 0.8)
        NSColor.white.setFill()
        innerPath.fill()
    }
}

// MARK: - Custom NSPanel

@MainActor
final class SpotlightPanel: NSPanel {
    private var fieldEditor: SpotlightFieldEditor?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    // Callbacks
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onMoveLeft: (() -> Void)?
    var onMoveRight: (() -> Void)?
    var onNextTab: (() -> Void)?
    var onPrevTab: (() -> Void)?
    var onSubmit: (() -> Void)?
    var onSecondarySubmit: (() -> Void)?
    var onOpenInFinder: (() -> Void)?
    var onCancel: (() -> Void)?
    var onTogglePin: (() -> Void)?
    var onManagePins: (() -> Void)?
    var onManageHistory: (() -> Void)?
    var onManageCustomCommands: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let firstResp = firstResponder, firstResp.performKeyEquivalent(with: event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    static let panelWidth: CGFloat = 740
    static let defaultHeight: CGFloat = 560

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.defaultHeight),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        isMovableByWindowBackground = true
        animationBehavior = .none

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        contentView = container
    }

    // Provide custom field editor for arrow-key interception
    override func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? {
        if fieldEditor == nil && createFlag {
            let editor = SpotlightFieldEditor()
            editor.isFieldEditor = true
            editor.drawsBackground = false
            editor.font = .systemFont(ofSize: 19, weight: .regular)
            editor.textColor = .white
            editor.insertionPointColor = .white
            editor.onMoveUp = { [weak self] in self?.onMoveUp?() }
            editor.onMoveDown = { [weak self] in self?.onMoveDown?() }
            editor.onMoveLeft = { [weak self] in self?.onMoveLeft?() }
            editor.onMoveRight = { [weak self] in self?.onMoveRight?() }
            editor.onNextTab = { [weak self] in self?.onNextTab?() }
            editor.onPrevTab = { [weak self] in self?.onPrevTab?() }
            editor.onSubmit = { [weak self] in self?.onSubmit?() }
            editor.onSecondarySubmit = { [weak self] in self?.onSecondarySubmit?() }
            editor.onOpenInFinder = { [weak self] in self?.onOpenInFinder?() }
            editor.onCancel = { [weak self] in self?.onCancel?() }
            editor.onTogglePin = { [weak self] in self?.onTogglePin?() }
            editor.onManagePins = { [weak self] in self?.onManagePins?() }
            editor.onManageHistory = { [weak self] in self?.onManageHistory?() }
            editor.onManageCustomCommands = { [weak self] in self?.onManageCustomCommands?() }
            fieldEditor = editor
        }
        return fieldEditor
    }

    // MARK: - Show / Hide

    func showPanel() {
        positionOnActiveScreen()

        alphaValue = 0
        makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }

        if let contentView = contentView {
            contentView.wantsLayer = true
            contentView.layer?.transform = CATransform3DMakeScale(0.97, 0.97, 1)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                contentView.layer?.transform = CATransform3DIdentity
            }
        }

        installMonitors()
    }

    func hidePanel() {
        removeMonitors()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                self.orderOut(nil)
                self.alphaValue = 1
            }
        })
    }

    func togglePanel() {
        if isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    // MARK: - Positioning

    private func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first!

        let screenFrame = screen.visibleFrame
        let width = Self.panelWidth
        let currentHeight = frame.height

        let x = screenFrame.midX - width / 2
        let y = screenFrame.maxY - (screenFrame.height * 0.16) - currentHeight

        setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Update panel height with animation only when height actually changes
    func updateHeight(_ newHeight: CGFloat) {
        guard abs(frame.height - newHeight) >= 1 else { return }

        let currentFrame = frame
        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: currentFrame.origin.y + currentFrame.height - newHeight,
            width: currentFrame.width,
            height: newHeight
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(newFrame, display: true)
        }
    }

    // MARK: - Event Monitors

    private func installMonitors() {
        // Global monitor: clicks outside the panel
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if NSApp.modalWindow != nil { return }
            self?.hidePanel()
        }

        // Local monitor: handle escape key and option/command return
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape key
                self?.onCancel?()
                return nil
            }
            let isReturn = event.keyCode == 36 || event.keyCode == 76
            if isReturn {
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if flags.contains(.option) {
                    self?.onSecondarySubmit?()
                    return nil
                } else if flags.contains(.command) {
                    self?.onOpenInFinder?()
                    return nil
                }
            }
            return event
        }
    }

    private func removeMonitors() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
}
