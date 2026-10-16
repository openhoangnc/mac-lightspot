import AppKit
import Foundation

// MARK: - Process Killer Provider

public final class ProcessKillerProvider: @unchecked Sendable {
    public static let shared = ProcessKillerProvider()

    struct CachedProcess: Sendable {
        let pid: Int32
        let name: String
        let cpu: String
        let ramMB: Int
    }

    private let lock = NSLock()
    private var cachedCLIProcesses: [CachedProcess] = []
    private var lastProcessScan: Date = .distantPast
    private var isScanningProcesses = false
    private var cachedListeningPorts: [UInt16: [PortListener]] = [:]
    private var lastPortScan: Date = .distantPast
    private var isScanningPorts = false
    private let processQueue = DispatchQueue(label: "com.lightspot.processkiller", qos: .utility)

    private init() {}

    /// Primes the process and listening-port snapshots without blocking, so the first
    /// `kill ...` keystroke already has something to match against.
    public func warmUp() {
        _ = getCLIProcesses()
        _ = getListeningPorts()
    }

    // MARK: - Protected Processes

    /// Never offered, whatever the query: killing these ends the login session or
    /// panics the machine, and a root-owned target is escalated through Touch ID by
    /// `terminateProcess`, so nothing downstream would stop it.
    static let protectedProcessNames: Set<String> = ["kernel_task", "launchd", "WindowServer", "loginwindow"]

    /// PID 0 (kernel_task), PID 1 (launchd), Lightspot itself, and the session
    /// processes in `protectedProcessNames`.
    static func isProtected(pid: Int32, name: String) -> Bool {
        pid <= 1 || pid == getpid() || protectedProcessNames.contains(name)
    }

