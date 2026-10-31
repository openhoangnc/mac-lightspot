import Foundation

// MARK: - Mac Tweaks: preferences and the undo journal
//
// The pieces Mac Tweaks' Settings section (and Background Items) share to change a setting and put
// it back: `PreferenceValue`, a preference as cfprefsd holds it; `PreferenceStore`, reading and
// writing through cfprefsd (invariant 8), injected so tests use scratch domains; and
// `MacTweaksJournal`, the file that keeps, for every setting Lightspot changed, its value from
// before Lightspot first changed it. Ported from RemoveMacAI's Prefs.swift and Engine.swift (MIT);
// the journal's format, its write-ahead saves and its tolerance for entries it can't read are
// Lightspot's.

/// A preference value as cfprefsd holds it. Booleans, integers, 64-bit reals and strings are kept
/// as they are; anything else (an array, a dictionary, data, a date, a 32-bit real) as binary plist
/// data, so it goes back exactly as it was read: cfprefsd keeps every type as written.
enum PreferenceValue: Sendable, Equatable {
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case plist(Data)

    /// A stored value, or nil when there is none (or it isn't a property list).
    init?(_ object: Any?) {
        guard let object else { return nil }
        let ref = object as AnyObject
        let type = CFGetTypeID(ref)
        if type == CFBooleanGetTypeID(), let flag = object as? Bool {
            self = .bool(flag)
            return
        }
        if type == CFNumberGetTypeID() {
            let number = ref as! CFNumber
            if !CFNumberIsFloatType(number) {
                var value: Int64 = 0
                CFNumberGetValue(number, .sInt64Type, &value)
                self = .int(value)
                return
            }
            let kind = CFNumberGetType(number)
            if kind == .float64Type || kind == .doubleType {
                var value = 0.0
                CFNumberGetValue(number, .float64Type, &value)
                self = .double(value)
                return
            }
            // A 32-bit real: exact only as a property list.
        }
        if type == CFStringGetTypeID(), let text = object as? String {
            self = .string(text)
            return
        }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0) else { return nil }
        self = .plist(data)
    }

    /// The object cfprefsd stores. Nil only for property list data that no longer decodes.
    var object: Any? {
        switch self {
        case .bool(let value): return NSNumber(value: value)
        case .int(let value): return NSNumber(value: value)
        case .double(let value): return NSNumber(value: value)
        case .string(let value): return value as NSString
        case .plist(let data): return try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        }
    }

    /// A number kept as a property list (a 32-bit real), as a Double.
    var realValue: Double? {
        guard case .plist = self, let number = object as? NSNumber, CFGetTypeID(number) == CFNumberGetTypeID() else { return nil }
        return number.doubleValue
    }

    /// How `CFPreferencesGetAppBooleanValue` reads it, which is how apps read their switches: a
    /// boolean, any number (0 is false), or "true"/"yes"/"1" and "false"/"no"/"0" in any case.
    /// Nil for anything else ("y", "SCcf").
    var boolReading: Bool? {
        switch self {
        case .bool(let value): return value
        case .int(let value): return value != 0
        case .double(let value): return value != 0
        case .string(let text):
            switch text.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        case .plist: return realValue.map { $0 != 0 }
        }
    }

    /// Whether a stored value means this one. A boolean matches what reads as that boolean
    /// (RemoveMacAI's 0/1 rule, plus the strings macOS itself accepts, as Lightspot's toggles
    /// do); an integer matches the same number, and a boolean only when it is 0 or 1 ("Siri Data
    /// Sharing Opt-In Status" 2 must not match true); a real matches the same number (as a Float
    /// when either side is 32-bit); a string matches itself. Unset matches nothing.
    func matches(_ stored: PreferenceValue?) -> Bool {
        guard let stored else { return false }
        switch self {
        case .bool(let wanted):
            return stored.boolReading == wanted
        case .int(let wanted):
            switch stored {
            case .int(let value): return value == wanted
            case .double(let value): return value == Double(wanted)
            case .bool(let value): return (wanted == 0 || wanted == 1) && value == (wanted == 1)
            case .plist: return stored.realValue == Double(wanted)
            case .string: return false
            }
        case .double(let wanted):
            switch stored {
            case .double(let value): return value == wanted
            case .int(let value): return Double(value) == wanted
            case .plist: return stored.realValue.map { Float($0) == Float(wanted) } ?? false
            case .bool, .string: return false
            }
        case .string(let wanted):
            if case .string(let value) = stored { return value == wanted }
            return false
        case .plist:
            return stored == self
        }
    }

    /// The same stored value: equal cases, and for property lists equal objects (a dictionary's
    /// binary encoding can order its keys differently each time).
    func isSameValue(_ other: PreferenceValue) -> Bool {
        if self == other { return true }
        guard case .plist = self, case .plist = other, let a = object, let b = other.object else { return false }
        return (a as AnyObject).isEqual(b)
    }

    /// For the plan and the receipt: "true", "2", "0.5", "\"SCcf\"", "an array of 3 items".
    var shown: String {
        switch self {
        case .bool(let value): return value ? "true" : "false"
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .string(let value): return "\"\(value)\""
        case .plist:
            let object = self.object
            if let real = realValue { return String(Float(real)) }
            if let array = object as? NSArray { return "an array of \(array.count) \(array.count == 1 ? "item" : "items")" }
            if let dict = object as? NSDictionary { return "a dictionary of \(dict.count) \(dict.count == 1 ? "key" : "keys")" }
            if let data = object as? Data { return "\(data.count) bytes of data" }
            if let date = object as? Date { return ISO8601DateFormatter().string(from: date) }
            return "a stored value"
        }
    }

    /// The type and value as `defaults write` takes them: "-bool true", "-float 0.0". Nil for an
    /// array, a dictionary, data or a date, which a plan describes instead.
    var defaultsArguments: String? {
        switch self {
        case .bool(let value): return "-bool \(value ? "true" : "false")"
        case .int(let value): return "-int \(value)"
        case .double(let value): return "-float \(value)"
        case .string(let value): return "-string " + MacTweaksSettings.shellWord(value)
        case .plist: return realValue.map { "-float \(Float($0))" }
        }
    }
}

