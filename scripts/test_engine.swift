import Foundation

// MARK: - Test Runner for Lightspot Core Logic
//
// Build & run:
//   swiftc -o /tmp/test_engine scripts/test_engine.swift \
//       Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift \
//       && /tmp/test_engine

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

    // MARK: - Helpers

    /// `FuzzyMatcher.score` consumes pre-tokenized targets so it never allocates on
    /// the search path; the tests build those forms the same way the models do.
    static func score(query: String, target: String) -> Double? {
        let lower = target.lowercased()
        let tokens = lower.split(separator: " ").map(String.init)
        let initials = String(tokens.compactMap { $0.first })
        return FuzzyMatcher.score(
            query: SearchQuery(query),
            targetLower: lower,
            targetTokens: tokens,
            targetInitials: initials
        )
    }

    static func commands(_ list: [String]) -> [ShellCommand] {
        list.map { ShellCommand(command: $0) }
    }

    /// True if the string contains a `"` that is not preceded by a backslash — i.e.
    /// a quote that would close an AppleScript literal early.
    static func containsUnescapedQuote(_ text: String) -> Bool {
        var escaped = false
        for character in text {
            if escaped {
                escaped = false
                continue
            }
            if character == "\\" {
                escaped = true
                continue
            }
            if character == "\"" { return true }
        }
        return false
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

        // Test 4: Fuzzy Matcher — the tiers are load-bearing (Top Hit uses >= 60)
        print("Testing FuzzyMatcher...")
        assertEqual(score(query: "safari", target: "safari"), 100, "Exact match score")
        assertEqual(score(query: "saf", target: "Safari"), 95, "Prefix match score")
        assertEqual(score(query: "monitor", target: "Activity Monitor"), 85, "Word boundary match")
        assertEqual(score(query: "am", target: "Activity Monitor"), 80, "Initials match")
        assertEqual(score(query: "term", target: "iTerm2"), 65, "Contains match")
        assertEqual(score(query: "ie2", target: "iTerm2"), 40, "Subsequence match")
        assertEqual(score(query: "", target: "Safari"), nil, "Empty query")
        assertEqual(score(query: "xyz123", target: "Safari"), nil, "No match")
        print("✅ FuzzyMatcher passed all tests!\n")

        // Test 5: Settings Provider
        print("Testing SettingsProvider...")
        let displayResults = SettingsProvider.shared.search(SearchQuery("display"))
        assertTrue(!displayResults.isEmpty, "Displays search returns results")
        assertEqual(displayResults.first?.title, "Displays", "Top result for 'display' is Displays")

        let soundResults = SettingsProvider.shared.search(SearchQuery("sound"))
        assertTrue(!soundResults.isEmpty, "Sound search returns results")
        assertEqual(soundResults.first?.title, "Sound", "Top result for 'sound' is Sound")

        let wifiResults = SettingsProvider.shared.search(SearchQuery("wifi"))
        assertTrue(!wifiResults.isEmpty, "Wi-Fi search returns results")
        assertEqual(wifiResults.first?.title, "Wi-Fi", "Top result for 'wifi' is Wi-Fi")

        let darkResults = SettingsProvider.shared.search(SearchQuery("dark"))
        assertTrue(!darkResults.isEmpty, "Dark mode search returns results")
        assertEqual(darkResults.first?.title, "Appearance", "Top result for 'dark' is Appearance")
        print("✅ SettingsProvider passed all tests!\n")

        // Test 6: Quick Actions Provider
        print("Testing QuickActionsProvider...")
        let lockResults = QuickActionsProvider.shared.search(SearchQuery("lock"))
        assertTrue(!lockResults.isEmpty, "Lock search returns results")
        assertEqual(lockResults.first?.title, "Lock Screen", "Top result for 'lock' is Lock Screen")

        let sleepResults = QuickActionsProvider.shared.search(SearchQuery("sleep"))
        assertTrue(!sleepResults.isEmpty, "Sleep search returns results")
        assertEqual(sleepResults.first?.title, "Sleep", "Top result for 'sleep' is Sleep")

        let trashResults = QuickActionsProvider.shared.search(SearchQuery("trash"))
        assertTrue(!trashResults.isEmpty, "Trash search returns results")
        assertEqual(trashResults.first?.title, "Empty Trash", "Top result for 'trash' is Empty Trash")

        let darkActionResults = QuickActionsProvider.shared.search(SearchQuery("toggle dark"))
        assertTrue(!darkActionResults.isEmpty, "Toggle dark search returns results")
        assertEqual(darkActionResults.first?.title, "Toggle Dark Mode", "Top result for 'toggle dark' is Toggle Dark Mode")
        print("✅ QuickActionsProvider passed all tests!\n")

        // Test 7: Web Search Provider
        print("Testing WebSearchProvider...")
        let webResults = WebSearchProvider.shared.search(SearchQuery("swift programming"))
        assertEqual(webResults.count, 1, "Web search returns 1 result")
        assertEqual(webResults.first?.title, "Search Google for 'swift programming'", "Web search format")
        assertEqual(webResults.first?.category, .webSearch, "Web search category")
        print("✅ WebSearchProvider passed all tests!\n")

        testShellHistoryParsing()
        testShellHistoryRanking()
        testTerminalLauncher()

        // Test 11: Search Engine Aggregation & Top Hit
        print("Testing SearchEngine...")
        let engineResults = SearchEngine.shared.searchImmediate(SearchQuery("display"))
        assertTrue(engineResults[.systemSettings] != nil, "SearchEngine includes System Settings")
        // Verify deduplication: Top Hit item is not in systemSettings category
        if let topHit = engineResults[.topHit]?.first, let settingsList = engineResults[.systemSettings] {
            let containsDuplicate = settingsList.contains(where: { $0.title == topHit.title })
            assertTrue(!containsDuplicate, "Top Hit item is not duplicated in systemSettings")
        }
        print("✅ SearchEngine passed all tests!\n")

        testPinnedCommandsStore()
        testSearchRankingAndHistoryManager()
        testCustomCommandsStore()
        testVSCodeProjectsProvider()

        print("🎉 ALL TESTS PASSED SUCCESSFULLY! 100% VERIFIED.")
    }

    // MARK: - Test 8: zsh history parsing

    static func testShellHistoryParsing() {
        print("Testing ShellHistoryProvider parsing...")

        // EXTENDED_HISTORY entries, a plain entry, and a `\`-continued multi-line entry.
        let sample = """
        : 1700000000:0;git status
        : 1700000001:12;git commit -m "fix: quoting"
        ls -la
        : not a timestamp;kept verbatim
        echo a; echo b
        : 1700000002:0;echo one \\
        two
        """

        let parsed = ShellHistoryProvider.parseCommands(from: sample)
        assertEqual(parsed.count, 6, "All six entries parse")
        assertEqual(parsed.first, "git status", "EXTENDED_HISTORY prefix is stripped")
        assertEqual(parsed[1], "git commit -m \"fix: quoting\"", "Quotes and colons inside a command survive")
        assertEqual(parsed[2], "ls -la", "Plain (non-extended) lines are kept")
        assertEqual(parsed[3], ": not a timestamp;kept verbatim", "Timestamp look-alikes are left alone")
        assertEqual(parsed[4], "echo a; echo b", "A semicolon in a plain command is not a timestamp separator")
        assertEqual(parsed[5], "echo one \ntwo", "Backslash continuation rejoins into one command")

        // A tail read starts mid-file, so the first fragment is not a real command.
        let truncated = ShellHistoryProvider.parseCommands(from: sample, dropFirstLine: true)
        assertEqual(truncated.count, 5, "Partial first line is dropped on a truncated read")
        assertEqual(truncated.first, "git commit -m \"fix: quoting\"", "Parsing resumes at the first whole line")

        assertEqual(ShellHistoryProvider.stripTimestamp(": 1700000000:0;ls"), "ls", "stripTimestamp strips a valid header")
        assertEqual(ShellHistoryProvider.stripTimestamp("ls -la"), "ls -la", "stripTimestamp leaves plain lines alone")
        assertEqual(ShellHistoryProvider.stripTimestamp(": abc:0;ls"), ": abc:0;ls", "stripTimestamp requires numeric fields")

        // zsh metafication: 0x83 escapes the following byte with XOR 32. "é" is C3 A9.
        let metafied = Data([0x83, 0xE3, 0x83, 0x89])
        assertEqual(ShellHistoryProvider.unmetafy(metafied), "é", "Metafied UTF-8 is restored")
        assertEqual(ShellHistoryProvider.unmetafy(Data("git status".utf8)), "git status", "ASCII passes through unmetafy")

        // Newest-first de-duplication.
        let entries = ShellHistoryProvider.dedupedEntries(from: ["ls", "git status", "ls"], limit: 10)
        assertEqual(entries.count, 2, "Duplicate commands collapse")
        assertEqual(entries.first?.command, "ls", "Most recent occurrence wins")
        assertEqual(entries.last?.command, "git status", "Older unique command follows")
        assertEqual(ShellHistoryProvider.dedupedEntries(from: ["a1", "b2", "c3"], limit: 2).count, 2, "Entry limit is honoured")

        // Pre-computed match forms and single-line display.
        let multiline = ShellCommand(command: "echo one \ntwo")
        assertEqual(multiline.displayTitle, "echo one ⏎ two", "Multi-line commands render on one line")
        assertEqual(ShellCommand(command: "docker compose up").initials, "dcu", "Initials are pre-computed")

        print("✅ ShellHistoryProvider parsing passed all tests!\n")
    }

    // MARK: - Test 9: history ranking

    static func testShellHistoryRanking() {
        print("Testing ShellHistoryProvider ranking...")

        // History is newest-first, exactly as `dedupedEntries` returns it.
        let history = commands(["git status", "git commit", "docker compose up"])

        let gitResults = ShellHistoryProvider.search(SearchQuery("git"), pinned: [], history: history)
        assertEqual(gitResults.count, 2, "Only matching commands are returned")
        assertEqual(gitResults.first?.title, "git status", "The more recent of two equal-tier matches ranks first")
        assertEqual(gitResults.first?.category, .shellHistory, "History results carry the shell history category")
        assertEqual(gitResults.first?.isPinned, false, "Unpinned by default")
        if case .runInTerminal(let command)? = gitResults.first?.action {
            assertEqual(command, "git status", "Action carries the raw command")
        } else {
            assertTrue(false, "History result must carry a .runInTerminal action")
        }

        // Single-character queries would match nearly everything.
        assertEqual(ShellHistoryProvider.search(SearchQuery("g"), pinned: [], history: history).count, 0, "Single-character queries are ignored")
        assertEqual(ShellHistoryProvider.search(SearchQuery(""), pinned: [], history: history).count, 0, "Empty query returns nothing")

        // Substring (65) is the quality bar; a subsequence-only match (40) is noise.
        assertEqual(ShellHistoryProvider.search(SearchQuery("ompose"), pinned: [], history: history).count, 1, "Substring matches are kept")
        assertEqual(ShellHistoryProvider.search(SearchQuery("dcu"), pinned: [], history: history).count, 1, "Initials matches are kept")
        assertEqual(ShellHistoryProvider.search(SearchQuery("dku"), pinned: [], history: history).count, 0, "Subsequence-only matches are dropped")

        // Pins outrank everything else and are never listed twice.
        let pinned = commands(["git commit"])
        let pinnedResults = ShellHistoryProvider.search(SearchQuery("git"), pinned: pinned, history: history)
        assertEqual(pinnedResults.count, 2, "A pinned command is not duplicated by its history copy")
        assertEqual(pinnedResults.first?.title, "git commit", "Pinned matches sort first")
        assertEqual(pinnedResults.first?.isPinned, true, "Pinned flag is set on the result")
        assertEqual(pinnedResults.first?.subtitle, "Pinned · Run in Terminal", "Pinned rows are labelled")

        // A pin stays searchable after it has aged out of the history file.
        let orphanPin = ShellHistoryProvider.search(SearchQuery("terraform"), pinned: commands(["terraform apply"]), history: history)
        assertEqual(orphanPin.count, 1, "Pins are searched independently of the history file")

        print("✅ ShellHistoryProvider ranking passed all tests!\n")
    }

    // MARK: - Test 10: Terminal command escaping

    static func testTerminalLauncher() {
        print("Testing TerminalLauncher escaping...")

        assertEqual(TerminalLauncher.escapeForAppleScriptLiteral("git status"), "git status", "Plain commands are unchanged")
        assertEqual(TerminalLauncher.escapeForAppleScriptLiteral("echo \"hi\""), "echo \\\"hi\\\"", "Double quotes are escaped")
        assertEqual(TerminalLauncher.escapeForAppleScriptLiteral("a\\b"), "a\\\\b", "Backslashes are doubled")
        assertEqual(TerminalLauncher.escapeForAppleScriptLiteral("a\nb"), "a\\nb", "Newlines become the \\n escape")
        assertEqual(TerminalLauncher.escapeForAppleScriptLiteral("a\tb"), "a\\tb", "Tabs become the \\t escape")
        assertEqual(TerminalLauncher.escapeForAppleScriptLiteral("a\u{07}b"), "ab", "Other control characters are dropped")

        // The whole point: a quote in the command must not terminate the literal and
        // let the rest of the command run as AppleScript.
        let hostile = "\"\nactivate\ndo script \"rm -rf /"
        let literal = TerminalLauncher.escapeForAppleScriptLiteral(hostile)
        let script = TerminalLauncher.script(for: hostile)
        assertTrue(!containsUnescapedQuote(literal), "The escaped literal cannot terminate the AppleScript string")
        assertTrue(script.contains("do script \"\(literal)\""), "The command is embedded as one escaped literal")
        assertTrue(script.hasSuffix("end tell"), "Script is well formed")

        print("✅ TerminalLauncher passed all tests!\n")
    }

    // MARK: - Test 12: pinned command store + engine integration

    static func testPinnedCommandsStore() {
        print("Testing PinnedCommandsStore...")

        let store = PinnedCommandsStore.shared
        let existing = store.commands()
        for command in existing { store.unpin(command) }

        let alpha = "lightspot-selftest-alpha --flag"
        let beta = "lightspot-selftest-beta --flag"

        store.pin(alpha)
        store.pin(beta)
        assertEqual(store.commands(), [beta, alpha], "Newly pinned commands go to the top")
        assertTrue(store.isPinned(alpha), "isPinned finds a pinned command")
        assertTrue(!store.isPinned("never pinned"), "isPinned rejects an unpinned command")

        store.pin(alpha)
        assertEqual(store.commands().count, 2, "Pinning twice is a no-op")

        store.move(from: 0, offset: 1)
        assertEqual(store.commands(), [alpha, beta], "Moving down reorders the list")
        store.move(from: 0, offset: -5)
        assertEqual(store.commands(), [alpha, beta], "Moves are clamped to the list bounds")

        assertEqual(store.toggle(alpha), false, "Toggling a pinned command unpins it")
        assertEqual(store.commands(), [beta], "Unpinned command is gone")
        assertEqual(store.toggle(alpha), true, "Toggling again re-pins it")

        // Engine integration: a pinned command is searchable with no history file, and
        // it is promoted to the Top Hit because it is an intentional user pin.
        let grouped = SearchEngine.shared.searchImmediate(SearchQuery("lightspot-selftest-alpha"))
        assertEqual(grouped[.topHit]?.count, 1, "Pinned command is promoted to Top Hit")
        assertEqual(grouped[.topHit]?.first?.title, alpha, "…as the pinned command itself")
        assertEqual(grouped[.shellHistory]?.count, nil, "Top Hit item is not duplicated in shellHistory")

        // Clean up so repeat runs start from an empty list.
        store.unpin(alpha)
        store.unpin(beta)
        for command in existing.reversed() { store.pin(command) }
        assertEqual(store.commands().count, existing.count, "Pre-existing pins are restored")

        print("✅ PinnedCommandsStore passed all tests!\n")
    }

    // MARK: - Test 13: search ranking & history manager

    static func testSearchRankingAndHistoryManager() {
        print("Testing SearchRanking and SearchHistoryManager...")

        let manager = SearchHistoryManager.shared
        manager.reset()

        let testAppId = "app-com.test.terminal"
        let now = Date()

        // 1. Fresh state: zero boost
        let initialBoost = manager.rankingBoost(for: testAppId, query: SearchQuery("term"), now: now)
        assertEqual(initialBoost, 0.0, "Unselected item has 0 boost")

        // 2. Record single selection for keyword "term"
        manager.recordSelection(
            itemId: testAppId,
            title: "Terminal Test",
            subtitle: "Application",
            category: .applications,
            iconType: .systemSymbol(name: "terminal"),
            action: .launchApp(path: "/Applications/Terminal.app"),
            query: "term",
            date: now
        )

        // Exact same keyword boost
        let exactBoost = manager.rankingBoost(for: testAppId, query: SearchQuery("term"), now: now)
        assertTrue(exactBoost >= 38.0 && exactBoost <= 39.0, "Exact same keyword produces ~38.5 boost (20 keyword + 15 recency + 3.5 freq)")

        // Different keyword: no same-keyword bonus, only recency + frequency
        let diffBoost = manager.rankingBoost(for: testAppId, query: SearchQuery("other"), now: now)
        assertTrue(diffBoost >= 18.0 && diffBoost <= 19.0, "Different keyword has no same-keyword bonus (~18.5)")
        assertTrue(exactBoost > diffBoost + 19.0, "Same keyword outscores different keyword by ~20 points")

        // Prefix keyword match: query "te" is prefix of "term"
        let prefixBoost = manager.rankingBoost(for: testAppId, query: SearchQuery("te"), now: now)
        assertTrue(prefixBoost > diffBoost, "Prefix of keyword gets partial keyword bonus")
        assertTrue(exactBoost > prefixBoost, "Exact keyword match beats prefix keyword match")

        // 3. Frequency boost with multiple selections
        for _ in 1...4 {
            manager.recordSelection(
                itemId: testAppId,
                title: "Terminal Test",
                subtitle: "Application",
                category: .applications,
                iconType: .systemSymbol(name: "terminal"),
                action: .launchApp(path: "/Applications/Terminal.app"),
                query: "term",
                date: now
            )
        }
        let multiBoost = manager.rankingBoost(for: testAppId, query: SearchQuery("term"), now: now)
        assertTrue(multiBoost > exactBoost + 5.0, "5 selections increase boost significantly over 1 selection")

        // 4. Recency decay over time
        let twoDaysLater = now.addingTimeInterval(86400 * 2)
        let decayedBoost = manager.rankingBoost(for: testAppId, query: SearchQuery("term"), now: twoDaysLater)
        assertTrue(decayedBoost < multiBoost, "Boost decays over time")

        let thirtyDaysLater = now.addingTimeInterval(86400 * 30)
        let staleBoost = manager.rankingBoost(for: testAppId, query: SearchQuery("term"), now: thirtyDaysLater)
        assertTrue(staleBoost < decayedBoost, "Boost continues decaying over 30 days")

        // 5. History entries inspection and deletion
        let entries = manager.entries()
        assertEqual(entries.count, 1, "History has 1 entry for this query/item pair")
        assertEqual(entries.first?.itemId, testAppId, "History records correct itemId")
        assertEqual(entries.first?.query, "term", "History records query")
        assertEqual(entries.first?.selectionCount, 5, "History records selection count 5")

        if let entryId = entries.first?.id {
            manager.deleteEntry(id: entryId)
            assertEqual(manager.entries().count, 0, "deleteEntry removes the item from history")
        }

        manager.clearHistory()
        assertEqual(manager.entries().count, 0, "clearHistory empties history entries")
        assertEqual(manager.rankingBoost(for: testAppId, query: SearchQuery("term"), now: now), 0.0, "clearHistory resets ranking boosts to 0")

        print("✅ SearchRanking and SearchHistoryManager passed all tests!\n")
    }

    // MARK: - Test 14: Custom Commands Store & Engine Integration

    static func testCustomCommandsStore() {
        print("Testing CustomCommandsStore...")

        let store = CustomCommandsStore.shared
        let existing = store.entries()

        // 1. Reset to empty and test defaults / initial seeding
        store.reset(to: [])
        assertEqual(store.count(), 0, "Store reset to empty")

        // 2. Add commands of different types
        let urlCmd = CustomCommand(
            name: "Hacker News",
            type: .url,
            target: "news.ycombinator.com",
            keywords: ["hn", "tech", "news"]
        )
        let termCmd = CustomCommand(
            name: "Disk Usage",
            type: .terminal,
            target: "df -h",
            keywords: ["disk", "space", "storage"]
        )
        let appleCmd = CustomCommand(
            name: "Mute System",
            type: .appleScript,
            target: "set volume with output muted",
            keywords: ["sound", "silence"]
        )
        let shellCmd = CustomCommand(
            name: "Touch Scratch",
            type: .shell,
            target: "touch /tmp/scratch.txt",
            keywords: ["scratch", "file"]
        )

        store.add(urlCmd)
        store.add(termCmd)
        store.add(appleCmd)
        store.add(shellCmd)

        assertEqual(store.count(), 4, "Store has 4 commands")
        // Newly added items are at the front
        assertEqual(store.entries().first?.id, shellCmd.id, "Latest added command is at index 0")

        // 3. URL normalization
        assertEqual(urlCmd.normalizedURL?.absoluteString, "https://news.ycombinator.com", "Bare hostname gets https:// prepended")
        let fullURL = CustomCommand(name: "Full", type: .url, target: "http://localhost:8080/app")
        assertEqual(fullURL.normalizedURL?.absoluteString, "http://localhost:8080/app", "Explicit scheme preserved")

        // 4. Action mapping
        if case .openURL(let url) = urlCmd.searchAction {
            assertEqual(url.absoluteString, "https://news.ycombinator.com", "URL action maps correctly")
        } else {
            assertTrue(false, "urlCmd should produce .openURL action")
        }

        if case .runInTerminal(let command) = termCmd.searchAction {
            assertEqual(command, "df -h", "Terminal action maps correctly")
        } else {
            assertTrue(false, "termCmd should produce .runInTerminal action")
        }

        if case .runQuickAction(let script, let usesOsascript) = appleCmd.searchAction {
            assertEqual(script, "set volume with output muted", "AppleScript action maps correctly")
            assertTrue(usesOsascript, "AppleScript uses osascript")
        } else {
            assertTrue(false, "appleCmd should produce .runQuickAction with usesOsascript: true")
        }

        if case .runQuickAction(let script, let usesOsascript) = shellCmd.searchAction {
            assertEqual(script, "touch /tmp/scratch.txt", "Shell action maps correctly")
            assertTrue(!usesOsascript, "Shell does not use osascript")
        } else {
            assertTrue(false, "shellCmd should produce .runQuickAction with usesOsascript: false")
        }

        // 5. Update
        var updatedTerm = termCmd
        updatedTerm.name = "Disk Free Space"
        store.update(updatedTerm)
        let foundUpdated = store.entries().first(where: { $0.id == termCmd.id })
        assertEqual(foundUpdated?.name, "Disk Free Space", "Command updated successfully")

        // 6. Move / Reorder
        store.move(from: 0, offset: 2)
        assertEqual(store.entries()[2].id, shellCmd.id, "Move reorders command")
        store.move(from: 2, offset: -10)
        assertEqual(store.entries()[0].id, shellCmd.id, "Move clamps to bounds")

        // 7. Search matching (Name, Keyword, Target)
        let searchName = store.search(SearchQuery("hacker"))
        assertTrue(!searchName.isEmpty, "Search by name finds command")
        assertEqual(searchName.first?.title, "Hacker News", "Top match is Hacker News")
        assertEqual(searchName.first?.category, .customCommands, "Category is .customCommands")

        let searchKeyword = store.search(SearchQuery("storage"))
        assertTrue(!searchKeyword.isEmpty, "Search by keyword finds command")
        assertEqual(searchKeyword.first?.title, "Disk Free Space", "Keyword search matches Disk Free Space")

        let searchTarget = store.search(SearchQuery("output muted"))
        assertTrue(!searchTarget.isEmpty, "Search by target content finds command")
        assertEqual(searchTarget.first?.title, "Mute System", "Target search matches Mute System")

        // Subsequence noise below 65 is dropped
        let searchNoise = store.search(SearchQuery("zzq"))
        assertTrue(searchNoise.isEmpty, "Unrelated query returns empty results")

        // 8. SearchEngine integration & Top Hit promotion
        let engineGrouped = SearchEngine.shared.searchImmediate(SearchQuery("Hacker News"))
        assertEqual(engineGrouped[.topHit]?.count, 1, "Custom command promoted to Top Hit for exact match")
        assertEqual(engineGrouped[.topHit]?.first?.title, "Hacker News", "Top Hit title matches custom command")

        // 9. Delete
        store.delete(id: urlCmd.id)
        assertEqual(store.count(), 3, "Delete removes command")
        assertTrue(store.entries().allSatisfy { $0.id != urlCmd.id }, "Deleted command no longer in store")

        // Restore pre-existing state
        store.reset(to: existing)
        assertEqual(store.count(), existing.count, "Pre-existing custom commands restored")

        print("✅ CustomCommandsStore passed all tests!\n")
    }

    // MARK: - Test 15: VS Code Projects Provider

    static func testVSCodeProjectsProvider() {
        print("Testing VSCodeProjectsProvider...")

        // 1. Test URI parsing & percent decoding
        assertEqual(
            VSCodeProjectsProvider.parseURIPath("file:///Users/test/priv/my-app"),
            "/Users/test/priv/my-app",
            "parseURIPath parses standard file:// URI"
        )
        assertEqual(
            VSCodeProjectsProvider.parseURIPath("file:///Users/test/priv/my%20app"),
            "/Users/test/priv/my app",
            "parseURIPath unquotes percent-encoded spaces"
        )
        assertEqual(
            VSCodeProjectsProvider.parseURIPath("/Users/test/priv/direct-path"),
            "/Users/test/priv/direct-path",
            "parseURIPath accepts raw absolute path"
        )

        // 2. Test Noise Exclusion Heuristics
        assertTrue(!VSCodeProjectsProvider.shouldIncludePath("/Users/test/priv/project/.git"), "Rejects .git directory")
        assertTrue(!VSCodeProjectsProvider.shouldIncludePath("/Users/test/priv/project/.claude/worktrees/feat1"), "Rejects Claude worktree")
        assertTrue(!VSCodeProjectsProvider.shouldIncludePath("/Users/test/Library/Application Support/Code/User/agent-sessions.code-workspace"), "Rejects internal Code workspace")
        assertTrue(!VSCodeProjectsProvider.shouldIncludePath(NSHomeDirectory()), "Rejects home directory itself")
        assertTrue(!VSCodeProjectsProvider.shouldIncludePath("/nonexistent_path_xyz_12345"), "Rejects non-existent path")

        // 3. Test Tilde Shortening
        let home = NSHomeDirectory()
        assertEqual(
            VSCodeProjectsProvider.tildeShortenedPath(for: "\(home)/priv/shopify-cpixel"),
            "~/priv",
            "Shortens home directory prefix to tilde parent"
        )
        assertEqual(
            VSCodeProjectsProvider.tildeShortenedPath(for: "\(home)/Desktop"),
            "~",
            "Top-level home child has ~ display path"
        )

        // 4. Test VSCodeProject model initialization & tokens
        let proj1 = VSCodeProject(
            name: "shopify-cpixel",
            path: "/Users/test/priv/shopify-cpixel",
            displayPath: "~/priv",
            recency: 200.0
        )
        let proj2 = VSCodeProject(
            name: "mac-lightspot",
            path: "/Users/test/priv/mac-lightspot",
            displayPath: "~/priv",
            recency: 100.0
        )
        let proj3 = VSCodeProject(
            name: "cdm",
            path: "/Users/test/priv/cleandevmac/cdm",
            displayPath: "~/priv/cleandevmac",
            recency: 50.0
        )

        assertEqual(proj1.nameTokens, ["shopify", "cpixel"], "Hyphenated name split into tokens")
        assertEqual(proj1.initials, "sc", "Initials computed from tokens")
        assertEqual(proj2.initials, "ml", "Initials for mac-lightspot are ml")
        assertTrue(proj3.pathTokens.contains("cleandevmac"), "Path tokens extracted for cdm")

        let mockProjects = [proj1, proj2, proj3]

        // 5. Exact match
        let exactRes = VSCodeProjectsProvider.search(SearchQuery("shopify-cpixel"), projects: mockProjects)
        assertTrue(!exactRes.isEmpty, "Exact search finds project")
        assertEqual(exactRes.first?.title, "shopify-cpixel", "Top match is shopify-cpixel")
        assertEqual(exactRes.first?.category, .recentProjects, "Category is .recentProjects")
        if case .openFolder(let path) = exactRes.first?.action {
            assertEqual(path, "/Users/test/priv/shopify-cpixel", "Action is .openFolder with correct path")
        } else {
            print("❌ FAIL: Expected action .openFolder")
            exit(1)
        }

        // 6. Word-boundary match on hyphenated segment
        let wordRes = VSCodeProjectsProvider.search(SearchQuery("cpixel"), projects: mockProjects)
        assertTrue(!wordRes.isEmpty, "Hyphenated token 'cpixel' matches")
        assertEqual(wordRes.first?.title, "shopify-cpixel", "Top result is shopify-cpixel")

        let lightspotRes = VSCodeProjectsProvider.search(SearchQuery("lightspot"), projects: mockProjects)
        assertTrue(!lightspotRes.isEmpty, "Word boundary 'lightspot' matches mac-lightspot")
        assertEqual(lightspotRes.first?.title, "mac-lightspot", "Top result is mac-lightspot")

        // 7. Acronym initials match
        let scRes = VSCodeProjectsProvider.search(SearchQuery("sc"), projects: mockProjects)
        assertTrue(!scRes.isEmpty, "Initials 'sc' finds shopify-cpixel")
        assertEqual(scRes.first?.title, "shopify-cpixel", "Matches by initials sc")

        let mlRes = VSCodeProjectsProvider.search(SearchQuery("ml"), projects: mockProjects)
        assertTrue(!mlRes.isEmpty, "Initials 'ml' finds mac-lightspot")
        assertEqual(mlRes.first?.title, "mac-lightspot", "Matches by initials ml")

        // 8. Path segment matching
        let pathRes = VSCodeProjectsProvider.search(SearchQuery("cleandevmac"), projects: mockProjects)
        assertTrue(!pathRes.isEmpty, "Path token 'cleandevmac' finds cdm")
        assertEqual(pathRes.first?.title, "cdm", "Matches cdm via parent dir")

        // 9. Generic browse keywords
        let browseRes = VSCodeProjectsProvider.search(SearchQuery("proj"), projects: mockProjects)
        assertEqual(browseRes.count, 3, "Browse keyword 'proj' returns all projects")

        // 10. Subsequence / noise filter
        let noiseRes = VSCodeProjectsProvider.search(SearchQuery("zzq"), projects: mockProjects)
        assertTrue(noiseRes.isEmpty, "Unrelated query returns empty")

        print("✅ VSCodeProjectsProvider passed all tests!\n")
    }
}