    func search(_ query: SearchQuery) -> [SearchResult] {
        let raw = query.raw
        let lowerRaw = raw.lowercased()

        guard lowerRaw.hasPrefix("kill ") || query.lowercased == "kill" else {
            return []
        }

        let target: String
        if lowerRaw.hasPrefix("kill ") {
            target = String(raw.dropFirst("kill ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            target = ""
        }
        if target.isEmpty {
            return [
                SearchResult(
                    id: "kill-hint",
                    title: "Kill Process",
                    subtitle: "Type an app name, PID, or port (e.g. 'kill chrome', 'kill 1420', 'kill :3000')",
                    iconType: .systemSymbol(name: "xmark.octagon.fill"),
                    category: .quickActions,
                    score: 95,
                    action: .copyToClipboard("kill ")
                )
            ]
        }

        var results: [SearchResult] = []

        // 1. Check for port-based kill: e.g. ":3000" or "3000"
        let port: UInt16? = {
            if target.hasPrefix(":") {
                return UInt16(target.dropFirst())
            } else if let portNum = UInt16(target), portNum > 80 && portNum < 65535 {
                return portNum
            }
            return nil
        }()

        let cliProcs = getCLIProcesses()

        if let port {
            results.append(contentsOf: processesListening(on: port))
        }

        // 2. Check for exact PID: e.g. "kill 14205"
        if let pid = Int32(target) {
            let runningApp = NSRunningApplication(processIdentifier: pid)
            let name = runningApp?.localizedName
                ?? cliProcs.first(where: { $0.pid == pid })?.name
                ?? "Process \(pid)"
            if !Self.isProtected(pid: pid, name: name) {
                let icon: ResultIconType = runningApp?.bundleURL?.path != nil ? .app(path: runningApp!.bundleURL!.path) : .systemSymbol(name: "gearshape.2.fill")

                results.append(SearchResult(
                    id: "kill-pid-\(pid)",
                    title: "Terminate \(name) (PID: \(pid))",
                    subtitle: "Press ↵ to terminate gracefully · ⌥↵ to force kill",
                    iconType: icon,
                    category: .quickActions,
                    score: 95,
                    action: .killProcess(pid: pid, name: name, force: false)
                ))
            }
        }

        // 3. Match running GUI Applications
        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            guard let name = app.localizedName, !name.isEmpty,
                  !Self.isProtected(pid: app.processIdentifier, name: name) else { continue }
            let lowerName = name.lowercased()
            let lowerTarget = target.lowercased()

            var score: Double?
            if lowerName == lowerTarget {
                score = 95
            } else if lowerName.hasPrefix(lowerTarget) {
                score = 90
            } else if lowerName.contains(lowerTarget) {
                score = 80
            }

            if let s = score {
                let pid = app.processIdentifier
                let icon: ResultIconType = app.bundleURL?.path != nil ? .app(path: app.bundleURL!.path) : .systemSymbol(name: "xmark.circle.fill")

                results.append(SearchResult(
                    id: "kill-app-\(pid)",
                    title: "Kill \(name)",
                    subtitle: "PID: \(pid) · ↵ Terminate · ⌥↵ Force Kill",
                    iconType: icon,
                    category: .quickActions,
                    score: s,
                    action: .killProcess(pid: pid, name: name, force: false)
                ))
            }
        }

        // 4. Background / CLI processes (matching node, python, etc.)
        let lowerTarget = target.lowercased()
        for proc in cliProcs where !Self.isProtected(pid: proc.pid, name: proc.name) {
            if proc.name.lowercased().contains(lowerTarget) {
                // Avoid duplicating already matched GUI apps
                if !results.contains(where: { $0.id == "kill-app-\(proc.pid)" || $0.id == "kill-pid-\(proc.pid)" }) {
                    results.append(SearchResult(
                        id: "kill-cli-\(proc.pid)",
                        title: "Kill \(proc.name) (PID: \(proc.pid))",
                        subtitle: "CPU: \(proc.cpu)% · RAM: \(proc.ramMB)MB · ↵ Terminate · ⌥↵ Force Kill",
                        iconType: .systemSymbol(name: "terminal.fill"),
                        category: .quickActions,
                        score: 75,
                        action: .killProcess(pid: proc.pid, name: proc.name, force: false)
                    ))
                }
            }
        }

        results.sort { $0.score > $1.score }
        return Array(results.prefix(8))
    }

    // MARK: - Port Resolution

    /// A process listening on a port, as `lsof` reports it.
    struct PortListener: Equatable, Sendable {
        let pid: Int32
        /// The executable name (`node`, `python3.12`). Only GUI apps have an
        /// `NSRunningApplication` name, and a CLI dev server is the usual target here.
        let command: String
    }

    /// Results for the processes listening on `port`, from the cached snapshot.
    private func processesListening(on port: UInt16) -> [SearchResult] {
        let listeners = getListeningPorts()[port] ?? []
        return listeners.compactMap { listener in
            let pid = listener.pid
            let runningApp = NSRunningApplication(processIdentifier: pid)
            let name = runningApp?.localizedName
                ?? (listener.command.isEmpty ? nil : listener.command)
                ?? "Port :\(port) Process"
            guard !Self.isProtected(pid: pid, name: name) else { return nil }
            let icon: ResultIconType = runningApp?.bundleURL?.path != nil ? .app(path: runningApp!.bundleURL!.path) : .systemSymbol(name: "network.badge.shield.half.filled")

            return SearchResult(
                id: "kill-port-\(port)-\(pid)",
                title: "Kill \(name) on Port :\(port)",
                subtitle: "PID: \(pid) · ↵ Terminate · ⌥↵ Force Kill",
                iconType: icon,
                category: .quickActions,
                score: 98,
                action: .killProcess(pid: pid, name: name, force: false)
            )
        }
    }

    /// `lsof` arguments listing every listening TCP socket as `-F` fields.
    /// `-sTCP:LISTEN` keeps out clients merely connected to a port — without it,
    /// `kill :3000` also offered the browser tab talking to the dev server. `-nP`
    /// skips host and service name lookups; `+c 0` reports command names untruncated.
    static let listeningPortsArguments = ["+c", "0", "-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcn"]

    /// Parses `lsof -F pcn` output (`p<pid>` and `c<command>` lines, each followed by
    /// `f<fd>` and `n<address>:<port>` lines) into port → listeners.
    static func parseListeningPorts(_ output: String) -> [UInt16: [PortListener]] {
        var ports: [UInt16: [PortListener]] = [:]
        var currentPID: Int32?
        var currentCommand = ""
        for line in output.split(whereSeparator: \.isNewline) {
            guard let tag = line.first else { continue }
            let value = line.dropFirst()
            switch tag {
            case "p":
                currentPID = Int32(value)
                currentCommand = ""
            case "c":
                currentCommand = String(value)
            case "n":
                // A connected socket reads `local->remote`; only listeners belong here.
                guard let pid = currentPID,
                      !value.contains("->"),
                      let colon = value.lastIndex(of: ":"),
                      let port = UInt16(value[value.index(after: colon)...]) else { continue }
                if ports[port]?.contains(where: { $0.pid == pid }) != true {
                    ports[port, default: []].append(PortListener(pid: pid, command: currentCommand))
                }
            default:
                continue
            }
        }
        return ports
    }

    /// Non-blocking: returns the cached port → listeners snapshot and schedules a refresh
    /// when it is stale. `lsof` costs ~55-110 ms and this runs from `search()` on every
    /// keystroke of a `kill <port>` query, so it used to be the one blocking call left
    /// on the keystroke path.
    private func getListeningPorts() -> [UInt16: [PortListener]] {
        lock.lock()
        let cached = cachedListeningPorts
        let isStale = Date().timeIntervalSince(lastPortScan) > 2.0
        let shouldRefresh = isStale && !isScanningPorts
        if shouldRefresh {
            // Claim the slot now so a burst of keystrokes queues one scan, not one each.
            isScanningPorts = true
            lastPortScan = Date()
        }
        lock.unlock()

        if shouldRefresh {
            processQueue.async { [weak self] in self?.scanListeningPorts() }
        }
        return cached
    }

    /// Blocking `lsof` snapshot. Only ever called on `processQueue` (and by
    /// scripts/test_engine.swift, which needs a fresh scan).
    @discardableResult
    func scanListeningPorts() -> [UInt16: [PortListener]] {
        defer {
            lock.lock()
            isScanningPorts = false
            lock.unlock()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = Self.listeningPortsArguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        var ports: [UInt16: [PortListener]] = [:]
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if let output = String(data: data, encoding: .utf8) {
                ports = Self.parseListeningPorts(output)
            }
        } catch {}

        lock.lock()
        cachedListeningPorts = ports
        lastPortScan = Date()
        lock.unlock()

        return ports
    }

    // MARK: - CLI Processes Snapshot

    /// Non-blocking: returns the cached snapshot and schedules a refresh when it is
    /// stale. `/bin/ps -axo` costs ~40 ms and this runs from `search()`, so calling it
    /// inline stalled one keystroke every two seconds for the whole time the user was
    /// typing a `kill ...` query.
    private func getCLIProcesses() -> [CachedProcess] {
        lock.lock()
        let cached = cachedCLIProcesses
        let isStale = Date().timeIntervalSince(lastProcessScan) > 2.0
        let shouldRefresh = isStale && !isScanningProcesses
        if shouldRefresh {
            // Claim the slot now so a burst of keystrokes queues one scan, not one each.
            isScanningProcesses = true
            lastProcessScan = Date()
        }
        lock.unlock()

        if shouldRefresh {
            processQueue.async { [weak self] in self?.scanCLIProcesses() }
        }
        return cached
    }

    /// Blocking `ps` snapshot. Only ever called on `processQueue` (and by
    /// scripts/test_engine.swift, which needs a fresh scan).
    @discardableResult
    func scanCLIProcesses() -> [CachedProcess] {
        defer {
            lock.lock()
            isScanningProcesses = false
            lock.unlock()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid,pcpu,rss,comm"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        var results: [CachedProcess] = []
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: .newlines)
                for line in lines.dropFirst() {
                    let parts = line.split(separator: " ").map(String.init)
                    if parts.count >= 4,
                       let pid = Int32(parts[0]),
                       let rssKB = Int(parts[2]) {
                        let fullComm = parts[3...].joined(separator: " ")
                        let name = URL(fileURLWithPath: fullComm).lastPathComponent
                        let ramMB = rssKB / 1024
                        results.append(CachedProcess(pid: pid, name: name, cpu: parts[1], ramMB: ramMB))
                    }
                }
            }
        } catch {}

        lock.lock()
        cachedCLIProcesses = results
        lastProcessScan = Date()
        lock.unlock()

        return results
    }

    // MARK: - Process Execution

    public static func terminateProcess(pid: Int32, force: Bool) {
        DispatchQueue.global(qos: .userInitiated).async {
            if let app = NSRunningApplication(processIdentifier: pid) {
                if force {
                    app.forceTerminate()
                } else {
                    app.terminate()
                }
            } else {
                let sig = force ? SIGKILL : SIGTERM
                if kill(pid, sig) != 0 && errno == EPERM {
                    let flag = force ? "-9" : "-15"
                    QuickActionsProvider.executePrivilegedWithTouchID(command: "kill \(flag) \(pid)")
                }
            }
        }
    }
}
