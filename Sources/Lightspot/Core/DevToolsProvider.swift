import Foundation
import AppKit
import CryptoKit

// MARK: - Dev Tools Provider

public final class DevToolsProvider: Sendable {
    public static let shared = DevToolsProvider()

    private init() {}

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

        // 2. Base64 encode: "b64 <text>" or "base64 <text>"
        if lower.hasPrefix("b64 ") || lower.hasPrefix("base64 ") {
            let prefixLen = lower.hasPrefix("b64 ") ? 4 : 7
            let text = String(trimmed.dropFirst(prefixLen))
            if !text.isEmpty, let data = text.data(using: .utf8) {
                let encoded = data.base64EncodedString()
                return [SearchResult(
                    id: "dev-b64-\(text.hashValue)",
                    title: encoded,
                    subtitle: "Base64 Encoded · '\(text)'",
                    iconType: .systemSymbol(name: "lock.rectangle.fill"),
                    category: .devTools,
                    score: 95,
                    action: .copyToClipboard(encoded)
                )]
            }
        }

        // 3. Base64 decode: "b64d <encoded>" or "b64 decode <encoded>"
        if lower.hasPrefix("b64d ") || lower.hasPrefix("b64 decode ") {
            let prefixLen = lower.hasPrefix("b64d ") ? 5 : 11
            let text = String(trimmed.dropFirst(prefixLen)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty, let data = Data(base64Encoded: text), let decoded = String(data: data, encoding: .utf8) {
                return [SearchResult(
                    id: "dev-b64d-\(text.hashValue)",
                    title: decoded,
                    subtitle: "Base64 Decoded Text",
                    iconType: .systemSymbol(name: "lock.open.trianglebadge.exclamationmark.fill"),
                    category: .devTools,
                    score: 95,
                    action: .copyToClipboard(decoded)
                )]
            }
        }

        // 4. URL encode: "urlencode <text>"
        if lower.hasPrefix("urlencode ") {
            let text = String(trimmed.dropFirst("urlencode ".count))
            if let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                return [SearchResult(
                    id: "dev-urlencode-\(text.hashValue)",
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
                    id: "dev-urldecode-\(text.hashValue)",
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

        // 7. Unix Epoch converter: "epoch <timestamp>"
        if lower.hasPrefix("epoch ") {
            let tsStr = String(trimmed.dropFirst("epoch ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if let ts = Double(tsStr) {
                let date = ts > 1e11 ? Date(timeIntervalSince1970: ts / 1000.0) : Date(timeIntervalSince1970: ts)
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .medium
                formatter.timeZone = TimeZone.current
                let localStr = formatter.string(from: date)

                formatter.timeZone = TimeZone(identifier: "UTC")
                let utcStr = formatter.string(from: date)

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
        }

        // 8. Hash generator: "hash <text>"
        if lower.hasPrefix("hash ") {
            let text = String(trimmed.dropFirst("hash ".count))
            if !text.isEmpty, let data = text.data(using: .utf8) {
                let sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                let md5 = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
                let sha1 = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()

                return [
                    SearchResult(
                        id: "dev-hash-sha256-\(text.hashValue)",
                        title: sha256,
                        subtitle: "SHA-256 · '\(text)'",
                        iconType: .systemSymbol(name: "number.square.fill"),
                        category: .devTools,
                        score: 95,
                        action: .copyToClipboard(sha256)
                    ),
                    SearchResult(
                        id: "dev-hash-md5-\(text.hashValue)",
                        title: md5,
                        subtitle: "MD5 · '\(text)'",
                        iconType: .systemSymbol(name: "number.square"),
                        category: .devTools,
                        score: 90,
                        action: .copyToClipboard(md5)
                    ),
                    SearchResult(
                        id: "dev-hash-sha1-\(text.hashValue)",
                        title: sha1,
                        subtitle: "SHA-1 · '\(text)'",
                        iconType: .systemSymbol(name: "number.square"),
                        category: .devTools,
                        score: 85,
                        action: .copyToClipboard(sha1)
                    )
                ]
            }
        }

        // 9. Hex / RGB Color inspector
        if let colorResult = Self.matchColor(trimmed) {
            return [colorResult]
        }

        // 10. JWT Decoder: "jwt <token>" or raw token (3 parts dot-separated)
        if lower.hasPrefix("jwt ") || (trimmed.components(separatedBy: ".").count == 3 && trimmed.hasPrefix("ey")) {
            let token = lower.hasPrefix("jwt ") ? String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
            if let jwtResult = Self.decodeJWT(token) {
                return [jwtResult]
            }
        }

        // 11. JSON Formatter: "json <compact>" or raw valid JSON string
        if lower.hasPrefix("json ") || (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            let jsonStr = lower.hasPrefix("json ") ? String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
            if let formatted = Self.formatJSON(jsonStr) {
                return [SearchResult(
                    id: "dev-json-\(jsonStr.hashValue)",
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

    // MARK: - Color Parsing

    private static func matchColor(_ text: String) -> SearchResult? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Match #HEX
        if clean.hasPrefix("#") {
            let hexStr = String(clean.dropFirst())
            if hexStr.count == 3 || hexStr.count == 6 || hexStr.count == 8 {
                guard let hexInt = UInt64(hexStr, radix: 16) else { return nil }
                var r: Double = 0, g: Double = 0, b: Double = 0, a: Double = 1.0

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
                } else if hexStr.count == 8 {
                    r = Double((hexInt >> 24) & 0xFF) / 255.0
                    g = Double((hexInt >> 16) & 0xFF) / 255.0
                    b = Double((hexInt >> 8) & 0xFF) / 255.0
                    a = Double(hexInt & 0xFF) / 255.0
                }

                let hexDisplay = clean.uppercased()
                let rInt = Int(round(r * 255)), gInt = Int(round(g * 255)), bInt = Int(round(b * 255))
                let rgbStr = a < 1.0 ? String(format: "rgba(%d, %d, %d, %.2f)", rInt, gInt, bInt, a) : "rgb(\(rInt), \(gInt), \(bInt))"
                let swiftColor = String(format: "Color(red: %.3f, green: %.3f, blue: %.3f)", r, g, b)

                return SearchResult(
                    id: "dev-color-\(hexDisplay)",
                    title: "\(hexDisplay) · \(rgbStr)",
                    subtitle: "\(swiftColor) · Press ↵ to copy HEX",
                    iconType: .systemSymbol(name: "paintpalette.fill"),
                    category: .devTools,
                    score: 95,
                    action: .copyToClipboard(hexDisplay)
                )
            }
        }

        // Match rgb(r, g, b)
        let lower = clean.lowercased()
        if lower.hasPrefix("rgb(") || lower.hasPrefix("rgba(") {
            let inner = lower.replacingOccurrences(of: "rgba(", with: "").replacingOccurrences(of: "rgb(", with: "").replacingOccurrences(of: ")", with: "")
            let parts = inner.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 3,
               let rInt = Int(parts[0]), let gInt = Int(parts[1]), let bInt = Int(parts[2]),
               rInt >= 0 && rInt <= 255 && gInt >= 0 && gInt <= 255 && bInt >= 0 && bInt <= 255 {
                let hexStr = String(format: "#%02X%02X%02X", rInt, gInt, bInt)
                let r = Double(rInt) / 255.0, g = Double(gInt) / 255.0, b = Double(bInt) / 255.0
                let swiftColor = String(format: "Color(red: %.3f, green: %.3f, blue: %.3f)", r, g, b)

                return SearchResult(
                    id: "dev-color-\(hexStr)",
                    title: "\(hexStr) · rgb(\(rInt), \(gInt), \(bInt))",
                    subtitle: "\(swiftColor) · Press ↵ to copy HEX",
                    iconType: .systemSymbol(name: "paintpalette.fill"),
                    category: .devTools,
                    score: 95,
                    action: .copyToClipboard(hexStr)
                )
            }
        }

        return nil
    }

    // MARK: - JWT Decoder

    private static func decodeJWT(_ token: String) -> SearchResult? {
        let parts = token.components(separatedBy: ".")
        guard parts.count == 3 else { return nil }

        // Decode payload (part 1)
        var base64 = parts[1]
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

        return SearchResult(
            id: "dev-jwt-\(token.prefix(16).hashValue)",
            title: "Decoded JWT Payload",
            subtitle: prettyString.replacingOccurrences(of: "\n", with: " "),
            iconType: .systemSymbol(name: "shield.lefthalf.filled"),
            category: .devTools,
            score: 95,
            action: .copyToClipboard(prettyString)
        )
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
