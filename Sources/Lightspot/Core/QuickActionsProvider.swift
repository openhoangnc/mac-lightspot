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
        )
    ]

    // MARK: - Search

    func search(_ query: String) -> [SearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        var results: [SearchResult] = []

        for action in actions {
            var highestScore: Double? = FuzzyMatcher.score(query: trimmedQuery, target: action.name)

            for keyword in action.keywords {
                if let kwScore = FuzzyMatcher.score(query: trimmedQuery, target: keyword) {
                    let weightedScore = kwScore * 0.95
                    if let current = highestScore {
                        highestScore = max(current, weightedScore)
                    } else {
                        highestScore = weightedScore
                    }
                }
            }

            if let score = highestScore {
                let script = action.script
                let usesOsascript = action.usesOsascript
                let icon = NSImage(systemSymbolName: action.sfSymbol, accessibilityDescription: action.name)

                let result = SearchResult(
                    title: action.name,
                    subtitle: action.subtitle,
                    icon: icon,
                    category: .quickActions,
                    score: score,
                    action: { @Sendable in
                        QuickActionsProvider.execute(script: script, usesOsascript: usesOsascript)
                    }
                )
                results.append(result)
            }
        }

        return results.sorted { $0.score > $1.score }
    }

    // MARK: - Execution

    static func execute(script: String, usesOsascript: Bool) {
        DispatchQueue.global(qos: .userInitiated).async {
            if usesOsascript {
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
                let path = String(script.dropFirst("open:".count))
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
