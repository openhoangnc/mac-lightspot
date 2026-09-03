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

    /// Runs `command` in the user's preferred terminal emulator.
    public static func run(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let terminal = currentTerminal
        DispatchQueue.global(qos: .userInitiated).async {
            switch terminal {
            case .terminal:
                runAppleScript(script(for: trimmed))

            case .iterm2:
                if terminal.isInstalled {
                    runAppleScript(itermScript(for: trimmed))
                } else {
                    runAppleScript(script(for: trimmed))
                }

            case .ghostty:
                if terminal.isInstalled {
                    runSubprocess(executable: "/usr/bin/open", arguments: ["-na", "Ghostty", "--args", "-e", trimmed])
                } else {
                    runAppleScript(script(for: trimmed))
                }

            case .warp:
                if terminal.isInstalled,
                   let url = URL(string: "warp://action/new_tab?path=~") {
                    NSWorkspace.shared.open(url)
                } else {
                    runAppleScript(script(for: trimmed))
                }

            case .kitty:
                if terminal.isInstalled {
                    runSubprocess(executable: "/usr/bin/open", arguments: ["-a", "kitty", "--args", "-e", trimmed])
                } else {
                    runAppleScript(script(for: trimmed))
                }

            case .wezterm:
                if terminal.isInstalled {
                    runSubprocess(executable: "/usr/bin/open", arguments: ["-a", "WezTerm", "--args", "start", "--", trimmed])
                } else {
                    runAppleScript(script(for: trimmed))
                }

            case .alacritty:
                if terminal.isInstalled {
                    runSubprocess(executable: "/usr/bin/open", arguments: ["-a", "Alacritty", "--args", "-e", trimmed])
                } else {
                    runAppleScript(script(for: trimmed))
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
                    runSubprocess(executable: "/usr/bin/open", arguments: ["-na", "Ghostty", "--args", "--working-directory=\(trimmed)"])
                } else {
                    openFolderInAppleTerminal(folderURL: folderURL, path: trimmed)
                }

            case .warp:
                if terminal.isInstalled,
                   let encodedPath = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "warp://action/new_tab?path=\(encodedPath)") {
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
                    runSubprocess(executable: "/usr/bin/open", arguments: ["-a", "kitty", "--args", "--directory", trimmed])
                } else {
                    openFolderInAppleTerminal(folderURL: folderURL, path: trimmed)
                }

            case .wezterm:
                if terminal.isInstalled {
                    runSubprocess(executable: "/usr/bin/open", arguments: ["-a", "WezTerm", "--args", "start", "--cwd", trimmed])
                } else {
                    openFolderInAppleTerminal(folderURL: folderURL, path: trimmed)
                }

            case .alacritty:
                if terminal.isInstalled {
                    runSubprocess(executable: "/usr/bin/open", arguments: ["-a", "Alacritty", "--args", "--working-directory", trimmed])
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

    /// Queries the frontmost Finder window or selected subfolder and returns its POSIX path.
    public static func activeFinderFolderPath() -> String? {
        let script = """
        tell application "Finder"
            if (count of Finder windows) > 0 then
                try
                    set theSelection to selection
                    if theSelection is not {} and class of item 1 of theSelection is folder then
                        return POSIX path of (item 1 of theSelection as alias)
                    else
                        return POSIX path of (target of front Finder window as alias)
                    end if
                on error
                    return ""
                end try
            end if
            return ""
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let output = appleScript.executeAndReturnError(&error)
            if error == nil, let stringVal = output.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !stringVal.isEmpty {
                return stringVal
            }
        }
        return nil
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
