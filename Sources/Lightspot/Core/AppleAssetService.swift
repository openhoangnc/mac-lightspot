import Foundation
import ObjectiveC

// MARK: - Apple's asset service, in a short-lived helper process
//
// Apple Intelligence's downloadable model sets live in `UnifiedAssetFramework`, reached
// through the LaunchDaemon `com.apple.assetsubscriptiond`. Ported from RemoveMacAI's
// `Sources/UAF/UAF.m` and `System.swift` (MIT), whose asset-service work follows pared
// (github.com/4evy/pared, MIT, see THIRD-PARTY-NOTICES.md); the call shapes are the platform
// report's A8 and A9, the pure-Swift versions the researcher compiled and measured.
//
// Lightspot's own process never calls the framework. AppKit already pulls the image in at
// launch, but *calling* it costs 9 to 11 MB of resident memory that never comes back
// (platform report A7, finding 1), which would break the lightness rule that closing the
// overlay returns memory. So every asset-service read, and the reset, runs in the Lightspot
// binary started as a short-lived child (`--asset-service`, handled in `main()` before the
// single-instance guard): the cost dies with the child. The app talks only to the child,
// through `AssetServiceClient`; `AssetServiceBridge` (the framework calls) is reached only
// from the helper flag and, read-only, from deep_verify.

/// What the service knows about one catalog model set, as the helper reports it.
struct AssetSetInfo: Codable, Sendable, Equatable {
    let name: String
    /// The service knows the set and its asset type still matches the catalog's
    /// (`getAssetSet:`/`autoAssetType`). A set macOS has retired (Spatial Photos on 26.7.2)
    /// is not known.
    let known: Bool
    /// The asset type the service reports for the set, or nil when it does not know it.
    let assetType: String?
    /// Bytes on disk, from the inventory (0 when it lists none). nil when the inventory call
    /// failed: a size Lightspot can't read is unknown, never 0, which would read as "deleted".
    let bytes: Int64?
}

/// The one JSON object `--asset-service inventory` prints. `available` false means the
/// service did not answer; the engine then treats every model size as unknown.
struct AssetInventory: Codable, Sendable, Equatable {
    let available: Bool
    let sets: [AssetSetInfo]

    func info(_ name: String) -> AssetSetInfo? { sets.first { $0.name == name } }

    /// Bytes for a set, or nil when the service did not answer or couldn't say (never a guessed 0).
    func bytes(_ name: String) -> Int64? { available ? info(name)?.bytes ?? nil : nil }
}

/// What one reset request came back with. `--asset-service reset <set>` prints it as JSON.
enum AssetResetOutcome: Equatable, Sendable {
    case done
    /// Nothing of the set is on disk (no tracked bytes, no files in its folder), so the helper
    /// sent nothing (RemoveMacAI's `present`).
    case notPresent
    /// Something on the Mac holds the set. Retry after 5 s, then 15 s; still locked means a
    /// restart is needed.
    case locked
    /// No reply within the timeout.
    case noAnswer
    /// The service answered with an error.
    case failed(String)
    /// The helper would not send the request (unknown set, empty, mismatched type).
    case refused(String)

    var rawName: String {
        switch self {
        case .done: return "done"
        case .notPresent: return "notPresent"
        case .locked: return "locked"
        case .noAnswer: return "noAnswer"
        case .failed: return "failed"
        case .refused: return "refused"
        }
    }

    var message: String? {
        switch self {
        case .failed(let m), .refused(let m): return m
        case .done, .notPresent, .locked, .noAnswer: return nil
        }
    }

    static func make(rawName: String, message: String?) -> AssetResetOutcome {
        switch rawName {
        case "done": return .done
        case "notPresent": return .notPresent
        case "locked": return .locked
        case "failed": return .failed(message ?? "")
        case "refused": return .refused(message ?? "")
        default: return .noAnswer
        }
    }
}

/// The reset JSON the helper prints and the client reads back.
private struct ResetReport: Codable { let outcome: String; let message: String? }

// MARK: - The bridge: the only code that calls the framework

