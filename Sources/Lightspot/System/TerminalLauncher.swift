import AppKit
import Foundation

/// Runs a command in Terminal.app.
///
/// Unlike `QuickActionsProvider`, whose scripts are literals that never interpolate
/// input, this *has* to embed a caller-supplied command in an AppleScript string —
/// that is the whole feature. The command therefore goes through
/// `escapeForAppleScriptLiteral` before it is spliced in, so a command containing
/// quotes or backslashes cannot terminate the literal and become script code.
/// The finished script is handed to `/usr/bin/osascript` as a single argument, so
/// no shell ever parses it either.
enum TerminalLauncher {
    /// Escapes a string for use inside an AppleScript double-quoted literal.
    /// AppleScript only understands `\"`, `\\`, `\n`, `\r` and `\t` — any other
    /// control character is dropped rather than emitted raw.
    static func escapeForAppleScriptLiteral(_ text: String) -> String {
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

    /// The AppleScript that opens a Terminal window and runs `command` in it.
    static func script(for command: String) -> String {
        let literal = escapeForAppleScriptLiteral(command)
        return """
        tell application "Terminal"
            activate
            do script "\(literal)"
        end tell
        """
    }

    /// Opens Terminal.app and runs `command` in a new window.
    ///
    /// Runs on a background queue: `osascript` blocks until Terminal has answered
    /// the Apple event, which is far too long to hold the main thread for.
    static func run(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let source = script(for: trimmed)
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                NSLog("TerminalLauncher: Failed to run command in Terminal: %@", error.localizedDescription)
            }
        }
    }
}
