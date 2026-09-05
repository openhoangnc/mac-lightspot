import AppKit
import Foundation
import IOKit.ps

// MARK: - System Info Provider

public final class SystemInfoProvider: @unchecked Sendable {
    public static let shared = SystemInfoProvider()

    private init() {}

    func search(_ query: SearchQuery) -> [SearchResult] {
        let lower = query.lowercased
        guard lower == "sys"
                || lower == "system"
                || lower == "specs"
                || lower == "battery"
                || lower == "ram"
                || lower == "cpu"
                || lower == "uptime"
                || lower == "hardware" else {
            return []
        }

        let info = collectSystemInfo()
        let subtitle = "CPU: \(info.cpuUsage)% · RAM: \(info.ramUsedGB) / \(info.ramTotalGB) GB · Disk: \(info.diskFreeGB) GB Free · Battery: \(info.battery) · Up: \(info.uptime)"

        let report = """
        macOS System Hardware Report:
        -----------------------------
        • CPU: \(info.cpuUsage)%
        • Memory: \(info.ramUsedGB) GB used / \(info.ramTotalGB) GB total
        • Boot Volume: \(info.diskFreeGB) GB free / \(info.diskTotalGB) GB total
        • Battery: \(info.battery)
        • System Uptime: \(info.uptime)
        """

        return [
            SearchResult(
                id: "system-hud",
                title: "System Hardware & Resource Status",
                subtitle: "\(subtitle) · Press ↵ to copy",
                iconType: .systemSymbol(name: "gauge.with.dots.needle.bottom.50percent"),
                category: .quickActions,
                score: 98,
                action: .copyToClipboard(report)
            )
        ]
    }

    // MARK: - Hardware Metrics Collection

    public struct SystemMetrics: Sendable {
        public let cpuUsage: String
        public let ramUsedGB: String
        public let ramTotalGB: String
        public let diskFreeGB: String
        public let diskTotalGB: String
        public let battery: String
        public let uptime: String
    }

    public func collectSystemInfo() -> SystemMetrics {
        // Bind once: reading `.used` and `.total` off separate calls ran the Mach VM
        // query and the statfs on "/" twice each, on the keystroke path.
        let ram = getRAMUsage()
        let disk = getDiskUsage()
        return SystemMetrics(
            cpuUsage: getCPUUsage(),
            ramUsedGB: ram.used,
            ramTotalGB: ram.total,
            diskFreeGB: disk.free,
            diskTotalGB: disk.total,
            battery: getBatteryStatus(),
            uptime: getUptime()
        )
    }

    // MARK: - CPU Load (Mach Host)

    private func getCPUUsage() -> String {
        var loadAvg: [Double] = [0.0, 0.0, 0.0]
        let samples = getloadavg(&loadAvg, 3)
        if samples > 0 {
            let count = Double(ProcessInfo.processInfo.activeProcessorCount)
            let pct = min(max(Int((loadAvg[0] / max(count, 1.0)) * 100.0), 0), 100)
            return "\(pct)"
        }
        return "N/A"
    }

    // MARK: - RAM (Mach VM Info)

    private func getRAMUsage() -> (used: String, total: String) {
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let totalGB = Double(totalBytes) / (1024.0 * 1024.0 * 1024.0)

        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            let pageSize = UInt64(getpagesize())
            let active = UInt64(vmStats.active_count) * pageSize
            let wired = UInt64(vmStats.wire_count) * pageSize
            let compressed = UInt64(vmStats.compressor_page_count) * pageSize
            let usedBytes = active + wired + compressed
            let usedGB = Double(usedBytes) / (1024.0 * 1024.0 * 1024.0)
            return (String(format: "%.1f", usedGB), String(format: "%.1f", totalGB))
        }

        return ("N/A", String(format: "%.1f", totalGB))
    }

    // MARK: - Disk Space

    private func getDiskUsage() -> (free: String, total: String) {
        let fm = FileManager.default
        if let attrs = try? fm.attributesOfFileSystem(forPath: "/") {
            let freeBytes = (attrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            let totalBytes = (attrs[.systemSize] as? NSNumber)?.int64Value ?? 0

            let freeGB = Double(freeBytes) / (1024.0 * 1024.0 * 1024.0)
            let totalGB = Double(totalBytes) / (1024.0 * 1024.0 * 1024.0)
            return (String(format: "%.0f", freeGB), String(format: "%.0f", totalGB))
        }
        return ("N/A", "N/A")
    }

    // MARK: - Battery (IOKit Power Sources)

    private func getBatteryStatus() -> String {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let desc = IOPSGetPowerSourceDescription(snapshot, first)?.takeUnretainedValue() as? [String: Any] else {
            return "No Battery (Desktop)"
        }

        let capacity = desc[kIOPSCurrentCapacityKey as String] as? Int ?? 0
        let isCharging = desc[kIOPSIsChargingKey as String] as? Bool ?? false
        let powerSource = desc[kIOPSPowerSourceStateKey as String] as? String ?? ""

        let state = isCharging ? "⚡ Charging" : (powerSource == (kIOPSACPowerValue as String) ? "🔌 AC Power" : "🔋")
        return "\(capacity)% \(state)"
    }

    // MARK: - Uptime (sysctl KERN_BOOTTIME)

    private func getUptime() -> String {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]

        let res = sysctl(&mib, u_int(mib.count), &bootTime, &size, nil, 0)
        if res == 0 {
            let now = time(nil)
            let uptimeSeconds = now - bootTime.tv_sec
            let days = uptimeSeconds / 86400
            let hours = (uptimeSeconds % 86400) / 3600
            let mins = (uptimeSeconds % 3600) / 60

            if days > 0 {
                return "\(days)d \(hours)h"
            } else if hours > 0 {
                return "\(hours)h \(mins)m"
            } else {
                return "\(mins)m"
            }
        }
        return "N/A"
    }
}
