import AppKit

// MARK: - Opening System Settings past LaunchServices' dead records
//
// Measured on macOS 27.2: launchservicesd learns of an app's exit late. System Settings' record
// stays, a Foreground app with a running dot in the Dock, after the process has gone: 1 to 21 s
// in most runs measured for this, over 150 s in one, and until its ten-minute sweep ("Forcibly
// removing application … because it seems we missed a death notification") when it misses the
// exit ("ListenForProcessExitFromRunningboard(…), failed twice to find expected application").
// Meanwhile LaunchServices hands every open of a System Settings link, profile or the app
// itself to that dead PID, even with a live instance beside it: the quiet open comes back as
// Cocoa 256 over procNotFound (-600), and CoreServicesUIAgent shows "The application "System
// Settings" is not open anymore." for the plain `NSWorkspace.open(_:)`, "The application can't
// be opened." -600 for `open(_:configuration:)` with its default `promptsUserIfNeeded`.
// `openApplication(at:)` gets -600 too. NSRunningApplication reads the same records.
//
// Nothing public makes LaunchServices drop a dead record sooner (measured on 27.2:
// `runningApplications(withBundleIdentifier:)`, `lsappinfo info`, `terminate()`,
// `forceTerminate()` and `lsappinfo kill -force` all leave it). So the opener never lets
// LaunchServices pick the instance while it holds one, and never adds one beside a live one:
//
// - A live instance (this user's System Settings process, from the process table): with no dead
//   record beside it, the ordinary quiet open. Otherwise the URL goes to that process by its PID,
//   the Apple Event LaunchServices would have sent (GURL for a link, odoc for a file), then it is
//   activated: System Settings keeps a URL that arrives while it is inactive pending, and opens
//   that pane once it becomes active. Measured on 27.2 from an ad-hoc signed app with no
//   Automation consent: both events are delivered, with no TCC prompt (sent with
//   kAEDoNotPromptForUserConsent all the same, so a macOS that wants consent fails quietly
//   instead of asking; `AEDeterminePermissionToAutomateTarget` says -1744 for every event, even
//   the quit `terminate()` sends without one, so it can't tell).
// - Only dead records: one new instance (`createsNewApplicationInstance`), given the URL at
//   launch, and the opener waits until it is up, so the next open finds it live.
// - Nothing recorded: the ordinary quiet open, which launches it.
//
// An instance is never asked to quit: 1.4.0 quit a live one beside a dead record and launched
// another, and every quit left one more dead record, a Dock of System Settings icons.

