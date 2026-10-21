import Foundation

// MARK: - Network Info Provider

public final class NetworkInfoProvider: @unchecked Sendable {
    public static let shared = NetworkInfoProvider()

    /// What the IP Address row can say about the public address. Only a lookup the user
    /// asked for moves this off `.notRequested` — see `requestPublicIPv4Address`.
    public enum PublicIPState: Equatable, Sendable {
        case notRequested
        case fetching
        case available(String)
        case unavailable
    }

    /// Delivers the looked-up address, or nil on failure, on an arbitrary queue.
    public typealias PublicIPFetcher = @Sendable (_ completion: @escaping @Sendable (String?) -> Void) -> Void

    private let lock = NSLock()
    private var cachedPublicIP: String? = nil
    private var lastSuccess: Date = .distantPast
    private var lastFailure: Date = .distantPast
    private var inFlight = false
    private var waiters: [@Sendable (String?) -> Void] = []
    private var lookups = 0
    private var fetcher: PublicIPFetcher = { NetworkInfoProvider.fetchFromIpify($0) }
    private let refreshInterval: TimeInterval = 900 // 15 minutes
    /// Keeps a burst of keystrokes from retrying every character while offline.
    private let failureBackoff: TimeInterval = 30

    // No lookup here: touching `shared` must never contact the network.
    private init() {}

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
    //
    // The public address can only be learned from a server, so this asks one
    // (GET https://api.ipify.org): the only request Lightspot sends to a third party, and
    // its only network use besides the GitHub update check. It is sent only when the user asks for
    // the public IP: a query that clearly names it (`QuickActionsProvider.queryAsksForPublicIP`)
    // or ↵ on the IP Address row. Nothing here runs at launch or on a loose fuzzy match.

    /// The public IP from the last successful lookup, if any. Never touches the network.
    public func cachedPublicIPv4Address() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return cachedPublicIP
    }

    /// Non-blocking snapshot for the IP Address row's subtitle.
    public func publicIPState() -> PublicIPState {
        lock.lock()
        defer { lock.unlock() }
        if let ip = cachedPublicIP { return .available(ip) }
        if inFlight { return .fetching }
        if lastFailure != .distantPast { return .unavailable }
        return .notRequested
    }

    /// Number of network lookups started so far (for tests).
    public var lookupCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return lookups
    }

    /// Looks up the public IP in the background unless a fresh one is cached or a lookup is
    /// already running (its result is shared). Never blocks, so the keystroke path may call it.
    /// - Parameters:
    ///   - force: ignore the failure backoff — for an explicit ↵, not for typing.
    ///   - completion: the address, or nil if the lookup failed; called immediately when a
    ///     fresh address is cached, otherwise on an arbitrary queue.
    public func requestPublicIPv4Address(force: Bool = false, completion: (@Sendable (String?) -> Void)? = nil) {
        lock.lock()
        let now = Date()
        if let ip = cachedPublicIP, now.timeIntervalSince(lastSuccess) < refreshInterval {
            lock.unlock()
            completion?(ip)
            return
        }
        if !inFlight && !force && now.timeIntervalSince(lastFailure) < failureBackoff {
            lock.unlock()
            completion?(nil)
            return
        }
        if let completion {
            waiters.append(completion)
        }
        guard !inFlight else {
            lock.unlock()
            return
        }
        inFlight = true
        lookups += 1
        let fetch = fetcher
        lock.unlock()

        DispatchQueue.global(qos: .utility).async { [self] in
            fetch { [weak self] ip in
                self?.finishLookup(ip)
            }
        }
    }

    private func finishLookup(_ ip: String?) {
        lock.lock()
        inFlight = false
        if let ip {
            cachedPublicIP = ip
            lastSuccess = Date()
            lastFailure = .distantPast
        } else {
            lastFailure = Date()
        }
        let pending = waiters
        waiters = []
        lock.unlock()
        pending.forEach { $0(ip) }
    }

    /// Replaces the HTTP lookup and forgets all lookup state, so tests can count and
    /// control lookups without touching the network.
    public func resetPublicIPState(fetcher: @escaping PublicIPFetcher) {
        lock.lock()
        self.fetcher = fetcher
        cachedPublicIP = nil
        lastSuccess = .distantPast
        lastFailure = .distantPast
        inFlight = false
        waiters = []
        lookups = 0
        lock.unlock()
    }

    /// Ephemeral, so neither the response nor any cookie reaches URLCache's on-disk store.
    private static let lookupSession = URLSession(configuration: .ephemeral)

    private static func fetchFromIpify(_ completion: @escaping @Sendable (String?) -> Void) {
        guard let url = URL(string: "https://api.ipify.org") else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3.0
        lookupSession.dataTask(with: request) { data, response, error in
            guard error == nil,
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let data,
                  let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  NetworkInfoProvider.isPlausibleIPAddress(ip) else {
                completion(nil)
                return
            }
            completion(ip)
        }.resume()
    }

    private static let ipAddressCharacters = CharacterSet(charactersIn: "0123456789abcdefABCDEF.:")

    /// A captive portal answers with an HTML page; only an address may reach the UI.
    static func isPlausibleIPAddress(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= 45 else { return false }
        return text.unicodeScalars.allSatisfy { ipAddressCharacters.contains($0) }
    }
}