/// The framework reads the helper needs. The real one (`AssetServiceBridge`) calls
/// `UnifiedAssetFramework`; tests pass a fake, so no test touches the framework.
protocol AssetBridging: Sendable {
    /// The framework loaded and the foundation-models set is known (RemoveMacAI's `available`).
    func available() -> Bool
    /// `getAssetSet:`/`autoAssetType` for a set, or nil when the service does not know it.
    func assetType(of setName: String) -> String?
    /// Bytes of present assets by asset type, from the inventory, or nil when it did not answer.
    func inventoryBytes() -> [String: Int64]?
    /// Whether the set's asset folder still holds model files. Read only within a removal.
    func folderHoldsFiles(assetType: String) -> Bool
    /// Whether the service's XPC protocol still has `operationWithConfig:completion:`; checked
    /// before any connection is created. Creates no connection.
    func operationSupported() -> Bool
    /// Removes one set's models through the asset service. Never called in tests or deep_verify.
    func reset(set: String, timeout: TimeInterval) -> AssetResetOutcome
}

/// The one Objective-C method of the asset service's XPC protocol Lightspot would call. Apple's
/// protocol is private, so the selector is declared here and the NSXPC proxy is cast to it; the
/// proxy builds the message from Apple's remote interface, so only the objc_msgSend shape has to
/// match (`Vv32@0:8@16@?24`). Platform report A9.
@objc private protocol UAFOperationCalling {
    @objc(operationWithConfig:completion:)
    func operation(config: NSDictionary, completion: @escaping @Sendable (NSError?) -> Void)
}

/// The real bridge. Calls `UnifiedAssetFramework` exactly as RemoveMacAI's UAF.m does, in the
/// three shapes the platform report compiled (A8). Only the helper process and deep_verify
/// create one; Lightspot's own process never does.
struct AssetServiceBridge: AssetBridging {
    static let frameworkPath =
        "/System/Library/PrivateFrameworks/UnifiedAssetFramework.framework/UnifiedAssetFramework"
    static let machService = "com.apple.siri.uaf.subscription.service"
    static let assetsRoot = "/System/Library/AssetsV2"

    /// dlopen the framework (a no-op on macOS 26, where AppKit already loaded it; kept for older
    /// systems and to fail closed).
    @discardableResult
    static func load() -> Bool { dlopen(frameworkPath, RTLD_NOW) != nil }

    func available() -> Bool { Self.load() && assetType(of: Catalog.foundationModels) != nil }

    func assetType(of setName: String) -> String? {
        guard let managerClass = NSClassFromString("UAFConfigurationManager") as? NSObject.Type,
              let manager = Self.callObject(managerClass, "defaultManager") as? NSObject,
              let set = Self.callObject(manager, "getAssetSet:", setName as NSString) as? NSObject
        else { return nil }
        return Self.callObject(set, "autoAssetType") as? String
    }

    func inventoryBytes() -> [String: Int64]? {
        guard Self.load(),
              let managerClass = NSClassFromString("UAFAssetSetManager") as? NSObject.Type
        else { return nil }
        var error: NSError?
        guard let info = Self.callClassWithError(managerClass, "generateInformationWithError:", error: &error)
        else { return nil }
        let dictionary: [String: Any]?
        if let json = info as? String {
            dictionary = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
        } else {
            dictionary = info as? [String: Any]
        }
        guard let dictionary else { return nil }
        return Self.parseInventory(dictionary)
    }

    /// RemoveMacAI's `parseInventory`, unchanged: bytes of present assets by asset type.
    static func parseInventory(_ info: [String: Any]) -> [String: Int64] {
        var bytes: [String: Int64] = [:]
        for asset in info["SystemAssets"] as? [[String: Any]] ?? [] {
            guard asset["isPresentOnDevice"] as? Bool == true,
                  let meta = asset["metadata"] as? [String: Any],
                  let type = meta["AssetType"] as? String
            else { continue }
            let size = meta["com.apple.UnifiedAssetFramework.UnarchivedSize"] ?? meta["_UnarchivedSize"]
            bytes[type, default: 0] += Int64("\(size ?? 0)") ?? 0
        }
        return bytes
    }

