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
    ] + MacTweaks.actions

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
                let actionPayload: SearchAction = .runQuickAction(script: action.script, usesOsascript: action.usesOsascript)

                if action.name == "IP Address" {
                    // The action stays `internal:copy-ip`, which embeds no address, so
                    // search history never stores one; the IPs are read again on ↵.
                    subtitle = Self.ipAddressSubtitle(query: query, score: score)
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
                } else if let dock = MacTweaksDock.action(forScript: action.script),
                          let status = MacTweaksDock.Status.shared.subtitle(for: dock) {
                    // No backup to restore, or what the last run ran into: a snapshot, never a read.
                    subtitle = status
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

    // MARK: - IP Address

    /// Weakest match that may look up the public IP: a word-boundary prefix (85) or better,
    /// so substring, initials and subsequence matches never do.
    static let publicIPLookupMinScore: Double = 85

    /// True only when the query names the IP itself ("ip", "my ip", "public ip", "ipv4").
    /// The lookup is a request to api.ipify.org, and quick actions have no score floor, so
    /// matching the action is not enough: "lo" prefixes the "local ip" keyword, "ad" the
    /// word "address" and "i" the name, and none of them asked for an IP. "local ip" is a
    /// question about the local address only.
    static func queryAsksForPublicIP(_ query: SearchQuery, score: Double) -> Bool {
        guard score >= publicIPLookupMinScore else { return false }
        let words = query.lowercased.split { !$0.isLetter && !$0.isNumber }
        return words.contains { $0 == "ip" || $0 == "ipv4" } && !words.contains("local")
    }

    /// Shows the local IP immediately (getifaddrs, < 0.1 ms) and the public IP only once
    /// it has been asked for. Non-blocking: a lookup, if due, runs in the background.
    static func ipAddressSubtitle(query: SearchQuery, score: Double) -> String {
        let network = NetworkInfoProvider.shared
        if queryAsksForPublicIP(query, score: score) {
            network.requestPublicIPv4Address()
        }
        let local = network.localIPv4Address() ?? "Offline"
        switch network.publicIPState() {
        case .available(let ip):
            return "Local: \(local) · Public: \(ip) · Press ↵ to copy"
        case .fetching:
            return "Local: \(local) · Public: Fetching... · Press ↵ to copy"
        case .unavailable:
            return "Local: \(local) · Public: Unavailable · Press ↵ to copy"
        case .notRequested:
            return "Local: \(local) · Press ↵ to copy with public IP"
        }
    }

    /// ↵ on the IP Address row: the user asked, so look up the public IP if none is cached
    /// fresh, then copy both. Falls back to the local IP alone if the lookup fails.
    static func copyIPAddresses() {
        guard let local = NetworkInfoProvider.shared.localIPv4Address() else { return }
        let changeCount = NSPasteboard.general.changeCount
        NetworkInfoProvider.shared.requestPublicIPv4Address(force: true) { pub in
            let text = pub.map { "\(local) (Local) · \($0) (Public)" } ?? local
            DispatchQueue.main.async {
                // The lookup can take up to 3 s; never overwrite something copied meanwhile.
                guard NSPasteboard.general.changeCount == changeCount else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
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

    /// Upper bound on authenticating a single PTY sudo attempt. pam_tid gives the user three
    /// tries at the fingerprint dialog; past this we abandon the attempt rather than pin a
    /// thread forever. It covers authentication only: once the command has started it runs up
    /// to `privilegedRunTimeout`.
    private static let touchIDPTYTimeout: TimeInterval = 60

    /// How long a command that has started may run before it is stopped. Generous: a stopped
    /// command is never run again, so this only keeps a hung one from pinning a thread.
    private static let privilegedRunTimeout: TimeInterval = 30 * 60

    /// What a privileged script's output is kept to.
    static let privilegedOutputCap = 256 * 1024

    /// How a script Lightspot built itself ran as root (`runPrivilegedScript`).
    enum PrivilegedRun: Equatable, Sendable {
        /// The password dialog was dismissed: nothing ran.
        case cancelled
        /// Not authorized (the password refused, not an administrator), or the runner could not
        /// start: nothing ran.
        case refused(String)
        /// The script ran, exactly once: its exit status and its output, capped.
        case ran(status: Int32, output: String)
    }

    /// What one Touch ID attempt on the pty came to.
    enum TouchIDRun: Equatable, Sendable {
        /// The command started (its start marker reached the pty) and ended. Never run again.
        case ran(status: Int32, output: String)
        /// sudo never started it: it asked for a password, timed out, refused, or could not
        /// start. The password dialog may run it instead.
        case notStarted
    }

    /// Executes a privileged command using Touch ID via a background pseudo-terminal (PTY).
    /// If /etc/pam.d/sudo_local has pam_tid.so, this triggers native Touch ID without opening any Terminal window.
    /// If Touch ID fails or is unavailable, falls back to AppleScript password authorization.
    /// A command that started under Touch ID is never run a second time: when it fails, the
    /// answer is false, with no password dialog.
    ///
    /// Blocking — call from a background queue only, never from the keystroke path.
    @discardableResult
    public static func executePrivilegedWithTouchID(command: String) -> Bool {
        privilegedCommand(normalizePrivilegedCommand(command), touchIDEnabled: TouchIdSudoCache.shared.refreshNow(),
                          touchID: runOnTouchIDPTY, dialog: { executePrivileged(shellScript: $0) })
    }

    /// `executePrivilegedWithTouchID`'s rule, with its two backends handed in: Touch ID on the
    /// pty first when sudo has it; a run that started there is final, its status the answer;
    /// only one that never started goes to the password dialog.
    static func privilegedCommand(_ command: String, touchIDEnabled: Bool, touchID: (String) -> TouchIDRun,
                                  dialog: (String) -> Bool) -> Bool {
        if touchIDEnabled, case .ran(let status, _) = touchID(command) {
            NSLog("QuickActionsProvider: Privileged command ran via Touch ID (status %d)", status)
            return status == 0
        }
        // Fallback to AppleScript Authorization Services (password dialog)
        return dialog(command)
    }

    /// Runs a script Lightspot built itself, every argument already single-quoted, as root:
    /// exactly as given (no `admin:` or `sudo` stripping), after at most one prompt, and never
    /// a second time once it has started. Touch ID on the pty when sudo has pam_tid, else the
    /// password dialog. Blocking, and `NSAppleScript` is not thread-safe: one call at a time,
    /// from a serial background queue.
    static func runPrivilegedScript(_ script: String) -> PrivilegedRun {
        privilegedScript(script, touchIDEnabled: TouchIdSudoCache.shared.refreshNow(), touchID: runOnTouchIDPTY,
                         dialog: runWithPasswordDialog)
    }

    /// `runPrivilegedScript`'s rule, with its two backends handed in: a run that started under
    /// Touch ID is final, whatever its status; only one that never started reaches the dialog.
    static func privilegedScript(_ script: String, touchIDEnabled: Bool, touchID: (String) -> TouchIDRun,
                                 dialog: (String) -> PrivilegedRun) -> PrivilegedRun {
        if touchIDEnabled, case .ran(let status, let output) = touchID(script) {
            NSLog("QuickActionsProvider: Privileged script ran via Touch ID (status %d)", status)
            return .ran(status: status, output: output)
        }
        return dialog(script)
    }

    /// The password dialog: `do shell script … with administrator privileges`, the script as given.
    private static func runWithPasswordDialog(_ script: String) -> PrivilegedRun {
        guard let appleScript = NSAppleScript(source: doShellScriptSource(script)) else {
            return .refused("The password dialog could not be built.")
        }
        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)
        let run = error.map {
            appleScriptOutcome(number: $0[NSAppleScript.errorNumber] as? Int ?? 0, message: $0[NSAppleScript.errorMessage] as? String ?? "")
        } ?? .ran(status: 0, output: (result.stringValue ?? "").replacingOccurrences(of: "\r", with: "\n"))
        switch run {
        case .cancelled: NSLog("QuickActionsProvider: Privileged script cancelled by user")
        case .refused: NSLog("QuickActionsProvider: Privileged script refused (error %d)", error?[NSAppleScript.errorNumber] as? Int ?? 0)
        case .ran(let status, _): NSLog("QuickActionsProvider: Privileged script ran via the password dialog (status %d)", status)
        }
        return run
    }

    /// What a `do shell script … with administrator privileges` error means: -128 is the
    /// dialog dismissed; a positive number is the script's exit status, its message the
    /// script's stderr (or stdout); anything else (a refused password) ran nothing.
    static func appleScriptOutcome(number: Int, message: String) -> PrivilegedRun {
        if number == -128 { return .cancelled }
        if number > 0 { return .ran(status: Int32(clamping: number), output: message.replacingOccurrences(of: "\r", with: "\n")) }
        return .refused(message)
    }

    /// The command the pty's sudo runs: it first prints `marker`, which only the command itself
    /// can print, so the marker reaching the pty means sudo authenticated and started it. The
    /// marker goes in as two halves, so the command line holds no copy of it: sudo echoing the
    /// command ("…is not allowed to execute '/bin/sh -c …'") can never pass for it. Then stdin
    /// is /dev/null: sudo needs the pty only before the marker, and a command that asks a
    /// question must not wait on it.
    static func markedCommand(_ command: String, marker: String) -> String {
        let half = marker.index(marker.startIndex, offsetBy: marker.count / 2)
        return "printf '%s%s\\n' '\(marker[..<half])' '\(marker[half...])'; exec </dev/null; " + command
    }

    /// Ends `process` (sudo): SIGTERM, which sudo passes on to its command; past `grace`,
    /// SIGKILL, which it can't pass on, so a command that started may run on as root. Whether
    /// sudo, which runs as root, takes the user's signals once its command runs could not be
    /// checked without a prompt: `kill` says, and the log with it. Either way the wait ends.
    /// True once sudo is gone.
    static func stop(_ process: Process, grace: TimeInterval = 5) -> Bool {
        process.terminate()
        if waitForExit(process, seconds: grace) { return true }
        if kill(process.processIdentifier, SIGKILL) == 0 {
            NSLog("QuickActionsProvider: sudo ignored SIGTERM and was killed; the command it started may still be running as root")
        } else {
            NSLog("QuickActionsProvider: sudo could not be stopped (errno %d); it may still be running", errno)
        }
        return waitForExit(process, seconds: 2)
    }

    private static func waitForExit(_ process: Process, seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while process.isRunning && Date() < deadline { usleep(20_000) }
        return !process.isRunning
    }

    /// Reads what non-blocking `fd` holds, handing each chunk to `take`, until it has nothing
    /// more, `limit` bytes are read, or `seconds` pass: a child that keeps the pty open and
    /// keeps writing can't keep it reading.
    static func drain(_ fd: Int32, seconds: TimeInterval, limit: Int, _ take: (ArraySlice<UInt8>) -> Void) {
        var buf = [UInt8](repeating: 0, count: 4096)
        var total = 0
        let deadline = Date().addingTimeInterval(seconds)
        while total < limit && Date() < deadline {
            let n = read(fd, &buf, buf.count)
            if n > 0 {
                take(buf[0..<n])
                total += n
            } else if !(n < 0 && errno == EINTR) {
                break
            }
        }
    }

    /// How a Touch ID run ended, from everything the pty printed (`transcript`, read to the
    /// end after the process exited) and its exit status. The marker decides: with it the
    /// command ran, whatever came before or after it (sudo's `Password:` cannot come after,
    /// and a `Password:` the command printed is its own output); without it, it never started.
    /// The output is what followed the marker's line, with the pty's `\r\n` made `\n`.
    static func touchIDVerdict(transcript: String, marker: String, status: Int32) -> TouchIDRun {
        guard let found = transcript.range(of: marker) else { return .notStarted }
        var output = String(transcript[found.upperBound...]).replacingOccurrences(of: "\r\n", with: "\n")
        if output.hasPrefix("\n") { output.removeFirst() }
        return .ran(status: status, output: output)
    }

    private static func contains(_ haystack: ArraySlice<UInt8>, _ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, haystack.count >= needle.count else { return false }
        var index = haystack.startIndex
        while index + needle.count <= haystack.endIndex {
            if haystack[index] == needle[0] && haystack[index..<index + needle.count].elementsEqual(needle) { return true }
            index += 1
        }
        return false
    }

    /// Runs `sudo /bin/sh -c <command>` against a headless PTY so pam_tid.so can raise Touch ID,
    /// the command preceded by a random start marker (`markedCommand`). Before the marker,
    /// sudo's `Password:` prompt (Touch ID unavailable or cancelled) or `touchIDPTYTimeout`
    /// ends the attempt, leaving nothing running. After it, the command runs to its end.
    private static func runOnTouchIDPTY(_ command: String) -> TouchIDRun {
        var master: Int32 = -1
        var slave: Int32 = -1
        guard openpty(&master, &slave, nil, nil, nil) == 0 else { return .notStarted }

        let marker = "__LS_ROOT_" + UUID().uuidString
        let markerBytes = Array(marker.utf8)
        // closeOnDealloc is deliberately off: FileHandle would close `slave` a second time and
        // could take down an unrelated descriptor opened meanwhile on one of the background queues.
        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["/bin/sh", "-c", markedCommand(command, marker: marker)]
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
            return .notStarted
        }
        close(slave)

        var transcript: [UInt8] = []
        var started = false
        var askedPassword = false
        var timedOut = false
        var buf = [UInt8](repeating: 0, count: 4096)
        let authDeadline = Date().addingTimeInterval(touchIDPTYTimeout)
        let runDeadline = Date().addingTimeInterval(privilegedRunTimeout)

        /// Keeps what the pty printed, up to the cap (past it the rest is read and dropped, so
        /// the command never blocks on a full pty), and notes the marker.
        func take(_ chunk: ArraySlice<UInt8>) {
            let room = privilegedOutputCap + markerBytes.count - transcript.count
            if room > 0 { transcript.append(contentsOf: chunk.prefix(room)) }
            if !started {
                // The new bytes, and enough before them for a marker split across two reads.
                let from = max(0, transcript.count - chunk.count - markerBytes.count)
                started = contains(transcript[from...], markerBytes)
            }
        }

        while process.isRunning {
            if Date() >= (started ? runDeadline : authDeadline) {
                timedOut = true
                break
            }
            let n = read(master, &buf, buf.count)
            if n > 0 {
                take(buf[0..<n])
                // Only sudo prompts before the marker; afterwards it is the command's own output.
                if !started && String(decoding: transcript.suffix(256), as: UTF8.self).localizedCaseInsensitiveContains("Password:") {
                    askedPassword = true
                    break
                }
            } else {
                usleep(50_000) // 50ms
            }
        }

        let exited = process.isRunning ? stop(process) : true
        if exited { process.waitUntilExit() }
        // What the command printed just before it ended is still in the pty: read it, so a
        // command that starts and ends between two reads is still seen to have started.
        drain(master, seconds: 1, limit: privilegedOutputCap, take)
        close(master)

        let status = exited ? process.terminationStatus : -1
        let verdict = touchIDVerdict(transcript: String(decoding: transcript, as: UTF8.self), marker: marker, status: status)
        if verdict == .notStarted {
            NSLog("QuickActionsProvider: PTY sudo fell through (status %d, askedPassword: %d, timedOut: %d)",
                  status, askedPassword ? 1 : 0, timedOut ? 1 : 0)
        }
        return verdict
    }

    /// The AppleScript `executePrivileged` runs: `do shell script` hands `command` to
    /// `/bin/sh -c`, as root with `administrator`. Only `\` and `"` need escaping inside an
    /// AppleScript string.
    static func doShellScriptSource(_ command: String, administrator: Bool = true) -> String {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\"" + (administrator ? " with administrator privileges" : "")
    }

    /// Executes a shell script with administrator privileges using macOS Authorization Services (Password).
    /// Logs the outcome only, never the script: its paths would reach the unified log.
    @discardableResult
    public static func executePrivileged(shellScript: String) -> Bool {
        let cleanCommand = normalizePrivilegedCommand(shellScript)
        let source = doShellScriptSource(cleanCommand)

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: source) {
            appleScript.executeAndReturnError(&error)
            if let error = error {
                let errNum = error[NSAppleScript.errorNumber] as? Int
                if errNum == -128 {
                    NSLog("QuickActionsProvider: Privileged execution cancelled by user")
                } else {
                    NSLog("QuickActionsProvider: Privileged execution failed (error %d)", errNum ?? 0)
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
                copyIPAddresses()
            } else if script == "internal:terminal-finder" {
                TerminalLauncher.openFinderCurrentFolderInTerminal()
            } else if script == "internal:toggle-touchid-sudo" {
                _ = toggleTouchIdForSudo()
            } else if let installer = ToolInstallersProvider.installer(forScript: script) {
                ToolInstallersProvider.shared.run(installer)
            } else if let dock = MacTweaksDock.action(forScript: script) {
                // Clear Dock Icons saves the icons first, the 1.3.x one-liner search history may
                // replay included. When either changes nothing, its row's subtitle says why.
                MacTweaksDock.run(dock)
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
                SystemSettingsOpener.openAny(url)
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
