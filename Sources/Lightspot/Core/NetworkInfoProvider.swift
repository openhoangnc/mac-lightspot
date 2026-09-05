import Foundation

// MARK: - Network Info Provider

public final class NetworkInfoProvider: @unchecked Sendable {
    public static let shared = NetworkInfoProvider()

    private let lock = NSLock()
    private var cachedPublicIP: String? = nil
    private var lastPublicIPFetch: Date = .distantPast
    private let refreshInterval: TimeInterval = 900 // 15 minutes

    private init() {
        // Prime public IP in background on launch
        refreshPublicIPIfNeeded()
    }

    // MARK: - Local IPv4 Address

    /// Returns the primary non-loopback local IPv4 address (e.g. 192.168.1.45) in < 0.1ms using POSIX getifaddrs.
    public func localIPv4Address() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return nil
        }
        defer { freeifaddrs(ifaddr) }

        var preferredIP: String?
        var fallbackIP: String?

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let cursor = ptr {
            let interface = cursor.pointee
            let flags = Int32(interface.ifa_flags)

            // getifaddrs leaves ifa_addr NULL for interfaces that carry no address
            // (down tunnels, some virtual devices). Swift imports it as an implicitly
            // unwrapped pointer, so dereferencing it unchecked traps.
            guard let addrPtr = interface.ifa_addr else {
                ptr = cursor.pointee.ifa_next
                continue
            }
            let addr = addrPtr.pointee

            // Check for IPv4 and non-loopback
            if addr.sa_family == UInt8(AF_INET) && (flags & IFF_LOOPBACK) == 0 && (flags & IFF_UP) != 0 {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(
                    addrPtr,
                    socklen_t(addr.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 {
                    let ipStr = hostname.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                    let name = String(cString: cursor.pointee.ifa_name)
                    // Prefer Wi-Fi (en0) or Ethernet (en1)
                    if name == "en0" {
                        preferredIP = ipStr
                        break
                    } else if name == "en1" && preferredIP == nil {
                        preferredIP = ipStr
                    } else if fallbackIP == nil {
                        fallbackIP = ipStr
                    }
                }
            }
            ptr = cursor.pointee.ifa_next
        }

        return preferredIP ?? fallbackIP
    }

    // MARK: - Public IPv4 Address

    /// Returns cached public IP address (zero-latency, never blocks search keystrokes).
    public func cachedPublicIPv4Address() -> String? {
        lock.lock()
        let ip = cachedPublicIP
        lock.unlock()
        refreshPublicIPIfNeeded()
        return ip
    }

    /// Asynchronously refreshes public IP if stale.
    public func refreshPublicIPIfNeeded() {
        lock.lock()
        let shouldFetch = Date().timeIntervalSince(lastPublicIPFetch) > refreshInterval
        if shouldFetch {
            lastPublicIPFetch = Date()
        }
        lock.unlock()

        guard shouldFetch else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            guard let url = URL(string: "https://api.ipify.org") else { return }

            var request = URLRequest(url: url)
            request.timeoutInterval = 3.0
            let task = URLSession.shared.dataTask(with: request) { data, _, error in
                guard error == nil, let data = data, let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !ip.isEmpty else {
                    return
                }
                self.lock.lock()
                self.cachedPublicIP = ip
                self.lock.unlock()
            }
            task.resume()
        }
    }
}