    /// RemoveMacAI's `folderHoldsFiles`: macOS will not list some of these folders, but it says
    /// how many entries a folder has and whether a named entry exists, so only those are used.
    /// Reads attributes under `/System/Library/AssetsV2` only (invariant 3), and only within a
    /// removal, for a set the inventory gives no bytes.
    func folderHoldsFiles(assetType: String) -> Bool {
        let name = assetType.replacingOccurrences(of: ".", with: "_")
        let folder = Self.assetsRoot + "/" + name
        var info = stat()
        if lstat(folder, &info) != 0 { return errno != ENOENT }
        let files = FileManager.default
        guard let top = Self.entryCount(folder) else { return true }
        let purpose = folder + "/purpose_auto"
        guard files.fileExists(atPath: purpose) else { return top > 0 }
        guard let before = Self.modified(purpose), let inner = Self.entryCount(purpose) else { return true }
        let catalog = [name + ".xml", name + ".xml.purged"].filter { files.fileExists(atPath: purpose + "/" + $0) }
        guard let after = Self.modified(purpose), after == before else { return true }
        return top > 1 || inner > catalog.count
    }

    func operationSupported() -> Bool { Self.remoteInterface() != nil }

    /// Apple's interface for the service, or nil when this macOS lacks it or its protocol no
    /// longer has `operationWithConfig:completion:`. Creates no connection.
    private static func remoteInterface() -> NSXPCInterface? {
        let factory = NSSelectorFromString("defaultInterface")
        guard let cls = NSClassFromString("UAFXPCProxyServiceInterface") as? NSObject.Type,
              cls.responds(to: factory),
              let interface = cls.perform(factory)?.takeUnretainedValue() as? NSXPCInterface
        else { return nil }
        let operation = NSSelectorFromString("operationWithConfig:completion:")
        let proto = interface.protocol
        guard protocol_getMethodDescription(proto, operation, true, true).name != nil
            || protocol_getMethodDescription(proto, operation, false, true).name != nil
        else { return nil }
        return interface
    }

    /// The reset request as UAF.m builds it: one set per request (the service reads a missing
    /// list as every set), its list an NSArray copy.
    static func resetConfig(set: String) -> NSDictionary {
        ["Operation": "ResetAssetSets", "AssetSets": NSArray(array: [set])]
    }

    /// Removes one set's downloaded models. Blocking. Every check runs before the connection
    /// exists, and the first of the completion, the error handler and an invalidation wins. Only
    /// ever reached through `--asset-service reset`, which Lightspot's own process never runs.
    func reset(set: String, timeout: TimeInterval) -> AssetResetOutcome {
        guard !set.isEmpty else { return .refused("refusing an empty asset set name") }
        guard let interface = Self.remoteInterface() else {
            return .failed("the asset service does not accept operations on this version of macOS")
        }
        let reply = FirstReply()
        let connection = NSXPCConnection(machServiceName: Self.machService, options: [])
        connection.remoteObjectInterface = interface
        connection.invalidationHandler = { reply.finish(.failed("the asset service connection was invalidated")) }
        connection.resume()
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in reply.finish(Self.outcome(error as NSError)) }
        let service = unsafeBitCast(proxy as AnyObject, to: (any UAFOperationCalling).self)
        service.operation(config: Self.resetConfig(set: set)) { error in reply.finish(error.map(Self.outcome) ?? .done) }
        let result = reply.wait(timeout) ?? .noAnswer
        connection.invalidate()
        return result
    }

    /// RemoveMacAI's lock test (System.swift `isLocked`).
    static func outcome(_ error: NSError) -> AssetResetOutcome {
        if error.userInfo["currentLockUsage"] != nil || error.localizedDescription.contains("current locks") {
            return .locked
        }
        return .failed("\(error.localizedDescription) (\(error.domain) \(error.code))")
    }

    // MARK: The three call shapes (platform report A8)

    /// An object-returning method (0 or 1 object arguments). `perform` hands back +0.
    private static func callObject(_ target: NSObjectProtocol, _ selectorName: String, _ argument: Any? = nil) -> AnyObject? {
        let selector = NSSelectorFromString(selectorName)
        guard target.responds(to: selector) else { return nil }
        let result = argument == nil ? target.perform(selector) : target.perform(selector, with: argument)
        return result?.takeUnretainedValue()
    }

    private static func callObject(_ cls: NSObject.Type, _ selectorName: String, _ argument: Any? = nil) -> AnyObject? {
        let selector = NSSelectorFromString(selectorName)
        guard cls.responds(to: selector) else { return nil }
        let result = argument == nil ? cls.perform(selector) : cls.perform(selector, with: argument)
        return result?.takeUnretainedValue()
    }

    /// A class method with an `NSError**` out-parameter; the IMP is cast to a C function so
    /// `&error` works.
    private typealias ObjectWithError =
        @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> Unmanaged<AnyObject>?

    private static func callClassWithError(_ cls: NSObject.Type, _ selectorName: String, error: inout NSError?) -> AnyObject? {
        let selector = NSSelectorFromString(selectorName)
        guard cls.responds(to: selector), let imp = cls.method(for: selector) else { return nil }
        return unsafeBitCast(imp, to: ObjectWithError.self)(cls, selector, &error)?.takeUnretainedValue()
    }

    /// Entries in a folder from its attributes rather than a listing (RemoveMacAI `entryCount`).
    private static func entryCount(_ path: String) -> Int? {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.dirattr = attrgroup_t(ATTR_DIR_ENTRYCOUNT)
        var reply: (length: UInt32, count: UInt32) = (0, 0)
        let status = withUnsafeMutableBytes(of: &reply) { getattrlist(path, &request, $0.baseAddress, $0.count, 0) }
        return status == 0 && reply.length >= UInt32(MemoryLayout.size(ofValue: reply)) ? Int(reply.count) : nil
    }

    private static func modified(_ path: String) -> (seconds: Int, nanoseconds: Int)? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return (info.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec)
    }
}

