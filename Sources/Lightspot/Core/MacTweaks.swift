import Foundation

// MARK: - macOS Tweaks
//
// The `defaults write` one-liners developers keep in a dotfiles README, as quick actions.
// Every setting except Clear Dock Icons is a toggle that reads the current value and flips
// it, so the same row turns it back. Nothing here needs an administrator password.

enum MacTweaks {
    /// A shell toggle for boolean preferences. `defaultValue` is what macOS uses while the
    /// first key is unset; every key in `keys` is written to the opposite of the first's
    /// current value. `restart` names a process to relaunch so the change shows at once.
    static func toggleScript(domain: String, keys: [String], defaultValue: Bool, restart: String? = nil) -> String {
        let current = "$(defaults read \(domain) \(keys[0]) 2>/dev/null || echo \(defaultValue ? 1 : 0))"
        func write(_ value: Bool) -> String {
            keys.map { "defaults write \(domain) \($0) -bool \(value)" }.joined(separator: "; ")
        }
        var script = "case \"\(current)\" in 1|[Yy][Ee][Ss]|[Tt][Rr][Uu][Ee]) \(write(false));; *) \(write(true));; esac"
        if let restart { script += "; killall \(restart)" }
        return script
    }

    /// Instant Dock auto-hide (no delay, a quick slide) while the delay key is set; back to
    /// macOS's own timing by deleting both keys.
    static func instantDockScript(domain: String = "com.apple.dock", restart: String? = "Dock") -> String {
        var script = "if defaults read \(domain) autohide-delay >/dev/null 2>&1; "
            + "then defaults delete \(domain) autohide-delay; defaults delete \(domain) autohide-time-modifier 2>/dev/null; "
            + "else defaults write \(domain) autohide-delay -float 0; defaults write \(domain) autohide-time-modifier -float 0.15; fi"
        if let restart { script += "; killall \(restart)" }
        return script
    }

