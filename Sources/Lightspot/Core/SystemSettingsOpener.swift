import AppKit

// MARK: - Opening System Settings past LaunchServices' dead records
//
// Measured on macOS 27.2: System Settings can exit without launchservicesd hearing of it
// ("ListenForProcessExitFromRunningboard(…), failed twice to find expected application"). Its
// record stays, a Foreground app with a running dot in the Dock, until launchservicesd notices
// late (67 s once) or its sweep ("Forcibly removing application … because it seems we missed a
// death notification", every ten minutes) drops it. Meanwhile every open of a System Settings
// link, profile or the app itself goes to that dead PID, even when a live instance is running
// and frontmost: the Apple Event finds no process (procNotFound, -600) and CoreServicesUIAgent
// shows an alert with Finder's icon instead of opening anything, "The application "System
// Settings" is not open anymore." for the plain `NSWorkspace.open(_:)`, "The application can't
// be opened." -600 for `open(_:configuration:)` with its default `promptsUserIfNeeded`.
// NSRunningApplication reads the same records, so it calls the dead instance running too.
//
// So the opener checks each recorded PID itself, and opens quietly. Only dead records: a new
// instance (`createsNewApplicationInstance`), which gets the URL at launch and hands nothing to
// the dead PID; it opens the right pane, and the dead record lingers harmlessly until
// launchservicesd drops it. Otherwise the open goes through LaunchServices with
// `promptsUserIfNeeded = false`, so a failed hand-off comes back as an error, never an alert.
// On that error a live instance that still shows its window is asked to quit (one already
// quitting has none left), the opener waits up to 5 s for the live ones to exit and retries once,
// quietly; if LaunchServices still hands it to a dead record, the URL opens in a new instance:
// one System Settings, on the pane asked for. A prompting open is used only after a quiet one
// failed some other way, so macOS speaks only for a failure that isn't this one.

enum SystemSettingsOpener {
    static let bundleIdentifier = "com.apple.systempreferences"
    static let appURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
    static let executablePath = appURL.path + "/Contents/MacOS/System Settings"
    static let urlScheme = "x-apple.systempreferences"
    /// How long to wait for a live instance to exit.
    static let exitWait: TimeInterval = 5
    static let pollInterval: TimeInterval = 0.1
    /// How long the live environment waits for LaunchServices to answer one open.
    static let answerWait: TimeInterval = 15

    enum Mode: Equatable, Sendable {
        /// `promptsUserIfNeeded` left on: a failure is macOS's to report.
        case normal
        /// `promptsUserIfNeeded = false`: a failure comes back as an error, never an alert.
        case quiet
        /// A new instance (`createsNewApplicationInstance`) given the URL at launch, quietly:
        /// nothing is handed to a recorded instance.
        case newInstance
        /// The same, prompting: a launch failure is macOS's to report, and a new instance has
        /// no hand-off to fail.
        case newInstancePrompting
    }

    enum Outcome: Equatable, Sendable {
        /// Launched, or handed to the live instance, at the first try.
        case opened
        /// Opened again once the instance had gone and LaunchServices had dropped its record.
        case reopened
        /// Opened in a new instance, past records of instances that had gone.
        case relaunched
        /// The quiet open failed for another reason; opened the ordinary way.
        case fellBack
    }

    /// The system access the decisions need, faked in test_engine.
    struct Environment: Sendable {
        /// The PIDs LaunchServices records for System Settings, dead or alive.
        var instances: @Sendable () -> [pid_t] = { [] }
        /// Whether that PID is a running System Settings process.
        var isAlive: @Sendable (pid_t) -> Bool = { _ in false }
        /// Whether that process has any window left (⌘Q closes them all at once).
        var hasWindows: @Sendable (pid_t) -> Bool = { _ in false }
        /// Asks that instance to quit, as ⌘Q does.
        var requestQuit: @Sendable (pid_t) -> Void = { _ in }
        /// Opens `url` and returns LaunchServices' error, nil once it took it.
        var open: @Sendable (_ url: URL, _ mode: Mode) -> Error? = { _, _ in nil }
        var now: @Sendable () -> Date = { Date() }
        var sleep: @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }

