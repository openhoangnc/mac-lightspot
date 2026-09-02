import Foundation

// MARK: - Calculator Engine

/// A safe, crash-free recursive-descent math parser and evaluator for Lightspot.
/// Evaluates arithmetic expressions, common mathematical functions, and constants.
public final class CalculatorEngine: Sendable {

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 10
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    private init() {}

    /// Evaluates a string input as a mathematical expression.
    /// Returns a formatted result string if valid, or `nil` if the input is not a math expression or is malformed.
    public static func evaluate(_ input: String) -> String? {
        var clean = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }

        // Strip trailing '=' if present (e.g. "2+2=")
        if clean.hasSuffix("=") {
            clean.removeLast()
            clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !clean.isEmpty else { return nil }

        // Quick heuristic check: must not be just a single letter or plain word
        if clean.count == 1 {
            // Only allow standalone "π"
            if clean != "π" {
                return nil
            }
        }

        // Tokenize the input string
        guard let rawTokens = Tokenizer.tokenize(clean), !rawTokens.isEmpty else {
            return nil
        }

        // Insert implicit multiplication where appropriate (e.g., 2pi -> 2 * pi, 2(3) -> 2 * 3)
        let tokens = insertImplicitMultiplication(rawTokens)

        // If the expression is only a single literal number, do not treat as a math expression to evaluate
        if tokens.count == 1, case .number = tokens[0] {
            return nil
        }

        // Parse and evaluate using recursive descent
        let parser = Parser(tokens: tokens)
        guard var result = parser.parse() else {
            return nil
        }

        // Clean up floating point representation issues (e.g. -0.0 or near-zero trig residuals)
        if abs(result) < 1e-12 {
            result = 0.0
        }
        if result == 0.0 {
            result = 0.0
        }

        // Format result
        guard let formatted = formatter.string(from: NSNumber(value: result)) else {
            return nil
        }

        return formatted
    }

    // MARK: - Implicit Multiplication

    private static func insertImplicitMultiplication(_ tokens: [Token]) -> [Token] {
        guard !tokens.isEmpty else { return [] }
        var result: [Token] = []

        for i in 0..<tokens.count {
            let current = tokens[i]
            if i > 0 {
                let previous = tokens[i - 1]
                if shouldInsertMultiply(between: previous, and: current) {
                    result.append(.multiply)
                }
            }
            result.append(current)
        }

        return result
    }

    private static func shouldInsertMultiply(between prev: Token, and next: Token) -> Bool {
        switch (prev, next) {
        case (.number, .leftParen),
             (.number, .constant),
             (.number, .function),
             (.constant, .leftParen),
             (.constant, .constant),
             (.constant, .function),
             (.rightParen, .leftParen),
             (.rightParen, .number),
             (.rightParen, .constant),
             (.rightParen, .function):
            return true
        default:
            return false
        }
    }
}

// MARK: - Tokens

private enum Token: Equatable {
    case number(Double)
    case constant(Double)
    case function(MathFunction)
    case plus
    case minus
    case multiply
    case divide
    case power
    case modulo
    case leftParen
    case rightParen
}

private enum MathFunction: String, Equatable {
    case sqrt
    case abs
    case sin
    case cos
    case tan
    case log // Base 10
    case ln  // Natural log (base e)
}

// MARK: - Tokenizer

private enum Tokenizer {
    static func tokenize(_ input: String) -> [Token]? {
        let chars = Array(input)
        var tokens: [Token] = []
        var index = 0

        while index < chars.count {
            let ch = chars[index]

            // Skip whitespace
            if ch.isWhitespace {
                index += 1
                continue
            }

            // Operators & Parens
            if ch == "+" {
                tokens.append(.plus)
                index += 1
            } else if ch == "-" || ch == "−" {
                tokens.append(.minus)
                index += 1
            } else if ch == "*" || ch == "×" {
                if index + 1 < chars.count && chars[index + 1] == "*" {
                    tokens.append(.power)
                    index += 2
                } else {
                    tokens.append(.multiply)
                    index += 1
                }
            } else if ch == "/" || ch == "÷" {
                tokens.append(.divide)
                index += 1
            } else if ch == "^" {
                tokens.append(.power)
                index += 1
            } else if ch == "%" {
                tokens.append(.modulo)
                index += 1
            } else if ch == "(" {
                tokens.append(.leftParen)
                index += 1
            } else if ch == ")" {
                tokens.append(.rightParen)
                index += 1
            } else if ch.isNumber || (ch == "." && index + 1 < chars.count && chars[index + 1].isNumber) {
                // Numbers
                var numStr = ""
                var hasDecimal = false

                while index < chars.count {
                    let c = chars[index]
                    if c.isNumber {
                        numStr.append(c)
                        index += 1
                    } else if c == "." && !hasDecimal {
                        hasDecimal = true
                        numStr.append(c)
                        index += 1
                    } else if c == "," && !hasDecimal && index + 1 < chars.count && chars[index + 1].isNumber {
                        // Skip thousand separator comma if between digits
                        index += 1
                    } else {
                        break
                    }
                }

                guard let value = Double(numStr) else { return nil }
                tokens.append(.number(value))
            } else if ch.isLetter || ch == "π" {
                // Identifiers (functions or constants)
                var identStr = ""
                while index < chars.count && (chars[index].isLetter || chars[index] == "π") {
                    identStr.append(chars[index])
                    index += 1
                }

                let lower = identStr.lowercased()
                switch lower {
                case "pi", "π":
                    tokens.append(.constant(Double.pi))
                case "e":
                    tokens.append(.constant(Darwin.M_E))
                case "sqrt":
                    tokens.append(.function(.sqrt))
                case "abs":
                    tokens.append(.function(.abs))
                case "sin":
                    tokens.append(.function(.sin))
                case "cos":
                    tokens.append(.function(.cos))
                case "tan":
                    tokens.append(.function(.tan))
                case "log":
                    tokens.append(.function(.log))
                case "ln":
                    tokens.append(.function(.ln))
                default:
                    return nil
                }
            } else {
                // Unrecognized character
                return nil
            }
        }

        return tokens
    }
}

