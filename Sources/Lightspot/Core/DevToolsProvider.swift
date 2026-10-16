import Foundation
import AppKit
import CryptoKit

// MARK: - Dev Tools Provider

public final class DevToolsProvider: Sendable {
    public static let shared = DevToolsProvider()

    private init() {}

    /// Swift seeds `String` hashing randomly per process, so ids built from it never
    /// matched across launches: every activation wrote a fresh, permanently unreachable
    /// row into the persisted search history and evicted a real one. SHA-256 is stable.
    private static func stableID(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    func search(_ query: SearchQuery) -> [SearchResult] {
        if query.isEmpty { return [] }

        let trimmed = query.trimmed
        let lower = query.lowercased

        // 1. UUID / GUID
        if lower == "uuid" || lower == "guid" {
            let id = UUID().uuidString.lowercased()
            return [SearchResult(
                id: "dev-uuid-\(id)",
                title: id,
                subtitle: "Fresh UUID v4 · Press ↵ to copy",
                iconType: .systemSymbol(name: "number.circle.fill"),
                category: .devTools,
                score: 95,
                action: .copyToClipboard(id)
            )]
        }

        // 2. Base64 decode: "b64d <encoded>", "b64 decode <encoded>" or "base64 decode <encoded>".
        // Checked before encode: "b64 " is a prefix of "b64 decode ", so encode used to win and
        // return the Base64 of the literal text "decode <encoded>". The bare command (no
        // argument yet, e.g. mid-typing "b64 decode") is claimed too, for the same reason.
        let decodePrefixes = ["b64d ", "b64 decode ", "base64 decode "]
        if let prefix = decodePrefixes.first(where: { lower.hasPrefix($0) || lower == $0.dropLast() }) {
            let text = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty, let data = Data(base64Encoded: text), let decoded = String(data: data, encoding: .utf8) {
                return [SearchResult(
                    id: "dev-b64d-\(Self.stableID(text))",
                    title: decoded,
                    subtitle: "Base64 Decoded Text",
                    iconType: .systemSymbol(name: "lock.open.trianglebadge.exclamationmark.fill"),
                    category: .devTools,
                    score: 95,
                    action: .copyToClipboard(decoded)
                )]
            }
            // Not (yet) valid Base64: show nothing rather than falling through to encode.
            return []
        }

        // 3. Base64 encode: "b64 <text>" or "base64 <text>"
        if lower.hasPrefix("b64 ") || lower.hasPrefix("base64 ") {
            let prefixLen = lower.hasPrefix("b64 ") ? 4 : 7
            let text = String(trimmed.dropFirst(prefixLen))
            if !text.isEmpty, let data = text.data(using: .utf8) {
                let encoded = data.base64EncodedString()
                return [SearchResult(
                    id: "dev-b64-\(Self.stableID(text))",
                    title: encoded,
                    subtitle: "Base64 Encoded · '\(text)'",
                    iconType: .systemSymbol(name: "lock.rectangle.fill"),
                    category: .devTools,
                    score: 95,
                    action: .copyToClipboard(encoded)
                )]
            }
        }

        // 4. URL encode: "urlencode <text>"
        if lower.hasPrefix("urlencode ") {
            let text = String(trimmed.dropFirst("urlencode ".count))
            if let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                return [SearchResult(
                    id: "dev-urlencode-\(Self.stableID(text))",
                    title: encoded,
                    subtitle: "URL Percent-Encoded",
                    iconType: .systemSymbol(name: "link"),
                    category: .devTools,
                    score: 95,
                    action: .copyToClipboard(encoded)
                )]
            }
        }

        // 5. URL decode: "urldecode <text>"
        if lower.hasPrefix("urldecode ") {
            let text = String(trimmed.dropFirst("urldecode ".count))
            if let decoded = text.removingPercentEncoding {
                return [SearchResult(
                    id: "dev-urldecode-\(Self.stableID(text))",
                    title: decoded,
                    subtitle: "URL Percent-Decoded",
                    iconType: .systemSymbol(name: "link.badge.plus"),
                    category: .devTools,
                    score: 95,
                    action: .copyToClipboard(decoded)
                )]
            }
        }

        // 6. Unix Epoch: "epoch" or "now"
        if lower == "epoch" || lower == "now" {
            let nowSec = Int64(Date().timeIntervalSince1970)
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.timeZone = TimeZone.current
            let localStr = isoFormatter.string(from: Date())

            return [SearchResult(
                id: "dev-epoch-now",
                title: "\(nowSec)",
                subtitle: "\(nowMs) ms · Local: \(localStr)",
                iconType: .systemSymbol(name: "clock.badge.fill"),
                category: .devTools,
                score: 95,
                action: .copyToClipboard(String(nowSec))
            )]
        }

        // 7. Unix Epoch converter: "epoch <timestamp>" -> date, "epoch <date>" -> timestamp
        if lower.hasPrefix("epoch ") {
            let tsStr = String(trimmed.dropFirst("epoch ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if let ts = Double(tsStr) {
                let date = ts > 1e11 ? Date(timeIntervalSince1970: ts / 1000.0) : Date(timeIntervalSince1970: ts)
                let localStr = Self.localDisplayFormatter.string(from: date)
                let utcStr = Self.utcDisplayFormatter.string(from: date)

                return [SearchResult(
                    id: "dev-epoch-\(tsStr)",
                    title: localStr,
                    subtitle: "UTC: \(utcStr) · Epoch: \(tsStr)",
                    iconType: .systemSymbol(name: "calendar.badge.clock"),
                    category: .devTools,
                    score: 95,
                    action: .copyToClipboard(localStr)
                )]
            }

            if let date = Self.parseDate(tsStr) {
                let sec = Int64(date.timeIntervalSince1970)
                let ms = Int64((date.timeIntervalSince1970 * 1000).rounded())
                let utcStr = Self.utcDisplayFormatter.string(from: date)

                return [SearchResult(
                    id: "dev-epoch-date-\(Self.stableID(tsStr))",
                    title: "\(sec)",
                    subtitle: "\(ms) ms · UTC: \(utcStr) · Press ↵ to copy",
                    iconType: .systemSymbol(name: "clock.badge.fill"),
                    category: .devTools,
                    score: 95,
                    action: .copyToClipboard(String(sec))
                )]
            }
        }

        // 8. Hash generator: "hash <text>" (SHA-256, MD5 and SHA-1) or "hash sha256|sha1|md5 <text>"
        if lower.hasPrefix("hash ") {
            let rest = String(trimmed.dropFirst("hash ".count))
            let word = rest.prefix { !$0.isWhitespace }
            if let algorithm = HashAlgorithm(rawValue: word.lowercased()) {
                // "hash sha256" with nothing after it yet: don't hash the algorithm name.
                let text = String(rest[word.endIndex...].drop { $0.isWhitespace })
                guard !text.isEmpty else { return [] }
                return [Self.hashResult(algorithm, of: text, score: 95)]
            }
            if !rest.isEmpty {
                return [
                    Self.hashResult(.sha256, of: rest, score: 95),
                    Self.hashResult(.md5, of: rest, score: 90),
                    Self.hashResult(.sha1, of: rest, score: 85)
                ]
            }
        }

        // 9. Hex / RGB Color inspector
        let colorResults = Self.matchColor(trimmed)
        if !colorResults.isEmpty {
            return colorResults
        }

        // 10. JWT Decoder: "jwt <token>" or raw token (3 parts dot-separated)
        if lower.hasPrefix("jwt ") || (trimmed.components(separatedBy: ".").count == 3 && trimmed.hasPrefix("ey")) {
            let token = lower.hasPrefix("jwt ") ? String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
            let jwtResults = Self.decodeJWT(token)
            if !jwtResults.isEmpty {
                return jwtResults
            }
        }

        // 11. JSON Formatter: "json <compact>" or raw valid JSON string
        if lower.hasPrefix("json ") || (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            let jsonStr = lower.hasPrefix("json ") ? String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
            if let formatted = Self.formatJSON(jsonStr) {
                return [SearchResult(
                    id: "dev-json-\(Self.stableID(jsonStr))",
                    title: "Formatted JSON",
                    subtitle: formatted.replacingOccurrences(of: "\n", with: " "),
                    iconType: .systemSymbol(name: "curlybraces"),
                    category: .devTools,
                    score: 95,
                    action: .copyToClipboard(formatted)
                )]
            }
        }

        return []
    }

    // MARK: - Epoch Dates

    // Built once: the epoch rows rebuild on every keystroke while "epoch …" is typed,
    // and constructing a DateFormatter costs far more than using one (invariant 0).
    private static let localDisplayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        f.timeZone = .autoupdatingCurrent
        return f
    }()

