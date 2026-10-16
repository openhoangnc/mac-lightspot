import Foundation

/// Keeps a single Lightspot running per user.
///
/// A second copy used to stay alive next to the first: it only failed to grab the
/// Carbon hotkey (which merely logs), so it kept its own menu bar icon, clipboard
/// poller and memory. Copies piled up because:
/// - `install.sh` deletes and re-copies the bundle, and LaunchServices then treats
///   `open` of the new bundle as a different app and starts another process instead
///   of reopening the running one (reproduced with a throwaway app);
/// - the scripts' `killall` fails silently from a sandboxed shell (EPERM on an app
///   started outside it), so nothing was stopped before that `open`;
/// - running the executable directly, or `open -n`, bypasses LaunchServices.
///
/// The lock is an `flock` on a per-user file. It is atomic, so two copies started
/// together cannot both win (a scan of `NSRunningApplication` can: neither may be
/// registered yet), and the kernel drops it when the process dies, even on SIGKILL,
/// so `install.sh`/`run.sh` can kill and relaunch without a stale lock.
///
/// A launch that finds the lock taken either hands off (the same build is running:
/// ask it to show its panel) or takes over (a different build is running, i.e. the
/// app was reinstalled, rebuilt or updated: ask it to quit, then take the lock).
enum SingleInstanceGuard {
    // MARK: - Lock file

