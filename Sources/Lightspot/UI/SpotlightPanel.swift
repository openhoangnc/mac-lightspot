import AppKit
import SwiftUI

// MARK: - Custom Field Editor (intercepts arrow keys for result navigation)

@MainActor
final class SpotlightFieldEditor: NSTextView {
    var onMoveUp: (@MainActor () -> Void)?
    var onMoveDown: (@MainActor () -> Void)?
    var onSubmit: (@MainActor () -> Void)?
    var onCancel: (@MainActor () -> Void)?

    override func doCommand(by selector: Selector) {
        if selector == #selector(NSResponder.moveUp(_:)) {
            onMoveUp?()
        } else if selector == #selector(NSResponder.moveDown(_:)) {
            onMoveDown?()
        } else if selector == #selector(NSResponder.insertNewline(_:)) {
            onSubmit?()
        } else if selector == #selector(NSResponder.cancelOperation(_:)) {
            onCancel?()
        } else {
            super.doCommand(by: selector)
        }
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
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 56),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = true
        animationBehavior = .none

        // Visual effect background
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 20
        visualEffect.layer?.cornerCurve = .continuous
        visualEffect.layer?.masksToBounds = true

        // Subtle border
        visualEffect.layer?.borderWidth = 0.5
        visualEffect.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor

        contentView = visualEffect
    }

    // Provide custom field editor for arrow-key interception
    override func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? {
        if fieldEditor == nil && createFlag {
            fieldEditor = SpotlightFieldEditor()
            fieldEditor?.isFieldEditor = true
            fieldEditor?.drawsBackground = false
            fieldEditor?.font = .systemFont(ofSize: 24, weight: .light)
            fieldEditor?.textColor = .labelColor
            fieldEditor?.onMoveUp = { [weak self] in self?.onMoveUp?() }
            fieldEditor?.onMoveDown = { [weak self] in self?.onMoveDown?() }
            fieldEditor?.onSubmit = { [weak self] in self?.onSubmit?() }
            fieldEditor?.onCancel = { [weak self] in self?.onCancel?() }
        }
        return fieldEditor
    }

    // MARK: - Show / Hide

    func showPanel() {
        positionOnActiveScreen()

        // Show with animation
        alphaValue = 0
        makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }

        // Content view scale animation
        if let contentView = contentView {
            contentView.wantsLayer = true
            contentView.layer?.transform = CATransform3DMakeScale(0.97, 0.97, 1)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                contentView.layer?.transform = CATransform3DIdentity
            }
        }

        installMonitors()
    }

    func hidePanel() {
        removeMonitors()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
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
        let panelWidth: CGFloat = 680
        let currentHeight = frame.height

        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.maxY - (screenFrame.height * 0.20) - currentHeight

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
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(newFrame, display: true)
        }
    }

    // MARK: - Event Monitors

    private func installMonitors() {
        // Global monitor: clicks outside the panel
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePanel()
        }

        // Local monitor: handle escape key
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape key
                self?.onCancel?()
                return nil
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