extension PreferenceValue: Codable {
    private enum CodingKeys: String, CodingKey { case bool, int, double, string, plist, shown }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(Bool.self, forKey: .bool) {
            self = .bool(value)
        } else if let value = try container.decodeIfPresent(Int64.self, forKey: .int) {
            self = .int(value)
        } else if let value = try container.decodeIfPresent(Double.self, forKey: .double) {
            self = .double(value)
        } else if let value = try container.decodeIfPresent(String.self, forKey: .string) {
            self = .string(value)
        } else if let value = try container.decodeIfPresent(Data.self, forKey: .plist) {
            self = .plist(value)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "no value"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bool(let value): try container.encode(value, forKey: .bool)
        case .int(let value): try container.encode(value, forKey: .int)
        case .double(let value): try container.encode(value, forKey: .double)
        case .string(let value): try container.encode(value, forKey: .string)
        case .plist(let data):
            try container.encode(data, forKey: .plist)
            try container.encode(shown, forKey: .shown)
        }
    }
}

// MARK: - Preferences through cfprefsd

/// Reads and writes preferences the way `defaults` does, through cfprefsd (invariant 8): the
/// daemon's copy is the truth, never the plist file. Injected so test_engine writes only scratch
/// domains (`scratch(run:)`) and deep_verify writes nothing.
struct PreferenceStore: Sendable {
    /// What apps see: a forced (managed) value wins over the user's own. Synchronize the domain
    /// first to see another process's changes.
    var read: @Sendable (_ domain: String, _ key: String) -> PreferenceValue? = { _, _ in nil }
    /// This user's own value, ignoring forced ones (CopyValue, current user, any host).
    var userValue: @Sendable (_ domain: String, _ key: String) -> PreferenceValue? = { _, _ in nil }
    /// Whether a configuration profile forces the key.
    var isForced: @Sendable (_ domain: String, _ key: String) -> Bool = { _, _ in false }
    /// Writes this user's value, nil deleting it, and synchronizes: true when cfprefsd took it.
    var write: @Sendable (_ domain: String, _ key: String, _ value: PreferenceValue?) -> Bool = { _, _, _ in false }
    /// Drops this process's cached copy of a domain, so the next read asks cfprefsd.
    var synchronize: @Sendable (_ domain: String) -> Void = { _ in }

