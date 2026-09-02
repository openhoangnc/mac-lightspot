import Foundation

// MARK: - Test Runner for Lightspot Core Logic

@main
struct TestRunner {
    static func assertEqual<T: Equatable>(_ actual: T?, _ expected: T?, _ message: String = "", file: String = #file, line: Int = #line) {
        if actual != expected {
            print("❌ FAIL [\(line)]: expected \(String(describing: expected)), got \(String(describing: actual)). \(message)")
            exit(1)
        }
    }

    static func assertTrue(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) {
        if !condition {
            print("❌ FAIL [\(line)]: condition was false. \(message)")
            exit(1)
        }
    }

    static func main() {
        print("🧪 Running Lightspot Core Tests...\n")

        // Test 1: Calculator Arithmetic
        print("Testing CalculatorEngine...")
        assertEqual(CalculatorEngine.evaluate("2+2"), "4", "2+2")
        assertEqual(CalculatorEngine.evaluate("10 - 3"), "7", "10 - 3")
        assertEqual(CalculatorEngine.evaluate("4 * 5"), "20", "4 * 5")
        assertEqual(CalculatorEngine.evaluate("100 / 4"), "25", "100 / 4")
        assertEqual(CalculatorEngine.evaluate("2 + 3 * 4"), "14", "Order of operations")
        assertEqual(CalculatorEngine.evaluate("(2 + 3) * 4"), "20", "Parentheses")
        assertEqual(CalculatorEngine.evaluate("2^8"), "256", "Power")
        assertEqual(CalculatorEngine.evaluate("2^10"), CalculatorEngine.evaluate("1024 + 0"), "Power 2^10")
        assertEqual(CalculatorEngine.evaluate("10 % 3"), "1", "Modulo")

        // Test 2: Calculator Functions & Constants
        assertEqual(CalculatorEngine.evaluate("sqrt(144)"), "12", "sqrt(144)")
        assertEqual(CalculatorEngine.evaluate("sqrt(256)"), "16", "sqrt(256)")
        assertEqual(CalculatorEngine.evaluate("abs(-42)"), "42", "abs(-42)")
        assertEqual(CalculatorEngine.evaluate("sin(0)"), "0", "sin(0)")
        assertEqual(CalculatorEngine.evaluate("cos(0)"), "1", "cos(0)")
        assertEqual(CalculatorEngine.evaluate("2pi"), CalculatorEngine.evaluate("2 * pi"), "Implicit multiplication 2pi")

        // Test 3: Calculator Error & Malformed Input Handling
        assertEqual(CalculatorEngine.evaluate("2 / 0"), nil, "Division by zero returns nil")
        assertEqual(CalculatorEngine.evaluate("sqrt(-1)"), nil, "sqrt of negative returns nil")
        assertEqual(CalculatorEngine.evaluate("12 + * 3"), nil, "Malformed syntax returns nil")
        assertEqual(CalculatorEngine.evaluate("hello"), nil, "Plain word returns nil")
        assertEqual(CalculatorEngine.evaluate("safari"), nil, "App name returns nil")
        assertEqual(CalculatorEngine.evaluate("42"), nil, "Single number returns nil (no evaluation needed)")
        print("✅ CalculatorEngine passed all tests!\n")

        // Test 4: Fuzzy Matcher
        print("Testing FuzzyMatcher...")
        assertEqual(FuzzyMatcher.score(query: "safari", target: "safari"), 100, "Exact match score")
        assertEqual(FuzzyMatcher.score(query: "saf", target: "Safari"), 95, "Prefix match score")
        assertTrue((FuzzyMatcher.score(query: "monitor", target: "Activity Monitor") ?? 0) >= 85, "Word boundary match")
        assertTrue((FuzzyMatcher.score(query: "am", target: "Activity Monitor") ?? 0) >= 80, "Initials match")
        assertTrue((FuzzyMatcher.score(query: "term", target: "iTerm2") ?? 0) >= 65, "Contains match")
        assertEqual(FuzzyMatcher.score(query: "", target: "Safari"), nil, "Empty query")
        assertEqual(FuzzyMatcher.score(query: "xyz123", target: "Safari"), nil, "No match")
        print("✅ FuzzyMatcher passed all tests!\n")

        // Test 5: Settings Provider
        print("Testing SettingsProvider...")
        let displayResults = SettingsProvider.shared.search("display")
        assertTrue(!displayResults.isEmpty, "Displays search returns results")
        assertEqual(displayResults.first?.title, "Displays", "Top result for 'display' is Displays")

        let soundResults = SettingsProvider.shared.search("sound")
        assertTrue(!soundResults.isEmpty, "Sound search returns results")
        assertEqual(soundResults.first?.title, "Sound", "Top result for 'sound' is Sound")

        let wifiResults = SettingsProvider.shared.search("wifi")
        assertTrue(!wifiResults.isEmpty, "Wi-Fi search returns results")
        assertEqual(wifiResults.first?.title, "Wi-Fi", "Top result for 'wifi' is Wi-Fi")

        let darkResults = SettingsProvider.shared.search("dark")
        assertTrue(!darkResults.isEmpty, "Dark mode search returns results")
        assertEqual(darkResults.first?.title, "Appearance", "Top result for 'dark' is Appearance")
        print("✅ SettingsProvider passed all tests!\n")

        // Test 6: Quick Actions Provider
        print("Testing QuickActionsProvider...")
        let lockResults = QuickActionsProvider.shared.search("lock")
        assertTrue(!lockResults.isEmpty, "Lock search returns results")
        assertEqual(lockResults.first?.title, "Lock Screen", "Top result for 'lock' is Lock Screen")

        let sleepResults = QuickActionsProvider.shared.search("sleep")
        assertTrue(!sleepResults.isEmpty, "Sleep search returns results")
        assertEqual(sleepResults.first?.title, "Sleep", "Top result for 'sleep' is Sleep")

        let trashResults = QuickActionsProvider.shared.search("trash")
        assertTrue(!trashResults.isEmpty, "Trash search returns results")
        assertEqual(trashResults.first?.title, "Empty Trash", "Top result for 'trash' is Empty Trash")

        let darkActionResults = QuickActionsProvider.shared.search("toggle dark")
        assertTrue(!darkActionResults.isEmpty, "Toggle dark search returns results")
        assertEqual(darkActionResults.first?.title, "Toggle Dark Mode", "Top result for 'toggle dark' is Toggle Dark Mode")
        print("✅ QuickActionsProvider passed all tests!\n")

        // Test 7: Web Search Provider
        print("Testing WebSearchProvider...")
        let webResults = WebSearchProvider.shared.search("swift programming")
        assertEqual(webResults.count, 1, "Web search returns 1 result")
        assertEqual(webResults.first?.title, "Search Google for 'swift programming'", "Web search format")
        assertEqual(webResults.first?.category, .webSearch, "Web search category")
        print("✅ WebSearchProvider passed all tests!\n")

        // Test 8: Search Engine Aggregation & Top Hit
        print("Testing SearchEngine...")
        let engineResults = SearchEngine.shared.searchImmediate("display")
        assertTrue(engineResults[.systemSettings] != nil, "SearchEngine includes System Settings")
        if let topHit = engineResults[.topHit]?.first {
            assertEqual(topHit.title, "Displays", "Top hit for 'display' is Displays")
        }

        let calcEngineResults = SearchEngine.shared.searchImmediate("50 * 4")
        assertTrue(calcEngineResults[.calculator] != nil, "SearchEngine includes Calculator for math")
        assertEqual(calcEngineResults[.calculator]?.first?.title, "200", "Calculator result is 200")
        assertTrue(calcEngineResults[.webSearch] != nil, "SearchEngine includes Web Search fallback")

        print("✅ SearchEngine passed all tests!\n")

        print("🎉 ALL TESTS PASSED SUCCESSFULLY! 100% VERIFIED.")
    }
}
