import AppKit

// MARK: - Quick Actions Provider

final class QuickActionsProvider: Sendable {
    static let shared = QuickActionsProvider()

    let actions: [QuickAction]

    init(actions: [QuickAction] = QuickActionsProvider.defaultActions) {
        self.actions = actions
    }

    // MARK: - Default Actions

    static let defaultActions: [QuickAction] = [
        QuickAction(
            name: "Lock Screen",
            keywords: ["lock", "screen", "sleep", "display"],
            sfSymbol: "lock.fill",
            subtitle: "Lock the current screen",
            script: #"tell app "System Events" to keystroke "q" using {command down, control down}"#,
            usesOsascript: true
        ),
        QuickAction(
            name: "Sleep",
            keywords: ["sleep", "suspend", "standby"],
            sfSymbol: "moon.fill",
            subtitle: "Put this Mac to sleep",
            script: "pmset sleepnow",
            usesOsascript: false
        ),
        QuickAction(
            name: "Restart",
            keywords: ["restart", "reboot"],
            sfSymbol: "arrow.clockwise",
            subtitle: "Restart this Mac",
            script: #"tell app "System Events" to restart"#,
            usesOsascript: true
        ),
        QuickAction(
            name: "Shut Down",
            keywords: ["shut down", "shutdown", "power off", "turn off"],
            sfSymbol: "power",
            subtitle: "Shut down this Mac",
            script: #"tell app "System Events" to shut down"#,
            usesOsascript: true
        ),
        QuickAction(
            name: "Empty Trash",
            keywords: ["empty trash", "trash", "bin", "clean"],
            sfSymbol: "trash.fill",
            subtitle: "Empty the Trash",
            script: #"tell app "Finder" to empty the trash"#,
            usesOsascript: true
        ),
        QuickAction(
            name: "Toggle Dark Mode",
            keywords: ["toggle dark mode", "dark mode", "light mode", "appearance", "theme"],
            sfSymbol: "circle.lefthalf.filled",
            subtitle: "Toggle between Dark and Light mode",
            script: #"tell app "System Events" to tell appearance preferences to set dark mode to not dark mode"#,
            usesOsascript: true
        ),
        QuickAction(
            name: "Mute Audio",
            keywords: ["mute", "mute audio", "silence", "volume", "sound", "quiet"],
            sfSymbol: "speaker.slash.fill",
            subtitle: "Mute system audio",
            script: "set volume with output muted",
            usesOsascript: true
        ),
        QuickAction(
            name: "Unmute Audio",
            keywords: ["unmute", "unmute audio", "volume", "sound"],
            sfSymbol: "speaker.wave.2.fill",
            subtitle: "Unmute system audio",
            script: "set volume without output muted",
            usesOsascript: true
        ),
        QuickAction(
            name: "Take Screenshot",
            keywords: ["take screenshot", "screenshot", "capture", "screen capture", "snip"],
            sfSymbol: "camera.viewfinder",
            subtitle: "Capture screen interactively",
            script: "/usr/sbin/screencapture -ui",
            usesOsascript: false
        ),
        QuickAction(
            name: "Activity Monitor",
            keywords: ["activity monitor", "task manager", "cpu", "memory", "processes", "activity", "monitor"],
            sfSymbol: "chart.bar.xaxis",
            subtitle: "Open Activity Monitor",
            script: "open:/System/Applications/Utilities/Activity Monitor.app",
            usesOsascript: false
        ),
        QuickAction(
            name: "Force Quit",
            keywords: ["force quit", "kill", "task manager", "close", "quit", "force"],
            sfSymbol: "xmark.circle.fill",
            subtitle: "Open Force Quit Applications window",
            script: #"tell application "System Events" to keystroke "." using {command down, option down}"#,
            usesOsascript: true
        ),
        QuickAction(
            name: "Flush DNS Cache",
            keywords: ["flush dns", "dns", "clear dns", "cache", "network", "resolve"],
            sfSymbol: "network.badge.shield.half.filled",
            subtitle: "Flush macOS DNS cache (dscacheutil)",
            script: "dscacheutil -flushcache; killall -HUP mDNSResponder",
            usesOsascript: false
        ),
        QuickAction(
            name: "Show Desktop",
            keywords: ["show desktop", "desktop", "hide windows", "minimize all", "clear screen"],
            sfSymbol: "menubar.dock.rectangle",
            subtitle: "Hide application windows to show desktop",
            script: #"tell application "Finder" to set visible of every process whose visible is true and name is not "Finder" to false"#,
            usesOsascript: true
        ),
        QuickAction(
            name: "Open Downloads",
            keywords: ["downloads", "download", "dl", "files", "folder"],
            sfSymbol: "arrow.down.circle.fill",
            subtitle: "Open ~/Downloads folder in Finder",
            script: "open:~/Downloads",
            usesOsascript: false
        ),
        QuickAction(
            name: "New Finder Window",
            keywords: ["new finder", "finder window", "open finder", "files", "browse"],
            sfSymbol: "macwindow.badge.plus",
            subtitle: "Open a new Finder window",
            script: #"tell application "Finder" to make new Finder window"#,
            usesOsascript: true
        ),
        QuickAction(
            name: "IP Address",
            keywords: ["ip", "ip address", "my ip", "network ip", "local ip", "public ip", "ipv4"],
            sfSymbol: "network",
            subtitle: "View and copy Local & Public IP addresses",
            script: "internal:copy-ip",
            usesOsascript: false
        ),
        QuickAction(
            name: "Terminal in Finder Folder",
            keywords: ["terminal here", "open terminal here", "terminal folder", "finder terminal", "term here"],
            sfSymbol: "terminal.fill",
            subtitle: "Open preferred terminal in active Finder directory",
            script: "internal:terminal-finder",
            usesOsascript: false
        )
    ]

