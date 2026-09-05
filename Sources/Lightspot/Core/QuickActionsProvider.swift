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
            keywords: ["flush dns", "dns", "clear dns", "cache", "network", "resolve", "sudo"],
            sfSymbol: "network.badge.shield.half.filled",
            subtitle: "Flush macOS DNS cache",
            script: "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder",
            usesOsascript: false,
            requiresAdmin: true
        ),
        QuickAction(
            name: "Purge Inactive Memory",
            keywords: ["purge", "clear ram", "free ram", "ram cache", "memory", "clean memory", "sudo"],
            sfSymbol: "memorychip",
            subtitle: "Free disk & inactive RAM buffers",
            script: "sudo purge",
            usesOsascript: false,
            requiresAdmin: true
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
        ),
        QuickAction(
            name: "Toggle Touch ID for Sudo",
            keywords: ["touch id", "sudo", "fingerprint", "pam", "terminal sudo", "touchid", "auth"],
            sfSymbol: "touchid",
            subtitle: "Enable / disable fingerprint for sudo in Terminal",
            script: "internal:toggle-touchid-sudo",
            usesOsascript: false,
            requiresAdmin: true
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
                } else if action.name == "Toggle Touch ID for Sudo" {
                    let enabled = Self.isTouchIdForSudoEnabled
                    subtitle = enabled ? "Touch ID for sudo is ENABLED · Press ↵ to disable" : "Touch ID for sudo is DISABLED · Press ↵ to enable (Touch ID / Admin)"
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

    // MARK: - Sudo & Privileged Execution

    /// Matches a bare `sudo` token at the start of the script or right after a shell separator.
    /// The `(?!-)` guard leaves `sudo -u postgres psql` alone: stripping the token there would
    /// promote `-u` to the command. Root's own `sudo` never re-prompts, so keeping it is harmless.
    private static let sudoTokenRegex = try? NSRegularExpression(pattern: #"(^|[;&|]\s*)sudo\s+(?!-)"#)

    /// Strips leading and chained `sudo ` calls since `with administrator privileges` executes as root directly.
    public static func stripSudo(from command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = sudoTokenRegex else { return trimmed }
        let full = NSRange(trimmed.startIndex..., in: trimmed)
        return regex.stringByReplacingMatches(in: trimmed, range: full, withTemplate: "$1")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Removes the `admin:` marker and any redundant `sudo` so a command is ready for either
    /// privileged backend. Both backends already run as root, so this must happen on both paths.
    public static func normalizePrivilegedCommand(_ command: String) -> String {
        var cleaned = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("admin:") {
            cleaned = String(cleaned.dropFirst("admin:".count))
        }
        return stripSudo(from: cleaned)
    }

    /// Determines if a shell script or action requires elevated administrator privileges.
    public static func requiresAdministratorPrivileges(script: String, requiresAdmin: Bool = false) -> Bool {
        if requiresAdmin { return true }
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("sudo ") || trimmed.contains("; sudo ") || trimmed.contains("&& sudo ") || trimmed.contains("|| sudo ") || trimmed.contains("| sudo ") {
            return true
        }
        if trimmed.hasPrefix("admin:") {
            return true
        }
        // `mDNSResponder` alone is too broad — only signalling it when the script actually
        // restarts the daemon keeps `grep mDNSResponder ...` out of the privileged path.
        if trimmed.contains("mDNSResponder") && trimmed.contains("killall") {
            return true
        }
        if trimmed == "purge" || trimmed.hasPrefix("purge ") {
            return true
        }
        // `SearchAction.runQuickAction` cannot carry the flag (it is Codable and persisted in
        // search history), so the action table stays the source of truth for built-in actions.
        return defaultActions.contains { $0.requiresAdmin && $0.script == trimmed }
    }

    /// Upper bound on a single PTY sudo attempt. pam_tid gives the user three tries at the
    /// fingerprint dialog; past this we abandon the attempt rather than pin a thread forever.
    private static let touchIDPTYTimeout: TimeInterval = 60

    /// Executes a privileged command using Touch ID via a background pseudo-terminal (PTY).
    /// If /etc/pam.d/sudo_local has pam_tid.so, this triggers native Touch ID without opening any Terminal window.
    /// If Touch ID fails or is unavailable, falls back to AppleScript password authorization.
    ///
    /// Blocking — call from a background queue only, never from the keystroke path.
    @discardableResult
    public static func executePrivilegedWithTouchID(command: String) -> Bool {
        let clean = normalizePrivilegedCommand(command)

        if TouchIdSudoCache.shared.refreshNow(), runOnTouchIDPTY(clean) {
            NSLog("QuickActionsProvider: Successfully executed via Touch ID PTY: %@", clean)
            return true
        }

        // Fallback to AppleScript Authorization Services (password dialog)
        return executePrivileged(shellScript: clean)
    }

    /// Runs `sudo /bin/sh -c <command>` against a headless PTY so pam_tid.so can raise Touch ID.
    /// Returns false — leaving nothing running — as soon as sudo falls through to a password prompt.
    private static func runOnTouchIDPTY(_ command: String) -> Bool {
        var master: Int32 = -1
        var slave: Int32 = -1
        guard openpty(&master, &slave, nil, nil, nil) == 0 else { return false }

        // closeOnDealloc is deliberately off: FileHandle would close `slave` a second time and
        // could take down an unrelated descriptor opened meanwhile on one of the background queues.
        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["/bin/sh", "-c", command]
        process.standardInput = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle

        let flags = fcntl(master, F_GETFL, 0)
        _ = fcntl(master, F_SETFL, flags | O_NONBLOCK)

        do {
            try process.run()
        } catch {
            close(slave)
            close(master)
            NSLog("QuickActionsProvider: PTY sudo spawn failed: %@", error.localizedDescription)
            return false
        }
        close(slave)

        var askedPassword = false
        var timedOut = false
        var tail = ""
        var buf = [UInt8](repeating: 0, count: 1024)
        let deadline = Date().addingTimeInterval(touchIDPTYTimeout)

        while process.isRunning {
            if Date() >= deadline {
                timedOut = true
                break
            }
            let n = read(master, &buf, buf.count)
            if n > 0 {
                // Keep a short tail so a prompt split across two reads is still recognised.
                tail = String((tail + String(decoding: buf[0..<n], as: UTF8.self)).suffix(256))
                if tail.localizedCaseInsensitiveContains("Password:") {
                    askedPassword = true
                    break
                }
            } else {
                usleep(50_000) // 50ms
            }
        }

        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()
        close(master)

        if !askedPassword && !timedOut && process.terminationStatus == 0 {
            return true
        }
        NSLog("QuickActionsProvider: PTY sudo fell through (status %d, askedPassword: %d, timedOut: %d)",
              process.terminationStatus, askedPassword ? 1 : 0, timedOut ? 1 : 0)
        return false
    }

    /// Executes a shell script with administrator privileges using macOS Authorization Services (Password).
    @discardableResult
    public static func executePrivileged(shellScript: String) -> Bool {
        let cleanCommand = normalizePrivilegedCommand(shellScript)

        let escaped = cleanCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: source) {
            appleScript.executeAndReturnError(&error)
            if let error = error {
                let errNum = error[NSAppleScript.errorNumber] as? Int
                if errNum == -128 {
                    NSLog("QuickActionsProvider: Privileged execution cancelled by user")
                } else {
                    NSLog("QuickActionsProvider: Privileged execution failed: %@", error)
                }
                return false
            }
            return true
        }
        return false
    }

    /// Whether Touch ID for sudo is enabled in /etc/pam.d/sudo_local.
    /// Non-blocking: returns the cached snapshot, so it is safe on the keystroke path.
    public static var isTouchIdForSudoEnabled: Bool {
        TouchIdSudoCache.shared.isEnabled
    }

    /// Toggles Touch ID authentication for sudo in Terminal via /etc/pam.d/sudo_local.
    /// Blocking — call from a background queue only.
    @discardableResult
    public static func toggleTouchIdForSudo() -> Bool {
        let ok: Bool
        if TouchIdSudoCache.shared.refreshNow() {
            let script = """
            if [ -f /etc/pam.d/sudo_local ]; then
                sed -i '' 's/^[[:space:]]*auth[[:space:]]*sufficient[[:space:]]*pam_tid.so/#auth       sufficient     pam_tid.so/' /etc/pam.d/sudo_local
            fi
            """
            ok = executePrivileged(shellScript: script)
        } else {
            let script = """
            if [ -f /etc/pam.d/sudo_local ]; then
                if grep -q "#auth.*pam_tid.so" /etc/pam.d/sudo_local; then
                    sed -i '' 's/#auth[[:space:]]*sufficient[[:space:]]*pam_tid.so/auth       sufficient     pam_tid.so/' /etc/pam.d/sudo_local
                elif ! grep -q "pam_tid.so" /etc/pam.d/sudo_local; then
                    echo "auth       sufficient     pam_tid.so" >> /etc/pam.d/sudo_local
                fi
            else
                if [ -f /etc/pam.d/sudo_local.template ]; then
                    sed 's/#auth[[:space:]]*sufficient[[:space:]]*pam_tid.so/auth       sufficient     pam_tid.so/' /etc/pam.d/sudo_local.template > /etc/pam.d/sudo_local
                else
                    echo "auth       sufficient     pam_tid.so" > /etc/pam.d/sudo_local
                fi
                chmod 444 /etc/pam.d/sudo_local
                chown root:wheel /etc/pam.d/sudo_local
            fi
            """
            ok = executePrivileged(shellScript: script)
        }
        // Refresh regardless: a cancelled dialog leaves the file untouched and simply re-reads
        // the same value, while a successful toggle must be reflected in the next search subtitle.
        _ = TouchIdSudoCache.shared.refreshNow()
        return ok
    }

    // MARK: - Execution

    static func execute(script: String, usesOsascript: Bool, requiresAdmin: Bool = false) {
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
            } else if script == "internal:toggle-touchid-sudo" {
                _ = toggleTouchIdForSudo()
            } else if requiresAdministratorPrivileges(script: script, requiresAdmin: requiresAdmin) {
                executePrivilegedWithTouchID(command: script)
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

// MARK: - Touch ID for sudo state cache

/// Caches the /etc/pam.d/sudo_local lookup. `QuickActionsProvider.search` reads this on every
/// keystroke that matches the Touch ID action, and invariant #0 forbids file I/O there — so the
/// property returns the last known snapshot and refreshes on a background queue behind an
/// in-flight flag, exactly like the Finder-folder and browser-tab caches.
private final class TouchIdSudoCache: @unchecked Sendable {
    static let shared = TouchIdSudoCache()

    private static let path = "/etc/pam.d/sudo_local"
    private static let staleAfter: TimeInterval = 5

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.lightspot.touchid-sudo")
    private var value = false
    private var lastRead = Date.distantPast
    private var refreshing = false

    private init() {
        scheduleRefresh()
    }

    /// Non-blocking snapshot for the keystroke path.
    var isEnabled: Bool {
        lock.lock()
        let snapshot = value
        let stale = Date().timeIntervalSince(lastRead) > Self.staleAfter
        lock.unlock()
        if stale { scheduleRefresh() }
        return snapshot
    }

    /// Blocking, authoritative read. Only for execution paths already off the main thread.
    @discardableResult
    func refreshNow() -> Bool {
        let fresh = Self.readFromDisk()
        lock.lock()
        value = fresh
        lastRead = Date()
        lock.unlock()
        return fresh
    }

    private func scheduleRefresh() {
        lock.lock()
        if refreshing {
            lock.unlock()
            return
        }
        refreshing = true
        lock.unlock()

        queue.async { [self] in
            let fresh = Self.readFromDisk()
            lock.lock()
            value = fresh
            lastRead = Date()
            refreshing = false
            lock.unlock()
        }
    }

    private static func readFromDisk() -> Bool {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return false
        }
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.hasPrefix("#") && trimmed.contains("pam_tid.so") {
                return true
            }
        }
        return false
    }
}