enum SystemSettingsOpener {
    static let bundleIdentifier = "com.apple.systempreferences"
    static let appURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
    static let executablePath = appURL.path + "/Contents/MacOS/System Settings"
    static let urlScheme = "x-apple.systempreferences"
    /// How long a live process without a window (launching, or quitting: ⌘Q closes every
    /// window first) is given to show one or exit.
    static let settleWait: TimeInterval = 5
    /// How long a new instance is given to finish launching and show its window.
    static let launchWait: TimeInterval = 10
    static let pollInterval: TimeInterval = 0.1
    /// How long the live environment waits for LaunchServices to answer one open.
    static let answerWait: TimeInterval = 15
    /// How long an Apple Event waits for System Settings' reply (measured 0.4–4.8 s on 27.2).
    static let replyWait: TimeInterval = 10

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
        /// Through LaunchServices, which launched System Settings or handed it to the live one.
        case opened
        /// Straight to the live instance by its PID, past LaunchServices' dead records.
        case delivered
        /// The live instance didn't take the URL; it was brought forward all the same.
        case undelivered
        /// Opened in a new instance, the only one running, past records of instances that had gone.
        case newInstance
        /// The quiet open failed for another reason; opened the ordinary way.
        case fellBack
    }

    /// The system access the decisions need, faked in test_engine.
    struct Environment: Sendable {
        /// The PIDs LaunchServices records for System Settings, dead or alive.
        var instances: @Sendable () -> [pid_t] = { [] }
        /// This user's running System Settings processes, oldest first (the process table, not
        /// LaunchServices).
        var liveProcesses: @Sendable () -> [pid_t] = { [] }
        /// Whether that process has any window (⌘Q closes them all at once).
        var hasWindows: @Sendable (pid_t) -> Bool = { _ in false }
        /// Whether that process has finished launching.
        var isFinishedLaunching: @Sendable (pid_t) -> Bool = { _ in true }
        /// Opens `url` through LaunchServices and returns its error, nil once it took it.
        var open: @Sendable (_ url: URL, _ mode: Mode) -> Error? = { _, _ in nil }
        /// Sends `url` to that process as an Apple Event; nil once delivered.
        var deliver: @Sendable (_ url: URL, _ pid: pid_t) -> Error? = { _, _ in nil }
        /// Brings that process forward.
        var activate: @Sendable (pid_t) -> Void = { _ in }
        var now: @Sendable () -> Date = { Date() }
        var sleep: @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }

        static let live: Environment = {
            var env = Environment()
            env.instances = { recordedInstances() }
            env.liveProcesses = { runningProcesses() }
            env.hasWindows = { ownsWindows(pid: $0) }
            env.isFinishedLaunching = { pid in
                DispatchQueue.main.sync { NSRunningApplication(processIdentifier: pid)?.isFinishedLaunching ?? false }
            }
            env.open = { url, mode in liveOpen(url, mode: mode) }
            env.deliver = { url, pid in sendEvent(url, to: pid) }
            env.activate = { pid in DispatchQueue.main.async { bringForward(pid) } }
            return env
        }()
    }

    /// Opens one at a time and in order: Apple Intelligence opens its profile file, then a
    /// second later Device Management, and a wait for an instance to launch holds both back.
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
            case .delivered: NSLog("SystemSettingsOpener: LaunchServices still recorded a System Settings that had gone; sent the link to the one running")
            case .undelivered: NSLog("SystemSettingsOpener: the running System Settings didn't take the link; brought it forward")
            case .newInstance: NSLog("SystemSettingsOpener: LaunchServices still recorded a System Settings that had gone; opened a new one")
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
        let live = settledProcesses(env)
        if let target = live.last {
            // With no dead record beside it, LaunchServices hands the open to this one.
            if env.instances().allSatisfy(live.contains) {
                guard let error = env.open(url, .quiet) else { return .opened }
                guard isHandOffFailure(error) else {
                    _ = env.open(url, .normal)
                    return .fellBack
                }
                // A dead record the list didn't show yet (measured): go round LaunchServices.
            }
            if env.deliver(url, target) == nil {
                env.activate(target)
                return .delivered
            }
            // It exited meanwhile: then only dead records are left.
            guard settledProcesses(env).isEmpty else {
                env.activate(target)
                return .undelivered
            }
            return launchNew(url, env)
        }
        // Only records of instances that have gone: any hand-off would go to a dead PID.
        if !env.instances().isEmpty { return launchNew(url, env) }
        // Quiet even with nothing recorded: the list can read empty for a moment while
        // LaunchServices still holds a dead record (measured), and then a prompting open alerts.
        guard let error = env.open(url, .quiet) else { return .opened }
        guard isHandOffFailure(error) else {
            _ = env.open(url, .normal)
            return .fellBack
        }
        return launchNew(url, env)
    }

    /// The live processes once none is half-way: one without a window is launching (it shows
    /// one in about a second) or quitting (it exits as fast), so it is given `settleWait` to
    /// do either. One still without a window then is running windowless, and counts.
    static func settledProcesses(_ env: Environment) -> [pid_t] {
        let deadline = env.now().addingTimeInterval(settleWait)
        var live = env.liveProcesses()
        while live.contains(where: { !env.hasWindows($0) }), env.now() < deadline {
            env.sleep(pollInterval)
            live = env.liveProcesses()
        }
        return live
    }

    /// One new instance with the URL, quietly; if that fails to launch, once more with macOS's
    /// own message. Then it waits until the instance is up, so the next open finds it live and
    /// sends it the URL instead of launching another.
    private static func launchNew(_ url: URL, _ env: Environment) -> Outcome {
        if env.open(url, .newInstance) != nil, env.open(url, .newInstancePrompting) != nil {
            return .newInstance
        }
        let deadline = env.now().addingTimeInterval(launchWait)
        while env.now() < deadline {
            if let pid = env.liveProcesses().last, env.isFinishedLaunching(pid), env.hasWindows(pid) { break }
            env.sleep(pollInterval)
        }
        return .newInstance
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

    // MARK: The Apple Event

    /// The event LaunchServices sends for `url`, addressed to `pid`: GURL with the link as
    /// UTF-8 text (System Settings reads the direct object as 8-bit text: a UTF-16 one arrived
    /// as "x"), odoc with a file; nil for System Settings itself, which only needs activating.
    static func event(for url: URL, to pid: pid_t) -> NSAppleEventDescriptor? {
        if url.isFileURL, isSystemSettingsApp(path: url.path) { return nil }
        let target = NSAppleEventDescriptor(processIdentifier: pid)
        if url.isFileURL {
            let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenDocuments),
                                               targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
                                               transactionID: AETransactionID(kAnyTransactionID))
            let files = NSAppleEventDescriptor.list()
            files.insert(NSAppleEventDescriptor(fileURL: url), at: 1)
            event.setParam(files, forKeyword: AEKeyword(keyDirectObject))
            return event
        }
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kInternetEventClass), eventID: AEEventID(kAEGetURL),
                                           targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        if let text = NSAppleEventDescriptor(descriptorType: DescType(typeUTF8Text), data: Data(url.absoluteString.utf8)) {
            event.setParam(text, forKeyword: AEKeyword(keyDirectObject))
        }
        return event
    }

    /// Sends the event and waits for the reply. A reply that takes longer than `replyWait`
    /// still counts: the event is in System Settings' queue. Never a consent prompt.
    static func sendEvent(_ url: URL, to pid: pid_t) -> Error? {
        guard let event = event(for: url, to: pid) else { return nil }
        let noPrompt = NSAppleEventDescriptor.SendOptions(rawValue: UInt(kAEDoNotPromptForUserConsent))
        do {
            _ = try event.sendEvent(options: NSAppleEventDescriptor.SendOptions.waitForReply.union(noPrompt), timeout: replyWait)
            return nil
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSOSStatusErrorDomain, nsError.code == Int(errAETimeout) { return nil }
            return error
        }
    }

    /// Activates that process. It needs to be: System Settings keeps a URL that arrives while
    /// it is inactive pending, and opens the pane once it becomes active (measured on 27.2; an
    /// open through LaunchServices activates it first). The panel is non-activating, but it took
    /// the keystroke that opened this, so Lightspot activates itself, as its own dialogs do, and
    /// from macOS 14 hands that activation over (cooperative activation).
    @MainActor
    static func bringForward(_ pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        if #available(macOS 14, *) {
            NSApplication.shared.activate()
            NSApplication.shared.yieldActivation(to: app)
            app.activate(from: NSRunningApplication.current, options: [])
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    // MARK: Live system access

    /// What LaunchServices records, which may include instances that have exited.
    static func recordedInstances() -> [pid_t] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { !$0.isTerminated }
            .map(\.processIdentifier)
    }

    /// This user's processes running System Settings' executable, oldest first, from the
    /// process table (`proc_pidpath`, and `proc_pidinfo`'s owner and start), so a dead record's
    /// PID, or one reused by another program, never counts.
    static func runningProcesses() -> [pid_t] {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 32)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        // PROC_PIDPATHINFO_MAXSIZE, a macro Swift does not import.
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let uid = getuid()
        var found: [(pid: pid_t, started: Double)] = []
        for pid in pids.prefix(Int(max(count, 0))) where pid > 0 {
            var info = proc_bsdinfo()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_uid == uid,
                  proc_pidpath(pid, &path, UInt32(path.count)) > 0,
                  String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) == executablePath else { continue }
            found.append((pid, Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1e6))
        }
        return found.sorted { $0.started < $1.started }.map(\.pid)
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
