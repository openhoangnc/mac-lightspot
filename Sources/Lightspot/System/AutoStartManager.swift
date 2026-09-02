import Foundation
import ServiceManagement
import AppKit

@MainActor
enum AutoStartManager {
    private static let userDefaultsKey = "lightspot_auto_start_enabled"

    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            if status == .enabled {
                return true
            } else if status == .notRegistered || status == .notFound {
                return UserDefaults.standard.bool(forKey: userDefaultsKey)
            }
            return status == .enabled
        } else {
            return UserDefaults.standard.bool(forKey: userDefaultsKey)
        }
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        UserDefaults.standard.set(enabled, forKey: userDefaultsKey)

        if #available(macOS 13.0, *) {
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
                return false
            }
        }
        return true
    }

    static func toggle() -> Bool {
        let newState = !isEnabled
        _ = setEnabled(newState)
        return newState
    }
}