    static let actions: [QuickAction] = [
        QuickAction(
            name: "Clear Dock Icons",
            keywords: ["clear dock", "clear dock icons", "empty dock", "remove dock icons", "remove dock apps"],
            sfSymbol: "dock.rectangle",
            subtitle: "Remove every app pinned to the Dock, then restart it",
            script: "defaults write com.apple.dock persistent-apps -array && killall Dock",
            usesOsascript: false
        ),
        QuickAction(
            name: "Restart Dock",
            keywords: ["restart dock", "reload dock", "relaunch dock", "fix dock"],
            sfSymbol: "arrow.triangle.2.circlepath",
            subtitle: "Relaunch the Dock, Launchpad and Mission Control",
            script: "killall Dock",
            usesOsascript: false
        ),
        QuickAction(
            name: "Toggle Dock Auto-Hide",
            keywords: ["dock autohide", "auto hide dock", "autohide", "hide dock", "show dock"],
            sfSymbol: "dock.arrow.down.rectangle",
            subtitle: "Hide the Dock until the pointer reaches it, or keep it shown",
            script: #"tell application "System Events" to tell dock preferences to set autohide to not autohide"#,
            usesOsascript: true
        ),
        QuickAction(
            name: "Toggle Instant Dock Auto-Hide",
            keywords: ["instant dock", "fast dock", "dock delay", "dock animation", "dock speed", "autohide delay"],
            sfSymbol: "hare.fill",
            subtitle: "Show an auto-hidden Dock with no delay, or go back to macOS's timing",
            script: instantDockScript(),
            usesOsascript: false
        ),
        QuickAction(
            name: "Toggle Dock Recent Apps",
            keywords: ["dock recents", "recent apps in dock", "show recents", "suggested apps"],
            sfSymbol: "clock.arrow.circlepath",
            subtitle: "Show or hide recent and suggested apps in the Dock",
            script: toggleScript(domain: "com.apple.dock", keys: ["show-recents"], defaultValue: true, restart: "Dock"),
            usesOsascript: false
        ),
        QuickAction(
            name: "Toggle Hidden Files in Finder",
            keywords: ["hidden files", "show hidden files", "hide hidden files", "dotfiles", "show dotfiles"],
            sfSymbol: "eye.slash",
            subtitle: "Show or hide dotfiles and hidden folders in Finder (relaunches Finder)",
            script: toggleScript(domain: "com.apple.finder", keys: ["AppleShowAllFiles"], defaultValue: false, restart: "Finder"),
            usesOsascript: false
        ),
        QuickAction(
            name: "Toggle File Extensions in Finder",
            keywords: ["file extensions", "show extensions", "show file extensions", "hide extensions"],
            sfSymbol: "doc.text.magnifyingglass",
            subtitle: "Always show or hide filename extensions (relaunches Finder)",
            script: toggleScript(domain: "NSGlobalDomain", keys: ["AppleShowAllExtensions"], defaultValue: false, restart: "Finder"),
            usesOsascript: false
        ),
        QuickAction(
            name: "Toggle Finder Path Bar",
            keywords: ["path bar", "finder path", "show path bar"],
            sfSymbol: "folder.badge.gearshape",
            subtitle: "Show or hide the folder path at the bottom of Finder windows",
            script: toggleScript(domain: "com.apple.finder", keys: ["ShowPathbar"], defaultValue: false, restart: "Finder"),
            usesOsascript: false
        ),
        QuickAction(
            name: "Toggle Desktop Icons",
            keywords: ["desktop icons", "hide desktop icons", "show desktop icons", "presentation mode"],
            sfSymbol: "rectangle.on.rectangle.slash",
            subtitle: "Hide or show the files on the desktop, e.g. for a screen share (relaunches Finder)",
            script: toggleScript(domain: "com.apple.finder", keys: ["CreateDesktop"], defaultValue: true, restart: "Finder"),
            usesOsascript: false
        ),
        QuickAction(
            name: "Restart Finder",
            keywords: ["restart finder", "relaunch finder", "reload finder", "fix finder"],
            sfSymbol: "arrow.clockwise.circle",
            subtitle: "Relaunch Finder; its windows come back",
            script: "killall Finder",
            usesOsascript: false
        ),
        QuickAction(
            name: "Toggle Screenshot Shadows",
            keywords: ["screenshot shadow", "window shadow", "screenshot shadows"],
            sfSymbol: "camera.on.rectangle",
            subtitle: "Turn the drop shadow on window screenshots off or on",
            script: toggleScript(domain: "com.apple.screencapture", keys: ["disable-shadow"], defaultValue: false, restart: "SystemUIServer"),
            usesOsascript: false
        ),
        QuickAction(
            name: "Toggle .DS_Store on Network & USB Drives",
            keywords: [".ds_store", "ds_store", "dsstore", "ds store", "network drives", "usb drives"],
            sfSymbol: "externaldrive.badge.xmark",
            subtitle: "Stop or resume Finder writing .DS_Store files to network and USB volumes",
            script: toggleScript(domain: "com.apple.desktopservices", keys: ["DSDontWriteNetworkStores", "DSDontWriteUSBStores"],
                                 defaultValue: false, restart: "Finder"),
            usesOsascript: false
        ),
        QuickAction(
            name: "Toggle Press-and-Hold Accents",
            keywords: ["key repeat", "press and hold", "accent menu", "hold to repeat", "vim key repeat"],
            sfSymbol: "keyboard",
            subtitle: "Holding a key repeats it instead of showing accents, or back (relaunch apps to apply)",
            script: toggleScript(domain: "NSGlobalDomain", keys: ["ApplePressAndHoldEnabled"], defaultValue: true),
            usesOsascript: false
        ),
        QuickAction(
            name: "Toggle Smart Quotes & Dashes",
            keywords: ["smart quotes", "curly quotes", "smart dashes", "auto quotes", "straight quotes"],
            sfSymbol: "quote.opening",
            subtitle: "Stop or resume macOS turning \" into “ ” and -- into — as you type",
            script: toggleScript(domain: "NSGlobalDomain", keys: ["NSAutomaticQuoteSubstitutionEnabled", "NSAutomaticDashSubstitutionEnabled"],
                                 defaultValue: true),
            usesOsascript: false
        ),
    ]
}