    private static let utcDisplayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// An explicit zone ("Z", "+07:00") first, then zone-less forms read in local time.
    /// `date(from:)` must consume the whole string, so "2024-01-15 10:30" never
    /// half-matches "yyyy-MM-dd". DateFormatter rather than ISO8601DateFormatter: the
    /// latter is not Sendable, so Swift 6 rejects it as a static.
    private static let dateParsers: [DateFormatter] = [
        "yyyy-MM-dd HH:mm:ssXXXXX", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"
    ].map { format in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .autoupdatingCurrent
        f.isLenient = false
        f.dateFormat = format
        return f
    }

    /// "2024-01-15", "2024-01-15 10:30[:45]" in local time, or "2024-01-15T10:30:00Z" /
    /// "…+07:00" with a zone. A "T" separator works for every form.
    private static func parseDate(_ text: String) -> Date? {
        let normalized = text.replacingOccurrences(of: "T", with: " ")
        for parser in dateParsers {
            if let date = parser.date(from: normalized) { return date }
        }
        return nil
    }

    // MARK: - Hashing

    private enum HashAlgorithm: String {
        case sha256, md5, sha1

        var displayName: String {
            switch self {
            case .sha256: return "SHA-256"
            case .md5: return "MD5"
            case .sha1: return "SHA-1"
            }
        }

