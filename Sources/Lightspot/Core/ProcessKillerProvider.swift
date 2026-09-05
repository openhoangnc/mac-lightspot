import AppKit
import Foundation

// MARK: - Process Killer Provider

public final class ProcessKillerProvider: @unchecked Sendable {
    public static let shared = ProcessKillerProvider()

    private struct CachedProcess: Sendable {
        let pid: Int32
        let name: String
        let cpu: String
        let ramMB: Int
    }

    private let lock = NSLock()
    private var cachedCLIProcesses: [CachedProcess] = []
    private var lastProcessScan: Date = .distantPast
    private var isScanningProcesses = false
    private let processQueue = DispatchQueue(label: "com.lightspot.processkiller", qos: .utility)

    private init() {}

    /// Primes the process snapshot without blocking, so the first `kill ...` keystroke
    /// already has CLI processes to match against.
    public func warmUp() {
        _ = getCLIProcesses()
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
        let portString: String? = {
            if target.hasPrefix(":") {
                let p = String(target.dropFirst())
                return UInt16(p) != nil ? p : nil
            } else if let portNum = UInt16(target), portNum > 80 && portNum < 65535 {
                return target
            }
            return nil
        }()

        if let port = portString, let portResults = findProcessesOnPort(port) {
            results.append(contentsOf: portResults)
        }

        // 2. Check for exact PID: e.g. "kill 14205"
        if let pid = Int32(target), pid > 1 {
            let runningApp = NSRunningApplication(processIdentifier: pid)
            let name = runningApp?.localizedName ?? "Process \(pid)"
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

        // 3. Match running GUI Applications
        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            guard let name = app.localizedName, !name.isEmpty else { continue }
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
        let cliProcs = getCLIProcesses()
        let lowerTarget = target.lowercased()
        for proc in cliProcs {
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

    private func findProcessesOnPort(_ port: String) -> [SearchResult]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-ti", ":\(port)"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty else {
                return nil
            }

            let pids = output.components(separatedBy: .newlines).compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
            return pids.map { pid in
                let runningApp = NSRunningApplication(processIdentifier: pid)
                let name = runningApp?.localizedName ?? "Port :\(port) Process"
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
        } catch {
            return nil
        }
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

    /// Blocking `ps` snapshot. Only ever called on `processQueue`.
    @discardableResult
    private func scanCLIProcesses() -> [CachedProcess] {
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
