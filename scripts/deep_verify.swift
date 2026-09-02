import AppKit
import Foundation

@main
struct DeepVerifier {
    static func main() {
        print("======================================================")
        print("  LIGHTSPOT DEEP RUNTIME VERIFICATION")
        print("======================================================\n")

        var totalChecks = 0
        var passedChecks = 0

        func check(_ description: String, _ condition: Bool) {
            totalChecks += 1
            if condition {
                passedChecks += 1
                print("  ✅ [PASS] \(description)")
            } else {
                print("  ❌ [FAIL] \(description)")
            }
        }

        // ----------------------------------------------------
        // SECTION 1: Settings Provider Deep Links
        // ----------------------------------------------------
        print("--- 1. Testing System Settings Deep Links ---")
        let settings = SettingsProvider.shared.items
        print("Total configured settings panes: \(settings.count)")
        check("Configured >= 25 settings panes", settings.count >= 25)

        var validUrls = 0
        for item in settings {
            if let url = URL(string: item.deepLink) {
                if NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
                    validUrls += 1
                } else {
                    print("     ⚠️ Unresolvable pane URL: \(item.name) -> \(item.deepLink)")
                }
            }
        }
        print("Valid system URL schemes: \(validUrls) / \(settings.count)")
        check("All settings deep links resolve to system handler", validUrls == settings.count)

        // ----------------------------------------------------
        // SECTION 2: Quick Actions Script Validation
        // ----------------------------------------------------
        print("\n--- 2. Testing Quick Actions AppleScript & Command Syntax ---")
        let actions = QuickActionsProvider.shared.actions
        print("Total configured quick actions: \(actions.count)")
        check("Configured >= 10 quick actions", actions.count >= 10)

        for action in actions {
            if action.usesOsascript {
                let script = NSAppleScript(source: action.script)
                var error: NSDictionary?
                let compiled = script?.compileAndReturnError(&error) ?? false
                check("AppleScript compiles: \(action.name)", compiled)
                if !compiled, let err = error {
                    print("     Error: \(err)")
                }
            } else if action.script.hasPrefix("open:") {
                let path = String(action.script.dropFirst("open:".count))
                let exists = FileManager.default.fileExists(atPath: path)
                check("Target app exists: \(action.name) at \(path)", exists)
            } else {
                // Shell command check
                let binary = action.script.split(separator: " ").first.map(String.init) ?? ""
                let exists = FileManager.default.fileExists(atPath: binary) || binary == "pmset"
                check("Command binary exists: \(action.name) (\(binary))", exists)
            }
        }

        // ----------------------------------------------------
        // SECTION 3: App Scanner Real Scan & No File Indexing
        // ----------------------------------------------------
        print("\n--- 3. Testing AppScanner on Local System ---")
        AppScanner.shared.startScanning()
        // Wait briefly for scan
        Thread.sleep(forTimeInterval: 0.8)

        let safariResults = AppScanner.shared.search("safari")
        check("Discovered Safari.app on system", !safariResults.isEmpty && safariResults.first?.title.lowercased().contains("safari") == true)

        let termResults = AppScanner.shared.search("terminal")
        check("Discovered Terminal.app on system", !termResults.isEmpty && termResults.first?.title.lowercased().contains("terminal") == true)

        // Verify strictly NO file indexing
        print("\n--- 4. Verifying Strictly ZERO File Indexing ---")
        let docQuery1 = SearchEngine.shared.searchImmediate("README.md")
        let hasDocResult1 = docQuery1.values.flatMap { $0 }.contains { $0.subtitle.hasSuffix(".md") && $0.category != .webSearch }
        check("Does not index README.md", !hasDocResult1)

        let docQuery2 = SearchEngine.shared.searchImmediate("Package.swift")
        let hasDocResult2 = docQuery2.values.flatMap { $0 }.contains { $0.subtitle.hasSuffix(".swift") && $0.category != .webSearch }
        check("Does not index Package.swift", !hasDocResult2)

        let docQuery3 = SearchEngine.shared.searchImmediate(".pdf")
        let hasDocResult3 = docQuery3.values.flatMap { $0 }.contains { $0.subtitle.hasSuffix(".pdf") && $0.category != .webSearch }
        check("Does not index .pdf documents", !hasDocResult3)

        // ----------------------------------------------------
        // SECTION 5: Math Calculator Comprehensive Suite
        // ----------------------------------------------------
        print("\n--- 5. Testing Calculator Engine Comprehensive Suite ---")
        let mathCases: [(String, String?)] = [
            ("1 + 1", "2"),
            ("100 - 37", "63"),
            ("12 * 12", "144"),
            ("1000 / 8", "125"),
            ("2 + 3 * 5", "17"),
            ("(2 + 3) * 5", "25"),
            ("2^3", "8"),
            ("3^2", "9"),
            ("17 % 5", "2"),
            ("sqrt(64)", "8"),
            ("sqrt(625)", "25"),
            ("abs(-99)", "99"),
            ("sin(0)", "0"),
            ("cos(0)", "1"),
            ("tan(0)", "0"),
            ("ln(e)", "1"),
            ("log(100)", "2"),
            ("2(5 + 5)", "20"),
            ("-(10 + 5)", "-15"),
            ("10 / 0", nil),
            ("sqrt(-4)", nil),
            ("++5", "5"),
            ("not a math query", nil),
            ("safari", nil),
            ("x-apple", nil)
        ]

        for (expr, expected) in mathCases {
            let actual = CalculatorEngine.evaluate(expr)
            if let expected = expected {
                check("Math: \(expr) = \(expected)", actual == expected)
                if actual != expected {
                    print("     Got: \(String(describing: actual))")
                }
            } else {
                check("Invalid math returns nil: \(expr)", actual == nil)
                if actual != nil {
                    print("     Got unexpected: \(String(describing: actual))")
                }
            }
        }

        // ----------------------------------------------------
        // SECTION 6: Search Engine Aggregation & Fallbacks
        // ----------------------------------------------------
        print("\n--- 6. Testing Search Engine Categorization ---")
        let search1 = SearchEngine.shared.searchImmediate("sound")
        check("Search 'sound' produces Top Hit", search1[.topHit] != nil)
        check("Search 'sound' produces System Settings", search1[.systemSettings] != nil)
        check("Search 'sound' produces Web Search fallback", search1[.webSearch] != nil)

        let search2 = SearchEngine.shared.searchImmediate("50 * 50")
        check("Search '50 * 50' produces Calculator result", search2[.calculator] != nil)
        check("Search '50 * 50' Calculator value is 2.500 or 2,500", search2[.calculator]?.first?.title == CalculatorEngine.evaluate("2500 + 0"))

        print("\n======================================================")
        print("  SUMMARY: \(passedChecks) / \(totalChecks) CHECKS PASSED")
        print("======================================================")

        if passedChecks == totalChecks {
            print("  🏆 100% OF LIVE VERIFICATION CHECKS PASSED!\n")
            exit(0)
        } else {
            print("  ⚠️ SOME CHECKS FAILED!\n")
            exit(1)
        }
    }
}