        func hexDigest(_ data: Data) -> String {
            switch self {
            case .sha256: return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            case .md5: return Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
            case .sha1: return Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
            }
        }
    }

    private static func hashResult(_ algorithm: HashAlgorithm, of text: String, score: Double) -> SearchResult {
        let digest = algorithm.hexDigest(Data(text.utf8))
        return SearchResult(
            id: "dev-hash-\(algorithm.rawValue)-\(stableID(text))",
            title: digest,
            subtitle: "\(algorithm.displayName) · '\(text)'",
            iconType: .systemSymbol(name: algorithm == .sha256 ? "number.square.fill" : "number.square"),
            category: .devTools,
            score: score,
            action: .copyToClipboard(digest)
        )
    }

    // MARK: - Color Parsing

    /// "#3498db" or "rgb(52, 152, 219)" -> three rows: HEX (with RGB and HSL shown alongside),
    /// then one row each to copy the rgb() and hsl() forms. Every id starts with
    /// "dev-color-<HEX>", which the preview pane reads to draw the swatch.
    private static func matchColor(_ text: String) -> [SearchResult] {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var r: Double = 0, g: Double = 0, b: Double = 0, a: Double = 1.0
        let hexDisplay: String

        if clean.hasPrefix("#") {
            // Match #HEX
            let hexStr = String(clean.dropFirst())
            guard hexStr.count == 3 || hexStr.count == 6 || hexStr.count == 8,
                  let hexInt = UInt64(hexStr, radix: 16) else { return [] }

            if hexStr.count == 3 {
                let r4 = (hexInt >> 8) & 0xF
                let g4 = (hexInt >> 4) & 0xF
                let b4 = hexInt & 0xF
                r = Double((r4 << 4) | r4) / 255.0
                g = Double((g4 << 4) | g4) / 255.0
                b = Double((b4 << 4) | b4) / 255.0
            } else if hexStr.count == 6 {
                r = Double((hexInt >> 16) & 0xFF) / 255.0
                g = Double((hexInt >> 8) & 0xFF) / 255.0
                b = Double(hexInt & 0xFF) / 255.0
            } else {
                r = Double((hexInt >> 24) & 0xFF) / 255.0
                g = Double((hexInt >> 16) & 0xFF) / 255.0
                b = Double((hexInt >> 8) & 0xFF) / 255.0
                a = Double(hexInt & 0xFF) / 255.0
            }
            hexDisplay = clean.uppercased()
        } else {
            // Match rgb(r, g, b)
            let lower = clean.lowercased()
            guard lower.hasPrefix("rgb(") || lower.hasPrefix("rgba(") else { return [] }
            let inner = lower.replacingOccurrences(of: "rgba(", with: "").replacingOccurrences(of: "rgb(", with: "").replacingOccurrences(of: ")", with: "")
            let parts = inner.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 3,
                  let rInt = Int(parts[0]), let gInt = Int(parts[1]), let bInt = Int(parts[2]),
                  rInt >= 0 && rInt <= 255 && gInt >= 0 && gInt <= 255 && bInt >= 0 && bInt <= 255 else { return [] }
            r = Double(rInt) / 255.0
            g = Double(gInt) / 255.0
            b = Double(bInt) / 255.0
            hexDisplay = String(format: "#%02X%02X%02X", rInt, gInt, bInt)
        }

        let rInt = Int(round(r * 255)), gInt = Int(round(g * 255)), bInt = Int(round(b * 255))
        let rgbStr = a < 1.0 ? String(format: "rgba(%d, %d, %d, %.2f)", rInt, gInt, bInt, a) : "rgb(\(rInt), \(gInt), \(bInt))"
        let hslStr = hslString(r: r, g: g, b: b, a: a)
        let swiftColor = String(format: "Color(red: %.3f, green: %.3f, blue: %.3f)", r, g, b)

        return [
            SearchResult(
                id: "dev-color-\(hexDisplay)",
                title: "\(hexDisplay) · \(rgbStr) · \(hslStr)",
                subtitle: "\(swiftColor) · Press ↵ to copy HEX",
                iconType: .systemSymbol(name: "paintpalette.fill"),
                category: .devTools,
                score: 95,
                action: .copyToClipboard(hexDisplay)
            ),
            SearchResult(
                id: "dev-color-\(hexDisplay)-rgb",
                title: rgbStr,
                subtitle: "RGB · \(hexDisplay) · Press ↵ to copy",
                iconType: .systemSymbol(name: "paintpalette"),
                category: .devTools,
                score: 90,
                action: .copyToClipboard(rgbStr)
            ),
            SearchResult(
                id: "dev-color-\(hexDisplay)-hsl",
                title: hslStr,
                subtitle: "HSL · \(hexDisplay) · Press ↵ to copy",
                iconType: .systemSymbol(name: "paintpalette"),
                category: .devTools,
                score: 85,
                action: .copyToClipboard(hslStr)
            )
        ]
    }