/// The first of the completion, the error handler and an invalidation wins; the rest are ignored.
private final class FirstReply: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var value: AssetResetOutcome?

    func finish(_ outcome: AssetResetOutcome) {
        lock.lock()
        defer { lock.unlock() }
        guard value == nil else { return }
        value = outcome
        semaphore.signal()
    }

    func wait(_ timeout: TimeInterval) -> AssetResetOutcome? {
        guard semaphore.wait(timeout: .now() + timeout) == .success else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

// MARK: - The helper's entry point

/// What runs inside the `--asset-service` child. Pure: it takes the bridge and a sink for the
/// one JSON line, so a test drives it with a fake bridge and no framework. The `reset` verb is
/// here for completeness and is never run by Lightspot itself.
enum AssetServiceHelper {
    /// Parses `--asset-service <verb> [set]`, runs the bridge, prints one JSON object, and
    /// returns the process's exit status.
    static func run(_ arguments: [String], bridge: AssetBridging, out: (String) -> Void) -> Int32 {
        guard let flag = arguments.firstIndex(of: "--asset-service") else { return 2 }
        let rest = Array(arguments[(flag + 1)...])
        switch rest.first {
        case "inventory":
            out(encode(inventory(bridge: bridge)))
            return 0
        case "reset":
            guard rest.count >= 2 else {
                out(encodeReset(.refused("no model set given")))
                return 2
            }
            out(encodeReset(reset(set: rest[1], bridge: bridge)))
            return 0
        default:
            out(#"{"error":"unknown asset-service verb"}"#)
            return 2
        }
    }

    /// Builds the inventory object: availability, and per catalog set its known flag, asset type
    /// and bytes. A failed inventory call leaves every size unknown (nil), never 0. Reads no
    /// folders: those are only looked at within a removal (`reset`).
    static func inventory(bridge: AssetBridging) -> AssetInventory {
        guard bridge.available() else { return AssetInventory(available: false, sets: []) }
        let bytes = bridge.inventoryBytes()
        let sets = Catalog.modelSets.map { set -> AssetSetInfo in
            let type = bridge.assetType(of: set.name)
            return AssetSetInfo(
                name: set.name,
                known: type == set.assetType,
                assetType: type,
                bytes: bytes.map { $0[set.assetType] ?? 0 })
        }
        return AssetInventory(available: true, sets: sets)
    }

    /// Refuses a set that is not in the catalog, an empty request, or one whose asset type no
    /// longer matches, before the bridge creates any connection. Then RemoveMacAI's `present`:
    /// a set with no tracked bytes and no files in its folder gets no request at all. Checks
    /// `operationWithConfig:` too. Never called by Lightspot's own process.
    static func reset(set: String, bridge: AssetBridging, timeout: TimeInterval = 120) -> AssetResetOutcome {
        guard !set.isEmpty else { return .refused("refusing an empty asset set request") }
        guard let model = Catalog.modelSet(set) else { return .refused("unknown model set \(set)") }
        guard bridge.available() else { return .failed("the asset service is unavailable") }
        guard let type = bridge.assetType(of: set), type == model.assetType else {
            return .refused("the asset type no longer matches \(set) on this version of macOS")
        }
        let tracked = bridge.inventoryBytes()?[model.assetType] ?? 0
        guard tracked > 0 || bridge.folderHoldsFiles(assetType: model.assetType) else { return .notPresent }
        guard bridge.operationSupported() else {
            return .failed("the asset service does not accept operations")
        }
        return bridge.reset(set: set, timeout: timeout)
    }

    static func encode(_ inventory: AssetInventory) -> String {
        guard let data = try? JSONEncoder().encode(inventory) else { return #"{"available":false,"sets":[]}"# }
        return String(decoding: data, as: UTF8.self)
    }

    static func encodeReset(_ outcome: AssetResetOutcome) -> String {
        let report = ResetReport(outcome: outcome.rawName, message: outcome.message)
        guard let data = try? JSONEncoder().encode(report) else { return #"{"outcome":"noAnswer"}"# }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - The client the app uses

/// Runs the `--asset-service` child and decodes its one JSON line. `runHelper` is injected so
/// tests can feed a crash (nil), a timeout (nil) or garbage (undecodable) and see the client
/// fail closed; `.live` spawns the Lightspot binary.
struct AssetServiceClient: Sendable {
    /// Runs the helper with these arguments and a timeout; nil when it could not start, crashed,
    /// or ran past the timeout.
    var runHelper: @Sendable (_ arguments: [String], _ timeout: TimeInterval) -> (status: Int32, output: String)?

    static let inventoryTimeout: TimeInterval = 30
    static let resetTimeout: TimeInterval = 150

    /// The inventory, or nil when the child did not answer or its output did not decode: the
    /// caller then treats the asset service as unavailable and changes nothing.
    func inventory() -> AssetInventory? {
        guard let result = runHelper(["--asset-service", "inventory"], Self.inventoryTimeout),
              result.status == 0,
              let data = Self.jsonData(result.output),
              let inventory = try? JSONDecoder().decode(AssetInventory.self, from: data)
        else { return nil }
        return inventory
    }

    /// Resets one set through the child. Fails closed to `.noAnswer` when the child did not
    /// answer, exited with an error, or its output did not decode.
    func reset(_ set: String) -> AssetResetOutcome {
        guard let result = runHelper(["--asset-service", "reset", set], Self.resetTimeout),
              result.status == 0,
              let data = Self.jsonData(result.output),
              let report = try? JSONDecoder().decode(ResetReport.self, from: data)
        else { return .noAnswer }
        return AssetResetOutcome.make(rawName: report.outcome, message: report.message)
    }

    /// The child prints exactly one JSON object on stdout; take the line that starts with "{"
    /// so a stray framework log can't spoil decoding.
    private static func jsonData(_ output: String) -> Data? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("{") { return Data(trimmed.utf8) }
        }
        return nil
    }

    static var live: AssetServiceClient { AssetServiceClient(runHelper: { liveRun($0, $1) }) }

    /// The Lightspot binary as the helper.
    private static func liveRun(_ arguments: [String], _ timeout: TimeInterval) -> (status: Int32, output: String)? {
        run(executable: Bundle.main.executablePath ?? CommandLine.arguments.first ?? "", arguments: arguments, timeout: timeout)
    }

    /// One child through Clean Dev Mac's runner: stdin from /dev/null, stdout read as it comes
    /// (invariant 1), stopped past the timeout. nil when it couldn't start or ran over; a crash
    /// comes back as a non-zero status, which the callers above refuse.
    static func run(executable: String, arguments: [String], timeout: TimeInterval) -> (status: Int32, output: String)? {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }
        let result = CleanDevMacEngine.run(executable, arguments, timeout: timeout)
        return result.status == -1 ? nil : result
    }
}