    /// `~/Library/Application Support/Lightspot/<bundle id>.lock`. Not the temporary
    /// directory: macOS deletes files there that go unread for three days, and a lock
    /// file deleted while held lets the next launch lock a fresh one.
    static func lockFilePath(bundleIdentifier: String) -> String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("Lightspot", isDirectory: true)
            .appendingPathComponent("\(bundleIdentifier).lock")
            .path
    }

    /// Identifies one build on disk. Reinstalling or rebuilding creates a new file, so
    /// the inode and modification time change even when the path does not.
    static func buildIdentity(executablePath: String) -> String {
        var info = stat()
        guard stat(executablePath, &info) == 0 else { return executablePath }
        return "\(executablePath)|\(info.st_dev):\(info.st_ino)|\(info.st_mtimespec.tv_sec).\(info.st_mtimespec.tv_nsec)"
    }

    /// What the process holding the lock wrote into the lock file.
    struct Holder: Equatable {
        var pid: pid_t
        var build: String
    }

    enum LockResult: Equatable {
        /// This process holds the lock for as long as `fileDescriptor` stays open.
        case acquired(fileDescriptor: Int32)
        /// Another process holds it. `nil` if it has not written its details yet.
        case held(by: Holder?)
        /// The lock file could not be opened. Callers should run rather than refuse to start.
        case unavailable
    }

    /// Tries to take the lock without blocking. On success the file records this
    /// process's PID and `build`.
    static func acquireLock(atPath path: String, build: String) -> LockResult {
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        // O_CLOEXEC: Lightspot spawns shells and terminals. A child that inherited the
        // descriptor would keep holding the lock after Lightspot exits, and every later
        // launch would defer to a process that is gone.
        let fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else { return .unavailable }

        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            let record = "\(getpid())\n\(build)\n"
            _ = ftruncate(fd, 0)
            _ = record.withCString { pwrite(fd, $0, strlen($0), 0) }
            return .acquired(fileDescriptor: fd)
        }

        let lockError = errno
        let holder = readHolder(fd)
        close(fd)
        return lockError == EWOULDBLOCK ? .held(by: holder) : .unavailable
    }

    private static func readHolder(_ fd: Int32) -> Holder? {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = pread(fd, &buffer, buffer.count, 0)
        guard count > 0 else { return nil }
        let lines = String(decoding: buffer[0..<count], as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 2, let pid = pid_t(lines[0]) else { return nil }
        return Holder(pid: pid, build: String(lines[1]))
    }

    // MARK: - Launch decision

    enum LaunchDecision: Equatable {
        /// Carry on launching. `lockFD` must stay open for the life of the process
        /// (`nil` when the lock file was unavailable: run unguarded rather than not at all).
        case run(lockFD: Int32?)
        /// The same build is already running and was asked to show its panel. Exit.
        case handedOff
        /// A different build is running and did not quit in time. Exit.
        case holderDidNotQuit(pid: pid_t?)
    }

    /// The whole start-up policy. Blocks for at most `takeOverTimeout` while a
    /// replaced build shuts down.
    static func claim(
        bundleIdentifier: String,
        lockPath: String,
        build: String,
        takeOverTimeout: TimeInterval = 5
    ) -> LaunchDecision {
        let deadline = Date().addingTimeInterval(takeOverTimeout)
        var askedToQuit: pid_t?

        while true {
            switch acquireLock(atPath: lockPath, build: build) {
            case .acquired(let fd):
                return .run(lockFD: fd)
            case .unavailable:
                return .run(lockFD: nil)
            case .held(let holder):
                if let holder, holder.build == build {
                    // Started again while running: a request to see it. If we were
                    // waiting for an old build to quit, another copy of this build
                    // won the race and has nothing to show yet.
                    if askedToQuit == nil {
                        requestShowPanel(bundleIdentifier: bundleIdentifier)
                    }
                    return .handedOff
                }
                if let holder, askedToQuit != holder.pid {
                    requestQuit(bundleIdentifier: bundleIdentifier, pid: holder.pid)
                    askedToQuit = holder.pid
                }
                if Date() >= deadline {
                    return .holderDidNotQuit(pid: holder?.pid)
                }
                usleep(50_000)
            }
        }
    }

    // MARK: - Requests between copies

    static func showPanelNotificationName(bundleIdentifier: String) -> Notification.Name {
        Notification.Name("\(bundleIdentifier).showPanel")
    }

    static func quitNotificationName(bundleIdentifier: String) -> Notification.Name {
        Notification.Name("\(bundleIdentifier).quit")
    }

    /// `deliverImmediately`: AppKit suspends distributed notifications while an app is
    /// inactive, and an agent app with a non-activating panel is practically never active.
    static func requestShowPanel(bundleIdentifier: String) {
        DistributedNotificationCenter.default().postNotificationName(
            showPanelNotificationName(bundleIdentifier: bundleIdentifier),
            object: nil, userInfo: nil, deliverImmediately: true
        )
    }

    /// Addressed by PID so that only the lock holder quits.
    static func requestQuit(bundleIdentifier: String, pid: pid_t) {
        DistributedNotificationCenter.default().postNotificationName(
            quitNotificationName(bundleIdentifier: bundleIdentifier),
            object: String(pid), userInfo: nil, deliverImmediately: true
        )
    }

    /// Receives the requests a later launch sends. Delivered on the main run loop;
    /// keep the listener alive for as long as requests should be answered.
    final class RequestListener: NSObject {
        private let onShowPanel: () -> Void
        private let onQuit: () -> Void

        init(bundleIdentifier: String, onShowPanel: @escaping () -> Void, onQuit: @escaping () -> Void) {
            self.onShowPanel = onShowPanel
            self.onQuit = onQuit
            super.init()
            let center = DistributedNotificationCenter.default()
            center.addObserver(
                self, selector: #selector(showPanelRequested(_:)),
                name: SingleInstanceGuard.showPanelNotificationName(bundleIdentifier: bundleIdentifier),
                object: nil, suspensionBehavior: .deliverImmediately
            )
            center.addObserver(
                self, selector: #selector(quitRequested(_:)),
                name: SingleInstanceGuard.quitNotificationName(bundleIdentifier: bundleIdentifier),
                object: nil, suspensionBehavior: .deliverImmediately
            )
        }

        deinit {
            DistributedNotificationCenter.default().removeObserver(self)
        }

        @objc private func showPanelRequested(_ notification: Notification) {
            onShowPanel()
        }

        @objc private func quitRequested(_ notification: Notification) {
            guard (notification.object as? String) == String(getpid()) else { return }
            onQuit()
        }
    }

    /// A show request this soon after launch comes from a second copy started
    /// alongside this one (the login item racing "Reopen windows when logging back
    /// in", or a launch script), not from someone asking for the panel: ignore it.
    static let launchGraceInterval: TimeInterval = 10

    static func shouldHonorShowRequest(launchedAt: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(launchedAt) >= launchGraceInterval
    }
}