    /// CSS hsl()/hsla() for sRGB components in 0...1.
    private static func hslString(r: Double, g: Double, b: Double, a: Double) -> String {
        let maxC = max(r, g, b), minC = min(r, g, b)
        let delta = maxC - minC
        let l = (maxC + minC) / 2
        var h = 0.0, s = 0.0
        if delta > 0 {
            s = delta / (1 - abs(2 * l - 1))
            if maxC == r {
                h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxC == g {
                h = (b - r) / delta + 2
            } else {
                h = (r - g) / delta + 4
            }
            h *= 60
            if h < 0 { h += 360 }
        }
        let hInt = Int(round(h)) % 360, sInt = Int(round(s * 100)), lInt = Int(round(l * 100))
        return a < 1.0 ? String(format: "hsla(%d, %d%%, %d%%, %.2f)", hInt, sInt, lInt, a) : "hsl(\(hInt), \(sInt)%, \(lInt)%)"
    }

    // MARK: - JWT Decoder

    /// Payload row first (it is what people want), header row second. Both ids keep the
    /// "dev-jwt-" prefix the preview pane keys its JSON view on.
    private static func decodeJWT(_ token: String) -> [SearchResult] {
        let parts = token.components(separatedBy: ".")
        guard parts.count == 3, let payload = decodeJWTSegment(parts[1]) else { return [] }

        // Keyed on the whole token: a prefix is just the header, which every HS256 token shares.
        let tokenID = stableID(token)
        var results = [SearchResult(
            id: "dev-jwt-\(tokenID)",
            title: "Decoded JWT Payload",
            subtitle: payload.replacingOccurrences(of: "\n", with: " "),
            iconType: .systemSymbol(name: "shield.lefthalf.filled"),
            category: .devTools,
            score: 95,
            action: .copyToClipboard(payload)
        )]
        if let header = decodeJWTSegment(parts[0]) {
            results.append(SearchResult(
                id: "dev-jwt-header-\(tokenID)",
                title: "Decoded JWT Header",
                subtitle: header.replacingOccurrences(of: "\n", with: " "),
                iconType: .systemSymbol(name: "shield.lefthalf.filled"),
                category: .devTools,
                score: 90,
                action: .copyToClipboard(header)
            ))
        }
        return results
    }

    /// Base64url-decodes one JWT segment and pretty-prints it as JSON.
    private static func decodeJWTSegment(_ segment: String) -> String? {
        var base64 = segment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }

        guard let data = Data(base64Encoded: base64),
              let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
              let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return nil
        }
        return prettyString
    }

    // MARK: - JSON Formatter

    private static func formatJSON(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
              let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return nil
        }
        return prettyString
    }
}