        static let live: Environment = {
            var env = Environment()
            env.instances = { recordedInstances() }
            env.isAlive = { isSystemSettingsProcess($0) }
            env.hasWindows = { ownsWindows(pid: $0) }
            env.requestQuit = { pid in
                DispatchQueue.main.async { _ = NSRunningApplication(processIdentifier: pid)?.terminate() }
            }
            env.open = { url, mode in liveOpen(url, mode: mode) }
            return env
        }()
    }

    /// Opens one at a time and in order: Apple Intelligence opens its profile file, then a
    /// second later Device Management, and a wait for an instance to exit holds both back.
    private static let queue = DispatchQueue(label: "com.lightspot.app.settings-opener", qos: .userInitiated)

    /// Opens a System Settings link (`x-apple.systempreferences:`), a file System Settings
    /// opens (a profile), or System Settings itself (`appURL`). Returns at once, from any
    /// thread; the work, and any wait, runs on the opener's own queue.
    static func open(_ url: URL) {
        open(url, environment: .live)
    }

    /// `open(_:)` with the system access given: test_engine checks the order with fakes.
    static func open(_ url: URL, environment: Environment) {
        queue.async {
            switch run(url, environment: environment) {
            case .opened: break
            case .reopened: NSLog("SystemSettingsOpener: opened again once the old System Settings had gone")
            case .relaunched: NSLog("SystemSettingsOpener: LaunchServices still recorded a System Settings that had gone; opened a new one")
            case .fellBack: NSLog("SystemSettingsOpener: the quiet open failed; opened the ordinary way")
            }
        }
    }

    /// Opens `url` through `open(_:)` when System Settings is what opens it, else straight
    /// through NSWorkspace, as before.
    static func openAny(_ url: URL) {
        if opensInSystemSettings(url) {
            open(url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    /// The decisions, synchronous. Never call it on the main thread with `.live`: it waits.
    static func run(_ url: URL, environment env: Environment) -> Outcome {
        let recorded = env.instances()
        let live = recorded.filter(env.isAlive)
        // Only records of instances that have gone: any hand-off would go to a dead PID.
        if !recorded.isEmpty, live.isEmpty { return launchNew(url, env) }
        // Quiet even with nothing recorded: the list can read empty for a moment while
        // LaunchServices still holds a dead record (measured), and then a prompting open alerts.
        guard let error = env.open(url, .quiet) else { return .opened }
        guard isHandOffFailure(error) else {
            _ = env.open(url, .normal)
            return .fellBack
        }
        // The open went to a dead record or to an instance on its way out. One still showing
        // its window is asked to quit, so the new instance is the only one; one that has none
        // left is quitting already.
        for pid in live where env.hasWindows(pid) { env.requestQuit(pid) }
        let deadline = env.now().addingTimeInterval(exitWait)
        while live.contains(where: env.isAlive), env.now() < deadline {
            env.sleep(pollInterval)
        }
        // The single retry, quiet: it launches System Settings once LaunchServices has dropped
        // the records, and is handed to a dead one, harmlessly, while it hasn't.
        guard let retryError = env.open(url, .quiet) else { return .reopened }
        guard isHandOffFailure(retryError) else {
            _ = env.open(url, .normal)
            return .fellBack
        }
        return launchNew(url, env)
    }

    /// A new instance with the URL, quietly; if that fails, once more with macOS's own message.
    private static func launchNew(_ url: URL, _ env: Environment) -> Outcome {
        if env.open(url, .newInstance) != nil {
            _ = env.open(url, .newInstancePrompting)
        }
        return .relaunched
    }

    /// LaunchServices handed the open to an instance that is gone or going: procNotFound
    /// (-600), measured on 27.2, or connectionInvalid (-609), its sibling when the process
    /// dies during the send. Looked for anywhere in the underlying-error chain.
    static func isHandOffFailure(_ error: Error) -> Bool {
        var current: NSError? = error as NSError
        while let nsError = current {
            if nsError.domain == NSOSStatusErrorDomain, nsError.code == -600 || nsError.code == -609 {
                return true
            }
            current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    /// Whether System Settings is what opens `url`: its links, the app itself, and the files
    /// it installs (configuration profiles, preference panes).
    static func opensInSystemSettings(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == urlScheme { return true }
        guard url.isFileURL else { return false }
        if isSystemSettingsApp(path: url.path) { return true }
        return ["mobileconfig", "prefpane"].contains(url.pathExtension.lowercased())
    }

    static func isSystemSettingsApp(path: String) -> Bool {
        URL(fileURLWithPath: path).standardizedFileURL.path == appURL.path
    }

    // MARK: Live system access

    /// What LaunchServices records, which may include instances that have exited.
    static func recordedInstances() -> [pid_t] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { !$0.isTerminated }
            .map(\.processIdentifier)
    }

    /// The process exists and runs System Settings' executable, so a reused PID doesn't count.
    static func isSystemSettingsProcess(_ pid: pid_t) -> Bool {
        guard pid > 0, kill(pid, 0) == 0 || errno == EPERM else { return false }
        // PROC_PIDPATHINFO_MAXSIZE, a macro Swift does not import.
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return true }
        let bytes = path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self) == executablePath
    }

    /// Any normal-level window, on screen or not (a hidden or minimized one counts). Window
    /// owners and levels need no screen-recording permission; only titles do.
    static func ownsWindows(pid: pid_t) -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains {
            ($0[kCGWindowOwnerPID as String] as? Int).map(pid_t.init) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
        }
    }

    /// One open through NSWorkspace, called on the main thread as the rest of the app calls
    /// it, with the answer awaited here, on the opener's queue.
    static func liveOpen(_ url: URL, mode: Mode) -> Error? {
        let newInstance = mode == .newInstance || mode == .newInstancePrompting
        return liveOpen(url, newInstance: newInstance, prompts: mode == .normal || mode == .newInstancePrompting)
    }

    static func liveOpen(_ url: URL, newInstance: Bool, prompts: Bool) -> Error? {
        dispatchPrecondition(condition: .notOnQueue(.main))
        let answer = Answer()
        DispatchQueue.main.async {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.promptsUserIfNeeded = prompts
            configuration.createsNewApplicationInstance = newInstance
            if url.isFileURL, isSystemSettingsApp(path: url.path) {
                NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in answer.set(error) }
            } else if newInstance {
                NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) { _, error in answer.set(error) }
            } else {
                NSWorkspace.shared.open(url, configuration: configuration) { _, error in answer.set(error) }
            }
        }
        // No answer in time: take it as handed over rather than risk opening twice.
        guard answer.done.wait(timeout: .now() + answerWait) == .success else { return nil }
        return answer.error
    }

    private final class Answer: @unchecked Sendable {
        let done = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var _error: Error?
        var error: Error? {
            lock.lock()
            defer { lock.unlock() }
            return _error
        }
        func set(_ error: Error?) {
            lock.lock()
            _error = error
            lock.unlock()
            done.signal()
        }
    }
}
