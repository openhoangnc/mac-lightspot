import Foundation

// MARK: - Test Runner for Lightspot Core Logic
//
// Build & run:
//   swiftc -o /tmp/test_engine scripts/test_engine.swift \
//       Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift \
//       Sources/Lightspot/System/AutoStartManager.swift Sources/Lightspot/System/SpotlightManager.swift \
//       Sources/Lightspot/System/FirstRunManager.swift \
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

    @MainActor
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
        testSettingsBackup()

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

        // 8. Prefix commands and argument interpolation
        let ghCmd = CustomCommand(
            name: "GitHub",
            type: .url,
            target: "https://github.com/search?q={query}&type=repositories",
            keywords: ["github", "git"],
            prefix: "gh",
            iconSource: .runner
        )
        store.add(ghCmd)

        // Test exact prefix match without argument
        let exactPrefixSearch = store.search(SearchQuery("gh"))
        assertTrue(!exactPrefixSearch.isEmpty, "Search by prefix 'gh' finds command")
        assertEqual(exactPrefixSearch.first?.score, 96.0, "Exact prefix match has 96.0 score")

        // Test prefix command with argument (e.g. "gh spotlight")
        let prefixWithArgSearch = store.search(SearchQuery("gh spotlight"))
        assertTrue(!prefixWithArgSearch.isEmpty, "Prefix command 'gh spotlight' matches")
        assertEqual(prefixWithArgSearch.first?.score, 98.0, "Prefix with arg has 98.0 score")
        assertEqual(prefixWithArgSearch.first?.title, "GitHub for 'spotlight'", "Dynamic title matches")
        assertTrue(prefixWithArgSearch.first?.subtitle.contains("https://github.com/search?q=spotlight") == true, "Subtitle has interpolated query")
        if case .openURL(let targetURL) = prefixWithArgSearch.first?.action {
            assertEqual(targetURL.absoluteString, "https://github.com/search?q=spotlight&type=repositories", "URL has query substituted")
        } else {
            assertTrue(false, "Prefix result should produce .openURL action")
        }

        // Test runner icon and custom base64 icon
        assertTrue(ghCmd.runnerAppName.contains("Browser") || ghCmd.runnerAppName.contains("Chrome") || ghCmd.runnerAppName.contains("Safari"), "Runner app name resolved")
        let testBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        var customIconCmd = ghCmd
        customIconCmd.iconSource = .custom
        customIconCmd.iconBase64 = testBase64
        if case .customImage(let b64) = customIconCmd.resolvedIconType {
            assertEqual(b64, testBase64, "Custom base64 icon preserved")
            let decoded = CustomIconCache.shared.image(for: b64)
            assertTrue(decoded != nil, "CustomIconCache successfully decodes base64 image")
        } else {
            assertTrue(false, "resolvedIconType should be .customImage")
        }

        // 9. SearchEngine integration & Top Hit promotion
        let engineGrouped = SearchEngine.shared.searchImmediate(SearchQuery("Hacker News"))
        assertEqual(engineGrouped[.topHit]?.count, 1, "Custom command promoted to Top Hit for exact match")
        assertEqual(engineGrouped[.topHit]?.first?.title, "Hacker News", "Top Hit title matches custom command")

        // Top Hit promotion for prefix commands ("gh spotlight")
        let enginePrefixGrouped = SearchEngine.shared.searchImmediate(SearchQuery("gh spotlight"))
        assertEqual(enginePrefixGrouped[.topHit]?.count, 1, "Prefix command promoted to Top Hit")
        assertEqual(enginePrefixGrouped[.topHit]?.first?.title, "GitHub for 'spotlight'", "Top hit title matches prefix command")

        // 10. Delete
        store.delete(id: ghCmd.id)
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

    // MARK: - Test 16: Settings Backup (Export / Import)

    @MainActor
    static func testSettingsBackup() {
        print("Testing SettingsBackup...")

        // 1. Model creation & roundtrip JSON serialization
        let originalDate = Date(timeIntervalSince1970: 1700000000)
        let cmd1 = CustomCommand(
            name: "Hacker News",
            type: .url,
            target: "https://news.ycombinator.com",
            keywords: ["hn", "tech"]
        )
        let cmd2 = CustomCommand(
            name: "Docker Containers",
            type: .terminal,
            target: "docker ps",
            keywords: ["docker", "containers"]
        )

        let historyEntry = SearchHistoryEntry(
            itemId: "app-com.apple.Safari",
            query: "safari",
            title: "Safari",
            subtitle: "Application",
            category: .applications,
            iconType: .systemSymbol(name: "safari"),
            action: .launchApp(path: "/Applications/Safari.app"),
            selectedAt: originalDate,
            selectionCount: 3
        )
        let usageRecord = ItemUsageRecord(
            totalCount: 3,
            lastSelected: originalDate,
            keywords: ["safari": KeywordUsage(count: 3, lastSelected: originalDate)]
        )

        let originalBackup = LightspotSettingsBackup(
            version: 1,
            app: "com.lightspot.app",
            exportedAt: originalDate,
            preferences: LightspotPreferencesBackup(
                hotkeyOption: "commandSpace",
                autoStartEnabled: true,
                hideMenuBarIcon: false
            ),
            customCommands: [cmd1, cmd2],
            pinnedCommands: ["git status", "make build"],
            searchHistory: SearchHistoryBackupData(
                entries: [historyEntry],
                itemStats: ["app-com.apple.Safari": usageRecord]
            ),
            recentAppBundleIDs: ["com.apple.Safari", "com.apple.Terminal"]
        )

        // 2. Encode to JSON Data
        guard let encodedData = try? originalBackup.encode() else {
            print("❌ FAIL: Failed to encode LightspotSettingsBackup to JSON")
            exit(1)
        }
        assertTrue(encodedData.count > 50, "Encoded JSON has reasonable length")

        guard let jsonString = String(data: encodedData, encoding: .utf8) else {
            print("❌ FAIL: Encoded data is not valid UTF-8 string")
            exit(1)
        }
        assertTrue(jsonString.contains("\"version\" : 1"), "JSON contains version")
        assertTrue(jsonString.contains("\"app\" : \"com.lightspot.app\""), "JSON contains appIdentifier")
        assertTrue(jsonString.contains("\"Hacker News\""), "JSON contains custom commands")
        assertTrue(jsonString.contains("\"git status\""), "JSON contains pinned commands")
        assertTrue(jsonString.contains("\"commandSpace\""), "JSON contains hotkeyOption")

        // 3. Decode back and assert equality
        guard let decodedBackup = try? LightspotSettingsBackup.decode(from: encodedData) else {
            print("❌ FAIL: Failed to decode LightspotSettingsBackup from JSON")
            exit(1)
        }
        assertEqual(decodedBackup.version, 1, "Decoded version matches")
        assertEqual(decodedBackup.app, "com.lightspot.app", "Decoded app identifier matches")
        assertEqual(decodedBackup.preferences.hotkeyOption, "commandSpace", "Decoded hotkey matches")
        assertEqual(decodedBackup.preferences.autoStartEnabled, true, "Decoded autoStart matches")
        assertEqual(decodedBackup.preferences.hideMenuBarIcon, false, "Decoded hideMenuBarIcon matches")
        assertEqual(decodedBackup.customCommands.count, 2, "Decoded custom commands count matches")
        assertEqual(decodedBackup.customCommands[0].name, "Hacker News", "First custom command name matches")
        assertEqual(decodedBackup.pinnedCommands, ["git status", "make build"], "Decoded pinned commands match")
        assertEqual(decodedBackup.searchHistory?.entries.count, 1, "Decoded search history entries count matches")
        assertEqual(decodedBackup.recentAppBundleIDs, ["com.apple.Safari", "com.apple.Terminal"], "Decoded recent apps match")

        // 4. Schema version rejection
        let futureVersionJSON = jsonString.replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 999")
        let futureData = futureVersionJSON.data(using: .utf8)!
        do {
            _ = try LightspotSettingsBackup.decode(from: futureData)
            print("❌ FAIL: Future version 999 should have been rejected")
            exit(1)
        } catch let error as SettingsBackupError {
            assertEqual(error, .unsupportedVersion(999), "Throws unsupportedVersion for schema 999")
        } catch {
            print("❌ FAIL: Unexpected error type: \(error)")
            exit(1)
        }

        // 5. Invalid app identifier rejection
        let alienAppJSON = jsonString.replacingOccurrences(of: "\"app\" : \"com.lightspot.app\"", with: "\"app\" : \"com.other.app\"")
        let alienData = alienAppJSON.data(using: .utf8)!
        do {
            _ = try LightspotSettingsBackup.decode(from: alienData)
            print("❌ FAIL: Alien app identifier should have been rejected")
            exit(1)
        } catch let error as SettingsBackupError {
            assertEqual(error, .invalidAppIdentifier("com.other.app"), "Throws invalidAppIdentifier for other apps")
        } catch {
            print("❌ FAIL: Unexpected error type: \(error)")
            exit(1)
        }

        // 6. Corrupted JSON rejection
        let corruptedData = "this is not json at all!".data(using: .utf8)!
        do {
            _ = try LightspotSettingsBackup.decode(from: corruptedData)
            print("❌ FAIL: Corrupted data should have thrown error")
            exit(1)
        } catch is SettingsBackupError {
            // Success
        } catch {
            print("❌ FAIL: Expected SettingsBackupError for corrupted data")
            exit(1)
        }

        // 7. PinnedCommandsStore reset(to:) verification
        let pinsStore = PinnedCommandsStore.shared
        let originalPins = pinsStore.commands()
        pinsStore.reset(to: ["echo test1", "echo test2", "echo test3"])
        assertEqual(pinsStore.commands(), ["echo test1", "echo test2", "echo test3"], "PinnedCommandsStore.reset replaces pins")
        pinsStore.reset(to: originalPins)
        assertEqual(pinsStore.commands(), originalPins, "PinnedCommandsStore restores original pins")

        // 9. PathSanitizer & Home directory export anonymization
        let userHome = NSHomeDirectory()
        let username = NSUserName()
        let rawPath = "\(userHome)/projects/my-app/run.sh"
        let sanitized = PathSanitizer.sanitizeForExport(rawPath)
        assertEqual(sanitized, "~/projects/my-app/run.sh", "PathSanitizer replaces home directory with ~")
        assertTrue(!sanitized.contains(username), "Sanitized string does not contain username")

        let expandedPath = PathSanitizer.expandForImport(sanitized)
        assertEqual(expandedPath, rawPath, "PathSanitizer restores ~ to home directory on import")

        let userVarStr = "Hello ${USER}"
        let expandedUserVar = PathSanitizer.expandForImport(userVarStr)
        assertEqual(expandedUserVar, "Hello \(username)", "PathSanitizer expands ${USER}")

        // Test export settings JSON does not leak username
        let userCmd = CustomCommand(
            name: "Local Script",
            type: .shell,
            target: "\(userHome)/bin/myscript.sh",
            keywords: ["local"]
        )
        let leakTestBackup = LightspotSettingsBackup(
            preferences: LightspotPreferencesBackup(hotkeyOption: "commandSpace", autoStartEnabled: false, hideMenuBarIcon: false),
            customCommands: [userCmd],
            pinnedCommands: ["cd \(userHome)/Desktop"],
            searchHistory: nil,
            recentAppBundleIDs: nil
        )
        let exportedJSONData = try! leakTestBackup.encode()
        let exportedJSONString = String(data: exportedJSONData, encoding: .utf8)!
        assertTrue(!exportedJSONString.contains("/Users/\(username)"), "Exported backup JSON does not contain /Users/<username>")
        assertTrue(exportedJSONString.contains("~/bin/myscript.sh"), "Exported backup contains sanitized ~ path")
        assertTrue(exportedJSONString.contains("cd ~/Desktop"), "Exported backup contains sanitized pinned command")

        print("✅ SettingsBackup passed all tests!\n")

        // Test 14: Conversion Engine (Relaxed units, bases, currency)
        print("Testing ConversionEngine...")
        let fResult = ConversionEngine.convert("72F")
        assertTrue(fResult != nil, "72F converts")
        assertEqual(fResult?.value, "22.2222°C", "72F converts to ~22.2°C")

        let cResult = ConversionEngine.convert("100C")
        assertTrue(cResult != nil, "100C converts")
        assertEqual(cResult?.value, "212°F", "100C converts to 212°F")

        let kmResult = ConversionEngine.convert("10km")
        assertTrue(kmResult != nil, "10km converts")
        assertTrue(kmResult?.value.contains("mi") == true, "10km converted to miles")

        let lbsResult = ConversionEngine.convert("150lbs")
        assertTrue(lbsResult != nil, "150lbs converts")
        assertTrue(lbsResult?.value.contains("kg") == true, "150lbs converted to kg")

        let gbResult = ConversionEngine.convert("16GB")
        assertTrue(gbResult != nil, "16GB converts")
        assertEqual(gbResult?.value, "16,384 MB", "16GB converts to 16,384 MB")

        let hexResult = ConversionEngine.convert("0xFF")
        assertTrue(hexResult != nil, "0xFF converts")
        assertEqual(hexResult?.value, "255", "0xFF converts to 255")

        let binResult = ConversionEngine.convert("42 in bin")
        assertTrue(binResult != nil, "42 in bin converts")
        assertEqual(binResult?.value, "0b101010", "42 in bin is 0b101010")

        let currResult = ConversionEngine.convert("100 USD in EUR")
        assertTrue(currResult != nil, "100 USD in EUR converts")
        assertEqual(currResult?.value, "92.00 EUR", "100 USD in EUR is 92.00 EUR")

        // Regression: formatCurrency used Int(_: Double), which traps past Int.max.
        // "100000000000000000000 USD" crashed the app straight from the search field.
        let hugeAmount = ConversionEngine.convert("100000000000000000000 USD")
        assertTrue(hugeAmount != nil, "Astronomically large currency amounts convert instead of trapping")

        // Regression: the " in "/" to " split took a range from `lower` and applied it to
        // `clean`. "İ".lowercased() is longer than "İ", so the index ran past the end.
        let unicodeSplit = ConversionEngine.convert(String(repeating: "\u{0130}", count: 20) + " in eur")
        assertTrue(unicodeSplit == nil, "Unicode that changes length when lowercased does not trap the currency split")

        // Regression: splitting on `clean` must preserve case so "R$" is still recognised.
        let brlResult = ConversionEngine.convert("R$100 in USD")
        assertTrue(brlResult?.subtitle.contains("BRL") == true, "R$ prefix survives the in/to split")

        // Whole amounts keep their thousands separators (decimalFormatter had grouping off).
        assertEqual(ConversionEngine.convert("1500 usd in eur")?.value, "1,380 EUR", "Whole currency amounts keep their thousands separators")

        // Regression: default targets were chosen by prefix tests that every long form
        // missed, so "10 kilograms" answered "10 kg" and "10 gigabytes" answered in KB.
        assertTrue(ConversionEngine.convert("10 kilometers")?.value.contains("mi") == true, "kilometers defaults to miles like km")
        assertTrue(ConversionEngine.convert("10 kilograms")?.value.contains("lbs") == true, "kilograms defaults to lbs like kg")
        assertTrue(ConversionEngine.convert("10 ounces")?.value.contains("g") == true, "ounces defaults to grams like oz")
        assertTrue(ConversionEngine.convert("10 milligrams")?.value.contains("g") == true, "milligrams defaults to grams like mg")
        assertEqual(ConversionEngine.convert("16 gigabytes")?.value, "16,384 MB", "gigabytes defaults to MB like gb")
        assertTrue(ConversionEngine.convert("2 terabytes")?.value.contains("GB") == true, "terabytes defaults to GB like tb")

        // Verify CalculatorEngine.evaluateExtended connects properly
        let ext = CalculatorEngine.evaluateExtended("72F")
        assertTrue(ext != nil, "CalculatorEngine.evaluateExtended handles 72F")
        assertEqual(ext?.value, "22.2222°C", "evaluateExtended returns 22.2222°C")
        print("✅ ConversionEngine passed all tests!\n")

        // Test 15: WebSearchProvider (Engines & Prefixes)
        print("Testing WebSearchProvider...")
        let webProvider = WebSearchProvider.shared
        webProvider.defaultEngine = .google
        let googleResults = webProvider.search(SearchQuery("swift programming"))
        assertEqual(googleResults.first?.title, "Search Google for 'swift programming'", "Default engine searches Google")

        webProvider.defaultEngine = .duckDuckGo
        let ddgResults = webProvider.search(SearchQuery("swift programming"))
        assertEqual(ddgResults.first?.title, "Search DuckDuckGo for 'swift programming'", "Switching engine searches DuckDuckGo")
        webProvider.defaultEngine = .google // Restore

        let ghPrefix = webProvider.search(SearchQuery("gh react"))
        assertTrue(!ghPrefix.isEmpty, "Prefix gh returns results")
        assertEqual(ghPrefix.first?.title, "Search GitHub for 'react'", "gh react searches GitHub")
        assertEqual(ghPrefix.first?.score, 95, "Prefix search receives top score 95")

        let ytPrefix = webProvider.search(SearchQuery("yt lofi"))
        assertEqual(ytPrefix.first?.title, "Search YouTube for 'lofi'", "yt lofi searches YouTube")

        // URL Auto-Detection Tests
        assertEqual(WebSearchProvider.detectURL("facebook.com")?.absoluteString, "https://facebook.com", "Detects facebook.com as https://facebook.com")
        assertEqual(WebSearchProvider.detectURL("https://facebook.com")?.absoluteString, "https://facebook.com", "Preserves https://facebook.com")
        assertEqual(WebSearchProvider.detectURL("http://localhost:3000")?.absoluteString, "http://localhost:3000", "Preserves http://localhost:3000")
        assertEqual(WebSearchProvider.detectURL("localhost:8080")?.absoluteString, "http://localhost:8080", "Detects localhost:8080 as http://localhost:8080")
        assertEqual(WebSearchProvider.detectURL("127.0.0.1:5000")?.absoluteString, "http://127.0.0.1:5000", "Detects 127.0.0.1:5000")
        assertEqual(WebSearchProvider.detectURL("192.168.1.1")?.absoluteString, "http://192.168.1.1", "Detects IPv4 192.168.1.1")
        assertEqual(WebSearchProvider.detectURL("github.com/torvalds/linux")?.absoluteString, "https://github.com/torvalds/linux", "Detects github path")
        assertEqual(WebSearchProvider.detectURL("my-app.dev")?.absoluteString, "https://my-app.dev", "Detects .dev modern TLD")
        assertEqual(WebSearchProvider.detectURL("test.io")?.absoluteString, "https://test.io", "Detects .io modern TLD")
        assertEqual(WebSearchProvider.detectURL("vietnamnet.vn")?.absoluteString, "https://vietnamnet.vn", "Detects ccTLD .vn")

        // Negative URL cases (should be nil)
        assertEqual(WebSearchProvider.detectURL("facebook login"), nil, "Query with spaces is not a URL")
        assertEqual(WebSearchProvider.detectURL("2+2"), nil, "Math query is not a URL")
        assertEqual(WebSearchProvider.detectURL("v1.2.3"), nil, "Version string is not a URL")
        assertEqual(WebSearchProvider.detectURL("file.txt"), nil, "File extension is not a URL")
        assertEqual(WebSearchProvider.detectURL("hello"), nil, "Single word is not a URL")

        // WebSearchProvider search with URL query
        let urlSearchResults = webProvider.search(SearchQuery("facebook.com"))
        assertTrue(!urlSearchResults.isEmpty, "URL query returns results")
        assertEqual(urlSearchResults.first?.id, "web-url-facebook.com", "Primary result is direct URL")
        assertEqual(urlSearchResults.first?.title, "Open facebook.com", "Primary title opens direct URL")
        assertEqual(urlSearchResults.first?.subtitle, "https://facebook.com", "Primary subtitle is full URL")
        assertEqual(urlSearchResults.first?.score, 95, "Direct URL receives top score 95")
        if case .openURL(let u) = urlSearchResults.first?.action {
            assertEqual(u.absoluteString, "https://facebook.com", "Action is openURL")
        } else {
            print("❌ FAIL: Expected .openURL action for direct URL search")
            exit(1)
        }
        assertTrue(urlSearchResults.count >= 2, "Fallback search is included below URL")
        assertEqual(urlSearchResults[1].id, "web-facebook.com", "Second result is fallback search")
        assertEqual(urlSearchResults[1].score, 25, "Fallback search receives low score 25")

        // SearchEngine Top Hit promotion for direct URLs
        let engineGrouped = SearchEngine.shared.searchImmediate(SearchQuery("facebook.com"))
        let topHits = engineGrouped[.topHit] ?? []
        assertTrue(!topHits.isEmpty, "facebook.com is promoted to Top Hit")
        assertEqual(topHits.first?.title, "Open facebook.com", "Top Hit title is direct URL")
        if case .openURL(let u) = topHits.first?.action {
            assertEqual(u.absoluteString, "https://facebook.com", "Top Hit action is openURL")
        } else {
            print("❌ FAIL: Expected .openURL action for Top Hit")
            exit(1)
        }

        print("✅ WebSearchProvider passed all tests!\n")

        // Test 16: DevToolsProvider
        print("Testing DevToolsProvider...")
        let devProvider = DevToolsProvider.shared

        let uuidResults = devProvider.search(SearchQuery("uuid"))
        assertTrue(!uuidResults.isEmpty, "uuid search returns result")
        assertEqual(uuidResults.first?.category, .devTools, "uuid is devTools category")
        assertTrue(uuidResults.first?.title.contains("-") == true, "uuid formatted with dashes")

        let b64Results = devProvider.search(SearchQuery("b64 hello"))
        assertTrue(!b64Results.isEmpty, "b64 search returns result")
        assertEqual(b64Results.first?.title, "aGVsbG8=", "Base64 encodes 'hello'")

        let b64dResults = devProvider.search(SearchQuery("b64d aGVsbG8="))
        assertTrue(!b64dResults.isEmpty, "b64d search returns result")
        assertEqual(b64dResults.first?.title, "hello", "Base64 decodes 'aGVsbG8='")

        let urlencResults = devProvider.search(SearchQuery("urlencode hello world"))
        assertEqual(urlencResults.first?.title, "hello%20world", "urlencode encodes spaces")

        let urldecResults = devProvider.search(SearchQuery("urldecode hello%20world"))
        assertEqual(urldecResults.first?.title, "hello world", "urldecode decodes %20")

        let epochResults = devProvider.search(SearchQuery("epoch"))
        assertTrue(!epochResults.isEmpty, "epoch returns current timestamp")

        let colorResults = devProvider.search(SearchQuery("#3B82F6"))
        assertTrue(!colorResults.isEmpty, "Hex color matches")
        assertTrue(colorResults.first?.title.contains("#3B82F6") == true, "Color title contains hex")

        let jsonResults = devProvider.search(SearchQuery("json {\"a\":1}"))
        assertTrue(!jsonResults.isEmpty, "json pretty-prints")
        assertTrue(jsonResults.first?.action != nil, "json action is copyToClipboard")

        print("✅ DevToolsProvider passed all tests!\n")

        // Test 17: NetworkInfoProvider & Enhanced TerminalLauncher
        print("Testing NetworkInfoProvider & TerminalLauncher...")
        let localIP = NetworkInfoProvider.shared.localIPv4Address()
        // If connected to network, localIP is non-nil IPv4 string
        if let ip = localIP {
            assertTrue(ip.contains("."), "Local IP contains dots")
        }

        let installedTerminals = TerminalAppOption.installedOptions
        assertTrue(installedTerminals.contains(.terminal), "Apple Terminal is always available")

        let currentTerm = TerminalLauncher.currentTerminal
        assertTrue(TerminalAppOption.allCases.contains(currentTerm), "Current terminal is valid")

        let itermScript = TerminalLauncher.itermScript(for: "git status")
        assertTrue(itermScript.contains("tell application \"iTerm\""), "iTerm script compiles structure")

        // Test 18: Enhanced Quick Actions
        print("Testing Enhanced Quick Actions...")
        let qaProvider = QuickActionsProvider.shared
        let dnsResults = qaProvider.search(SearchQuery("dns"))
        assertTrue(!dnsResults.isEmpty, "DNS search finds Flush DNS Cache")
        assertEqual(dnsResults.first?.title, "Flush DNS Cache", "Top result for dns is Flush DNS Cache")

        let desktopResults = qaProvider.search(SearchQuery("desktop"))
        assertTrue(!desktopResults.isEmpty, "Desktop search finds Show Desktop")
        assertEqual(desktopResults.first?.title, "Show Desktop", "Top result for desktop is Show Desktop")

        let dlResults = qaProvider.search(SearchQuery("downloads"))
        assertTrue(!dlResults.isEmpty, "Downloads search finds Open Downloads")
        assertEqual(dlResults.first?.title, "Open Downloads", "Top result for downloads is Open Downloads")

        let finderWinResults = qaProvider.search(SearchQuery("new finder"))
        assertTrue(!finderWinResults.isEmpty, "New finder search finds New Finder Window")
        assertEqual(finderWinResults.first?.title, "New Finder Window", "Top result for new finder is New Finder Window")

        let ipResults = qaProvider.search(SearchQuery("ip address"))
        assertTrue(!ipResults.isEmpty, "IP search finds IP Address")
        assertEqual(ipResults.first?.title, "IP Address", "Top result for ip is IP Address")
        assertTrue(ipResults.first?.subtitle.contains("Local:") == true, "IP Address subtitle shows Local IP")

        let termFinderResults = qaProvider.search(SearchQuery("terminal here"))
        if TerminalLauncher.activeFinderFolderPath() != nil {
            assertTrue(!termFinderResults.isEmpty, "Terminal here search finds Terminal in Finder Folder when Finder is open")
            assertEqual(termFinderResults.first?.title, "Terminal in Finder Folder", "Top result is Terminal in Finder Folder")
        } else {
            assertTrue(termFinderResults.isEmpty, "Terminal in Finder Folder is hidden when no Finder window is open")
        }

        // Test Sudo Stripping & Privilege Detection
        assertEqual(QuickActionsProvider.stripSudo(from: "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"),
                    "dscacheutil -flushcache; killall -HUP mDNSResponder", "Strips leading and chained sudo")
        assertEqual(QuickActionsProvider.stripSudo(from: "sudo purge"), "purge", "Strips sudo from single command")
        assertEqual(QuickActionsProvider.stripSudo(from: "echo 1 && sudo echo 2"), "echo 1 && echo 2", "Strips chained && sudo")
        assertEqual(QuickActionsProvider.stripSudo(from: "echo 1 || sudo echo 2"), "echo 1 || echo 2", "Strips chained || sudo")
        assertEqual(QuickActionsProvider.stripSudo(from: "cat foo | sudo tee bar"), "cat foo | tee bar", "Strips piped | sudo")
        assertEqual(QuickActionsProvider.stripSudo(from: "sudo -u postgres psql"), "sudo -u postgres psql",
                    "Keeps sudo that carries its own options (stripping would promote -u to the command)")
        assertEqual(QuickActionsProvider.stripSudo(from: "echo \"install sudo now\""), "echo \"install sudo now\"",
                    "Leaves a mid-argument sudo word alone")
        assertEqual(QuickActionsProvider.normalizePrivilegedCommand("admin:sudo purge"), "purge",
                    "normalizePrivilegedCommand strips both the admin: marker and sudo")

        assertTrue(QuickActionsProvider.requiresAdministratorPrivileges(script: "sudo dscacheutil -flushcache"), "sudo prefix requires admin")
        assertTrue(QuickActionsProvider.requiresAdministratorPrivileges(script: "dscacheutil -flushcache; killall -HUP mDNSResponder"), "mDNSResponder requires admin")
        assertTrue(QuickActionsProvider.requiresAdministratorPrivileges(script: "purge"), "purge requires admin")
        assertTrue(QuickActionsProvider.requiresAdministratorPrivileges(script: "sudo purge"), "sudo purge requires admin")
        assertTrue(QuickActionsProvider.requiresAdministratorPrivileges(script: "admin:whoami"), "admin: prefix requires admin")
        assertTrue(!QuickActionsProvider.requiresAdministratorPrivileges(script: "echo hello"), "echo hello does not require admin")
        assertTrue(!QuickActionsProvider.requiresAdministratorPrivileges(script: "pmset sleepnow"), "pmset sleepnow does not require admin")
        assertTrue(!QuickActionsProvider.requiresAdministratorPrivileges(script: "grep mDNSResponder /var/log/system.log"),
                   "Merely mentioning mDNSResponder does not require admin")
        assertTrue(QuickActionsProvider.requiresAdministratorPrivileges(script: "internal:toggle-touchid-sudo"),
                   "Actions flagged requiresAdmin in the action table are detected by script")

        // Every requiresAdmin action must actually route through the privileged path.
        for action in QuickActionsProvider.defaultActions where action.requiresAdmin {
            assertTrue(QuickActionsProvider.requiresAdministratorPrivileges(script: action.script),
                       "Admin action '\(action.name)' is detected as privileged")
        }

        let purgeResults = qaProvider.search(SearchQuery("purge"))
        assertTrue(!purgeResults.isEmpty, "Purge search finds Purge Inactive Memory")
        assertEqual(purgeResults.first?.title, "Purge Inactive Memory", "Top result for purge is Purge Inactive Memory")

        let touchIdResults = qaProvider.search(SearchQuery("touch id sudo"))
        assertTrue(!touchIdResults.isEmpty, "Touch ID sudo search finds Toggle Touch ID for Sudo")
        assertEqual(touchIdResults.first?.title, "Toggle Touch ID for Sudo", "Top result for touch id sudo is Toggle Touch ID for Sudo")

        print("✅ Enhanced Quick Actions passed all tests!\n")

        // Test 19: Universal Recent Projects Provider (Multi-IDE)
        print("Testing RecentProjectsProvider...")
        let discovered = RecentProjectsProvider.discoverAllProjects()
        assertTrue(!discovered.isEmpty, "Discovered >= 1 recent project across installed IDEs")
        if let first = discovered.first {
            assertTrue(!first.name.isEmpty, "First project has valid name")
            assertTrue(!first.displayPath.isEmpty, "First project has valid display path")
            assertTrue(!first.ideName.isEmpty, "First project has IDE tag")
        }

        // Test 20: Process Killer Provider
        print("Testing ProcessKillerProvider...")
        let killer = ProcessKillerProvider.shared

        let hintResults = killer.search(SearchQuery("kill "))
        assertTrue(!hintResults.isEmpty, "kill with trailing space returns hint")
        assertEqual(hintResults.first?.id, "kill-hint", "Returns kill-hint")

        let pidResults = killer.search(SearchQuery("kill 99999"))
        assertTrue(!pidResults.isEmpty, "kill with PID returns result")
        if case .killProcess(let pid, _, _) = pidResults.first?.action {
            assertEqual(pid, 99999, "Kills correct PID 99999")
        } else {
            print("❌ FAIL: Expected .killProcess action for kill 99999")
            exit(1)
        }

        let finderResults = killer.search(SearchQuery("kill Finder"))
        assertTrue(!finderResults.isEmpty, "kill Finder finds running Finder process")
        assertTrue(finderResults.first?.title.contains("Finder") == true, "Title mentions Finder")
        if case .killProcess(_, let name, _) = finderResults.first?.action {
            assertTrue(name.contains("Finder"), "Action target is Finder")
        } else {
            print("❌ FAIL: Expected .killProcess action for kill Finder")
            exit(1)
        }

        print("✅ RecentProjectsProvider & ProcessKillerProvider passed all tests!\n")

        // Test 21: Default Browser Integration
        print("Testing BrowserIntegrationProvider...")
        if let defaultBrowser = BrowserIntegrationProvider.defaultBrowser() {
            assertTrue(!defaultBrowser.name.isEmpty, "Default browser has name")
            assertTrue(!defaultBrowser.bundleID.isEmpty, "Default browser has bundle ID")
        }
        let formattedURL1 = BrowserIntegrationProvider.formatDisplayURL("https://partners.shopify.com/12345/stores")
        assertEqual(formattedURL1, "partners.shopify.com/12345/stores", "Formats clean URL with full path")
        let formattedURL2 = BrowserIntegrationProvider.formatDisplayURL("https://apple.com/")
        assertEqual(formattedURL2, "apple.com", "Strips trailing slash for root URL")
        let formattedURL3 = BrowserIntegrationProvider.formatDisplayURL("https://github.com/pulls?q=is%3Apr")
        assertEqual(formattedURL3, "github.com/pulls?q=is%3Apr", "Preserves query parameters")

        // Browser History Option & ItemType Tests
        assertEqual(BrowserHistoryDays.threeDays.rawValue, 3, "3 days rawValue")
        assertEqual(BrowserHistoryDays.sevenDays.rawValue, 7, "7 days rawValue")
        assertEqual(BrowserHistoryDays.disabled.rawValue, 0, "0 days rawValue")

        let browserProvider = BrowserIntegrationProvider.shared
        let originalLimit = browserProvider.historyLimitDays
        browserProvider.historyLimitDays = .threeDays
        assertEqual(browserProvider.historyLimitDays, .threeDays, "Sets 3 days limit")
        browserProvider.historyLimitDays = .sevenDays
        assertEqual(browserProvider.historyLimitDays, .sevenDays, "Sets 7 days limit")
        browserProvider.historyLimitDays = originalLimit // Restore

        // BrowserItem with .history
        let testHistoryItem = BrowserItem(
            title: "Test History Page",
            urlString: "https://example.com/test",
            itemType: .history,
            browserName: "Google Chrome",
            browserAppPath: "/Applications/Google Chrome.app"
        )
        assertEqual(testHistoryItem.itemType, .history, "ItemType is history")
        assertEqual(testHistoryItem.displayURL, "example.com/test", "Formatted display URL")

        // Test 22: In-Memory Clipboard History
        print("Testing ClipboardHistoryManager...")
        let clipManager = ClipboardHistoryManager.shared
        clipManager.clearHistory()
        clipManager.addEntry(content: "Lightspot ephemeral clipboard test string")
        let entries = clipManager.allEntries()
        assertTrue(!entries.isEmpty, "Clipboard entry was added")
        assertEqual(entries.first?.content, "Lightspot ephemeral clipboard test string", "Content matches")

        let clipSearch = clipManager.search(SearchQuery("clip Lightspot"))
        assertTrue(!clipSearch.isEmpty, "clip search matches clipboard entry")
        clipManager.clearHistory()
        assertTrue(clipManager.allEntries().isEmpty, "clearHistory purges in-memory buffer")

        // Test 23: Quick Text Snippets & Variable Expansion
        print("Testing SnippetsStore...")
        let expanded = SnippetsStore.expandVariables(in: "Date: {{date}}, UUID: {{uuid}}")
        assertTrue(!expanded.contains("{{date}}"), "date placeholder replaced")
        assertTrue(!expanded.contains("{{uuid}}"), "uuid placeholder replaced")

        let snippetSearch = SnippetsStore.shared.search(SearchQuery("date"))
        assertTrue(!snippetSearch.isEmpty, "Snippet search finds Date snippet")

        // `displayOrder` drives the UI. A category missing from it would vanish from the
        // panel entirely, and duplicates would render a section twice.
        assertEqual(ResultCategory.displayOrder.count, ResultCategory.allCases.count,
                    "displayOrder covers every ResultCategory")
        assertEqual(Set(ResultCategory.displayOrder).count, ResultCategory.displayOrder.count,
                    "displayOrder has no duplicates")
        for category in ResultCategory.allCases {
            assertTrue(ResultCategory.displayOrder.contains(category),
                       "\(category.displayName) has a display position")
        }
        assertEqual(ResultCategory.displayOrder.first, .topHit, "Top Hit sorts first")
        assertEqual(ResultCategory.displayOrder.last, .webSearch, "Web Search is the trailing fallback")
        assertTrue(ResultCategory.displayOrder.firstIndex(of: .calculator)!
                   < ResultCategory.displayOrder.firstIndex(of: .applications)!,
                   "Calculator outranks Applications")
        assertTrue(ResultCategory.displayOrder.firstIndex(of: .devTools)!
                   < ResultCategory.displayOrder.firstIndex(of: .shellHistory)!,
                   "Developer Tools outrank Terminal History")

        // The engine renders in displayOrder, not in enum declaration order.
        let orderProbe: [ResultCategory: [SearchResult]] = [
            .webSearch: [SearchResult(id: "w", title: "w", subtitle: "", iconType: .systemSymbol(name: "globe"),
                                      category: .webSearch, score: 10, action: .copyToClipboard("w"))],
            .calculator: [SearchResult(id: "c", title: "c", subtitle: "", iconType: .systemSymbol(name: "equal"),
                                       category: .calculator, score: 90, action: .copyToClipboard("c"))],
            .applications: [SearchResult(id: "a", title: "a", subtitle: "", iconType: .systemSymbol(name: "app"),
                                         category: .applications, score: 95, action: .copyToClipboard("a"))]
        ]
        assertEqual(SearchEngine.orderedCategories(from: orderProbe), [.calculator, .applications, .webSearch],
                    "orderedCategories renders calculator above applications above web search")

        // Regression: FuzzyMatcher's substring tier used String.contains, a Foundation
        // collating search ~31x slower than a byte-wise scan. Verify the replacement
        // agrees with Foundation on the cases the matcher actually sees.
        for (hay, needle) in [("hello world", "lo w"), ("hello", "hello"), ("a", "abc"),
                              ("h\u{e9}llo", "\u{e9}ll"), ("abc", "abcd"), ("aaab", "aab"),
                              ("safari browser", "saf"), ("safari", "zzz")] {
            assertEqual(containsSubstring(hay, needle), hay.contains(needle),
                        "containsSubstring(\"\(hay)\", \"\(needle)\") matches Foundation")
        }
        assertEqual(FuzzyMatcher.score(query: SearchQuery("ari"), targetLower: "safari", targetTokens: ["safari"]), 65,
                    "Substring tier still scores 65")
        assertTrue(FuzzyMatcher.score(query: SearchQuery("zzq"), targetLower: "safari", targetTokens: ["safari"]) == nil,
                   "Non-matching query still scores nil")

        // Regression: `.urlQueryAllowed` leaves &, =, + and ? intact, so a query became
        // part of the URL's structure — "c++" reached the engine as "c  ".
        for (raw, mustNotContain) in [("c++", "q=c++"), ("a&b=c", "q=a&b=c"), ("1+1", "q=1+1")] {
            let webResults = WebSearchProvider.shared.search(SearchQuery(raw))
            guard case .openWebSearch(let url)? = webResults.last?.action else {
                assertTrue(false, "Web search produced a URL for '\(raw)'")
                continue
            }
            assertTrue(!url.absoluteString.contains(mustNotContain),
                       "'\(raw)' is percent-encoded as a query value, not left as URL structure")
            assertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?
                            .queryItems?.first(where: { $0.name == "q" })?.value,
                        raw, "'\(raw)' round-trips through the search URL intact")
        }

        // Custom URL commands share the same encoder.
        let encodedCmd = CustomCommand(name: "Issue", type: .url, target: "https://example.com/s?x=1", keywords: ["iss"])
        assertTrue(encodedCmd.interpolatedTarget(with: "a&b").hasSuffix("q=a%26b"),
                   "Custom URL command encodes & in the interpolated query")

        // Regression: DevTools ids were built from String.hashValue, which is seeded per
        // process, so every launch produced ids that could never match persisted history.
        let b64a = DevToolsProvider.shared.search(SearchQuery("b64 hello"))
        let b64b = DevToolsProvider.shared.search(SearchQuery("b64 hello"))
        assertEqual(b64a.first?.id, b64b.first?.id, "DevTools ids are deterministic for the same input")
        assertTrue(b64a.first?.id.hasPrefix("dev-b64-") == true, "DevTools id keeps its stable prefix")
        assertTrue(DevToolsProvider.shared.search(SearchQuery("b64 world")).first?.id != b64a.first?.id,
                   "DevTools ids still differ between inputs")

        // Regression: clipboard search lowercased every entry's full content per keystroke.
        clipManager.clearHistory()
        clipManager.addEntry(content: "MiXeD CaSe Lightspot Needle " + String(repeating: "x", count: 200_000))
        assertTrue(!clipManager.search(SearchQuery("clip needle")).isEmpty,
                   "Clipboard search matches case-insensitively via the pre-computed field")
        assertEqual(clipManager.allEntries().first?.firstLine.hasPrefix("MiXeD CaSe"), true,
                    "firstLine is derived from the head of a large entry")
        clipManager.clearHistory()

        // Test 24: System Info Provider (Mach/IOKit)
        print("Testing SystemInfoProvider...")
        let sysInfo = SystemInfoProvider.shared.collectSystemInfo()
        assertTrue(!sysInfo.ramTotalGB.isEmpty, "RAM total is reported")
        assertTrue(!sysInfo.uptime.isEmpty, "Uptime is reported")

        let sysResults = SystemInfoProvider.shared.search(SearchQuery("sys"))
        assertTrue(!sysResults.isEmpty, "sys search returns hardware HUD")
        assertEqual(sysResults.first?.id, "system-hud", "HUD result ID is system-hud")

        print("✅ Browser, Clipboard, Snippets, and System HUD passed all tests!\n")

        // Test 25: FirstRunManager
        print("Testing FirstRunManager...")
        @MainActor
        final class MockFirstRunDelegate: FirstRunDelegate {
            var rebuildMenuCallCount = 0
            var alertTitle: String?
            var alertMessage: String?

            func rebuildMenu() {
                rebuildMenuCallCount += 1
            }

            func showAlert(title: String, message: String) {
                alertTitle = title
                alertMessage = message
            }
        }

        let originalFirstRun = UserDefaults.standard.object(forKey: FirstRunManager.userDefaultsKey)
        let originalAutoStart = UserDefaults.standard.object(forKey: "lightspot_auto_start_enabled")

        FirstRunManager.resetFirstRunForTesting()
        assertTrue(FirstRunManager.isFirstRun, "isFirstRun is true after reset")

        FirstRunManager.markFirstRunCompleted()
        assertTrue(!FirstRunManager.isFirstRun, "isFirstRun is false after markFirstRunCompleted")

        FirstRunManager.resetFirstRunForTesting()
        let mockDelegate = MockFirstRunDelegate()
        // promptDelay: -1 skips the UI modal prompt during headless unit tests
        FirstRunManager.handleFirstRunIfNeeded(delegate: mockDelegate, promptDelay: -1)

        assertTrue(!FirstRunManager.isFirstRun, "isFirstRun is false after handleFirstRunIfNeeded")
        assertTrue(AutoStartManager.isEnabled, "AutoStartManager is enabled on first run")
        assertEqual(mockDelegate.rebuildMenuCallCount, 1, "rebuildMenu called on first run")

        // Second run must be a no-op
        FirstRunManager.handleFirstRunIfNeeded(delegate: mockDelegate, promptDelay: -1)
        assertEqual(mockDelegate.rebuildMenuCallCount, 1, "rebuildMenu not called again on subsequent run")

        // Restore original state
        if let original = originalFirstRun {
            UserDefaults.standard.set(original, forKey: FirstRunManager.userDefaultsKey)
        } else {
            FirstRunManager.resetFirstRunForTesting()
        }
        if let originalAuto = originalAutoStart {
            UserDefaults.standard.set(originalAuto, forKey: "lightspot_auto_start_enabled")
        } else {
            UserDefaults.standard.removeObject(forKey: "lightspot_auto_start_enabled")
        }
        print("✅ FirstRunManager passed all tests!\n")
    }
}
