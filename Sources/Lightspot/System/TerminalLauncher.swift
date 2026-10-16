import AppKit
import Foundation

// MARK: - Terminal App Option

public enum TerminalAppOption: String, CaseIterable, Identifiable, Sendable {
    case terminal = "terminal"
    case iterm2 = "iterm2"
    case ghostty = "ghostty"
    case warp = "warp"
    case kitty = "kitty"
    case wezterm = "wezterm"
    case alacritty = "alacritty"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .terminal: return "Terminal"
        case .iterm2: return "iTerm2"
        case .ghostty: return "Ghostty"
        case .warp: return "Warp"
        case .kitty: return "Kitty"
        case .wezterm: return "WezTerm"
        case .alacritty: return "Alacritty"
        }
    }

    public var bundleIdentifier: String {
        switch self {
        case .terminal: return "com.apple.Terminal"
        case .iterm2: return "com.googlecode.iterm2"
        case .ghostty: return "com.mitchellh.ghostty"
        case .warp: return "dev.warp.Warp-Stable"
        case .kitty: return "net.kovidgoyal.kitty"
        case .wezterm: return "com.github.wez.wezterm"
        case .alacritty: return "org.alacritty"
        }
    }

    public var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    public static var installedOptions: [TerminalAppOption] {
        allCases.filter { $0.isInstalled || $0 == .terminal }
    }
}

// MARK: - Terminal Launcher

public enum TerminalLauncher {
    private static let defaultsKey = "lightspot_terminal_app"

    public static var currentTerminal: TerminalAppOption {
        get {
            if let saved = UserDefaults.standard.string(forKey: defaultsKey),
               let option = TerminalAppOption(rawValue: saved) {
                return option
            }
            return .terminal
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }

    /// Escapes a string for use inside an AppleScript double-quoted literal.
    public static func escapeForAppleScriptLiteral(_ text: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.unicodeScalars.count + 8)

        for scalar in text.unicodeScalars {
            switch scalar {
            case "\\":
                escaped += "\\\\"
            case "\"":
                escaped += "\\\""
            case "\n":
                escaped += "\\n"
            case "\r":
                escaped += "\\r"
            case "\t":
                escaped += "\\t"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F { continue }
                escaped.unicodeScalars.append(scalar)
            }
        }
        return escaped
    }

    /// The AppleScript that opens an Apple Terminal window and runs `command` in it.
    public static func script(for command: String) -> String {
        let literal = escapeForAppleScriptLiteral(command)
        return """
        tell application "Terminal"
            activate
            do script "\(literal)"
        end tell
        """
    }

    /// The AppleScript that opens an iTerm2 window and runs `command` in it.
    public static func itermScript(for command: String) -> String {
        let literal = escapeForAppleScriptLiteral(command)
        return """
        tell application "iTerm"
            activate
            try
                set myWindow to (create window with default profile)
                tell current session of myWindow
                    write text "\(literal)"
                end tell
            on error
                set myWindow to (current window)
                tell current session of myWindow
                    write text "\(literal)"
                end tell
            end try
        end tell
        """
    }

    /// The terminal `run(_:)` actually uses. Warp has no reliable way to start a
    /// command from outside the app (see `run(_:)`), and a terminal that is no longer
    /// installed falls back too, so both run commands in Apple Terminal.
    public static var commandTerminal: TerminalAppOption {
        let terminal = currentTerminal
        if terminal == .terminal || terminal == .warp || !terminal.isInstalled {
            return .terminal
        }
        return terminal
    }

