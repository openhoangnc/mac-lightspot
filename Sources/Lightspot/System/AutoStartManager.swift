import Foundation
import ServiceManagement
import AppKit

@MainActor
enum AutoStartManager {
    private nonisolated static let userDefaultsKey = "lightspot_auto_start_enabled"

    // `SMAppService.mainApp.status` costs ~3 ms (XPC round trip) and was read from
    // SwiftUI `Menu` content, which is re-evaluated on every body pass. Cache it and
    // refresh off the main thread instead. See SpotlightManager for the same pattern.
    private static var cachedEnabled: Bool = UserDefaults.standard.bool(forKey: userDefaultsKey)

    /// Instant, non-blocking read of the last known state.
    static var isEnabled: Bool { cachedEnabled }

    /// Re-reads the real registration status on a background queue.
    /// `onChange` runs on the main actor only when the value actually changed.
    static func refreshState(onChange: (@Sendable @MainActor () -> Void)? = nil) {
        DispatchQueue.global(qos: .utility).async {
            let probed = probeEnabled()
            Task { @MainActor in
                guard probed != cachedEnabled else { return }
                cachedEnabled = probed
                onChange?()
            }
        }
    }

    private nonisolated static func probeEnabled() -> Bool {
        let status = SMAppService.mainApp.status
        if status == .notRegistered || status == .notFound {
            return UserDefaults.standard.bool(forKey: userDefaultsKey)
        }
        return status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        UserDefaults.standard.set(enabled, forKey: userDefaultsKey)
        cachedEnabled = enabled // optimistic; refreshState() reconciles

        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            NSLog("AutoStartManager: Failed to update SMAppService: %@", error.localizedDescription)
            refreshState()
            return false
        }
    }

    static func toggle() -> Bool {
        let newState = !isEnabled
        _ = setEnabled(newState)
        return newState
    }
}
