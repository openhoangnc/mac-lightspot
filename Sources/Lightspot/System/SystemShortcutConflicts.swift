import Foundation

/// Spots a macOS system shortcut that is bound to the same key combination as the
/// Lightspot hotkey, so the shortcut submenu can say so.
///
/// This is a different failure from invariant 9. Carbon reports a hard conflict
/// (`eventHotKeyExistsErr`) only when the other owner registered through Carbon too,
/// and `HotkeyManager.isRegistered` covers that case. A symbolic hotkey is quieter:
/// `RegisterEventHotKey` succeeds, the panel opens, and the system shortcut still acts
/// on the same keystroke. Measured with ⌃Space, which macOS binds to "Select the
/// previous input source" (entry 60): the panel opened and the keyboard input source
/// switched underneath it. Nothing in the app could tell the user why, so the menu does.
///
/// Reads go through `cfprefsd` (invariant 8) and the answer is cached off the main
/// thread (invariant 0) because the menu reads it while being built.
@MainActor
enum SystemShortcutConflicts {
    // MARK: - Modifier masks
    //
    // `AppleSymbolicHotKeys` stores a binding as `parameters`:
    // [character code, virtual keycode, Cocoa modifier mask].

    nonisolated static let shiftMask = 131_072
    nonisolated static let controlMask = 262_144
    nonisolated static let optionMask = 524_288
    nonisolated static let commandMask = 1_048_576

    /// `kVK_Space`. Hardcoded rather than imported from Carbon so this file stays
    /// Foundation-only and the test runner can compile it on its own.
    nonisolated static let spaceKeyCode = 49

    /// A macOS shortcut that binds Space by default, and therefore competes with one
    /// of `HotkeyOption`'s combinations.
    struct SystemShortcut: Sendable, Equatable {
        /// The `AppleSymbolicHotKeys` entry key.
        let id: Int
        /// Apple's factory modifier mask for the entry, used when the user never
        /// customised it (there is then no `value` dict to read).
        let factoryModifiers: Int
        /// How System Settings names it.
        let name: String
        /// What the keystroke also does, phrased for a menu item suffix.
        let note: String
    }

    /// Every system shortcut on Space that can collide with a `HotkeyOption`.
    /// 64 and 65 are the Spotlight pair `SpotlightManager` manages; 60 and 61 are the
    /// input-source switchers, which nothing in the app can turn off for the user.
    nonisolated static let spaceShortcuts: [SystemShortcut] = [
        SystemShortcut(id: 60, factoryModifiers: controlMask,
                       name: "Select the previous input source",
                       note: "also switches input source"),
        SystemShortcut(id: 61, factoryModifiers: controlMask | optionMask,
                       name: "Select the next input source",
                       note: "also switches input source"),
        SystemShortcut(id: 64, factoryModifiers: commandMask,
                       name: "Show Spotlight search",
                       note: "macOS Spotlight still uses it"),
        SystemShortcut(id: 65, factoryModifiers: optionMask | commandMask,
                       name: "Show Finder search window",
                       note: "also opens a Finder search window"),
    ]

    /// The mask a Lightspot option's combination carries in symbolic-hotkey terms.
    nonisolated static func symbolicModifierMask(for option: HotkeyOption) -> Int {
        switch option {
        case .commandSpace: return commandMask
        case .commandShiftSpace: return commandMask | shiftMask
        case .optionSpace: return optionMask
        case .controlSpace: return controlMask
        }
    }

    // MARK: - Reading an entry

    /// `parameters` arrives as CFNumbers, which bridge to `Int` or `NSNumber`
    /// depending on how the value was written.
    nonisolated static func parameters(of entry: Any?) -> [Int]? {
        guard let entry = entry as? [String: Any],
              let value = entry["value"] as? [String: Any],
              let raw = value["parameters"] as? [Any] else { return nil }
        let numbers = raw.compactMap { $0 as? NSNumber }
        return numbers.count == raw.count ? numbers.map(\.intValue) : nil
    }

    /// The modifier mask an entry binds Space to, or `nil` when it is disabled or
    /// bound to some other key. An entry with no `value` means the factory binding:
    /// on a Mac where the shortcut was never customised there is no `value` dict at
    /// all, which is the same gap that made `SpotlightManager` create entries rather
    /// than set them.
    nonisolated static func spaceModifiers(of entry: Any?, factory: Int) -> Int? {
        guard SpotlightManager.isHotkeyEntryEnabled(entry) else { return nil }
        guard let parameters = parameters(of: entry) else { return factory }
        guard parameters.count >= 3, parameters[1] == spaceKeyCode else { return nil }
        return parameters[2]
    }

    /// The enabled system shortcut that holds `option`'s combination, if any.
    nonisolated static func conflict(for option: HotkeyOption, in root: [String: Any]) -> SystemShortcut? {
        let wanted = symbolicModifierMask(for: option)
        return spaceShortcuts.first { shortcut in
            spaceModifiers(of: root[String(shortcut.id)], factory: shortcut.factoryModifiers) == wanted
        }
    }

    /// Every option that currently collides, keyed by raw value so the snapshot stays
    /// `Equatable` and cheap to compare.
    nonisolated static func conflicts(in root: [String: Any]) -> [String: SystemShortcut] {
        var found: [String: SystemShortcut] = [:]
        for option in HotkeyOption.allCases {
            if let shortcut = conflict(for: option, in: root) {
                found[option.rawValue] = shortcut
            }
        }
        return found
    }

    // MARK: - Cached snapshot

    private static var cached: [String: SystemShortcut] = [:]
    private static var lastRefresh = Date.distantPast
    private static var isRefreshing = false

    /// Long enough that opening the menu twice in a row does not re-read, short enough
    /// that a shortcut changed in System Settings shows up on the next open.
    private nonisolated static let staleAfter: TimeInterval = 2

    /// Instant, non-blocking read for menu construction.
    static func cachedConflict(for option: HotkeyOption) -> SystemShortcut? {
        cached[option.rawValue]
    }

    /// Re-reads the system shortcuts on a background queue. `onChange` runs on the
    /// main actor only when the snapshot actually changed, so a menu rebuild happens
    /// no more often than the facts do.
    static func refresh(onChange: (@Sendable @MainActor () -> Void)? = nil) {
        guard !isRefreshing, Date().timeIntervalSince(lastRefresh) > staleAfter else { return }
        isRefreshing = true

        DispatchQueue.global(qos: .utility).async {
            let found = conflicts(in: SpotlightManager.readHotkeyRoot())
            Task { @MainActor in
                let changed = found != cached
                cached = found
                lastRefresh = Date()
                isRefreshing = false
                if changed { onChange?() }
            }
        }
    }
}