// MARK: - Recursive Descent Parser

private final class Parser {
    private let tokens: [Token]
    private var position: Int = 0

    init(tokens: [Token]) {
        self.tokens = tokens
    }

    private var currentToken: Token? {
        guard position < tokens.count else { return nil }
        return tokens[position]
    }

    private func consume() -> Token? {
        guard position < tokens.count else { return nil }
        let token = tokens[position]
        position += 1
        return token
    }

    private func match(_ token: Token) -> Bool {
        if currentToken == token {
            position += 1
            return true
        }
        return false
    }

    func parse() -> Double? {
        guard !tokens.isEmpty else { return nil }
        guard let result = parseExpression() else { return nil }
        guard position == tokens.count else { return nil } // Ensure entire input is consumed
        guard !result.isNaN && !result.isInfinite else { return nil }
        return result
    }

    // expression = term ( ("+" | "-") term )*
    private func parseExpression() -> Double? {
        guard var lhs = parseTerm() else { return nil }

        while let token = currentToken {
            if token == .plus {
                _ = consume()
                guard let rhs = parseTerm() else { return nil }
                lhs = lhs + rhs
            } else if token == .minus {
                _ = consume()
                guard let rhs = parseTerm() else { return nil }
                lhs = lhs - rhs
            } else {
                break
            }
        }

        return lhs
    }

    // term = unary ( ("*" | "/" | "%") unary )*
    private func parseTerm() -> Double? {
        guard var lhs = parseUnary() else { return nil }

        while let token = currentToken {
            if token == .multiply {
                _ = consume()
                guard let rhs = parseUnary() else { return nil }
                lhs = lhs * rhs
            } else if token == .divide {
                _ = consume()
                guard let rhs = parseUnary() else { return nil }
                guard rhs != 0 else { return nil }
                lhs = lhs / rhs
            } else if token == .modulo {
                _ = consume()
                guard let rhs = parseUnary() else { return nil }
                guard rhs != 0 else { return nil }
                lhs = lhs.truncatingRemainder(dividingBy: rhs)
            } else {
                break
            }
        }

        return lhs
    }

    // unary = ("+" | "-") unary | power
    private func parseUnary() -> Double? {
        if match(.plus) {
            return parseUnary()
        } else if match(.minus) {
            guard let operand = parseUnary() else { return nil }
            return -operand
        } else {
            return parsePower()
        }
    }

    // power = primary ( "^" unary )?
    private func parsePower() -> Double? {
        guard let base = parsePrimary() else { return nil }

        if match(.power) {
            guard let exponent = parseUnary() else { return nil }

            // Domain checks for power
            if base < 0 && exponent.truncatingRemainder(dividingBy: 1) != 0 {
                return nil
            }
            if base == 0 && exponent < 0 {
                return nil
            }

            let val = Darwin.pow(base, exponent)
            guard !val.isNaN && !val.isInfinite else { return nil }
            return val
        }

        return base
    }

    // primary = NUMBER | CONSTANT | FUNCTION "(" expression ")" | "(" expression ")"
    private func parsePrimary() -> Double? {
        guard let token = currentToken else { return nil }

        switch token {
        case .number(let value):
            _ = consume()
            return value

        case .constant(let value):
            _ = consume()
            return value

        case .function(let fn):
            _ = consume()
            guard match(.leftParen) else { return nil }
            guard let arg = parseExpression() else { return nil }
            guard match(.rightParen) else { return nil }
            return applyFunction(fn, arg: arg)

        case .leftParen:
            _ = consume()
            guard let inner = parseExpression() else { return nil }
            guard match(.rightParen) else { return nil }
            return inner

        default:
            return nil
        }
    }

    private func applyFunction(_ fn: MathFunction, arg: Double) -> Double? {
        switch fn {
        case .sqrt:
            guard arg >= 0 else { return nil }
            return Darwin.sqrt(arg)

        case .abs:
            return Darwin.fabs(arg)

        case .sin:
            return Darwin.sin(arg)

        case .cos:
            return Darwin.cos(arg)

        case .tan:
            let cosVal = Darwin.cos(arg)
            guard abs(cosVal) > 1e-15 else { return nil }
            let result = Darwin.tan(arg)
            guard !result.isNaN && !result.isInfinite else { return nil }
            return result

        case .log:
            guard arg > 0 else { return nil }
            return Darwin.log10(arg)

        case .ln:
            guard arg > 0 else { return nil }
            return Darwin.log(arg)
        }
    }
}
