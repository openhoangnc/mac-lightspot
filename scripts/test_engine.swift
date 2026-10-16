import Foundation

// MARK: - Test Runner for Lightspot Core Logic
//
// Build & run:
//   swiftc -o /tmp/test_engine scripts/test_engine.swift \
//       Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift \
//       Sources/Lightspot/System/AutoStartManager.swift Sources/Lightspot/System/SpotlightManager.swift \
//       Sources/Lightspot/System/FirstRunManager.swift \
//       Sources/Lightspot/System/UpdateManager.swift \
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

    /// The text a `.copyToClipboard` result would copy, or nil for any other action.
    static func copiedText(_ result: SearchResult?) -> String? {
        if case .copyToClipboard(let text) = result?.action { return text }
        return nil
    }

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

        // No test may reach api.ipify.org: any lookup a search triggers gets a fixed answer.
        NetworkInfoProvider.shared.resetPublicIPState(fetcher: { completion in completion("203.0.113.7") })

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
        testSpotlightShortcutState()
        testUpdateManager()
        testPublicIPLookupIsOnDemand()
        testHistoryDoesNotPersistCopiedContent()
        testBareClipListsLatestEntries()
        testHistoryDoesNotRecordProcessKills()

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

        // Flag-driven terminals exec their program directly, so a multi-word command
        // must reach them wrapped in a shell, as one argument.
        let program = TerminalLauncher.shellCommandArguments(for: "git status # mine", shell: "/bin/zsh")
        assertEqual(program, ["/bin/zsh", "-l", "-i", "-c", "git status # mine\nexec '/bin/zsh' -l"],
                    "Command runs in an interactive login shell, then the window keeps a shell")
        assertEqual(TerminalLauncher.shellQuoted("it's"), "'it'\\''s'", "Single quotes survive shell quoting")

        assertEqual(TerminalLauncher.openArguments(for: .ghostty, command: "git status", shell: "/bin/zsh"),
                    ["-n", "-b", "com.mitchellh.ghostty", "--args", "-e"] + TerminalLauncher.shellCommandArguments(for: "git status", shell: "/bin/zsh"),
                    "Ghostty: -e then the shell argv")
        assertEqual(TerminalLauncher.openArguments(for: .alacritty, command: "git status", shell: "/bin/zsh"),
                    ["-n", "-b", "org.alacritty", "--args", "-e"] + TerminalLauncher.shellCommandArguments(for: "git status", shell: "/bin/zsh"),
                    "Alacritty: -e then the shell argv")
        assertEqual(TerminalLauncher.openArguments(for: .kitty, command: "git status", shell: "/bin/zsh"),
                    ["-n", "-b", "net.kovidgoyal.kitty", "--args"] + TerminalLauncher.shellCommandArguments(for: "git status", shell: "/bin/zsh"),
                    "kitty: the program is positional (kitty documents no -e)")
        assertEqual(TerminalLauncher.openArguments(for: .wezterm, command: "git status", shell: "/bin/zsh"),
                    ["-n", "-b", "com.github.wez.wezterm", "--args", "start", "--"] + TerminalLauncher.shellCommandArguments(for: "git status", shell: "/bin/zsh"),
                    "WezTerm: start -- then the shell argv")
        for option in [TerminalAppOption.terminal, .iterm2, .warp] {
            assertEqual(TerminalLauncher.openArguments(for: option, command: "ls", shell: "/bin/zsh"), nil,
                        "\(option.displayName) is not driven through open --args")
        }
        for option in TerminalAppOption.allCases {
            if let arguments = TerminalLauncher.openArguments(for: option, command: "ls", shell: "/bin/zsh") {
                // Without -n, `open` only activates a running app and drops --args.
                assertEqual(arguments.first, "-n", "\(option.displayName) launches a new instance so its arguments arrive")
            }
        }

        // Run the wrapper for real: the multi-word command executes, and the trailing
        // `# comment` does not swallow the hand-off to the follow-up shell, which then
        // reads its commands from stdin here.
        let shellRun = Process()
        shellRun.executableURL = URL(fileURLWithPath: "/bin/sh")
        shellRun.arguments = Array(TerminalLauncher.shellCommandArguments(for: "echo lightspot ran # trailing", shell: "/bin/sh").dropFirst())
        let shellIn = Pipe()
        let shellOut = Pipe()
        shellRun.standardInput = shellIn
        shellRun.standardOutput = shellOut
        shellRun.standardError = FileHandle.nullDevice
        do {
            try shellRun.run()
            shellIn.fileHandleForWriting.write("echo lightspot after\n".data(using: .utf8)!)
            try? shellIn.fileHandleForWriting.close()
            let output = String(data: shellOut.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            shellRun.waitUntilExit()
            assertTrue(output.contains("lightspot ran"), "The multi-word command ran (got: \(output))")
            assertTrue(output.contains("lightspot after"), "The window's follow-up shell started after the command (got: \(output))")
        } catch {
            print("❌ FAIL: could not run /bin/sh: \(error)")
            exit(1)
        }

        // Warp cannot be told to run a command, so commands go to Apple Terminal.
        let terminalKey = "lightspot_terminal_app"
        let savedTerminal = UserDefaults.standard.string(forKey: terminalKey)
        TerminalLauncher.currentTerminal = .warp
        assertEqual(TerminalLauncher.commandTerminal, .terminal, "Warp runs commands in Apple Terminal")
        TerminalLauncher.currentTerminal = .terminal
        assertEqual(TerminalLauncher.commandTerminal, .terminal, "Apple Terminal runs its own commands")
        if let savedTerminal {
            UserDefaults.standard.set(savedTerminal, forKey: terminalKey)
        } else {
            UserDefaults.standard.removeObject(forKey: terminalKey)
        }

        assertEqual(TerminalLauncher.warpNewTabURL(path: "/tmp/a&b=c d")?.absoluteString,
                    "warp://action/new_tab?path=/tmp/a%26b%3Dc%20d", "Warp folder URL escapes query delimiters")

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

    // MARK: - Test 26: public IP lookup only when asked for

    /// Polls until `condition` holds or two seconds pass; lookups finish on a background queue.
    static func waitUntil(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while !condition() && Date() < deadline {
            usleep(1_000)
        }
        return condition()
    }

    static func testPublicIPLookupIsOnDemand() {
        print("Testing public IP lookup is on demand...")
        let network = NetworkInfoProvider.shared
        let qa = QuickActionsProvider.shared
        let ipId = "action-ip-address"

        let gate = DispatchSemaphore(value: 0)
        network.resetPublicIPState(fetcher: { completion in
            gate.wait()
            completion("203.0.113.7")
        })
        assertEqual(network.publicIPState(), .notRequested, "Nothing is looked up before it is asked for")

        // The decision itself: the query must name the IP and match strongly.
        assertTrue(QuickActionsProvider.queryAsksForPublicIP(SearchQuery("ip"), score: 95), "'ip' asks for the IP")
        assertTrue(QuickActionsProvider.queryAsksForPublicIP(SearchQuery("My IP"), score: 95), "'My IP' asks for the IP")
        assertTrue(QuickActionsProvider.queryAsksForPublicIP(SearchQuery("ipv4"), score: 95), "'ipv4' asks for the IP")
        assertTrue(!QuickActionsProvider.queryAsksForPublicIP(SearchQuery("ip s"), score: 40), "A subsequence match is not enough")
        assertTrue(!QuickActionsProvider.queryAsksForPublicIP(SearchQuery("lo"), score: 90.25), "A keyword prefix without 'ip' is not enough")
        assertTrue(!QuickActionsProvider.queryAsksForPublicIP(SearchQuery("local ip"), score: 95), "'local ip' does not ask for the public IP")

        // Loose matches still show the row with the local IP, but send nothing.
        for query in ["i", "lo", "loc", "ad", "address", "network", "my", "pu", "public", "local ip", "ipa"] {
            let row = qa.search(SearchQuery(query)).first { $0.id == ipId }
            if let row {
                assertTrue(row.subtitle.hasPrefix("Local: "), "'\(query)' shows the local IP")
                assertTrue(!row.subtitle.contains("Fetching"), "'\(query)' does not claim a lookup")
            }
        }
        for query in ["i", "lo", "ad", "network", "local ip"] {
            assertTrue(qa.search(SearchQuery(query)).contains { $0.id == ipId }, "'\(query)' matches the IP row, so the check above is meaningful")
        }
        _ = SearchEngine.shared.searchImmediate(SearchQuery("lo"))
        assertEqual(network.lookupCount, 0, "Loose matches never contact the network")

        // A query that names the IP starts one background lookup; the row says so.
        let fetching = qa.search(SearchQuery("my ip")).first { $0.id == ipId }
        assertTrue(fetching?.subtitle.contains("Public: Fetching...") == true, "Strong match shows Fetching...")
        assertTrue(fetching?.subtitle.hasPrefix("Local: ") == true, "Local IP shows while the lookup runs")
        assertEqual(network.lookupCount, 1, "Strong match starts a lookup")
        if case .runQuickAction(let script, _)? = fetching?.action {
            assertEqual(script, "internal:copy-ip", "IP row action carries no address")
        } else {
            assertTrue(false, "IP row action is the internal:copy-ip quick action")
        }

        _ = qa.search(SearchQuery("ip"))
        _ = qa.search(SearchQuery("ip address"))
        assertEqual(network.lookupCount, 1, "Keystrokes during a lookup share it")

        gate.signal()
        assertTrue(waitUntil { network.cachedPublicIPv4Address() != nil }, "Lookup completes")
        let done = qa.search(SearchQuery("ip")).first { $0.id == ipId }
        assertTrue(done?.subtitle.contains("Public: 203.0.113.7") == true, "Row shows the looked-up address")
        let loose = qa.search(SearchQuery("lo")).first { $0.id == ipId }
        assertTrue(loose?.subtitle.contains("Public: 203.0.113.7") == true, "A cached address is shown without a lookup")
        assertEqual(network.lookupCount, 1, "A fresh address is not looked up again")

        // Failure: the row says so, typing does not retry, ↵ (force) does.
        network.resetPublicIPState(fetcher: { completion in completion(nil) })
        _ = qa.search(SearchQuery("ip"))
        assertTrue(waitUntil { network.publicIPState() == .unavailable }, "Failed lookup is reported")
        let failed = qa.search(SearchQuery("ip")).first { $0.id == ipId }
        assertTrue(failed?.subtitle.contains("Public: Unavailable") == true, "Row shows Unavailable after a failure")
        assertEqual(network.lookupCount, 1, "Typing does not retry inside the backoff")
        let retried = DispatchSemaphore(value: 0)
        network.requestPublicIPv4Address(force: true) { _ in retried.signal() }
        assertTrue(retried.wait(timeout: .now() + 2) == .success, "Forced lookup reports back")
        assertEqual(network.lookupCount, 2, "↵ retries despite the backoff")

        assertTrue(NetworkInfoProvider.isPlausibleIPAddress("203.0.113.7"), "IPv4 is accepted")
        assertTrue(NetworkInfoProvider.isPlausibleIPAddress("2001:db8::1"), "IPv6 is accepted")
        assertTrue(!NetworkInfoProvider.isPlausibleIPAddress("<html>login</html>"), "A captive portal page is rejected")
        assertTrue(!NetworkInfoProvider.isPlausibleIPAddress(""), "Empty body is rejected")

        network.resetPublicIPState(fetcher: { completion in completion("203.0.113.7") })
        print("✅ Public IP lookup passed all tests!\n")
    }

    // MARK: - Test 27: search history never stores copied content

    static func testHistoryDoesNotPersistCopiedContent() {
        print("Testing search history does not persist copied content...")
        let history = SearchHistoryManager.shared
        history.reset()
        let secret = "eyJhbGciOiJIUzI1NiJ9.c2VjcmV0LXBheWxvYWQ.signature"

        // Clipboard history: not recorded at all.
        let clip = ClipboardHistoryManager.shared
        clip.clearHistory()
        clip.addEntry(content: secret)
        let clipResult = clip.search(SearchQuery("clip eyj")).first
        assertEqual(clipResult?.category, .clipboard, "Clipboard search yields a clipboard result")
        if let clipResult {
            history.recordSelection(result: clipResult, query: "clip eyj")
            assertTrue(history.itemRecord(for: clipResult.id) == nil, "Clipboard selection leaves no ranking stats")
        }
        clip.clearHistory()

        // Dev tools and calculator: derived from the query, not recorded at all.
        let devResults = DevToolsProvider.shared.search(SearchQuery("sha256 \(secret)"))
            + DevToolsProvider.shared.search(SearchQuery("b64 \(secret)"))
        assertTrue(!devResults.isEmpty, "Dev tools produce results to select")
        for result in devResults {
            history.recordSelection(result: result, query: "sha256 \(secret)")
            assertTrue(history.itemRecord(for: result.id) == nil, "\(result.id) leaves no ranking stats")
        }
        if let dev = devResults.first {
            let promoted = SearchResult(
                id: "top-\(dev.id)", title: dev.title, subtitle: dev.subtitle, iconType: dev.iconType,
                category: .topHit, score: dev.score, action: dev.action, promotedFrom: .devTools
            )
            history.recordSelection(result: promoted, query: secret)
            assertTrue(history.itemRecord(for: dev.id) == nil, "A dev tool promoted to Top Hit is not recorded either")
        }
        let calc = SearchEngine.shared.searchImmediate(SearchQuery("1337*42"))[.calculator]?.first
        assertTrue(calc != nil, "Calculator produces a result to select")
        if let calc {
            history.recordSelection(result: calc, query: "1337*42")
            assertTrue(history.itemRecord(for: calc.id) == nil, "Calculator selection leaves no ranking stats")
        }
        assertTrue(history.entries().isEmpty, "Clipboard, dev tools and calculator leave no history entries")

        // Other copy results keep ranking stats, but no entry holding the copied text.
        history.recordSelection(
            itemId: "snippet-test",
            title: "Signature",
            subtitle: secret,
            category: .snippets,
            iconType: .systemSymbol(name: "text.quote"),
            action: .copyToClipboard(secret),
            query: "sig"
        )
        assertEqual(history.itemRecord(for: "snippet-test")?.totalCount, 1, "Snippet selection keeps ranking stats")
        assertTrue(history.rankingBoost(for: "snippet-test", query: SearchQuery("sig")) > 0, "Snippet still gets its ranking boost")
        assertTrue(history.entries().isEmpty, "Snippet selection stores no replayable entry")
        assertEqual(SearchHistoryManager.retention(itemId: "system-hud", category: .quickActions, action: .copyToClipboard("CPU ...")),
                    .statsOnly, "Hardware HUD keeps stats only")

        // The IP row is replayable, but stored without the addresses in its live subtitle.
        let ipRow = SearchResult(
            id: "top-action-ip-address", title: "IP Address",
            subtitle: "Local: 192.0.2.10 · Public: 203.0.113.7 · Press ↵ to copy",
            iconType: .systemSymbol(name: "network"), category: .topHit, score: 95,
            action: .runQuickAction(script: "internal:copy-ip", usesOsascript: false), promotedFrom: .quickActions
        )
        history.recordSelection(result: ipRow, query: "ip")
        let ipEntry = history.entries().first
        assertEqual(ipEntry?.itemId, "action-ip-address", "IP Address selection is recorded")
        assertTrue(ipEntry?.subtitle.contains("203.0.113.7") == false, "History subtitle omits the public IP")
        assertTrue(ipEntry?.subtitle.contains("192.0.2.10") == false, "History subtitle omits the local IP")

        // What reached UserDefaults (persisted asynchronously) holds none of it.
        let key = "lightspot_search_history"
        assertTrue(waitUntil {
            UserDefaults.standard.data(forKey: key).map { String(decoding: $0, as: UTF8.self).contains("action-ip-address") } ?? false
        }, "History was persisted")
        let stored = UserDefaults.standard.data(forKey: key).map { String(decoding: $0, as: UTF8.self) } ?? ""
        assertTrue(!stored.contains("eyJhbGciOiJIUzI1NiJ9"), "Persisted history holds no copied secret")
        assertTrue(!stored.contains("1337"), "Persisted history holds no calculator input")
        if let calcTitle = calc?.title {
            assertTrue(!stored.contains(calcTitle), "Persisted history holds no calculator output")
        }
        assertTrue(!stored.contains("203.0.113.7"), "Persisted history holds no public IP")

        // History written by an earlier version (or restored from its backup) is scrubbed.
        let legacyCopy = SearchHistoryEntry(
            itemId: "dev-jwt-abc", query: "jwt \(secret)", title: secret, subtitle: "JWT",
            category: .devTools, iconType: .systemSymbol(name: "key"), action: .copyToClipboard(secret)
        )
        let legacySnippet = SearchHistoryEntry(
            itemId: "snippet-old", query: "sig", title: "Signature", subtitle: "Signature",
            category: .snippets, iconType: .systemSymbol(name: "text.quote"), action: .copyToClipboard(secret)
        )
        let legacyIP = SearchHistoryEntry(
            itemId: "action-ip-address", query: "ip", title: "IP Address",
            subtitle: "Local: 192.0.2.10 · Public: 203.0.113.7 · Press ↵ to copy",
            category: .quickActions, iconType: .systemSymbol(name: "network"),
            action: .runQuickAction(script: "internal:copy-ip", usesOsascript: false)
        )
        let legacyApp = SearchHistoryEntry(
            itemId: "app-com.apple.Terminal", query: "term", title: "Terminal", subtitle: "Application",
            category: .applications, iconType: .systemSymbol(name: "terminal"), action: .launchApp(path: "/System/Applications/Utilities/Terminal.app")
        )
        let usage = ItemUsageRecord(totalCount: 1, lastSelected: Date())
        history.restore(
            entries: [legacyCopy, legacySnippet, legacyIP, legacyApp],
            stats: ["calc-1337*42": usage, "dev-jwt-abc": usage, "clip-123": usage, "snippet-old": usage, "app-com.apple.Terminal": usage]
        )
        let restored = history.entries()
        assertEqual(restored.map(\.itemId), ["action-ip-address", "app-com.apple.Terminal"], "Only replayable, content-free entries survive")
        assertTrue(restored.first?.subtitle.contains("203.0.113.7") == false, "Legacy IP subtitle is rewritten")
        assertTrue(history.itemRecord(for: "calc-1337*42") == nil, "Legacy calculator stats are dropped")
        assertTrue(history.itemRecord(for: "dev-jwt-abc") == nil, "Legacy dev-tools stats are dropped")
        assertTrue(history.itemRecord(for: "clip-123") == nil, "Legacy clipboard stats are dropped")
        assertTrue(history.itemRecord(for: "snippet-old") != nil, "Snippet ranking stats are kept")
        assertTrue(history.itemRecord(for: "app-com.apple.Terminal") != nil, "App ranking stats are kept")

        history.reset()
        print("✅ Search history privacy passed all tests!\n")
    }

    // MARK: - Test 28: bare `clip` lists the clipboard

    static func testBareClipListsLatestEntries() {
        print("Testing bare clip lists latest clipboard entries...")
        let clip = ClipboardHistoryManager.shared
        clip.clearHistory()
        for index in 1...10 {
            clip.addEntry(content: "Lightspot bare clip entry \(index)")
        }

        for query in ["clip", "Clip", "clipboard", "clip "] {
            let results = clip.search(SearchQuery(query))
            assertEqual(results.count, 8, "'\(query)' lists the latest 8 entries")
            assertEqual(results.first?.title, "Lightspot bare clip entry 10", "'\(query)' lists the newest entry first")
            assertTrue(results.allSatisfy { $0.category == .clipboard && $0.score == 95 }, "'\(query)' rows are clipboard rows at 95")
        }

        let filtered = clip.search(SearchQuery("clip entry 7"))
        assertEqual(filtered.first?.title, "Lightspot bare clip entry 7", "'clip <text>' still filters the entries")

        clip.clearHistory()
        assertTrue(clip.search(SearchQuery("clip")).isEmpty, "Bare clip with an empty clipboard history shows nothing")
        print("✅ Bare clip passed all tests!\n")
    }

    // MARK: - Test 31: process kills are never replayable from history

    static func testHistoryDoesNotRecordProcessKills() {
        print("Testing search history does not record process kills...")
        let history = SearchHistoryManager.shared
        history.reset()

        // A real `kill <pid>` result, as selected and as promoted to Top Hit.
        // Deliberately not this process's own PID: ProcessKillerProvider refuses to
        // offer killing Lightspot itself (`isProtected`), so a short-lived child
        // stands in for a real, killable target.
        let victim = Process()
        victim.executableURL = URL(fileURLWithPath: "/bin/sleep")
        victim.arguments = ["30"]
        try? victim.run()
        let pid = victim.processIdentifier
        assertTrue(pid > 1 && pid != getpid(), "The stand-in target is a real, unprotected PID")
        let pidResult = ProcessKillerProvider.shared.search(SearchQuery("kill \(pid)"))
            .first { $0.id == "kill-pid-\(pid)" }
        assertTrue(pidResult != nil, "kill <pid> yields a kill-pid result")
        if let pidResult {
            history.recordSelection(result: pidResult, query: "kill \(pid)")
            let promoted = SearchResult(
                id: "top-\(pidResult.id)", title: pidResult.title, subtitle: pidResult.subtitle,
                iconType: pidResult.iconType, category: .topHit, score: pidResult.score,
                action: pidResult.action, promotedFrom: .quickActions
            )
            history.recordSelection(result: promoted, query: "kill \(pid)")
            assertTrue(history.itemRecord(for: pidResult.id) == nil, "kill-pid selection leaves no ranking stats")
        }

        // The other process-killer ids, and a force kill.
        for id in ["kill-app-4242", "kill-cli-4242", "kill-port-3000-4242"] {
            history.recordSelection(
                itemId: id, title: "Kill node", subtitle: "PID: 4242", category: .quickActions,
                iconType: .systemSymbol(name: "terminal.fill"),
                action: .killProcess(pid: 4242, name: "node", force: id == "kill-cli-4242"),
                query: "kill node"
            )
            assertTrue(history.itemRecord(for: id) == nil, "\(id) selection leaves no ranking stats")
        }
        assertEqual(SearchHistoryManager.retention(itemId: "renamed-kill", category: .quickActions,
                                                   action: .killProcess(pid: 4242, name: "node", force: false)),
                    HistoryRetention.none, "Any kill action is unrecorded, whatever its id")
        assertTrue(history.entries().isEmpty, "Process kills leave no replayable history entry")

        // The `kill` hint carries no PID and keeps its ranking stats.
        let hint = ProcessKillerProvider.shared.search(SearchQuery("kill")).first
        assertEqual(hint?.id, "kill-hint", "Bare kill yields the hint row")
        if let hint {
            history.recordSelection(result: hint, query: "kill")
            assertEqual(history.itemRecord(for: "kill-hint")?.totalCount, 1, "kill-hint keeps ranking stats")
            assertTrue(history.entries().isEmpty, "kill-hint stores no replayable entry")
        }

        let key = "lightspot_search_history"
        assertTrue(waitUntil {
            UserDefaults.standard.data(forKey: key).map { String(decoding: $0, as: UTF8.self).contains("kill-hint") } ?? false
        }, "History was persisted")
        let stored = UserDefaults.standard.data(forKey: key).map { String(decoding: $0, as: UTF8.self) } ?? ""
        assertTrue(!stored.contains("killProcess"), "Persisted history holds no kill action")
        assertTrue(!stored.contains("kill-pid-") && !stored.contains("kill-port-"), "Persisted history holds no PID-keyed ids")

        // Kill entries written by an earlier version (or restored from its backup) are scrubbed.
        let legacyKill = SearchHistoryEntry(
            itemId: "kill-pid-4242", query: "kill 4242", title: "Terminate node (PID: 4242)",
            subtitle: "Press ↵ to terminate gracefully · ⌥↵ to force kill", category: .quickActions,
            iconType: .systemSymbol(name: "gearshape.2.fill"),
            action: .killProcess(pid: 4242, name: "node", force: false)
        )
        let legacyPortKill = SearchHistoryEntry(
            itemId: "kill-port-3000-4242", query: "kill :3000", title: "Kill node on Port :3000",
            subtitle: "PID: 4242", category: .quickActions,
            iconType: .systemSymbol(name: "network.badge.shield.half.filled"),
            action: .killProcess(pid: 4242, name: "node", force: true)
        )
        let legacyApp = SearchHistoryEntry(
            itemId: "app-com.apple.Terminal", query: "term", title: "Terminal", subtitle: "Application",
            category: .applications, iconType: .systemSymbol(name: "terminal"), action: .launchApp(path: "/System/Applications/Utilities/Terminal.app")
        )
        let usage = ItemUsageRecord(totalCount: 1, lastSelected: Date())
        history.restore(
            entries: [legacyKill, legacyPortKill, legacyApp],
            stats: [
                "kill-pid-4242": usage, "kill-app-4242": usage, "kill-cli-4242": usage,
                "kill-port-3000-4242": usage, "kill-hint": usage, "app-com.apple.Terminal": usage,
            ]
        )
        assertEqual(history.entries().map(\.itemId), ["app-com.apple.Terminal"], "Legacy kill entries are dropped")
        for id in ["kill-pid-4242", "kill-app-4242", "kill-cli-4242", "kill-port-3000-4242"] {
            assertTrue(history.itemRecord(for: id) == nil, "Legacy \(id) stats are dropped")
        }
        assertTrue(history.itemRecord(for: "kill-hint") != nil, "kill-hint ranking stats are kept")
        assertTrue(history.itemRecord(for: "app-com.apple.Terminal") != nil, "App ranking stats are kept")

        victim.terminate()
        history.reset()
        print("✅ Process kill history passed all tests!\n")
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

        // Regression: the bare 0x/0b literal branches ran first, tried to parse "ff in dec"
        // as hex, failed and returned nil, so the README's own examples converted to nothing.
        assertEqual(ConversionEngine.convert("0xFF in dec")?.value, "255", "0xFF in dec converts to 255")
        assertEqual(ConversionEngine.convert("0b1010 in dec")?.value, "10", "0b1010 in dec converts to 10")
        assertEqual(ConversionEngine.convert("0xFF in bin")?.value, "0b11111111", "0xFF in bin converts to binary")
        assertEqual(ConversionEngine.convert("0b1010 to hex")?.value, "0xA", "0b1010 to hex converts to hex")
        assertEqual(ConversionEngine.convert("0XFF IN DEC")?.value, "255", "Prefixed base conversion is case-insensitive")
        assertEqual(ConversionEngine.convert("0xFF in dec")?.subtitle, "0xFF in decimal = 255", "Subtitle keeps the input as typed")
        assertEqual(ConversionEngine.convert("0b1010")?.value, "10", "Bare 0b1010 still converts")
        assertTrue(ConversionEngine.convert("0xZZ in dec") == nil, "Invalid hex digits do not convert")
        assertTrue(ConversionEngine.convert("10km in mi")?.value.contains("mi") == true, "Unit 'in' conversions still reach the unit engine")

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

        // Regression: "b64 " was matched before "b64 decode ", so decode encoded the word "decode".
        assertEqual(devProvider.search(SearchQuery("b64 decode aGVsbG8=")).first?.title, "hello", "b64 decode decodes")
        assertEqual(devProvider.search(SearchQuery("base64 decode aGVsbG8=")).first?.title, "hello", "base64 decode decodes")
        assertTrue(devProvider.search(SearchQuery("b64 decode")).isEmpty, "Bare 'b64 decode' does not encode the word 'decode'")
        assertTrue(devProvider.search(SearchQuery("b64 decode !!!")).isEmpty, "Invalid Base64 after 'b64 decode' does not fall through to encode")
        assertEqual(devProvider.search(SearchQuery("base64 hi")).first?.title, "aGk=", "base64 <text> still encodes")

        // Regression: "hash sha256 <text>" hashed the literal string "sha256 <text>".
        let helloSHA256 = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        let helloMD5 = "5d41402abc4b2a76b9719d911017c592"
        let helloSHA1 = "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d"
        let allHashes = devProvider.search(SearchQuery("hash hello"))
        assertEqual(allHashes.map(\.title), [helloSHA256, helloMD5, helloSHA1], "hash <text> returns SHA-256, MD5 and SHA-1")
        let sha256Only = devProvider.search(SearchQuery("hash sha256 hello"))
        assertEqual(sha256Only.map(\.title), [helloSHA256], "hash sha256 <text> returns only SHA-256 of <text>")
        assertEqual(copiedText(sha256Only.first), helloSHA256, "hash sha256 copies the digest")
        assertEqual(devProvider.search(SearchQuery("hash md5 hello")).map(\.title), [helloMD5], "hash md5 <text> returns only MD5")
        assertEqual(devProvider.search(SearchQuery("hash SHA1 hello")).map(\.title), [helloSHA1], "hash SHA1 <text> is case-insensitive")
        assertEqual(devProvider.search(SearchQuery("hash md5 hello world")).first?.subtitle, "MD5 · 'hello world'", "Algorithm subcommand keeps spaces in the text")
        assertTrue(devProvider.search(SearchQuery("hash sha256")).isEmpty, "hash sha256 with no text does not hash the algorithm name")

        // Regression: only the JWT payload was decoded; the README promises the header too.
        let jwtToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        let jwtResults = devProvider.search(SearchQuery("jwt \(jwtToken)"))
        assertEqual(jwtResults.map(\.title), ["Decoded JWT Payload", "Decoded JWT Header"], "jwt shows payload then header")
        assertTrue(copiedText(jwtResults.first)?.contains("\"name\" : \"John Doe\"") == true, "JWT payload row copies the pretty payload")
        assertTrue(copiedText(jwtResults.last)?.contains("\"alg\" : \"HS256\"") == true, "JWT header row copies the pretty header")
        assertTrue(jwtResults.allSatisfy { $0.id.hasPrefix("dev-jwt-") }, "Both JWT rows keep the prefix the preview pane keys on")
        assertTrue(jwtResults.first?.id != jwtResults.last?.id, "JWT payload and header rows have distinct ids")
        assertEqual(devProvider.search(SearchQuery(jwtToken)).count, 2, "A raw token also decodes both parts")
        let otherJWT = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI0MiJ9.c2ln"
        assertTrue(devProvider.search(SearchQuery(otherJWT)).first?.id != jwtResults.first?.id,
                   "Tokens sharing a header get different ids")

        // Regression: the README promised HEX, RGB and HSL copying; only HEX was offered.
        let swatch = devProvider.search(SearchQuery("#3498db"))
        assertEqual(swatch.count, 3, "Colour returns HEX, RGB and HSL rows")
        assertEqual(swatch.first?.title, "#3498DB · rgb(52, 152, 219) · hsl(204, 70%, 53%)", "Colour title shows HEX, RGB and HSL")
        assertEqual(swatch.map { copiedText($0) ?? "" }, ["#3498DB", "rgb(52, 152, 219)", "hsl(204, 70%, 53%)"], "Each colour row copies its own format")
        assertTrue(swatch.allSatisfy { $0.id.hasPrefix("dev-color-#3498DB") }, "Every colour row id starts with the HEX the swatch reads")
        assertEqual(Set(swatch.map(\.id)).count, 3, "Colour rows have distinct ids")
        assertEqual(copiedText(devProvider.search(SearchQuery("rgb(52, 152, 219)")).last), "hsl(204, 70%, 53%)", "rgb() input also offers HSL")
        assertEqual(copiedText(devProvider.search(SearchQuery("#ff00ff")).last), "hsl(300, 100%, 50%)", "Magenta hue wraps to 300, not -60")
        assertEqual(copiedText(devProvider.search(SearchQuery("#fff")).last), "hsl(0, 0%, 100%)", "Achromatic colours have zero hue and saturation")
        assertEqual(copiedText(devProvider.search(SearchQuery("#3498DB80")).last), "hsla(204, 70%, 53%, 0.50)", "Alpha carries into hsla()")

        // Regression: README says epoch converts "vice-versa"; only epoch -> date existed.
        let zoned = devProvider.search(SearchQuery("epoch 2024-01-15T10:30:00Z"))
        assertEqual(zoned.first?.title, "1705314600", "ISO 8601 date with zone converts to epoch seconds")
        assertEqual(copiedText(zoned.first), "1705314600", "Date -> epoch copies the seconds")
        assertEqual(devProvider.search(SearchQuery("epoch 2024-01-15T17:30:00+07:00")).first?.title, "1705314600", "A numeric zone offset is honoured")
        var localParts = DateComponents()
        (localParts.year, localParts.month, localParts.day, localParts.hour, localParts.minute) = (2024, 1, 15, 10, 30)
        let localEpoch = Int64(Calendar.current.date(from: localParts)!.timeIntervalSince1970)
        assertEqual(devProvider.search(SearchQuery("epoch 2024-01-15 10:30")).first?.title, "\(localEpoch)", "Zone-less date-time is read in local time")
        assertEqual(devProvider.search(SearchQuery("epoch 2024-01-15T10:30")).first?.title, "\(localEpoch)", "A T separator works too")
        (localParts.hour, localParts.minute) = (0, 0)
        let midnightEpoch = Int64(Calendar.current.date(from: localParts)!.timeIntervalSince1970)
        assertEqual(devProvider.search(SearchQuery("epoch 2024-01-15")).first?.title, "\(midnightEpoch)", "Bare date is local midnight")
        assertTrue(devProvider.search(SearchQuery("epoch 2024-02-30")).isEmpty, "Impossible dates do not convert")
        assertTrue(devProvider.search(SearchQuery("epoch hello")).isEmpty, "Non-dates do not convert")
        assertTrue(devProvider.search(SearchQuery("epoch 1700000000")).first?.id == "dev-epoch-1700000000", "Epoch -> date still works")

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

        // JetBrains config folders map to products by their name prefix.
        let jetBrainsCases: [(folder: String, name: String, firstID: String)] = [
            ("IntelliJIdea2025.2", "IntelliJ IDEA", "com.jetbrains.intellij"),
            ("IdeaIC2024.3", "IntelliJ IDEA CE", "com.jetbrains.intellij.ce"),
            ("PyCharm2025.1", "PyCharm", "com.jetbrains.pycharm"),
            ("PyCharmCE2024.3", "PyCharm CE", "com.jetbrains.pycharm.ce"),
            ("WebStorm2024.1", "WebStorm", "com.jetbrains.WebStorm"),
            ("GoLand2024.1", "GoLand", "com.jetbrains.goland"),
            ("CLion2024.1", "CLion", "com.jetbrains.CLion"),
            ("RustRover2024.2", "RustRover", "com.jetbrains.rustrover"),
            ("Rider2024.3", "Rider", "com.jetbrains.rider"),
            ("PhpStorm2025.1", "PhpStorm", "com.jetbrains.PhpStorm"),
            ("DataGrip2024.3", "DataGrip", "com.jetbrains.datagrip"),
            ("RubyMine2024.3", "RubyMine", "com.jetbrains.rubymine"),
            ("DataSpell2024.1", "DataSpell", "com.jetbrains.dataspell"),
            ("AndroidStudio2026.2.1", "Android Studio", "com.google.android.studio"),
            ("AndroidStudioPreview2026.3", "Android Studio Preview", "com.google.android.studio-EAP"),
        ]
        for testCase in jetBrainsCases {
            let product = RecentProjectsProvider.jetBrainsProduct(forFolder: testCase.folder)
            assertEqual(product?.name, testCase.name, "\(testCase.folder) is \(testCase.name)")
            assertEqual(product?.bundleIDs.first, testCase.firstID, "\(testCase.folder) prefers \(testCase.firstID)")
        }
        for folder in ["Toolbox", "consentOptions", "Chrome", "2024.1"] {
            assertEqual(RecentProjectsProvider.jetBrainsProduct(forFolder: folder), nil, "\(folder) is not an IDE config folder")
        }

        let ideaIDs = ["com.jetbrains.intellij", "com.jetbrains.intellij.ce"]
        assertEqual(RecentProjectsProvider.resolveInstalledBundleID(ideaIDs, isInstalled: { $0 == "com.jetbrains.intellij.ce" }),
                    "com.jetbrains.intellij.ce", "Falls through to the Community edition when only it is installed")
        assertEqual(RecentProjectsProvider.resolveInstalledBundleID(ideaIDs, isInstalled: { _ in true }),
                    "com.jetbrains.intellij", "Prefers the first candidate when several are installed")
        assertEqual(RecentProjectsProvider.resolveInstalledBundleID(["com.jetbrains.CLion"], isInstalled: { $0 == "com.jetbrains.CLion-EAP" }),
                    "com.jetbrains.CLion-EAP", "Finds an EAP build")
        assertEqual(RecentProjectsProvider.resolveInstalledBundleID(["com.jetbrains.CLion"], isInstalled: { _ in true }),
                    "com.jetbrains.CLion", "Prefers the stable build over EAP")
        assertEqual(RecentProjectsProvider.resolveInstalledBundleID(["com.jetbrains.rider"], isInstalled: { _ in false }), nil,
                    "No bundle ID when the IDE is not installed")

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

        // Protected processes are never offered.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        assertTrue(ProcessKillerProvider.isProtected(pid: 0, name: "kernel_task"), "kernel_task is protected")
        assertTrue(ProcessKillerProvider.isProtected(pid: 1, name: "launchd"), "launchd is protected")
        assertTrue(ProcessKillerProvider.isProtected(pid: ownPID, name: "test_engine"), "Lightspot's own PID is protected")
        assertTrue(ProcessKillerProvider.isProtected(pid: 54321, name: "WindowServer"), "WindowServer is protected by name")
        assertTrue(ProcessKillerProvider.isProtected(pid: 54321, name: "loginwindow"), "loginwindow is protected by name")
        assertTrue(ProcessKillerProvider.isProtected(pid: -1, name: "Process -1"), "kill(-1) would signal every process")
        assertTrue(!ProcessKillerProvider.isProtected(pid: 54321, name: "node"), "Ordinary processes are offered")

        func killedPIDs(_ query: String) -> [Int32] {
            killer.search(SearchQuery(query)).compactMap {
                if case .killProcess(let pid, _, _) = $0.action { return pid }
                return nil
            }
        }
        killer.scanCLIProcesses()
        assertTrue(!killedPIDs("kill launchd").contains(1), "kill launchd does not offer PID 1")
        assertTrue(!killedPIDs("kill 1").contains(1), "kill 1 does not offer PID 1")
        assertTrue(!killedPIDs("kill -1").contains(-1), "kill -1 does not offer PID -1")
        assertTrue(!killedPIDs("kill \(ownPID)").contains(ownPID), "Lightspot's own PID is not offered")
        assertTrue(!killer.search(SearchQuery("kill windowserver")).contains(where: { $0.title.contains("WindowServer") }),
                   "WindowServer is not offered")

        // Port lookups list listeners only, named by their command.
        assertTrue(ProcessKillerProvider.listeningPortsArguments.contains("-sTCP:LISTEN"), "lsof is restricted to listening sockets")
        let lsofSample = "p100\ncnode\nf5\nn*:3000\nf6\nn[::1]:3000\np200\ncpostgres\nf7\nn127.0.0.1:5432\nf8\nn127.0.0.1:50990->127.0.0.1:3000\n"
        assertEqual(ProcessKillerProvider.parseListeningPorts(lsofSample), [
            3000: [ProcessKillerProvider.PortListener(pid: 100, command: "node")],
            5432: [ProcessKillerProvider.PortListener(pid: 200, command: "postgres")],
        ], "Parses lsof -F output, de-duplicates IPv4/IPv6 and skips connected sockets")

        // Live: an nc server listens, a second nc connects as a client. Only the server
        // is offered, and under its command name rather than "Port :N Process".
        let probe = socket(AF_INET, SOCK_STREAM, 0)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        var addressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                bind(probe, generic, addressLength) == 0 && getsockname(probe, generic, &addressLength) == 0
            }
        }
        close(probe)
        assertTrue(bound, "Found a free port")
        let livePort = UInt16(bigEndian: address.sin_port)

        func netcat(_ arguments: [String]) -> Process {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
            process.arguments = arguments
            process.standardInput = Pipe()  // held open so nc keeps its socket
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            return process
        }
        let server = netcat(["-l", "127.0.0.1", String(livePort)])
        let client = netcat(["127.0.0.1", String(livePort)])
        do {
            try server.run()
            Thread.sleep(forTimeInterval: 0.4)
            try client.run()
            Thread.sleep(forTimeInterval: 0.4)
            let listeners = killer.scanListeningPorts()[livePort] ?? []
            assertEqual(listeners.map(\.pid), [server.processIdentifier], "Only the listening process is found on :\(livePort)")
            let liveResults = killer.search(SearchQuery("kill :\(livePort)"))
            let serverRow = liveResults.first(where: { $0.id == "kill-port-\(livePort)-\(server.processIdentifier)" })
            assertEqual(serverRow?.title, "Kill nc on Port :\(livePort)", "A CLI listener is titled by its command")
            assertTrue(!killedPIDs("kill :\(livePort)").contains(client.processIdentifier), "kill :port does not offer the client")
        } catch {
            print("⚠️  Skipped live port test: could not start nc: \(error)")
        }
        for process in [client, server] where process.isRunning { process.terminate() }

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

            var reclaimHotkeyCallCount = 0
            func reclaimHotkeyIfFreed() {
                reclaimHotkeyCallCount += 1
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

    // MARK: - Test 29: Spotlight symbolic-hotkey entry handling
    //
    // Guards the three ways disabling ⌘Space used to fail silently: only hotkey 64
    // being touched, a missing entry being `Set` (which errors) instead of created,
    // and an existing custom key binding being destroyed on the way through.

    static func testSpotlightShortcutState() {
        print("Testing SpotlightManager shortcut state...")

        assertEqual(SpotlightManager.spotlightHotkeyIDs, [64, 65],
                    "Both Spotlight hotkey IDs are managed (65 is ⌥⌘Space)")
        assertEqual(SpotlightManager.defaultHotkeyParameters(for: 64), [32, 49, 1_048_576],
                    "Hotkey 64 defaults to ⌘Space")
        assertEqual(SpotlightManager.defaultHotkeyParameters(for: 65), [32, 49, 1_572_864],
                    "Hotkey 65 defaults to ⌥⌘Space")

        // An absent entry means the factory default, and Spotlight ships enabled.
        assertTrue(SpotlightManager.isHotkeyEntryEnabled(nil), "Missing entry reads as enabled")
        assertTrue(SpotlightManager.isHotkeyEntryEnabled([String: Any]()), "Empty entry reads as enabled")
        assertTrue(SpotlightManager.isHotkeyEntryEnabled(["enabled": true]), "CFBoolean true")
        assertTrue(!SpotlightManager.isHotkeyEntryEnabled(["enabled": false]), "CFBoolean false")
        // `defaults write -int 0` stores a number, not a boolean.
        assertTrue(!SpotlightManager.isHotkeyEntryEnabled(["enabled": NSNumber(value: 0)]),
                   "CFNumber 0 reads as disabled")
        assertTrue(SpotlightManager.isHotkeyEntryEnabled(["enabled": NSNumber(value: 1)]),
                   "CFNumber 1 reads as enabled")

        // Disabling writes both IDs, not just 64.
        let fromEmpty = SpotlightManager.hotkeyRoot([:], settingEnabled: false)
        for id in SpotlightManager.spotlightHotkeyIDs {
            let entry = fromEmpty[String(id)] as? [String: Any]
            assertTrue(entry != nil, "Entry \(id) is created when absent")
            assertTrue(!SpotlightManager.isHotkeyEntryEnabled(entry), "Entry \(id) is disabled")
            // A missing `value` has to be filled in: an `enabled`-only entry is inert,
            // so a later restore would produce a shortcut that does nothing.
            let value = entry?["value"] as? [String: Any]
            assertTrue(value != nil, "Entry \(id) gets a key binding")
            assertEqual(value?["type"] as? String, "standard", "Entry \(id) binding type")
            assertEqual(value?["parameters"] as? [Int],
                        SpotlightManager.defaultHotkeyParameters(for: id),
                        "Entry \(id) binding parameters")
        }

        // A user's own key binding must survive the toggle untouched. Someone who
        // remapped Spotlight to ⌥Space should get ⌥Space back when they restore.
        let custom: [String: Any] = [
            "64": ["enabled": true,
                   "value": ["type": "standard", "parameters": [32, 49, 524_288]] as [String: Any]] as [String: Any],
            "32": ["enabled": true] as [String: Any],
        ]
        let disabled = SpotlightManager.hotkeyRoot(custom, settingEnabled: false)
        let keptBinding = (disabled["64"] as? [String: Any])?["value"] as? [String: Any]
        assertEqual(keptBinding?["parameters"] as? [Int], [32, 49, 524_288],
                    "An existing custom key binding is preserved")
        assertTrue(!SpotlightManager.isHotkeyEntryEnabled(disabled["64"]), "Custom entry still gets disabled")

        // Unrelated hotkeys (Mission Control, screenshots, …) must not be rewritten.
        assertTrue(SpotlightManager.isHotkeyEntryEnabled(disabled["32"]), "Unrelated hotkey 32 untouched")
        assertEqual(disabled.count, 3, "Only the Spotlight IDs are added")

        // Re-enabling is symmetric and keeps the binding.
        let reEnabled = SpotlightManager.hotkeyRoot(disabled, settingEnabled: true)
        for id in SpotlightManager.spotlightHotkeyIDs {
            assertTrue(SpotlightManager.isHotkeyEntryEnabled(reEnabled[String(id)]),
                       "Entry \(id) is enabled again")
        }
        assertEqual(((reEnabled["64"] as? [String: Any])?["value"] as? [String: Any])?["parameters"] as? [Int],
                    [32, 49, 524_288], "Restore keeps the custom binding")

        // The onboarding summary must not announce a change macOS refused.
        let refused = SpotlightManager.ApplyResult(shortcut: false, service: true, indexing: true)
        let refusedSummary = FirstRunManager.summary(for: refused)
        assertTrue(refusedSummary.contains("Unchanged"), "A refused shortcut write is reported as unchanged")
        assertTrue(!refusedSummary.contains("primary launcher"),
                   "A refused shortcut write is not reported as full success")

        let allDone = SpotlightManager.ApplyResult(shortcut: true, service: true, indexing: true)
        let doneSummary = FirstRunManager.summary(for: allDone)
        assertTrue(!doneSummary.contains("Unchanged"), "A fully applied change reports no leftovers")
        assertTrue(doneSummary.contains("primary launcher"), "A fully applied change reports success")

        // Indexing left out of the request is left out of the summary.
        let noIndexing = SpotlightManager.ApplyResult(shortcut: true, service: true, indexing: nil)
        assertTrue(!FirstRunManager.summary(for: noIndexing).contains("File Indexing"),
                   "Indexing is omitted when it was not attempted")

        print("✅ SpotlightManager shortcut state passed all tests!\n")
    }

    // MARK: - Test 30: UpdateManager (version maths, release parsing, install gate)

    static func testUpdateManager() {
        print("Testing UpdateManager...")

        // --- Version parsing & ordering ---
        assertEqual(SemanticVersion("1.2.3")?.description, "1.2.3", "Plain version")
        assertEqual(SemanticVersion("v1.2.3")?.description, "1.2.3", "Leading v is stripped")
        assertEqual(SemanticVersion("V2.0.0")?.description, "2.0.0", "Capital V is stripped")
        assertTrue(SemanticVersion("")?.description == nil, "Empty string is not a version")
        assertTrue(SemanticVersion("v")?.description == nil, "Bare v is not a version")
        assertTrue(SemanticVersion("nightly")?.description == nil, "Words are not versions")
        assertTrue(SemanticVersion("1.2.x")?.description == nil, "Non-numeric components are rejected")

        assertTrue(SemanticVersion("1.2.3")! < SemanticVersion("1.2.4")!, "Patch ordering")
        assertTrue(SemanticVersion("1.2.9")! < SemanticVersion("1.10.0")!, "Minor compares numerically, not as text")
        assertTrue(SemanticVersion("1.9.0")! < SemanticVersion("2.0.0")!, "Major ordering")
        assertTrue(SemanticVersion("1.2")! == SemanticVersion("1.2.0")!, "Missing components count as zero")
        assertTrue(SemanticVersion("1.2.0")! == SemanticVersion("1.2.0.0")!, "Trailing zeros are equal")
        assertTrue(!(SemanticVersion("1.2.3")! < SemanticVersion("1.2.3")!), "A version is not newer than itself")
        // A pre-release precedes its final release, so 1.3.0-beta must not beat 1.3.0.
        assertTrue(SemanticVersion("1.3.0-beta.1")! < SemanticVersion("1.3.0")!, "Pre-release sorts below release")
        assertTrue(SemanticVersion("1.2.9")! < SemanticVersion("1.3.0-beta.1")!, "Pre-release still beats an older release")

        // --- Download host allowlist ---
        assertTrue(UpdateManager.isAllowedDownloadHost(URL(string: "https://github.com/openhoangnc/mac-lightspot/releases/download/v1/Lightspot.zip")!),
                   "github.com over HTTPS is allowed")
        assertTrue(UpdateManager.isAllowedDownloadHost(URL(string: "https://objects.githubusercontent.com/x")!),
                   "GitHub's object store is allowed")
        assertTrue(!UpdateManager.isAllowedDownloadHost(URL(string: "http://github.com/x.zip")!),
                   "Plain HTTP is refused")
        assertTrue(!UpdateManager.isAllowedDownloadHost(URL(string: "https://evil.example.com/Lightspot.zip")!),
                   "An unrelated host is refused")
        // Suffix matching would wave this through; the check is on the whole host.
        assertTrue(!UpdateManager.isAllowedDownloadHost(URL(string: "https://github.com.evil.example/x.zip")!),
                   "A look-alike host is refused")

        // --- Release payload parsing ---
        let payload = """
        {
          "tag_name": "v1.4.0",
          "html_url": "https://github.com/openhoangnc/mac-lightspot/releases/tag/v1.4.0",
          "body": "Fixes the Spotlight shortcut.",
          "assets": [
            {"name": "Lightspot.zip", "size": 2411724,
             "browser_download_url": "https://github.com/openhoangnc/mac-lightspot/releases/download/v1.4.0/Lightspot.zip"}
          ]
        }
        """.data(using: .utf8)!

        guard let release = try? UpdateManager.parseRelease(from: payload) else {
            print("❌ FAIL: parseRelease rejected a valid payload")
            exit(1)
        }
        assertEqual(release.displayVersion, "1.4.0", "Version read from the tag")
        assertEqual(release.tagName, "v1.4.0", "Tag kept verbatim for skip bookkeeping")
        assertEqual(release.assetSize, 2411724, "Asset size parsed")
        assertEqual(release.notes, "Fixes the Spotlight shortcut.", "Release notes parsed")
        assertTrue(release.pageURL?.absoluteString.hasSuffix("tag/v1.4.0") == true, "Release page parsed")

        // A release whose asset points off-GitHub must be refused outright.
        let offsiteAsset = """
        {"tag_name": "v9.9.9", "assets": [
          {"name": "Lightspot.zip", "browser_download_url": "https://evil.example.com/Lightspot.zip"}]}
        """.data(using: .utf8)!
        assertTrue((try? UpdateManager.parseRelease(from: offsiteAsset)) == nil,
                   "An off-GitHub download URL is refused")

        let noAsset = #"{"tag_name": "v1.5.0", "assets": []}"#.data(using: .utf8)!
        assertTrue((try? UpdateManager.parseRelease(from: noAsset)) == nil, "A release with no asset is refused")

        let badTag = #"{"tag_name": "nightly", "assets": []}"#.data(using: .utf8)!
        assertTrue((try? UpdateManager.parseRelease(from: badTag)) == nil, "A non-version tag is refused")

        assertTrue((try? UpdateManager.parseRelease(from: Data("not json".utf8))) == nil, "Garbage is refused")

        // --- Check outcome ---
        let ok = HTTPURLResponse(url: URL(string: "https://api.github.com/x")!,
                                 statusCode: 200, httpVersion: nil, headerFields: nil)!

        switch UpdateManager.evaluate(data: payload, response: ok, error: nil, current: "1.3.0") {
        case .available(let found): assertEqual(found.displayVersion, "1.4.0", "A newer release is offered")
        default: print("❌ FAIL: expected an available update"); exit(1)
        }

        switch UpdateManager.evaluate(data: payload, response: ok, error: nil, current: "1.4.0") {
        case .upToDate(let current): assertEqual(current, "1.4.0", "An equal version is up to date")
        default: print("❌ FAIL: expected upToDate for an equal version"); exit(1)
        }

        // Never walk backwards: a newer local build must not be "updated" to an older release.
        switch UpdateManager.evaluate(data: payload, response: ok, error: nil, current: "2.0.0") {
        case .upToDate: break
        default: print("❌ FAIL: a downgrade was offered as an update"); exit(1)
        }

        let rateLimited = HTTPURLResponse(url: URL(string: "https://api.github.com/x")!,
                                          statusCode: 403, httpVersion: nil, headerFields: nil)!
        switch UpdateManager.evaluate(data: payload, response: rateLimited, error: nil, current: "1.0.0") {
        case .failed(let message): assertTrue(message.contains("rate-limited"), "403 is reported as rate limiting")
        default: print("❌ FAIL: expected a failure for HTTP 403"); exit(1)
        }

        let missing = HTTPURLResponse(url: URL(string: "https://api.github.com/x")!,
                                      statusCode: 404, httpVersion: nil, headerFields: nil)!
        switch UpdateManager.evaluate(data: payload, response: missing, error: nil, current: "1.0.0") {
        case .failed: break
        default: print("❌ FAIL: expected a failure for HTTP 404"); exit(1)
        }

        switch UpdateManager.evaluate(data: nil, response: ok, error: nil, current: "1.0.0") {
        case .failed: break
        default: print("❌ FAIL: expected a failure for an empty body"); exit(1)
        }

        // --- Bundle validation gate ---
        // Releases carry no Developer ID signature, so these checks are the whole gate.
        let fm = FileManager.default
        let sandbox = fm.temporaryDirectory.appendingPathComponent("lightspot-update-test-\(UUID().uuidString)")

        func makeBundle(identifier: String, version: String, withExecutable: Bool) -> URL {
            let bundle = sandbox.appendingPathComponent("\(UUID().uuidString)/Lightspot.app")
            let macos = bundle.appendingPathComponent("Contents/MacOS")
            try? fm.createDirectory(at: macos, withIntermediateDirectories: true)
            let info: [String: Any] = [
                "CFBundleIdentifier": identifier,
                "CFBundleExecutable": "Lightspot",
                "CFBundleShortVersionString": version,
            ]
            (info as NSDictionary).write(to: bundle.appendingPathComponent("Contents/Info.plist"),
                                         atomically: true)
            if withExecutable {
                let binary = macos.appendingPathComponent("Lightspot")
                fm.createFile(atPath: binary.path, contents: Data("#!/bin/sh\n".utf8))
                try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
            }
            return bundle
        }

        let expected = SemanticVersion("1.4.0")!
        let good = makeBundle(identifier: "com.lightspot.app", version: "1.4.0", withExecutable: true)
        assertTrue(UpdateManager.validate(bundle: good, expected: expected, fileManager: fm) == nil,
                   "A matching Lightspot bundle is accepted")

        let imposter = makeBundle(identifier: "com.example.evil", version: "1.4.0", withExecutable: true)
        assertTrue(UpdateManager.validate(bundle: imposter, expected: expected, fileManager: fm) != nil,
                   "A bundle with a different identifier is refused")

        let wrongVersion = makeBundle(identifier: "com.lightspot.app", version: "1.3.0", withExecutable: true)
        assertTrue(UpdateManager.validate(bundle: wrongVersion, expected: expected, fileManager: fm) != nil,
                   "A bundle whose version differs from the release is refused")

        let noBinary = makeBundle(identifier: "com.lightspot.app", version: "1.4.0", withExecutable: false)
        assertTrue(UpdateManager.validate(bundle: noBinary, expected: expected, fileManager: fm) != nil,
                   "A bundle with no runnable executable is refused")

        assertTrue(UpdateManager.validate(bundle: sandbox.appendingPathComponent("Nope.app"),
                                          expected: expected, fileManager: fm) != nil,
                   "A missing bundle is refused")

        // findAppBundle copes with the archive layout `ditto` produces.
        let nested = sandbox.appendingPathComponent("nested", isDirectory: true)
        try? fm.createDirectory(at: nested.appendingPathComponent("Lightspot.app"), withIntermediateDirectories: true)
        assertEqual(UpdateManager.findAppBundle(in: nested, fileManager: fm)?.lastPathComponent,
                    "Lightspot.app", "The app bundle is found at the archive root")

        // --- Swap helper script ---
        assertEqual(UpdateManager.shellQuote("/Applications/Lightspot.app"),
                    "'/Applications/Lightspot.app'", "Ordinary paths are single-quoted")
        // A quote in a path must not be able to break out of the script.
        assertEqual(UpdateManager.shellQuote("/tmp/it's here"), "'/tmp/it'\\''s here'",
                    "An embedded quote is escaped")

        let script = UpdateManager.installerScript(pid: 4242,
                                                   stagedBundle: "/tmp/stage/Lightspot.app",
                                                   destination: "/Applications/Lightspot.app",
                                                   workDirectory: "/tmp/stage",
                                                   uid: 501,
                                                   privileged: false)
        assertTrue(script.contains("kill -0 4242"), "The helper waits for the running app to exit")
        assertTrue(script.contains("/usr/bin/ditto '/tmp/stage/Lightspot.app' '/Applications/Lightspot.app'"),
                   "The helper copies the staged bundle over the installed one")
        assertTrue(script.contains("mv '/Applications/Lightspot.app' '/Applications/Lightspot.app.lightspot-old'"),
                   "The helper keeps the old bundle for rollback")
        assertTrue(script.contains("codesign --force --deep --sign -"),
                   "The helper re-signs ad-hoc, which a plain copy does not preserve")
        assertTrue(script.contains("xattr -dr com.apple.quarantine"), "The helper clears quarantine")
        assertTrue(script.contains("/usr/bin/open '/Applications/Lightspot.app'"), "The helper relaunches the app")
        assertTrue(!script.contains("launchctl asuser"), "The unprivileged helper relaunches directly")

        let privileged = UpdateManager.installerScript(pid: 4242,
                                                       stagedBundle: "/tmp/stage/Lightspot.app",
                                                       destination: "/Applications/Lightspot.app",
                                                       workDirectory: "/tmp/stage",
                                                       uid: 501,
                                                       privileged: true)
        // Relaunching from a root shell would start Lightspot as root.
        assertTrue(privileged.contains("/bin/launchctl asuser 501 /usr/bin/open '/Applications/Lightspot.app'"),
                   "The privileged helper relaunches back in the user's session")
        assertTrue(privileged.contains("chown -R 501"), "The privileged helper hands the bundle back to the user")

        try? fm.removeItem(at: sandbox)
        print("✅ UpdateManager passed all tests!\n")
    }
}
