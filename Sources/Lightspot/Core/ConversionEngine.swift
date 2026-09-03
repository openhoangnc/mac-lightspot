import Foundation

// MARK: - Conversion Result

public struct ConversionResult: Sendable, Equatable {
    public let value: String
    public let subtitle: String

    public init(value: String, subtitle: String) {
        self.value = value
        self.subtitle = subtitle
    }
}

// MARK: - Conversion Engine

public enum ConversionEngine: Sendable {

    private static let decimalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 4
        f.minimumFractionDigits = 0
        f.usesGroupingSeparator = false
        return f
    }()

    private static let integerFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        return f
    }()

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        f.usesGroupingSeparator = true
        return f
    }()

    // MARK: - Baseline Currency Rates (USD = 1.0)

    private static let baseCurrencyRates: [String: Double] = [
        "USD": 1.0,
        "EUR": 0.92,
        "GBP": 0.79,
        "JPY": 154.5,
        "CAD": 1.38,
        "AUD": 1.52,
        "CHF": 0.90,
        "CNY": 7.24,
        "INR": 83.5,
        "SGD": 1.35,
        "HKD": 7.81,
        "KRW": 1375.0,
        "VND": 25450.0,
        "SEK": 10.85,
        "NOK": 10.95,
        "NZD": 1.66,
        "MXN": 16.95,
        "BRL": 5.15,
        "TWD": 32.4,
        "THB": 36.8,
        "IDR": 16200.0,
        "PLN": 3.98,
        "TRY": 32.2,
        "ZAR": 18.5,
        "PHP": 57.5,
        "CZK": 23.3,
        "DKK": 6.87,
        "HUF": 362.0,
        "ILS": 3.72,
        "MYR": 4.72
    ]

    private static let currencySymbols: [String: String] = [
        "$": "USD",
        "€": "EUR",
        "£": "GBP",
        "¥": "JPY",
        "₫": "VND",
        "₩": "KRW",
        "₹": "INR",
        "R$": "BRL",
        "CHF": "CHF"
    ]

    // MARK: - Main Entry Point

    public static func convert(_ input: String) -> ConversionResult? {
        let clean = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return nil }

        // 1. Number bases (e.g. 0xFF, 0b1010, 255 in hex)
        if let baseResult = convertNumberBase(clean) {
            return baseResult
        }

        // 2. Currency (e.g. $100, 100 USD, 50 EUR in JPY)
        if let currencyResult = convertCurrency(clean) {
            return currencyResult
        }

        // 3. Relaxed Unit Conversion (Temperature, Length, Weight, Digital, Speed, Time)
        if let unitResult = convertUnits(clean) {
            return unitResult
        }

        return nil
    }

    // MARK: - Number Base Conversions

    private static func convertNumberBase(_ input: String) -> ConversionResult? {
        let lower = input.lowercased()

        // Explicit hex literal: 0x...
        if lower.hasPrefix("0x") {
            let hexStr = String(lower.dropFirst(2))
            guard let val = UInt64(hexStr, radix: 16) else { return nil }
            let bin = String(val, radix: 2)
            let oct = String(val, radix: 8)
            let dec = String(val)
            return ConversionResult(
                value: dec,
                subtitle: "\(input) = \(dec) (dec) · 0b\(bin) · oct: \(oct)"
            )
        }

        // Explicit binary literal: 0b...
        if lower.hasPrefix("0b") {
            let binStr = String(lower.dropFirst(2))
            guard let val = UInt64(binStr, radix: 2) else { return nil }
            let hex = String(val, radix: 16).uppercased()
            let oct = String(val, radix: 8)
            let dec = String(val)
            return ConversionResult(
                value: dec,
                subtitle: "\(input) = \(dec) (dec) · 0x\(hex) · oct: \(oct)"
            )
        }

        // Pattern: <number> (in|to) (hex|bin|binary|oct|dec|decimal)
        let parts = lower.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if parts.count >= 3 && (parts[1] == "in" || parts[1] == "to") {
            let numStr = parts[0]
            let targetBase = parts[2]

            var parsedVal: UInt64?
            if numStr.hasPrefix("0x") {
                parsedVal = UInt64(numStr.dropFirst(2), radix: 16)
            } else if numStr.hasPrefix("0b") {
                parsedVal = UInt64(numStr.dropFirst(2), radix: 2)
            } else {
                parsedVal = UInt64(numStr)
            }

            guard let val = parsedVal else { return nil }

            switch targetBase {
            case "hex":
                let hex = "0x" + String(val, radix: 16).uppercased()
                return ConversionResult(value: hex, subtitle: "\(numStr) in hex = \(hex)")
            case "bin", "binary":
                let bin = "0b" + String(val, radix: 2)
                return ConversionResult(value: bin, subtitle: "\(numStr) in binary = \(bin)")
            case "oct", "octal":
                let oct = "0o" + String(val, radix: 8)
                return ConversionResult(value: oct, subtitle: "\(numStr) in octal = \(oct)")
            case "dec", "decimal":
                let dec = String(val)
                return ConversionResult(value: dec, subtitle: "\(numStr) in decimal = \(dec)")
            default:
                break
            }
        }

        return nil
    }

    // MARK: - Currency Conversions

    private static func convertCurrency(_ input: String) -> ConversionResult? {
        let clean = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var sourceCurrency: String?
        var amount: Double?
        var targetCurrency: String?

        // Check for target override e.g. "100 USD in EUR" or "50 EUR to JPY" or "$100 in GBP"
        let lower = clean.lowercased()
        let inToTokens = [" in ", " to "]
        var queryPart = clean

        for sep in inToTokens {
            if let range = lower.range(of: sep) {
                let targetCandidate = String(lower[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if baseCurrencyRates[targetCandidate] != nil {
                    targetCurrency = targetCandidate
                    queryPart = String(clean[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
        }

        // Check for leading symbol: e.g. "$100", "€ 50"
        for (symbol, code) in currencySymbols {
            if queryPart.hasPrefix(symbol) {
                let numStr = queryPart.dropFirst(symbol.count).trimmingCharacters(in: .whitespacesAndNewlines)
                if let val = Double(numStr.replacingOccurrences(of: ",", with: "")) {
                    sourceCurrency = code
                    amount = val
                    break
                }
            }
        }

        // Check for trailing symbol: e.g. "100$", "50€"
        if amount == nil {
            for (symbol, code) in currencySymbols {
                if queryPart.hasSuffix(symbol) {
                    let numStr = queryPart.dropLast(symbol.count).trimmingCharacters(in: .whitespacesAndNewlines)
                    if let val = Double(numStr.replacingOccurrences(of: ",", with: "")) {
                        sourceCurrency = code
                        amount = val
                        break
                    }
                }
            }
        }

        // Check for format: "<number> <CODE>" e.g. "100 USD", "50 eur"
        if amount == nil {
            let tokens = queryPart.split(separator: " ").map(String.init)
            if tokens.count == 2 {
                if let val = Double(tokens[0].replacingOccurrences(of: ",", with: "")),
                   let code = baseCurrencyRates.keys.first(where: { $0.caseInsensitiveCompare(tokens[1]) == .orderedSame }) {
                    amount = val
                    sourceCurrency = code
                }
            }
        }

        guard let src = sourceCurrency, let amt = amount, let srcRate = baseCurrencyRates[src] else {
            return nil
        }

        // Determine destination currency
        let dest: String
        if let explicitTarget = targetCurrency {
            dest = explicitTarget
        } else {
            // Default to local currency, or EUR if local is USD, or USD if local is unknown
            let localCode = Locale.current.currency?.identifier ?? "USD"
            if localCode != src && baseCurrencyRates[localCode] != nil {
                dest = localCode
            } else if src == "USD" {
                dest = "EUR"
            } else {
                dest = "USD"
            }
        }

        guard let destRate = baseCurrencyRates[dest] else { return nil }

        // Conversion: base rate is amount * (destRate / srcRate)
        let converted = amt * (destRate / srcRate)
        let formattedAmt = formatCurrency(amt)
        let formattedDest = formatCurrency(converted)

        let valueString = "\(formattedDest) \(dest)"
        let subtitleString = "\(formattedAmt) \(src) = \(formattedDest) \(dest)"

        return ConversionResult(value: valueString, subtitle: subtitleString)
    }

    private static func formatCurrency(_ val: Double) -> String {
        if val >= 1000 && val == floor(val) {
            return decimalFormatter.string(from: NSNumber(value: Int(val))) ?? String(format: "%.0f", val)
        }
        return currencyFormatter.string(from: NSNumber(value: val)) ?? String(format: "%.2f", val)
    }

    // MARK: - Unit Conversions

    private static func convertUnits(_ input: String) -> ConversionResult? {
        let clean = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = clean.lowercased()

        // Optional target override e.g. "10km in miles" or "100c to f"
        var sourceExpression = lower
        var explicitTargetUnit: String? = nil

        let inToTokens = [" in ", " to "]
        for sep in inToTokens {
            if let range = lower.range(of: sep) {
                explicitTargetUnit = String(lower[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                sourceExpression = String(lower[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        // Parse number + unit from sourceExpression
        // e.g. "72f", "72°f", "10 km", "150lbs", "16gb"
        guard let parsed = parseQuantity(sourceExpression) else {
            return nil
        }

        let num = parsed.amount
        let unit = parsed.unit

        // 1. Temperature
        if let temp = convertTemperature(amount: num, unit: unit, target: explicitTargetUnit) {
            return temp
        }

        // 2. Length / Distance
        if let len = convertLength(amount: num, unit: unit, target: explicitTargetUnit) {
            return len
        }

        // 3. Weight / Mass
        if let weight = convertWeight(amount: num, unit: unit, target: explicitTargetUnit) {
            return weight
        }

        // 4. Digital Storage
        if let digital = convertDigital(amount: num, unit: unit, target: explicitTargetUnit) {
            return digital
        }

        // 5. Speed
        if let speed = convertSpeed(amount: num, unit: unit, target: explicitTargetUnit) {
            return speed
        }

        // 6. Time Duration
        if let time = convertTime(amount: num, unit: unit, target: explicitTargetUnit) {
            return time
        }

        return nil
    }

    private static func parseQuantity(_ text: String) -> (amount: Double, unit: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        // Find the boundary between number and unit
        var numPart = ""
        var unitPart = ""
        var foundUnit = false

        for char in trimmed {
            if !foundUnit && (char.isNumber || char == "." || (char == "-" && numPart.isEmpty)) {
                numPart.append(char)
            } else {
                foundUnit = true
                unitPart.append(char)
            }
        }

        unitPart = unitPart.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let amt = Double(numPart), !unitPart.isEmpty else { return nil }
        return (amt, unitPart)
    }

    // MARK: - Temperature

    private static func convertTemperature(amount: Double, unit: String, target: String?) -> ConversionResult? {
        let u = unit.replacingOccurrences(of: "°", with: "").lowercased()
        let t = target?.replacingOccurrences(of: "°", with: "").lowercased()

        if u == "f" || u == "fahrenheit" {
            let c = (amount - 32.0) * 5.0 / 9.0
            let k = c + 273.15
            if t == "k" || t == "kelvin" {
                let kStr = formatDecimal(k)
                return ConversionResult(value: "\(kStr) K", subtitle: "\(formatDecimal(amount))°F = \(kStr) K")
            }
            let cStr = formatDecimal(c)
            let kStr = formatDecimal(k)
            return ConversionResult(value: "\(cStr)°C", subtitle: "\(formatDecimal(amount))°F = \(cStr)°C · \(kStr) K")
        } else if u == "c" || u == "celsius" {
            let f = amount * 9.0 / 5.0 + 32.0
            let k = amount + 273.15
            if t == "k" || t == "kelvin" {
                let kStr = formatDecimal(k)
                return ConversionResult(value: "\(kStr) K", subtitle: "\(formatDecimal(amount))°C = \(kStr) K")
            }
            let fStr = formatDecimal(f)
            let kStr = formatDecimal(k)
            return ConversionResult(value: "\(fStr)°F", subtitle: "\(formatDecimal(amount))°C = \(fStr)°F · \(kStr) K")
        } else if u == "k" || u == "kelvin" {
            let c = amount - 273.15
            let f = c * 9.0 / 5.0 + 32.0
            if t == "f" || t == "fahrenheit" {
                let fStr = formatDecimal(f)
                return ConversionResult(value: "\(fStr)°F", subtitle: "\(formatDecimal(amount)) K = \(fStr)°F")
            }
            let cStr = formatDecimal(c)
            let fStr = formatDecimal(f)
            return ConversionResult(value: "\(cStr)°C", subtitle: "\(formatDecimal(amount)) K = \(cStr)°C · \(fStr)°F")
        }

        return nil
    }

    // MARK: - Length

    private static func convertLength(amount: Double, unit: String, target: String?) -> ConversionResult? {
        // Base: meters
        let toMeters: [String: Double] = [
            "km": 1000.0, "kilometer": 1000.0, "kilometers": 1000.0,
            "m": 1.0, "meter": 1.0, "meters": 1.0,
            "cm": 0.01, "centimeter": 0.01, "centimeters": 0.01,
            "mm": 0.001, "millimeter": 0.001, "millimeters": 0.001,
            "mi": 1609.344, "mile": 1609.344, "miles": 1609.344,
            "yd": 0.9144, "yard": 0.9144, "yards": 0.9144,
            "ft": 0.3048, "foot": 0.3048, "feet": 0.3048,
            "in": 0.0254, "inch": 0.0254, "inches": 0.0254
        ]

        guard let factor = toMeters[unit.lowercased()] else { return nil }
        let meters = amount * factor

        let defaultTarget: String
        let u = unit.lowercased()
        if u.hasPrefix("km") { defaultTarget = "mi" }
        else if u == "m" || u.hasPrefix("meter") { defaultTarget = "ft" }
        else if u == "cm" || u == "mm" || u.hasPrefix("cent") || u.hasPrefix("milli") { defaultTarget = "in" }
        else if u == "mi" || u.hasPrefix("mile") { defaultTarget = "km" }
        else if u == "ft" || u.hasPrefix("foot") || u.hasPrefix("feet") { defaultTarget = "cm" }
        else if u == "in" || u.hasPrefix("inch") { defaultTarget = "cm" }
        else if u == "yd" || u.hasPrefix("yard") { defaultTarget = "m" }
        else { defaultTarget = "m" }

        let targetUnit = target ?? defaultTarget
        guard let targetFactor = toMeters[targetUnit.lowercased()] else { return nil }

        let converted = meters / targetFactor
        let valStr = "\(formatDecimal(converted)) \(targetUnit)"
        let subStr = "\(formatDecimal(amount)) \(unit) = \(valStr)"
        return ConversionResult(value: valStr, subtitle: subStr)
    }

    // MARK: - Weight

    private static func convertWeight(amount: Double, unit: String, target: String?) -> ConversionResult? {
        // Base: kilograms
        let toKg: [String: Double] = [
            "kg": 1.0, "kgs": 1.0, "kilogram": 1.0, "kilograms": 1.0,
            "g": 0.001, "gram": 0.001, "grams": 0.001,
            "mg": 0.000001, "milligram": 0.000001, "milligrams": 0.000001,
            "lb": 0.45359237, "lbs": 0.45359237, "pound": 0.45359237, "pounds": 0.45359237,
            "oz": 0.028349523, "ounce": 0.028349523, "ounces": 0.028349523,
            "st": 6.35029, "stone": 6.35029
        ]

        guard let factor = toKg[unit.lowercased()] else { return nil }
        let kg = amount * factor

        let defaultTarget: String
        let u = unit.lowercased()
        if u.hasPrefix("kg") { defaultTarget = "lbs" }
        else if u == "g" || u.hasPrefix("gram") { defaultTarget = "oz" }
        else if u == "mg" { defaultTarget = "g" }
        else if u.hasPrefix("lb") { defaultTarget = "kg" }
        else if u.hasPrefix("oz") { defaultTarget = "g" }
        else { defaultTarget = "kg" }

        let targetUnit = target ?? defaultTarget
        guard let targetFactor = toKg[targetUnit.lowercased()] else { return nil }

        let converted = kg / targetFactor
        let valStr = "\(formatDecimal(converted)) \(targetUnit)"
        let subStr = "\(formatDecimal(amount)) \(unit) = \(valStr)"
        return ConversionResult(value: valStr, subtitle: subStr)
    }

    // MARK: - Digital Storage

    private static func convertDigital(amount: Double, unit: String, target: String?) -> ConversionResult? {
        // Base: Megabytes (MB)
        let toMB: [String: Double] = [
            "tb": 1048576.0, "terabyte": 1048576.0, "terabytes": 1048576.0,
            "gb": 1024.0, "gigabyte": 1024.0, "gigabytes": 1024.0,
            "mb": 1.0, "megabyte": 1.0, "megabytes": 1.0,
            "kb": 1.0 / 1024.0, "kilobyte": 1.0 / 1024.0, "kilobytes": 1.0 / 1024.0,
            "b": 1.0 / (1024.0 * 1024.0), "bytes": 1.0 / (1024.0 * 1024.0), "byte": 1.0 / (1024.0 * 1024.0)
        ]

        guard let factor = toMB[unit.lowercased()] else { return nil }
        let mb = amount * factor

        let defaultTarget: String
        let u = unit.lowercased()
        if u.hasPrefix("tb") { defaultTarget = "gb" }
        else if u.hasPrefix("gb") { defaultTarget = "mb" }
        else if u.hasPrefix("mb") { defaultTarget = "gb" }
        else if u.hasPrefix("kb") { defaultTarget = "mb" }
        else { defaultTarget = "kb" }

        let targetUnit = target ?? defaultTarget
        guard let targetFactor = toMB[targetUnit.lowercased()] else { return nil }

        let converted = mb / targetFactor
        let valStr = "\(formatDecimal(converted)) \(targetUnit.uppercased())"
        let subStr = "\(formatDecimal(amount)) \(unit.uppercased()) = \(valStr)"
        return ConversionResult(value: valStr, subtitle: subStr)
    }

    // MARK: - Speed

    private static func convertSpeed(amount: Double, unit: String, target: String?) -> ConversionResult? {
        // Base: km/h
        let toKmh: [String: Double] = [
            "kmh": 1.0, "kph": 1.0, "km/h": 1.0,
            "mph": 1.609344, "mi/h": 1.609344,
            "m/s": 3.6, "mps": 3.6,
            "knot": 1.852, "knots": 1.852
        ]

        guard let factor = toKmh[unit.lowercased()] else { return nil }
        let kmh = amount * factor

        let defaultTarget: String
        let u = unit.lowercased()
        if u.contains("mph") { defaultTarget = "km/h" }
        else if u.contains("km") || u.contains("kph") { defaultTarget = "mph" }
        else if u.contains("m/s") || u.contains("mps") { defaultTarget = "km/h" }
        else { defaultTarget = "km/h" }

        let targetUnit = target ?? defaultTarget
        guard let targetFactor = toKmh[targetUnit.lowercased()] else { return nil }

        let converted = kmh / targetFactor
        let valStr = "\(formatDecimal(converted)) \(targetUnit)"
        let subStr = "\(formatDecimal(amount)) \(unit) = \(valStr)"
        return ConversionResult(value: valStr, subtitle: subStr)
    }

    // MARK: - Time Duration

    private static func convertTime(amount: Double, unit: String, target: String?) -> ConversionResult? {
        // Base: seconds
        let toSeconds: [String: Double] = [
            "s": 1.0, "sec": 1.0, "secs": 1.0, "second": 1.0, "seconds": 1.0,
            "min": 60.0, "mins": 60.0, "minute": 60.0, "minutes": 60.0,
            "h": 3600.0, "hr": 3600.0, "hrs": 3600.0, "hour": 3600.0, "hours": 3600.0,
            "d": 86400.0, "day": 86400.0, "days": 86400.0,
            "w": 604800.0, "wk": 604800.0, "week": 604800.0, "weeks": 604800.0
        ]

        guard let factor = toSeconds[unit.lowercased()] else { return nil }
        let seconds = amount * factor

        let defaultTarget: String
        let u = unit.lowercased()
        if u.hasPrefix("s") { defaultTarget = "min" }
        else if u.hasPrefix("min") { defaultTarget = "hours" }
        else if u.hasPrefix("h") { defaultTarget = "minutes" }
        else if u.hasPrefix("d") { defaultTarget = "hours" }
        else { defaultTarget = "days" }

        let targetUnit = target ?? defaultTarget
        guard let targetFactor = toSeconds[targetUnit.lowercased()] else { return nil }

        let converted = seconds / targetFactor
        let valStr = "\(formatDecimal(converted)) \(targetUnit)"
        let subStr = "\(formatDecimal(amount)) \(unit) = \(valStr)"
        return ConversionResult(value: valStr, subtitle: subStr)
    }

    private static func formatDecimal(_ val: Double) -> String {
        if val == floor(val) && abs(val) < 1e12 {
            return integerFormatter.string(from: NSNumber(value: Int64(val))) ?? String(format: "%.0f", val)
        }
        return decimalFormatter.string(from: NSNumber(value: val)) ?? String(format: "%.2f", val)
    }
}
