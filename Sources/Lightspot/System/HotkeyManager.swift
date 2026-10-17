import Carbon
import AppKit

enum HotkeyOption: String, CaseIterable, Identifiable, Sendable {
    case commandSpace = "cmd_space"
    case commandShiftSpace = "cmd_shift_space"
    case optionSpace = "option_space"
    case controlSpace = "control_space"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .commandSpace: return "⌘Space (Command + Space)"
        case .commandShiftSpace: return "⌘⇧Space (Command + Shift + Space)"
        case .optionSpace: return "⌥Space (Option + Space)"
        case .controlSpace: return "⌃Space (Control + Space)"
        }
    }

    var shortLabel: String {
        switch self {
        case .commandSpace: return "⌘Space"
        case .commandShiftSpace: return "⌘⇧Space"
        case .optionSpace: return "⌥Space"
        case .controlSpace: return "⌃Space"
        }
    }

    var keyEquivalentModifierMask: NSEvent.ModifierFlags {
        switch self {
        case .commandSpace: return [.command]
        case .commandShiftSpace: return [.command, .shift]
        case .optionSpace: return [.option]
        case .controlSpace: return [.control]
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .commandSpace: return UInt32(cmdKey)
        case .commandShiftSpace: return UInt32(cmdKey | shiftKey)
        case .optionSpace: return UInt32(optionKey)
        case .controlSpace: return UInt32(controlKey)
        }
    }
}

final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    var onToggle: (() -> Void)?

    /// Whether the key combination is actually ours right now. False means some other
    /// owner (most often the system Spotlight shortcut) holds it and the hotkey is dead.
    private(set) var isRegistered = false

    private let userDefaultsKey = "lightspot_hotkey_option"
    private let signature: OSType = 0x4C535054 // "LSPT"

    var currentOption: HotkeyOption {
        get {
            if let saved = UserDefaults.standard.string(forKey: userDefaultsKey),
               let option = HotkeyOption(rawValue: saved) {
                return option
            }
            // Default to Command + Space
            return .commandSpace
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey)
            reRegister()
        }
    }

    init() {}

    deinit {
        unregister()
    }

    func register() {
        // Install event handler for hot key events if not already installed
        if eventHandler == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                          eventKind: UInt32(kEventHotKeyPressed))

            let handlerBlock: EventHandlerUPP = { _, event, userData -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.onToggle?()
                return noErr
            }

            let selfPtr = Unmanaged.passUnretained(self).toOpaque()

            InstallEventHandler(
                GetApplicationEventTarget(),
                handlerBlock,
                1,
                &eventType,
                selfPtr,
                &eventHandler
            )
        }

        registerCurrentKey()
    }

    @discardableResult
    private func registerCurrentKey() -> Bool {
        let option = currentOption
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(
            UInt32(kVK_Space),
            option.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        isRegistered = (status == noErr)
        if !isRegistered {
            // Carbon hands out a key combination once. While the system Spotlight
            // shortcut still owns ⌘Space this fails with eventHotKeyExistsErr
            // (-9878) and the panel simply never opens — so the failure is recorded
            // and `reRegisterIfNeeded()` retries once the shortcut is freed.
            hotKeyRef = nil
            NSLog("HotkeyManager: RegisterEventHotKey returned %d for %@ (already taken?)",
                  status, option.shortLabel)
        }
        return isRegistered
    }

    func unregister() {
        isRegistered = false
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    @discardableResult
    func reRegister() -> Bool {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        return registerCurrentKey()
    }

    /// Retries a registration that lost the race for the key combination. Call after
    /// freeing a conflicting system shortcut; a no-op when the hotkey is already live.
    @discardableResult
    func reRegisterIfNeeded() -> Bool {
        guard !isRegistered else { return true }
        return reRegister()
    }
}