    /// The user's login shell, the one Terminal and iTerm2 would open.
    public static var loginShell: String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return "/bin/zsh"
    }

    /// argv that runs `command` the way Terminal's `do script` does: in an interactive
    /// login shell (so aliases and PATH from the rc files apply), then hands the window
    /// over to a fresh shell so it stays open once the command exits.
    ///
    /// The terminals below exec their `-e` program directly, without a shell, so passing
    /// `git status` as one argument would look for a binary named "git status". The
    /// command is joined to the `exec` with a newline rather than `;` so a trailing
    /// `# comment` in a history entry cannot swallow it.
    public static func shellCommandArguments(for command: String, shell: String) -> [String] {
        [shell, "-l", "-i", "-c", "\(command)\nexec \(shellQuoted(shell)) -l"]
    }

    /// Single-quotes `text` for POSIX shells.
    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// `/usr/bin/open` arguments that start `terminal` running `command`, for the
    /// terminals driven by command-line flags; nil for the ones scripted another way.
    ///
    /// `-n` is required: when the app is already running, plain `open -a … --args`
    /// only activates it and silently drops the arguments, so the command never ran.
    /// `-b` targets the bundle ID that `isInstalled` checked, not a display name.
    public static func openArguments(for terminal: TerminalAppOption, command: String, shell: String) -> [String]? {
        let program = shellCommandArguments(for: command, shell: shell)
        let launch = ["-n", "-b", terminal.bundleIdentifier, "--args"]
        switch terminal {
        case .ghostty, .alacritty:
            // Everything after -e is the program and its arguments.
            return launch + ["-e"] + program
        case .kitty:
            // kitty takes the program positionally and stops parsing its own options there.
            return launch + program
        case .wezterm:
            return launch + ["start", "--"] + program
        case .terminal, .iterm2, .warp:
            return nil
        }
    }

    /// `warp://action/new_tab?path=…` for `path`. `.urlQueryAllowed` leaves `&`, `=`
    /// and `+` alone, which would split or rewrite a folder name containing them.
    public static func warpNewTabURL(path: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "warp://action/new_tab?path=\(encoded)")
    }

    /// Runs `command` in the user's preferred terminal emulator.
    public static func run(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let terminal = commandTerminal
        DispatchQueue.global(qos: .userInitiated).async {
            switch terminal {
            case .terminal, .warp:
                // Warp exposes no AppleScript dictionary and no CLI for running a
                // command. Its only documented route is a launch configuration opened
                // via warp://launch/<name>, which matches the YAML `name:` field rather
                // than a path (warpdotdev/warp#15003) and does not reliably pick up a
                // file written by another program (warpdotdev/warp#3780) — so the URI
                // could open nothing, or a stale command. `commandTerminal` therefore
                // maps Warp to Apple Terminal; opening folders in Warp still works.
                runAppleScript(script(for: trimmed))

            case .iterm2:
                runAppleScript(itermScript(for: trimmed))

            case .ghostty, .kitty, .wezterm, .alacritty:
                if let arguments = openArguments(for: terminal, command: trimmed, shell: loginShell) {
                    runSubprocess(executable: "/usr/bin/open", arguments: arguments)
                }
            }
        }
    }

    /// Opens the user's preferred terminal emulator with working directory set to `path`.
    public static func openFolder(at path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let folderURL = URL(fileURLWithPath: trimmed)
        let terminal = currentTerminal

        DispatchQueue.global(qos: .userInitiated).async {
            switch terminal {
            case .terminal:
                if let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = true
                    NSWorkspace.shared.open([folderURL], withApplicationAt: terminalURL, configuration: config) { _, error in
                        if error != nil {
                            runAppleScript(script(for: "cd \"\(escapeForAppleScriptLiteral(trimmed))\""))
                        }
                    }
                } else {
                    runAppleScript(script(for: "cd \"\(escapeForAppleScriptLiteral(trimmed))\""))
                }

            case .iterm2:
                if let itermURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") {
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = true
                    NSWorkspace.shared.open([folderURL], withApplicationAt: itermURL, configuration: config) { _, error in
                        if error != nil {
                            runAppleScript(itermScript(for: "cd \"\(escapeForAppleScriptLiteral(trimmed))\""))
                        }
                    }
                } else {
                    openFolderInAppleTerminal(folderURL: folderURL, path: trimmed)
                }

            case .ghostty:
                if terminal.isInstalled {
                    runSubprocess(executable: "/usr/bin/open", arguments: ["-n", "-b", terminal.bundleIdentifier, "--args", "--working-directory=\(trimmed)"])
                } else {
                    openFolderInAppleTerminal(folderURL: folderURL, path: trimmed)
                }

            case .warp:
                if terminal.isInstalled, let url = warpNewTabURL(path: trimmed) {
                    NSWorkspace.shared.open(url)
                } else if let warpURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "dev.warp.Warp-Stable") {
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = true
                    NSWorkspace.shared.open([folderURL], withApplicationAt: warpURL, configuration: config)
                } else {
                    openFolderInAppleTerminal(folderURL: folderURL, path: trimmed)
                }

            case .kitty:
                if terminal.isInstalled {
                    runSubprocess(executable: "/usr/bin/open", arguments: ["-n", "-b", terminal.bundleIdentifier, "--args", "--directory", trimmed])
                } else {
                    openFolderInAppleTerminal(folderURL: folderURL, path: trimmed)
                }

            case .wezterm:
                if terminal.isInstalled {
                    runSubprocess(executable: "/usr/bin/open", arguments: ["-n", "-b", terminal.bundleIdentifier, "--args", "start", "--cwd", trimmed])
                } else {
                    openFolderInAppleTerminal(folderURL: folderURL, path: trimmed)
                }

            case .alacritty:
                if terminal.isInstalled {
                    runSubprocess(executable: "/usr/bin/open", arguments: ["-n", "-b", terminal.bundleIdentifier, "--args", "--working-directory", trimmed])
                } else {
                    openFolderInAppleTerminal(folderURL: folderURL, path: trimmed)
                }
            }
        }
    }

    private static func openFolderInAppleTerminal(folderURL: URL, path: String) {
        if let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open([folderURL], withApplicationAt: terminalURL, configuration: config) { _, error in
                if error != nil {
                    runAppleScript(script(for: "cd \"\(escapeForAppleScriptLiteral(path))\""))
                }
            }
        } else {
            runAppleScript(script(for: "cd \"\(escapeForAppleScriptLiteral(path))\""))
        }
    }

    // MARK: - Finder Integration

    nonisolated(unsafe) private static var cachedFinderPath: (path: String?, timestamp: Date) = (nil, .distantPast)
    nonisolated(unsafe) private static var isRefreshingFinderPath = false
    private static let finderPathLock = NSLock()
    /// NSAppleScript is not thread-safe, so Finder queries are serialized here.
    private static let finderQueue = DispatchQueue(label: "com.lightspot.finderpath", qos: .utility)
    private static let finderPathStaleInterval: TimeInterval = 1.0

    /// Non-blocking variant for the search path: returns the last known folder right
    /// away and refreshes in the background when stale.
    ///
    /// `activeFinderFolderPath()` asks Finder over AppleScript and, if that fails,
    /// spawns `osascript` and waits — up to ~260 ms. QuickActionsProvider.search()
    /// runs on every keystroke, so it must never call the blocking form.
    public static func cachedFinderFolderPath() -> String? {
        finderPathLock.lock()
        let cached = cachedFinderPath.path
        let isStale = Date().timeIntervalSince(cachedFinderPath.timestamp) >= finderPathStaleInterval
        let shouldRefresh = isStale && !isRefreshingFinderPath
        if shouldRefresh {
            isRefreshingFinderPath = true
            // Claim the slot now so a burst of keystrokes queues only one query.
            cachedFinderPath.timestamp = Date()
        }
        finderPathLock.unlock()

        if shouldRefresh {
            finderQueue.async {
                _ = activeFinderFolderPath(forceRefresh: true)
                finderPathLock.lock()
                isRefreshingFinderPath = false
                finderPathLock.unlock()
            }
        }
        return cached
    }

    /// Queries the frontmost Finder window or selected subfolder and returns its POSIX path.
    /// Blocking — only call this when acting on the result, never from search.
    public static func activeFinderFolderPath(forceRefresh: Bool = false) -> String? {
        finderPathLock.lock()
        if !forceRefresh && Date().timeIntervalSince(cachedFinderPath.timestamp) < finderPathStaleInterval {
            let cached = cachedFinderPath.path
            finderPathLock.unlock()
            return cached
        }
        finderPathLock.unlock()

        let script = """
        tell application "Finder"
            if (count of windows) > 0 then
                try
                    set theSelection to selection
                    if theSelection is not {} then
                        set selItem to item 1 of theSelection
                        if class of selItem is folder then
                            return POSIX path of (selItem as alias)
                        end if
                    end if
                end try
                try
                    set winTarget to target of Finder window 1
                    return POSIX path of (winTarget as alias)
                end try
                try
                    set frontTarget to target of front window
                    return POSIX path of (frontTarget as alias)
                end try
                try
                    return POSIX path of (insertion location as alias)
                end try
            end if
            return ""
        end tell
        """

        var resolvedPath: String? = nil

        // 1. Try in-process NSAppleScript (< 1ms)
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let output = appleScript.executeAndReturnError(&error)
            if error == nil, let val = output.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !val.isEmpty {
                resolvedPath = val
            }
        }

        // 2. Fallback to /usr/bin/osascript if in-process AppleScript failed or returned nil
        if resolvedPath == nil {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if let val = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !val.isEmpty {
                    resolvedPath = val
                }
            } catch {}
        }

        finderPathLock.lock()
        cachedFinderPath = (resolvedPath, Date())
        finderPathLock.unlock()

        return resolvedPath
    }

    /// Opens the current Finder directory in the user's preferred terminal emulator.
    public static func openFinderCurrentFolderInTerminal() {
        if let folder = activeFinderFolderPath() {
            openFolder(at: folder)
        } else {
            // Fall back to home directory
            openFolder(at: NSHomeDirectory())
        }
    }

    // MARK: - Subprocess & AppleScript Execution

    private static func runAppleScript(_ source: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("TerminalLauncher: Failed to run osascript: %@", error.localizedDescription)
        }
    }

    private static func runSubprocess(executable: String, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("TerminalLauncher: Failed to run subprocess %@: %@", executable, error.localizedDescription)
        }
    }
}
