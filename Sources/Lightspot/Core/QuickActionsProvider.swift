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
                let result = SearchResult(
                    id: "action-\(action.lowercaseName.replacingOccurrences(of: " ", with: "-"))",
                    title: action.name,
                    subtitle: action.subtitle,
                    iconType: .systemSymbol(name: action.sfSymbol),
                    category: .quickActions,
                    score: score,
                    action: .runQuickAction(script: action.script, usesOsascript: action.usesOsascript)
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
