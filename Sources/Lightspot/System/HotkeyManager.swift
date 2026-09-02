import Carbon
import AppKit

enum HotkeyOption: String, CaseIterable, Sendable {
    case commandSpace = "cmd_space"
    case commandShiftSpace = "cmd_shift_space"
    case optionSpace = "option_space"

    var displayName: String {
        switch self {
        case .commandSpace: return "⌘Space (Command + Space)"
        case .commandShiftSpace: return "⌘⇧Space (Command + Shift + Space)"
        case .optionSpace: return "⌥Space (Option + Space)"
        }
    }

    var shortLabel: String {
        switch self {
        case .commandSpace: return "⌘Space"
        case .commandShiftSpace: return "⌘⇧Space"
        case .optionSpace: return "⌥Space"
        }
    }

    var keyEquivalentModifierMask: NSEvent.ModifierFlags {
        switch self {
        case .commandSpace: return [.command]
        case .commandShiftSpace: return [.command, .shift]
        case .optionSpace: return [.option]
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .commandSpace: return UInt32(cmdKey)
        case .commandShiftSpace: return UInt32(cmdKey | shiftKey)
        case .optionSpace: return UInt32(optionKey)
        }
    }
}

final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    var onToggle: (() -> Void)?

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

    private func registerCurrentKey() {
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

        if status != noErr {
            print("Notice: RegisterEventHotKey returned \(status) for \(option.shortLabel)")
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    func reRegister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        registerCurrentKey()
    }
}