    // MARK: - Search

    func search(_ query: SearchQuery) -> [SearchResult] {
        if query.isEmpty { return [] }

        var results: [SearchResult] = []

        for action in actions {
            var highestScore: Double? = FuzzyMatcher.score(query: query, targetLower: action.lowercaseName, targetTokens: [], targetInitials: nil)

            for keyword in action.lowercaseKeywords {
                if let kwScore = FuzzyMatcher.score(query: query, targetLower: keyword, targetTokens: [], targetInitials: nil) {
                    let weightedScore = kwScore * 0.95
                    if let current = highestScore {
                        highestScore = max(current, weightedScore)
                    } else {
                        highestScore = weightedScore
                    }
                }
            }

            if let score = highestScore {
                var subtitle = action.subtitle
                var actionPayload: SearchAction = .runQuickAction(script: action.script, usesOsascript: action.usesOsascript)

                if action.name == "IP Address" {
                    let local = NetworkInfoProvider.shared.localIPv4Address() ?? "Offline"
                    let pub = NetworkInfoProvider.shared.cachedPublicIPv4Address() ?? "Fetching..."
                    subtitle = "Local: \(local) · Public: \(pub) · Press ↵ to copy"
                    actionPayload = .copyToClipboard(pub != "Fetching..." ? "\(local) (Local) · \(pub) (Public)" : local)
                } else if action.name == "Terminal in Finder Folder" {
                    guard let folder = TerminalLauncher.cachedFinderFolderPath(), !folder.isEmpty else {
                        continue
                    }
                    let termName = TerminalLauncher.currentTerminal.displayName
                    let displayFolder = folder.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                    subtitle = "Open \(termName) in \(displayFolder)"
                }

                let result = SearchResult(
                    id: action.id,
                    title: action.name,
                    subtitle: subtitle,
                    iconType: .systemSymbol(name: action.sfSymbol),
                    category: .quickActions,
                    score: score,
                    action: actionPayload
                )
                results.append(result)
            }
        }

        return results.sorted { $0.score > $1.score }
    }

    // MARK: - Execution

    static func execute(script: String, usesOsascript: Bool) {
        DispatchQueue.global(qos: .userInitiated).async {
            if script == "internal:copy-ip" {
                if let local = NetworkInfoProvider.shared.localIPv4Address() {
                    let pub = NetworkInfoProvider.shared.cachedPublicIPv4Address()
                    let text = pub != nil ? "\(local) (Local) · \(pub!) (Public)" : local
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            } else if script == "internal:terminal-finder" {
                TerminalLauncher.openFinderCurrentFolderInTerminal()
            } else if usesOsascript {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    NSLog("QuickActionsProvider: Failed to run osascript '%@': %@", script, error.localizedDescription)
                }
            } else if script.hasPrefix("open:") {
                var path = String(script.dropFirst("open:".count))
                if path.hasPrefix("~") {
                    path = NSString(string: path).expandingTildeInPath
                }
                let url = URL(fileURLWithPath: path)
                NSWorkspace.shared.open(url)
            } else {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", script]
                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    NSLog("QuickActionsProvider: Failed to run shell command '%@': %@", script, error.localizedDescription)
                }
            }
        }
    }
}