    /// Reads nothing, writes nothing: the default for environments that don't change settings.
    static let inert = PreferenceStore()

    /// The application ID CFPreferences takes: "NSGlobalDomain" and ".GlobalPreferences" are
    /// every application's (report B1: both read the same values).
    static func application(_ domain: String) -> CFString {
        domain == "NSGlobalDomain" || domain == ".GlobalPreferences" ? kCFPreferencesAnyApplication : domain as CFString
    }

    /// cfprefsd, with every domain and key passed through the maps first, so a mapped domain can
    /// never reach the real global one (the mapping comes before `application`).
    static func live(domain mapDomain: @escaping @Sendable (String) -> String = { $0 },
                     key mapKey: @escaping @Sendable (String) -> String = { $0 }) -> PreferenceStore {
        let app: @Sendable (String) -> CFString = { application(mapDomain($0)) }
        var store = PreferenceStore()
        store.read = { domain, key in
            PreferenceValue(CFPreferencesCopyAppValue(mapKey(key) as CFString, app(domain)))
        }
        store.userValue = { domain, key in
            PreferenceValue(CFPreferencesCopyValue(mapKey(key) as CFString, app(domain), kCFPreferencesCurrentUser, kCFPreferencesAnyHost))
        }
        store.isForced = { domain, key in CFPreferencesAppValueIsForced(mapKey(key) as CFString, app(domain)) }
        store.write = { domain, key, value in
            var object: CFPropertyList?
            if let value {
                guard let decoded = value.object else { return false }
                object = decoded as CFPropertyList
            }
            CFPreferencesSetValue(mapKey(key) as CFString, object, app(domain), kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            return CFPreferencesSynchronize(app(domain), kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
        store.synchronize = { domain in
            CFPreferencesAppSynchronize(app(domain))
            CFPreferencesSynchronize(app(domain), kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
        return store
    }

    /// The prefix every scratch domain starts with: nothing else is ever written by a test.
    static let scratchPrefix = "com.lightspot.test."

    /// The scratch domain a real domain maps to for test run `run`.
    static func scratchDomain(_ domain: String, run: String) -> String {
        scratchPrefix + run + "." + domain.replacingOccurrences(of: " ", with: "-")
    }

    /// The live code path on scratch domains only: every domain becomes
    /// `com.lightspot.test.<run>.<domain>`, and every key gains a prefix, because a key a scratch
    /// domain doesn't hold falls back to the real global domain's value (CopyAppValue).
    static func scratch(run: String) -> PreferenceStore {
        live(domain: { domain in
            let mapped = scratchDomain(domain, run: run)
            precondition(mapped.hasPrefix(scratchPrefix), "scratch domains only")
            return mapped
        }, key: { "LightspotTest." + $0 })
    }
}

// MARK: - The undo journal

/// `~/Library/Application Support/Lightspot/tweaks-journal.json`: for every setting Lightspot
/// changed, its value from before Lightspot first changed it, so undo can put it back.
///
/// - One entry per changed thing, keyed `pref:<domain>:<key>`, `service:<label>`,
///   `dock:<bundle ids>`, `library`, or (Background Items) `background:gui|system/<label>`. Each
///   holds what its undo needs, so an entry undoes without the catalog that wrote it.
/// - First previous value wins: an entry is added only when there is none for its key, and is
///   removed once its undo is verified.
/// - Every entry is kept as compact JSON with sorted keys, and written back as it was read: a
///   kind this version doesn't read (a later version's, or Background Items' own fields) is never
///   dropped or rewritten. Typed entries (`pref`, `service`, `dock`, `hidden`) decode on demand.
/// - Saved ahead of each change (`saveAhead`), atomically. An unreadable file is never
///   overwritten: a scan only reports it (`status`); a write moves it aside first
///   (`loadForWriting`), and when it can't be moved nothing changes.
///
/// Read and written only on MacTweaksProvider's serial queue.
struct MacTweaksJournal: Sendable, Equatable {
    static let version = 1
    static let fileName = "tweaks-journal.json"

    static func url(home: String) -> URL {
        URL(fileURLWithPath: home + "/Library/Application Support/Lightspot/" + fileName)
    }

    /// The kinds this version reads; every other kind is kept as it is.
    static let typedKinds: Set<String> = ["pref", "service", "dock", "hidden"]

    /// One typed entry.
    struct Entry: Codable, Sendable, Equatable {
        var kind: String
        /// The tweak that changed it.
        var tweak: String
        var date: Date
        // pref
        var domain: String?
        var key: String?
        /// The user's own value before; absent when the key was unset.
        var previous: PreferenceValue?
        /// The processes that read it only at launch (Finder, Dock, SystemUIServer).
        var restart: [String]?
        // service
        var label: String?
        var wasDisabled: Bool?
        /// The job's plist, bootstrapped again on undo when it isn't loaded (com.apple.rcd).
        var plist: String?
        // dock
        var tiles: [Tile]?
        // hidden
        /// Home-relative ("Library").
        var path: String?
        var wasHidden: Bool?

        static func pref(tweak: String, date: Date, domain: String, key: String, previous: PreferenceValue?, restart: [String]) -> Entry {
            Entry(kind: "pref", tweak: tweak, date: date, domain: domain, key: key, previous: previous,
                  restart: restart.isEmpty ? nil : restart)
        }

        static func service(tweak: String, date: Date, label: String, wasDisabled: Bool, plist: String?) -> Entry {
            Entry(kind: "service", tweak: tweak, date: date, label: label, wasDisabled: wasDisabled, plist: plist)
        }

        static func dock(tweak: String, date: Date, tiles: [Tile], restart: [String]) -> Entry {
            Entry(kind: "dock", tweak: tweak, date: date, restart: restart, tiles: tiles)
        }

        static func hidden(tweak: String, date: Date, path: String, wasHidden: Bool) -> Entry {
            Entry(kind: "hidden", tweak: tweak, date: date, path: path, wasHidden: wasHidden)
        }
    }

    /// A Dock tile Lightspot removed: where it was, its name, and the tile itself.
    struct Tile: Codable, Sendable, Equatable {
        var index: Int
        var label: String
        var plist: Data
    }

    /// Every entry, by key, as compact JSON with sorted keys.
    private(set) var stored: [String: Data] = [:]

    var isEmpty: Bool { stored.isEmpty }
    var keys: [String] { stored.keys.sorted() }

    /// An entry's raw JSON object.
    func json(_ key: String) -> Data? { stored[key] }

    /// An entry's kind, read from its JSON.
    func kind(_ key: String) -> String? {
        guard let data = stored[key], let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["kind"] as? String
    }

    /// A typed entry, or nil for another kind or one that doesn't decode.
    func entry(_ key: String) -> Entry? {
        guard let data = stored[key], let kind = kind(key), Self.typedKinds.contains(kind) else { return nil }
        return try? Self.decoder.decode(Entry.self, from: data)
    }

    /// The typed entries, by key.
    var entries: [(key: String, entry: Entry)] {
        keys.compactMap { key in entry(key).map { (key, $0) } }
    }

    /// The entries of one kind, as Background Items reads its own: `(key, json)`.
    func entries(kind: String) -> [(key: String, json: Data)] {
        keys.compactMap { key in self.kind(key) == kind ? stored[key].map { (key, $0) } : nil }
    }

    /// Adds a typed entry unless one exists for the key. True when it was added.
    @discardableResult
    mutating func recordIfAbsent(_ key: String, _ entry: Entry) -> Bool {
        guard stored[key] == nil, let data = try? Self.encoder.encode(entry) else { return false }
        stored[key] = data
        return true
    }

    /// Adds a raw JSON object (Background Items' entries) unless one exists for the key. The
    /// object is kept in canonical form, so a load and save leaves it byte for byte. True when it
    /// was added; false when the key exists or the JSON isn't an object.
    @discardableResult
    mutating func recordIfAbsent(_ key: String, _ json: Data) -> Bool {
        guard stored[key] == nil, let object = try? JSONSerialization.jsonObject(with: json),
              object is [String: Any], let data = Self.canonical(object) else { return false }
        stored[key] = data
        return true
    }

    /// Replaces or adds a raw JSON object (a Background Items delete, which gains where its plist
    /// went), in canonical form as `recordIfAbsent` keeps one. False when the JSON isn't an object.
    @discardableResult
    mutating func replace(_ key: String, _ json: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: json), object is [String: Any],
              let data = Self.canonical(object) else { return false }
        stored[key] = data
        return true
    }

    /// Replaces a typed entry (the Dock's, which gains tiles).
    mutating func replace(_ key: String, _ entry: Entry) {
        if let data = try? Self.encoder.encode(entry) { stored[key] = data }
    }

    mutating func remove(_ key: String) { stored[key] = nil }

    /// Puts a key back as `json` (from `json(_:)`, nil for none) after the change recorded for it
    /// didn't happen.
    mutating func reset(_ key: String, to json: Data?) { stored[key] = json }

    // MARK: The file

    /// Compact, sorted keys, ISO 8601 dates. Made per use: they are cheap and not Sendable.
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func canonical(_ object: Any) -> Data? {
        try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
    }

    /// The file's bytes: one entry per line, keys sorted, so a diff reads well and entries this
    /// version doesn't read come back exactly as they went in.
    func encoded() -> Data {
        var text = "{\n  \"entries\" : {"
        let lines = keys.compactMap { key -> String? in
            guard let name = try? Self.encoder.encode(key), let value = stored[key] else { return nil }
            return "\n    " + String(decoding: name, as: UTF8.self) + " : " + String(decoding: value, as: UTF8.self)
        }
        text += lines.joined(separator: ",")
        text += (lines.isEmpty ? "" : "\n  ") + "},\n  \"version\" : \(Self.version)\n}\n"
        return Data(text.utf8)
    }

    /// The journal in `data`, or nil when it isn't a JSON object with an `entries` object.
    static func decode(_ data: Data) -> MacTweaksJournal? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["entries"] as? [String: Any] else { return nil }
        var journal = MacTweaksJournal()
        for (key, object) in entries {
            guard let data = canonical(object) else { return nil }
            journal.stored[key] = data
        }
        return journal
    }

    /// The file operations, injected so deep_verify can forbid every write.
    struct FileSystem: Sendable {
        var exists: @Sendable (URL) -> Bool = { _ in false }
        /// Nil when it can't be read.
        var read: @Sendable (URL) -> Data? = { _ in nil }
        /// Atomically, creating the folder.
        var write: @Sendable (URL, Data) throws -> Void = { _, _ in throw CocoaError(.featureUnsupported) }
        var remove: @Sendable (URL) throws -> Void = { _ in throw CocoaError(.featureUnsupported) }
        var move: @Sendable (URL, URL) throws -> Void = { _, _ in throw CocoaError(.featureUnsupported) }
        /// Whether a file in the folder can be renamed (the folder is writable).
        var canRename: @Sendable (URL) -> Bool = { _ in false }

        static let inert = FileSystem()

        static let live: FileSystem = {
            var fs = FileSystem()
            fs.exists = { FileManager.default.fileExists(atPath: $0.path) }
            fs.read = { FileManager.default.contents(atPath: $0.path) }
            fs.write = { url, data in
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            }
            fs.remove = { try FileManager.default.removeItem(at: $0) }
            fs.move = { try FileManager.default.moveItem(at: $0, to: $1) }
            fs.canRename = { FileManager.default.isWritableFile(atPath: $0.deletingLastPathComponent().path) }
            return fs
        }()
    }

    /// What reading the file found.
    enum Load: Sendable, Equatable {
        case missing
        case loaded(MacTweaksJournal)
        case unreadable

        /// The journal to work from: empty when there is no file, nil when it can't be read.
        var journal: MacTweaksJournal? {
            switch self {
            case .missing: return MacTweaksJournal()
            case .loaded(let journal): return journal
            case .unreadable: return nil
            }
        }
    }

    static func load(url: URL, fileSystem: FileSystem = .live) -> Load {
        guard fileSystem.exists(url) else { return .missing }
        guard let data = fileSystem.read(url), let journal = decode(data) else { return .unreadable }
        return .loaded(journal)
    }

    /// What a scan reports, moving and writing nothing.
    enum Status: Sendable, Equatable {
        case ready
        /// It can't be read: the first write moves it aside.
        case unreadable(String)
        /// It can't be read, nor moved: nothing changes.
        case blocked(String)

        var isBlocked: Bool { if case .blocked = self { return true }; return false }
        var reason: String? {
            switch self {
            case .ready: return nil
            case .unreadable(let reason), .blocked(let reason): return reason
            }
        }
    }

    static func unreadableReason(_ shown: String) -> String {
        "Lightspot can't read its undo journal (\(shown)). Applying keeps it aside as a new file; undo can't use what it recorded."
    }

    static func blockedReason(_ shown: String) -> String {
        "Lightspot can't read or move its undo journal (\(shown)), so it changes nothing here until that file is moved or fixed."
    }

    /// Readable (or absent), unreadable, or blocked; never moves or writes anything.
    static func status(url: URL, home: String = NSHomeDirectory(), fileSystem: FileSystem = .live) -> Status {
        guard case .unreadable = load(url: url, fileSystem: fileSystem) else { return .ready }
        let shown = CleanDevMacEngine.displayPath(url.path, home: home)
        return fileSystem.canRename(url) ? .unreadable(unreadableReason(shown)) : .blocked(blockedReason(shown))
    }

    /// The journal a write starts from.
    enum WriteAccess: Sendable, Equatable {
        /// `movedAside` names where an unreadable file went.
        case ready(MacTweaksJournal, movedAside: String?)
        case blocked(String)

        var journal: MacTweaksJournal? { if case .ready(let journal, _) = self { return journal }; return nil }
        var movedAside: String? { if case .ready(_, let name) = self { return name }; return nil }
        var blockedReason: String? { if case .blocked(let reason) = self { return reason }; return nil }
    }

    /// `tweaks-journal-unreadable-2026-10-30T13-20-00Z-1a2b3c4d.json`: unique, so two bad files
    /// are both kept.
    static func asideName(now: Date, id: String = String(UUID().uuidString.prefix(8)).lowercased()) -> String {
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        return "tweaks-journal-unreadable-\(stamp)-\(id).json"
    }

    /// The journal before a write: an unreadable file is moved aside first, and when it can't be,
    /// the write is blocked and nothing changes.
    static func loadForWriting(url: URL, now: Date, home: String = NSHomeDirectory(), fileSystem: FileSystem = .live) -> WriteAccess {
        switch load(url: url, fileSystem: fileSystem) {
        case .missing: return .ready(MacTweaksJournal(), movedAside: nil)
        case .loaded(let journal): return .ready(journal, movedAside: nil)
        case .unreadable:
            let name = asideName(now: now)
            do {
                try fileSystem.move(url, url.deletingLastPathComponent().appendingPathComponent(name))
                return .ready(MacTweaksJournal(), movedAside: name)
            } catch {
                return .blocked(blockedReason(CleanDevMacEngine.displayPath(url.path, home: home)) + " (\(error.localizedDescription))")
            }
        }
    }

    /// Saves before the change it records, atomically; an empty journal removes the file.
    func saveAhead(url: URL, fileSystem: FileSystem = .live) throws {
        if isEmpty {
            if fileSystem.exists(url) { try fileSystem.remove(url) }
            return
        }
        try fileSystem.write(url, encoded())
    }
}
