import AppKit
import Foundation
import ServiceManagement

// MARK: - Test Runner for Lightspot Core Logic
//
// Build & run:
//   swiftc -o /tmp/test_engine scripts/test_engine.swift \
//       Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift \
//       Sources/Lightspot/System/AutoStartManager.swift Sources/Lightspot/System/SpotlightManager.swift \
//       Sources/Lightspot/System/FirstRunManager.swift Sources/Lightspot/System/SingleInstanceGuard.swift \
//       Sources/Lightspot/System/UpdateManager.swift Sources/Lightspot/System/LegacyNetworkStores.swift \
//       Sources/Lightspot/System/HotkeyManager.swift Sources/Lightspot/System/SystemShortcutConflicts.swift \
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
        // Child mode for testSingleInstanceGuard: this binary, re-executed, plays the
        // Lightspot that already holds the lock.
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--single-instance-holder"), arguments.count > flag + 3 {
            runSingleInstanceHolder(lockPath: arguments[flag + 1], bundleIdentifier: arguments[flag + 2], build: arguments[flag + 3])
        }

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
        testSystemShortcutConflicts()
        testUpdateManager()
        testUpdateHandOver()
        testPublicIPLookupIsOnDemand()
        testHistoryDoesNotPersistCopiedContent()
        testBareClipListsLatestEntries()
        testHistoryDoesNotRecordProcessKills()
        testSingleInstanceGuard()
        testLegacyNetworkStores()
        testSettingsSearchTerms()
        testCleanDevMacRules()
        testCleanDevMacEngine()
        testCleanDevMacUserFolder()
        testCleanDevMacProvider()
        testToolInstallers()
        testMacTweaks()
        testCleanDevMacRepoScan()

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

        // Words that name the HUD outright beat an app that only starts with them.
        for word in ["memory", "mem", "cpu usage", "free memory", "disk space", "load average", "resources", "System Info"] {
            assertEqual(SystemInfoProvider.shared.search(SearchQuery(word)).first?.score, 98, "'\(word)' names the HUD")
        }
        // Words that also name Disk Utility, the Storage pane or PowerPoint list it below them.
        for word in ["disk", "storage", "power", "charging", "performance"] {
            assertEqual(SystemInfoProvider.shared.search(SearchQuery(word)).first?.score, 90, "'\(word)' lists the HUD")
        }
        // Three letters of a one-word keyword list it while typing; phrases need the whole word.
        for partial in ["hardw", "upti", "memo", "batt", "res", "spec"] {
            assertEqual(SystemInfoProvider.shared.search(SearchQuery(partial)).first?.score, 75, "'\(partial)' lists the HUD")
        }
        for unrelated in ["up", "me", "dis", "fre", "boo", "chrome", "systemd"] {
            assertTrue(SystemInfoProvider.shared.search(SearchQuery(unrelated)).isEmpty, "'\(unrelated)' does not list the HUD")
        }
        let diskEngine = SearchEngine.shared.searchImmediate(SearchQuery("storage"))
        assertEqual(diskEngine[.topHit]?.first?.title, "Storage", "The Storage pane keeps Top Hit for 'storage'")
        assertTrue(diskEngine[.quickActions]?.contains(where: { $0.id == "system-hud" }) == true, "The HUD is still listed for 'storage'")

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
        // This runner is a bare executable: registering it would list "test_engine" under Login Items.
        assertTrue(!AutoStartManager.canRegisterLoginItem, "A binary outside an .app bundle never registers")
        assertTrue(SMAppService.mainApp.status != .enabled, "The test runner is not a login item")
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

        // Re-enabling the agent has to load and start it, not only clear the override:
        // after a login with it disabled launchd never loaded it, and `enable` alone
        // left Spotlight gone until the next login.
        let target = "gui/501/com.apple.Spotlight"
        let enable = SpotlightManager.serviceCommands(enabled: true, uid: 501)
        assertEqual(enable.first, ["enable", target], "Enabling clears the override first")
        assertEqual(enable.dropFirst().first, ["bootstrap", "gui/501", SpotlightManager.servicePlistPath],
                    "Then loads the agent into the GUI domain")
        assertEqual(enable.last, ["kickstart", target], "Then starts it now")
        assertTrue(FileManager.default.fileExists(atPath: SpotlightManager.servicePlistPath),
                   "The Spotlight agent plist exists where bootstrap looks for it")
        assertEqual(SpotlightManager.serviceCommands(enabled: false, uid: 501), [["disable", target]],
                    "Disabling only sets the override")

        print("✅ SpotlightManager shortcut state passed all tests!\n")
    }

    // MARK: - Test 34: a system shortcut sitting on Lightspot's key combination
    //
    // The quiet half of invariant 9. Carbon only refuses a combination another Carbon
    // owner holds; a symbolic hotkey lets the registration succeed and still acts on
    // the keystroke, so ⌃Space opens the panel *and* switches the input source. These
    // cover the reading of `AppleSymbolicHotKeys` that the menu note is built from.

    static func testSystemShortcutConflicts() {
        print("Testing SystemShortcutConflicts...")

        // 1. Every option maps to the mask macOS stores in `parameters[2]`.
        assertEqual(SystemShortcutConflicts.symbolicModifierMask(for: .commandSpace), 1_048_576, "⌘ mask")
        assertEqual(SystemShortcutConflicts.symbolicModifierMask(for: .commandShiftSpace), 1_179_648, "⌘⇧ mask")
        assertEqual(SystemShortcutConflicts.symbolicModifierMask(for: .optionSpace), 524_288, "⌥ mask")
        assertEqual(SystemShortcutConflicts.symbolicModifierMask(for: .controlSpace), 262_144, "⌃ mask")

        // 2. The watched entries, and their factory bindings. 64/65 must agree with
        // the defaults SpotlightManager writes, or the two would disagree about what
        // "untouched" means.
        assertEqual(SystemShortcutConflicts.spaceShortcuts.map(\.id), [60, 61, 64, 65],
                    "Input-source pair and Spotlight pair are watched")
        for shortcut in SystemShortcutConflicts.spaceShortcuts where shortcut.id >= 64 {
            assertEqual(SpotlightManager.defaultHotkeyParameters(for: shortcut.id),
                        [32, SystemShortcutConflicts.spaceKeyCode, shortcut.factoryModifiers],
                        "Entry \(shortcut.id) factory binding matches SpotlightManager")
        }
        // ⌃Space and ⌃⌥Space, as measured on a stock Mac.
        assertEqual(SystemShortcutConflicts.spaceShortcuts.first?.factoryModifiers, 262_144, "Entry 60 is ⌃Space")
        assertEqual(SystemShortcutConflicts.spaceShortcuts.dropFirst().first?.factoryModifiers, 786_432,
                    "Entry 61 is ⌃⌥Space")

        // 3. `parameters` has to survive both ways a CFNumber array bridges in.
        assertEqual(SystemShortcutConflicts.parameters(of: nil), nil, "No entry, no parameters")
        assertEqual(SystemShortcutConflicts.parameters(of: ["enabled": true]), nil, "No value dict")
        let asInts: [String: Any] = ["value": ["parameters": [32, 49, 262_144]] as [String: Any]]
        assertEqual(SystemShortcutConflicts.parameters(of: asInts), [32, 49, 262_144], "Int array")
        let asNumbers: [String: Any] = ["value": ["parameters": [NSNumber(value: 32), NSNumber(value: 49), NSNumber(value: 262_144)]] as [String: Any]]
        assertEqual(SystemShortcutConflicts.parameters(of: asNumbers), [32, 49, 262_144], "NSNumber array")
        let notNumbers: [String: Any] = ["value": ["parameters": ["32", "49", "262144"]] as [String: Any]]
        assertEqual(SystemShortcutConflicts.parameters(of: notNumbers), nil, "Strings are not a binding")

        // 4. Reading one entry's Space binding.
        let factory = 262_144
        assertEqual(SystemShortcutConflicts.spaceModifiers(of: nil, factory: factory), factory,
                    "A missing entry means the factory binding")
        assertEqual(SystemShortcutConflicts.spaceModifiers(of: [String: Any](), factory: factory), factory,
                    "An entry with no value means the factory binding")
        assertEqual(SystemShortcutConflicts.spaceModifiers(of: ["enabled": false], factory: factory), nil,
                    "A disabled entry holds nothing")
        assertEqual(SystemShortcutConflicts.spaceModifiers(of: ["enabled": NSNumber(value: 0)], factory: factory), nil,
                    "`defaults write -int 0` also reads as disabled")
        let remapped: [String: Any] = ["enabled": true,
                                       "value": ["parameters": [32, 49, 524_288]] as [String: Any]]
        assertEqual(SystemShortcutConflicts.spaceModifiers(of: remapped, factory: factory), 524_288,
                    "A custom binding wins over the factory one")
        let otherKey: [String: Any] = ["enabled": true,
                                       "value": ["parameters": [9, 48, 262_144]] as [String: Any]]
        assertEqual(SystemShortcutConflicts.spaceModifiers(of: otherKey, factory: factory), nil,
                    "Remapped off Space entirely, so no collision")
        let truncated: [String: Any] = ["enabled": true,
                                        "value": ["parameters": [32, 49]] as [String: Any]]
        assertEqual(SystemShortcutConflicts.spaceModifiers(of: truncated, factory: factory), nil,
                    "A short parameters array is not a binding")

        // 5. A stock Mac: no entries written at all, every default live. ⌃Space and
        // ⌘Space are taken; ⌥Space and ⌘⇧Space are free (65 is ⌥⌘Space, not ⌥Space).
        let stock: [String: Any] = [:]
        assertEqual(SystemShortcutConflicts.conflict(for: .controlSpace, in: stock)?.id, 60,
                    "⌃Space is the previous-input-source shortcut")
        assertEqual(SystemShortcutConflicts.conflict(for: .controlSpace, in: stock)?.note,
                    "also switches input source", "…and the menu says what it does")
        assertEqual(SystemShortcutConflicts.conflict(for: .commandSpace, in: stock)?.id, 64,
                    "⌘Space is Spotlight")
        assertEqual(SystemShortcutConflicts.conflict(for: .optionSpace, in: stock)?.id, nil, "⌥Space is free")
        assertEqual(SystemShortcutConflicts.conflict(for: .commandShiftSpace, in: stock)?.id, nil,
                    "⌘⇧Space is free")
        assertEqual(SystemShortcutConflicts.conflicts(in: stock).count, 2, "Two options collide on a stock Mac")
        assertEqual(SystemShortcutConflicts.conflicts(in: stock)[HotkeyOption.controlSpace.rawValue]?.id, 60,
                    "The snapshot is keyed by raw value")

        // 6. Turning the system shortcut off clears the warning — including the one
        // Lightspot itself turns off when it disables Spotlight's ⌘Space.
        let quiet = SpotlightManager.hotkeyRoot(["60": ["enabled": false] as [String: Any]], settingEnabled: false)
        assertEqual(SystemShortcutConflicts.conflicts(in: quiet).count, 0, "Nothing collides once the entries are off")

        // 7. A user who remapped input-source switching to ⌥Space moves the collision
        // with it, which is why the entry's own binding is read instead of assumed.
        let moved: [String: Any] = ["60": ["enabled": true,
                                           "value": ["parameters": [32, 49, 524_288]] as [String: Any]] as [String: Any]]
        assertEqual(SystemShortcutConflicts.conflict(for: .optionSpace, in: moved)?.id, 60, "⌥Space now collides")
        assertEqual(SystemShortcutConflicts.conflict(for: .controlSpace, in: moved)?.id, nil, "⌃Space is free again")

        print("✅ SystemShortcutConflicts passed all tests!\n")
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
                                                   helperDirectory: "/tmp/helper",
                                                   uid: 501,
                                                   privileged: false)
        assertTrue(script.contains("kill -0 4242"), "The helper waits out the running app after the swap")
        assertTrue(!script.contains("kill -9"), "The helper never kills the running app: it quits once the new build is up")
        assertTrue(script.contains("/usr/bin/ditto '/tmp/stage/Lightspot.app' '/Applications/Lightspot.app'"),
                   "The helper copies the staged bundle over the installed one")
        assertTrue(script.contains("mv '/Applications/Lightspot.app' '/Applications/Lightspot.app.lightspot-old'"),
                   "The helper keeps the old bundle for rollback")
        assertTrue(script.contains("codesign --force --deep --sign -"),
                   "The helper re-signs ad-hoc, which a plain copy does not preserve")
        assertTrue(script.contains("xattr -dr com.apple.quarantine"), "The helper clears quarantine")
        // Up to 1.3.2 the helper relaunched after the app had quit, and the first launch
        // of the new bundle sat in a Gatekeeper scan with no Lightspot on screen.
        assertTrue(!script.contains("/usr/bin/open"), "The helper does not relaunch: the running app starts the new build")
        assertTrue(script.contains("report swapped") && script.contains("'/tmp/helper/status'"),
                   "The helper reports the swap in its status file")
        assertTrue(script.contains("'/tmp/helper/restore'"), "The helper watches for a restore request")
        let swapIndex = script.range(of: "report swapped")!.lowerBound
        let waitIndex = script.range(of: "kill -0 4242")!.lowerBound
        assertTrue(swapIndex < waitIndex, "The swap happens before the running app quits, not after")
        assertTrue(script.contains("rm -rf '/tmp/stage'") && script.contains("rm -rf '/tmp/helper'"),
                   "The helper removes the staging folder and its own folder")
        assertTrue(!script.contains("chown"), "The unprivileged helper leaves ownership alone")

        let privileged = UpdateManager.installerScript(pid: 4242,
                                                       stagedBundle: "/tmp/stage/Lightspot.app",
                                                       destination: "/Applications/Lightspot.app",
                                                       workDirectory: "/tmp/stage",
                                                       helperDirectory: "/tmp/helper",
                                                       uid: 501,
                                                       privileged: true)
        assertTrue(privileged.contains("chown -R 501 '/Applications/Lightspot.app'"),
                   "The privileged helper hands the bundle back to the user")
        // The app, running as the user, starts the new build; a root helper never does.
        assertTrue(!privileged.contains("/usr/bin/open") && !privileged.contains("launchctl"),
                   "The privileged helper launches nothing as root")
        assertTrue(privileged.range(of: "chown")!.lowerBound < privileged.range(of: "report swapped")!.lowerBound,
                   "The bundle is the user's before the app is told to start it")

        // Regression: the check ran on URLSession.shared, which stored every release feed
        // in ~/Library/Caches/<bundle id>/Cache.db and its cookies in ~/Library/HTTPStorages.
        let updateSession = UpdateManager.session
        assertTrue(updateSession !== URLSession.shared, "The update check does not use the shared session")
        assertEqual(updateSession.configuration.urlCache?.diskCapacity ?? 0, 0,
                    "The update check never caches a response on disk")
        assertTrue(updateSession.configuration.httpCookieStorage !== HTTPCookieStorage.shared,
                   "The update check does not touch the persistent cookie store")

        try? fm.removeItem(at: sandbox)
        print("✅ UpdateManager passed all tests!\n")
    }

    // MARK: - Test 31b: update hand-over (swap while running, new build takes over)

    /// Runs the real helper script against fake bundles. A `sleep` stands in for the
    /// running Lightspot, so its exit is the old copy quitting.
    @MainActor
    static func testUpdateHandOver() {
        print("Testing update hand-over...")
        let fm = FileManager.default

        // --- Pure decisions ---
        assertEqual(UpdateManager.handOverStep(isTerminated: false, isFinishedLaunching: false, timedOut: false),
                    .waiting, "A copy still launching is waited for")
        assertEqual(UpdateManager.handOverStep(isTerminated: false, isFinishedLaunching: true, timedOut: false),
                    .launched, "A copy that finished launching takes over")
        assertEqual(UpdateManager.handOverStep(isTerminated: true, isFinishedLaunching: true, timedOut: false),
                    .failed("it quit while starting"), "A copy that died is a failed hand-over, even if it had launched")
        assertEqual(UpdateManager.handOverStep(isTerminated: false, isFinishedLaunching: false, timedOut: true),
                    .failed("it took too long to start"), "A copy that never finishes launching is a failed hand-over")
        assertTrue(UpdateManager.handOverTimeout >= 60, "The hand-over outlasts a first-launch Gatekeeper scan (30 s measured)")

        let arguments = SingleInstanceGuard.replacingArguments(pid: 4242)
        assertEqual(SingleInstanceGuard.replacedPID(arguments: ["/x/Lightspot"] + arguments), 4242,
                    "The new copy reads the PID it replaces")
        assertEqual(SingleInstanceGuard.replacedPID(arguments: ["/x/Lightspot"]), nil, "An ordinary launch replaces nothing")
        assertEqual(SingleInstanceGuard.replacedPID(arguments: ["/x/Lightspot", "--replacing"]), nil, "A flag without a PID is ignored")
        assertEqual(SingleInstanceGuard.replacedPID(arguments: ["/x/Lightspot", "--replacing", "abc"]), nil, "A malformed PID is ignored")

        // --- The helper script, for real ---
        let sandbox = fm.temporaryDirectory.appendingPathComponent("lightspot-handover-\(getpid())", isDirectory: true)
        try? fm.removeItem(at: sandbox)
        defer { try? fm.removeItem(at: sandbox) }

        func makeBundle(at url: URL, marker: String) {
            let macos = url.appendingPathComponent("Contents/MacOS", isDirectory: true)
            try? fm.createDirectory(at: macos, withIntermediateDirectories: true)
            fm.createFile(atPath: macos.appendingPathComponent("Lightspot").path,
                          contents: Data("#!/bin/sh\n# \(marker)\n".utf8),
                          attributes: [.posixPermissions: 0o755])
        }
        func marker(of url: URL) -> String? {
            guard let text = try? String(contentsOf: url.appendingPathComponent("Contents/MacOS/Lightspot"),
                                         encoding: .utf8) else { return nil }
            return text.contains("# new") ? "new" : text.contains("# old") ? "old" : "?"
        }
        func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while !condition() {
                if Date() >= deadline { return false }
                usleep(50_000)
            }
            return true
        }

        struct Run {
            let app: URL, rollback: URL, work: URL, helper: URL
            let runningApp: Process, script: Process
        }
        func start(_ name: String, stageNewBuild: Bool = true) -> Run {
            let root = sandbox.appendingPathComponent(name, isDirectory: true)
            let app = root.appendingPathComponent("Applications/Lightspot.app", isDirectory: true)
            let work = root.appendingPathComponent("stage", isDirectory: true)
            let helper = root.appendingPathComponent("helper", isDirectory: true)
            makeBundle(at: app, marker: "old")
            try? fm.createDirectory(at: work, withIntermediateDirectories: true)
            if stageNewBuild { makeBundle(at: work.appendingPathComponent("Lightspot.app"), marker: "new") }
            try? fm.createDirectory(at: helper, withIntermediateDirectories: true)

            let runningApp = Process()
            runningApp.executableURL = URL(fileURLWithPath: "/bin/sleep")
            runningApp.arguments = ["60"]
            try? runningApp.run()

            let body = UpdateManager.installerScript(pid: runningApp.processIdentifier,
                                                     stagedBundle: work.appendingPathComponent("Lightspot.app").path,
                                                     destination: app.path,
                                                     workDirectory: work.path,
                                                     helperDirectory: helper.path,
                                                     uid: getuid(),
                                                     privileged: false)
            let scriptURL = helper.appendingPathComponent("install.sh")
            try? body.write(to: scriptURL, atomically: true, encoding: .utf8)
            let script = Process()
            script.executableURL = URL(fileURLWithPath: "/bin/sh")
            script.arguments = [scriptURL.path]
            script.standardOutput = FileHandle.nullDevice
            script.standardError = FileHandle.nullDevice
            try? script.run()
            return Run(app: app, rollback: URL(fileURLWithPath: app.path + ".lightspot-old"),
                       work: work, helper: helper, runningApp: runningApp, script: script)
        }

        // 1. Success: the swap lands while the app still runs; its exit clears the rollback.
        let ok = start("ok")
        assertTrue(waitUntil(30) { UpdateManager.helperStatus(in: ok.helper) != nil }, "The helper reports the swap")
        assertEqual(UpdateManager.helperStatus(in: ok.helper), "swapped", "The swap succeeds")
        assertTrue(ok.runningApp.isRunning, "The running app is still up when the swap is reported")
        assertEqual(marker(of: ok.app), "new", "The new build is in place before the app quits")
        assertEqual(marker(of: ok.rollback), "old", "The old bundle is kept aside until the hand-over is over")
        assertTrue(!fm.fileExists(atPath: ok.work.path), "The staging folder is gone after the swap")
        assertTrue(ok.script.isRunning, "The helper waits for the hand-over")
        ok.runningApp.terminate()
        assertTrue(waitUntil(10) { !ok.script.isRunning }, "The helper finishes once the old copy has quit")
        assertEqual(marker(of: ok.app), "new", "The new build stays")
        assertTrue(!fm.fileExists(atPath: ok.rollback.path), "The rollback copy is removed after the hand-over")
        assertTrue(!fm.fileExists(atPath: ok.helper.path), "The helper removes its own folder")

        // 2. The new build did not start: the old copy asks for its bundle back.
        let back = start("restore")
        assertTrue(waitUntil(30) { UpdateManager.helperStatus(in: back.helper) == "swapped" }, "The second swap lands")
        UpdateManager.requestRestore(in: back.helper)
        assertTrue(waitUntil(10) { UpdateManager.helperStatus(in: back.helper) == "restored" }, "The helper reports the rollback")
        assertEqual(marker(of: back.app), "old", "The old bundle is back in place")
        assertTrue(!fm.fileExists(atPath: back.rollback.path), "Nothing is left beside it")
        assertTrue(back.runningApp.isRunning, "The old copy keeps running through a rollback")
        assertTrue(waitUntil(5) { !back.script.isRunning }, "The helper exits after a rollback")
        back.runningApp.terminate()

        // 3. The copy fails: nothing changes and the old copy is told so.
        let broken = start("broken", stageNewBuild: false)
        assertTrue(waitUntil(30) { UpdateManager.helperStatus(in: broken.helper) != nil }, "The helper reports a failed copy")
        assertEqual(UpdateManager.helperStatus(in: broken.helper), "failed", "A failed copy is reported as such")
        assertEqual(marker(of: broken.app), "old", "A failed copy leaves the installed bundle in place")
        assertTrue(!fm.fileExists(atPath: broken.rollback.path), "A failed copy leaves no rollback behind")
        assertTrue(waitUntil(5) { !broken.script.isRunning }, "The helper exits after a failed copy")
        broken.runningApp.terminate()

        // --- The new copy waits for the old one instead of asking it to quit ---
        let directory = sandbox.appendingPathComponent("locks", isDirectory: true).path
        try? fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let bundleIdentifier = "com.lightspot.tests.handover.\(getpid())"
        let lock = directory + "/handover.lock"
        let old = HolderProcess(lockPath: lock, bundleIdentifier: bundleIdentifier, build: "build-A")
        assertTrue(old.waitFor("locked"), "The old copy holds the lock")
        assertEqual(SingleInstanceGuard.claimReplacing(old.pid, bundleIdentifier: bundleIdentifier, lockPath: lock, build: "build-B"),
                    nil, "The new copy waits while the copy it replaces holds the lock")
        usleep(500_000)
        assertTrue(old.process.isRunning, "The old copy was not asked to quit: it quits once the new one has launched")
        old.process.terminate()
        old.process.waitUntilExit()
        let tookOver = SingleInstanceGuard.claimReplacing(old.pid, bundleIdentifier: bundleIdentifier, lockPath: lock, build: "build-B")
        guard case .run(let fd?) = tookOver else {
            assertTrue(false, "The new copy takes the lock once the old one has quit, got \(String(describing: tookOver))"); return
        }
        close(fd)

        // Anyone else holding the lock gets the ordinary take-over.
        let other = HolderProcess(lockPath: lock, bundleIdentifier: bundleIdentifier, build: "build-C")
        assertTrue(other.waitFor("locked"), "An unrelated copy holds the lock")
        let overOther = SingleInstanceGuard.claimReplacing(4_000_000, bundleIdentifier: bundleIdentifier, lockPath: lock, build: "build-B")
        guard case .run(let fd2?) = overOther else {
            assertTrue(false, "An unrelated holder is taken over as usual, got \(String(describing: overOther))"); return
        }
        assertTrue(other.waitFor("quit"), "The unrelated holder was asked to quit")
        other.process.waitUntilExit()
        close(fd2)

        print("✅ Update hand-over passed all tests!\n")
    }

    // MARK: - Test 32: single instance guard

    /// Child process: takes the lock, prints `locked`, then prints `show` / `quit` for
    /// each request a later launch sends (exiting on `quit`). Lives 10 s at most so a
    /// failed test cannot leave it behind.
    @MainActor
    static func runSingleInstanceHolder(lockPath: String, bundleIdentifier: String, build: String) -> Never {
        func say(_ line: String) { FileHandle.standardOutput.write(Data((line + "\n").utf8)) }
        guard case .acquired = SingleInstanceGuard.acquireLock(atPath: lockPath, build: build) else {
            say("busy")
            exit(2)
        }
        let listener = SingleInstanceGuard.RequestListener(
            bundleIdentifier: bundleIdentifier,
            onShowPanel: { say("show") },
            onQuit: { say("quit"); exit(0) }
        )
        say("locked")
        RunLoop.main.run(until: Date().addingTimeInterval(10))
        withExtendedLifetime(listener) {}
        exit(3)
    }

    final class HolderProcess {
        let process = Process()
        private let pipe = Pipe()
        private var output = ""

        init(lockPath: String, bundleIdentifier: String, build: String) {
            process.executableURL = Bundle.main.executableURL
            process.arguments = ["--single-instance-holder", lockPath, bundleIdentifier, build]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try? process.run()
        }

        var pid: pid_t { process.processIdentifier }

        /// Blocks until the child prints `line`; false if it exits first.
        func waitFor(_ line: String) -> Bool {
            while !output.split(separator: "\n").contains(Substring(line)) {
                let data = pipe.fileHandleForReading.availableData
                if data.isEmpty { return false }
                output += String(decoding: data, as: UTF8.self)
            }
            return true
        }
    }

    @MainActor
    static func testSingleInstanceGuard() {
        print("Testing SingleInstanceGuard...")
        let fileManager = FileManager.default
        let directory = NSTemporaryDirectory() + "lightspot-guard-\(getpid())"
        try? fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(atPath: directory) }

        // 1. Build identity: stable for one file, new once the file is replaced the way
        //    install.sh does (delete, copy), even at the same path with the same bytes.
        let executable = directory + "/Lightspot"
        fileManager.createFile(atPath: executable, contents: Data("build".utf8))
        let identity = SingleInstanceGuard.buildIdentity(executablePath: executable)
        assertEqual(SingleInstanceGuard.buildIdentity(executablePath: executable), identity, "Identity of an unchanged executable is stable")
        try? fileManager.removeItem(atPath: executable)
        fileManager.createFile(atPath: executable, contents: Data("build".utf8))
        assertTrue(SingleInstanceGuard.buildIdentity(executablePath: executable) != identity, "A reinstalled executable has a new identity")

        // 2. The lock excludes a second holder and records who holds it; closing frees it.
        let lockA = directory + "/a.lock"
        guard case .acquired(let fdA) = SingleInstanceGuard.acquireLock(atPath: lockA, build: "build-1") else {
            assertTrue(false, "First acquire takes the lock"); return
        }
        assertEqual(
            SingleInstanceGuard.acquireLock(atPath: lockA, build: "build-2"),
            .held(by: SingleInstanceGuard.Holder(pid: getpid(), build: "build-1")),
            "Second acquire sees the holder's PID and build"
        )
        close(fdA)
        guard case .acquired(let fdA2) = SingleInstanceGuard.acquireLock(atPath: lockA, build: "build-2") else {
            assertTrue(false, "Lock is free again once the holder closes it"); return
        }
        close(fdA2)

        // 3. An unusable lock path must not stop Lightspot from starting.
        assertEqual(SingleInstanceGuard.acquireLock(atPath: "/dev/null/x.lock", build: "b"), .unavailable, "Unopenable lock file")
        assertEqual(
            SingleInstanceGuard.claim(bundleIdentifier: "com.lightspot.tests.none", lockPath: "/dev/null/x.lock", build: "b"),
            .run(lockFD: nil),
            "Unopenable lock file runs unguarded"
        )

        // 4. Show requests right after launch are a start-up race, not a user.
        let launched = Date()
        assertTrue(!SingleInstanceGuard.shouldHonorShowRequest(launchedAt: launched, now: launched.addingTimeInterval(1)), "Show request 1 s after launch is ignored")
        assertTrue(SingleInstanceGuard.shouldHonorShowRequest(launchedAt: launched, now: launched.addingTimeInterval(SingleInstanceGuard.launchGraceInterval)), "Show request after the grace interval is honored")

        // 5. Across processes, through distributed notifications.
        let bundleIdentifier = "com.lightspot.tests.guard.\(getpid())"
        let lockB = directory + "/b.lock"
        let holder = HolderProcess(lockPath: lockB, bundleIdentifier: bundleIdentifier, build: "build-A")
        assertTrue(holder.waitFor("locked"), "Holder process took the lock")
        assertEqual(
            SingleInstanceGuard.acquireLock(atPath: lockB, build: "probe"),
            .held(by: SingleInstanceGuard.Holder(pid: holder.pid, build: "build-A")),
            "Another process's lock is visible with its PID"
        )

        // Same build started again: hand off, the running copy is asked to show its panel.
        assertEqual(
            SingleInstanceGuard.claim(bundleIdentifier: bundleIdentifier, lockPath: lockB, build: "build-A"),
            .handedOff,
            "Second launch of the same build hands off"
        )
        assertTrue(holder.waitFor("show"), "Running copy received the show request")

        // A different build (reinstall / rebuild / update): the old copy quits, the new one runs.
        let takeOver = SingleInstanceGuard.claim(bundleIdentifier: bundleIdentifier, lockPath: lockB, build: "build-B")
        guard case .run(let fdB?) = takeOver else {
            assertTrue(false, "New build takes over, got \(takeOver)"); return
        }
        assertTrue(holder.waitFor("quit"), "Old build received the quit request")
        holder.process.waitUntilExit()
        assertEqual(
            SingleInstanceGuard.acquireLock(atPath: lockB, build: "probe"),
            .held(by: SingleInstanceGuard.Holder(pid: getpid(), build: "build-B")),
            "New build now holds the lock"
        )
        close(fdB)

        // 6. SIGKILL (install.sh's last resort) releases the lock: no stale lock.
        let lockC = directory + "/c.lock"
        let killed = HolderProcess(lockPath: lockC, bundleIdentifier: bundleIdentifier, build: "build-A")
        assertTrue(killed.waitFor("locked"), "Second holder took the lock")
        kill(killed.pid, SIGKILL)
        killed.process.waitUntilExit()
        guard case .acquired(let fdC) = SingleInstanceGuard.acquireLock(atPath: lockC, build: "build-B") else {
            assertTrue(false, "Lock is free once its holder is killed"); return
        }
        close(fdC)

        // 7. A holder that cannot answer (stopped) keeps the lock: the new build gives up.
        let lockD = directory + "/d.lock"
        let stuck = HolderProcess(lockPath: lockD, bundleIdentifier: bundleIdentifier, build: "build-A")
        assertTrue(stuck.waitFor("locked"), "Third holder took the lock")
        kill(stuck.pid, SIGSTOP)
        let gaveUp = SingleInstanceGuard.claim(bundleIdentifier: bundleIdentifier, lockPath: lockD, build: "build-B", takeOverTimeout: 0.5)
        kill(stuck.pid, SIGKILL)
        stuck.process.waitUntilExit()
        assertEqual(gaveUp, .holderDidNotQuit(pid: stuck.pid), "Unresponsive holder: new build exits instead of running twice")

        print("✅ SingleInstanceGuard passed all tests!\n")
    }

    // MARK: - Test 33: HTTP cache and cookies left by URLSession.shared (≤ 1.2.0)

    static func testLegacyNetworkStores() {
        print("Testing LegacyNetworkStores...")
        let fm = FileManager.default
        let home = NSTemporaryDirectory() + "lightspot-legacy-\(getpid())"
        let library = home + "/Library"
        try? fm.removeItem(atPath: home)
        try? fm.createDirectory(atPath: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: home) }
        let id = "com.lightspot.app"
        func make(_ relative: String, directory: Bool = false) {
            let path = library + "/" + relative
            if directory {
                try? fm.createDirectory(atPath: path, withIntermediateDirectories: true)
            } else {
                try? fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                fm.createFile(atPath: path, contents: Data("x".utf8))
            }
        }
        func exists(_ relative: String) -> Bool { fm.fileExists(atPath: library + "/" + relative) }
        func tree() -> [String] { (fm.subpaths(atPath: home) ?? []).sorted() }

        // 1. Fresh install, no ~/Library at all: nothing is created, not even the folders.
        assertEqual(LegacyNetworkStores.remove(bundleIdentifier: id, libraryPath: library), [],
                    "Nothing to remove on a fresh install")
        assertEqual(tree(), [], "A fresh install gets no Library, Caches or HTTPStorages folder")

        // 2. Fresh install on a lived-in Mac: other apps' stores with the same names stay.
        make("Caches/com.other.app/Cache.db")
        make("Caches/com.lightspot.app.helper/Cache.db")
        make("HTTPStorages/com.other.app/httpstorages.sqlite")
        make("HTTPStorages/com.other.app.binarycookies")
        let lived = tree()
        assertEqual(LegacyNetworkStores.leftovers(bundleIdentifier: id, libraryPath: library), [],
                    "No leftovers without Lightspot's own folders")
        assertEqual(LegacyNetworkStores.remove(bundleIdentifier: id, libraryPath: library), [],
                    "Nothing of other apps is removed")
        assertEqual(tree(), lived, "A fresh install leaves the Library exactly as it was")

        // 3. Upgraded from 1.2.0: exactly what URLSession.shared wrote (measured layout).
        for name in ["Cache.db", "Cache.db-wal", "Cache.db-shm"] { make("Caches/\(id)/\(name)") }
        make("Caches/\(id)/fsCachedData/0A1B2C3D-response-body")
        for name in ["httpstorages.sqlite", "httpstorages.sqlite-wal", "httpstorages.sqlite-shm"] {
            make("HTTPStorages/\(id)/\(name)")
        }
        make("HTTPStorages/\(id).binarycookies")
        let known = LegacyNetworkStores.knownPaths(bundleIdentifier: id, libraryPath: library)
        assertEqual(known.count, 8, "Cache.db + WAL + SHM + bodies, HSTS store + WAL + SHM, cookie jar")
        assertEqual(LegacyNetworkStores.leftovers(bundleIdentifier: id, libraryPath: library), known,
                    "Every known entry is found")
        assertEqual(LegacyNetworkStores.remove(bundleIdentifier: id, libraryPath: library), known,
                    "Every known entry is removed")
        assertTrue(!exists("Caches/\(id)"), "The emptied cache folder goes too")
        assertTrue(!exists("HTTPStorages/\(id)"), "The emptied HTTP storage folder goes too")
        assertTrue(!exists("HTTPStorages/\(id).binarycookies"), "The cookie jar is removed")
        assertEqual(tree(), lived, "Only Lightspot's leftovers went; other apps' stores and the parents stay")

        // 4. Idempotent: the next launch finds nothing and touches nothing.
        assertEqual(LegacyNetworkStores.remove(bundleIdentifier: id, libraryPath: library), [],
                    "A second launch has nothing to do")
        assertEqual(tree(), lived, "A second launch changes nothing")

        // 5. Something unknown in the cache folder is kept, and so is the folder.
        make("Caches/\(id)/Cache.db")
        make("Caches/\(id)/not-from-urlsession.dat")
        assertEqual(LegacyNetworkStores.remove(bundleIdentifier: id, libraryPath: library),
                    [library + "/Caches/\(id)/Cache.db"], "Only the known entry is removed")
        assertTrue(exists("Caches/\(id)/not-from-urlsession.dat") && !exists("Caches/\(id)/Cache.db"),
                   "An unknown file and its folder are kept")
        try? fm.removeItem(atPath: library + "/Caches/\(id)")

        // 6. Cookies only (a version that never cached a response): still removed.
        make("HTTPStorages/\(id).binarycookies")
        assertEqual(LegacyNetworkStores.remove(bundleIdentifier: id, libraryPath: library),
                    [library + "/HTTPStorages/\(id).binarycookies"], "A lone cookie jar is removed")
        assertEqual(tree(), lived, "Back to the lived-in Library")

        // 7. An unusable identifier never resolves to Caches or HTTPStorages themselves.
        make("Caches/Cache.db")
        for bad in ["", ".", "..", "com/lightspot"] {
            assertEqual(LegacyNetworkStores.knownPaths(bundleIdentifier: bad, libraryPath: library), [],
                        "No paths for identifier '\(bad)'")
            assertEqual(LegacyNetworkStores.remove(bundleIdentifier: bad, libraryPath: library), [],
                        "Nothing removed for identifier '\(bad)'")
        }
        assertTrue(exists("Caches/Cache.db"), "A file directly in Caches is never touched")

        print("✅ LegacyNetworkStores passed all tests!\n")
    }

    // MARK: - Test 34: System Settings' own search terms

    static func testSettingsSearchTerms() {
        print("Testing SettingsSearchTerms...")
        let provider = SettingsProvider.shared
        let items = provider.items
        func item(_ deepLinkSuffix: String) -> SettingsItem? {
            items.first { $0.deepLink.hasSuffix(deepLinkSuffix) }
        }

        // The pane list: real pane IDs, and stable IDs for panes macOS renamed.
        assertEqual(Set(items.map(\.id)).count, items.count, "Settings item IDs are unique")
        for settingsItem in items {
            assertTrue(settingsItem.deepLink.hasPrefix(SettingsItem.deepLinkScheme), "\(settingsItem.name) is a System Settings link")
            assertTrue(!settingsItem.extensionID.isEmpty && !settingsItem.extensionID.contains(":") && !settingsItem.extensionID.contains("?"),
                       "\(settingsItem.name) names its extension")
        }
        assertTrue(item(":com.apple.systempreferences.GeneralSettings") != nil, "General opens the General pane")
        assertTrue(item(":com.apple.settings.PrivacySecurity.extension") != nil, "Privacy & Security opens its pane")
        assertTrue(!items.contains { $0.deepLink.contains("General-Settings") || $0.deepLink.contains("Privacy-Settings") },
                   "No link to the pane IDs System Settings does not know")
        assertEqual(item("ControlCenter-Settings.extension")?.id, "settings-control-center", "Menu Bar keeps the Control Center ID")
        assertEqual(item("Siri-Settings.extension")?.id, "settings-siri", "Apple Intelligence & Siri keeps the Siri ID")
        assertEqual(item("Touch-ID-Settings.extension")?.id, "settings-touch-id", "Touch ID & Password keeps the Touch ID ID")
        assertEqual(item("Passwords-Settings.extension")?.id, "settings-passwords", "AutoFill & Passwords keeps the Passwords ID")
        let iCloud = item("AppleIDSettings:icloud")
        assertEqual(iCloud?.extensionID, "com.apple.systempreferences.AppleIDSettings", "iCloud is served by the Apple Account extension")
        assertEqual(iCloud?.termSections, ["iCloud"], "iCloud takes only the iCloud section")
        for (query, pane) in [("family", "Family"), ("vpn", "VPN"), ("icloud", "iCloud"), ("game center", "Game Center"),
                              ("apple pay", "Wallet & Apple Pay"), ("about this mac", "About"), ("login items", "Login Items"),
                              ("language", "Language & Region"), ("profiles", "Device Management")] {
            assertEqual(provider.search(SearchQuery(query)).first?.title, pane, "'\(query)' finds \(pane)")
        }

        assertEqual(SettingsSearchTerms.normalize(" Wi\u{2011}Fi\u{00A0}Help "), "wi-fi help", "Apple's typography folds to typed text")

        // A fake ExtensionKit folder shaped like /System/Library/ExtensionKit/Extensions.
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory() + "lightspot-settings-terms-\(getpid())")
        try? fm.removeItem(at: root)
        defer { try? fm.removeItem(at: root) }
        func writePlist(_ object: Any, to url: URL) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try? PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
            fm.createFile(atPath: url.path, contents: data)
        }
        func makePane(_ folder: String, id: String, termsFile: String, point: String = SettingsSearchTerms.settingsExtensionPoint,
                      terms: [String: [String: [(title: String, index: String)]]]) {
            let bundle = root.appendingPathComponent("\(folder).appex/Contents")
            writePlist([
                "CFBundleIdentifier": id,
                "EXAppExtensionAttributes": [
                    "EXExtensionPointIdentifier": point,
                    "SettingsExtensionAttributes": ["searchTermsFileName": termsFile],
                ],
            ], to: bundle.appendingPathComponent("Info.plist"))
            for (language, sections) in terms {
                let plist = sections.mapValues { entries in
                    ["localizableStrings": entries.map { ["title": $0.title, "index": $0.index, "comments": "Localizable index words"] }]
                }
                writePlist(plist, to: bundle.appendingPathComponent("Resources/\(language).lproj/\(termsFile).searchTerms"))
            }
        }
        makePane("DisplaysExt", id: "com.apple.Displays-Settings.extension", termsFile: "DisplaysSearchGroups", terms: [
            "en": ["nightShiftSection": [("Night Shift options", "warm, sunset, night shift")],
                   "ambienceSection": [("True Tone", "white balance")]],
            "vi": ["nightShiftSection": [("Tùy chọn Night Shift", "ấm, hoàng hôn")]],
            "fr": ["nightShiftSection": [("Options de Night Shift", "coucher du soleil")]],
        ])
        makePane("AppleIDSettings", id: "com.apple.systempreferences.AppleIDSettings", termsFile: "appleIDSettingsSearchTerms", terms: [
            "en": ["AppleAccount": [("Apple ID", "two-factor authentication, legacy contact")],
                   "iCloud": [("iCloud", "hide my email, private relay")]],
        ])
        makePane("Wi-Fi", id: "com.apple.wifi-settings-extension", termsFile: "WiFiSettings", terms: [
            "en": ["General_Main": [("Wi\u{2011}Fi", "turn wi\u{2011}fi on, 802.11")]],
        ])
        // Same bundle ID as a real pane, but not a settings extension: never read.
        makePane("SoundIntents", id: "com.apple.Sound-Settings.extension", termsFile: "Sound",
                 point: "com.apple.appintents-extension", terms: ["en": ["Sound": [("Decoy volume", "decoyword")]]])

        func row(_ query: String, _ pane: String) -> SearchResult? {
            provider.search(SearchQuery(query)).first { $0.title == pane }
        }

        assertTrue(provider.loadSearchTerms(from: [root], languages: ["en"]) > 0, "Fixture terms are indexed")
        assertEqual(row("night shift options", "Displays")?.score, 90, "An exact entry title scores 90")
        assertEqual(row("sunset", "Displays")?.subtitle, "System Settings → Displays → Night Shift options",
                    "An index word finds its pane and names the setting")
        assertTrue((row("sunset", "Displays")?.score ?? 100) < 60, "An index word alone never makes a Top Hit")
        assertEqual(row("shift", "Displays")?.subtitle, "System Settings → Displays → Night Shift options", "A later word of a title matches")
        assertEqual(row("white bal", "Displays")?.subtitle, "System Settings → Displays → True Tone", "A prefix of an index phrase matches")
        let display = provider.search(SearchQuery("display")).first
        assertEqual(display?.title, "Displays", "The pane name still leads")
        assertEqual(display?.subtitle, "System Settings → Displays", "A name match keeps the plain subtitle")
        assertEqual(provider.search(SearchQuery("hide my email")).first?.title, "iCloud", "iCloud takes the iCloud section")
        assertEqual(row("legacy contact", "Apple Account")?.subtitle, "System Settings → Apple Account → Apple ID",
                    "Apple Account takes the account section")
        assertTrue(row("legacy contact", "iCloud") == nil, "iCloud does not take the account section")
        assertEqual(row("turn wi-fi", "Wi-Fi")?.subtitle, "System Settings → Wi-Fi → Wi\u{2011}Fi", "A typed hyphen matches U+2011")
        assertTrue(row("decoyword", "Sound") == nil, "An extension of another kind is not read")
        assertTrue(!provider.search(SearchQuery("w")).contains { $0.subtitle.components(separatedBy: " → ").count > 2 },
                   "A single letter does not match System Settings terms")
        assertTrue(row("hoàng hôn", "Displays") == nil, "A language the user does not use is not read")

        // Every preferred language is searched; the earlier one names the setting on a tie.
        provider.loadSearchTerms(from: [root], languages: ["vi-VN", "en"])
        assertEqual(row("hoàng hôn", "Displays")?.subtitle, "System Settings → Displays → Tùy chọn Night Shift",
                    "A Vietnamese term finds the pane")
        assertEqual(row("shift", "Displays")?.subtitle, "System Settings → Displays → Tùy chọn Night Shift", "The first language wins a tie")
        assertTrue(row("coucher", "Displays") == nil, "Only preferred languages are read")
        provider.loadSearchTerms(from: [root], languages: ["en-VN", "vi-VN"])
        assertEqual(row("shift", "Displays")?.subtitle, "System Settings → Displays → Night Shift options", "English first wins the tie back")

        assertEqual(provider.loadSearchTerms(from: [], languages: ["en"]), 0, "No extensions, no terms")
        assertTrue(row("sunset", "Displays") == nil, "Without terms, only names and keywords match")

        print("✅ SettingsSearchTerms passed all tests!\n")
    }

    // MARK: - Test 35: cdm's rules

    /// The rules snapshot build.sh ships in the app, read from the checkout the runner starts in.
    static var bundledCdmRules: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/Resources/cdm-rules", isDirectory: true)
    }

    static func testCleanDevMacRules() {
        print("Testing CleanDevMac rules...")

        // The snapshot shipped in the app is cdm's own rules folder, and it parses whole.
        guard let bundled = CleanDevMacRules.load(directory: bundledCdmRules, source: .bundled) else {
            print("❌ FAIL: Resources/cdm-rules did not load (run the tests from the repository root)")
            exit(1)
        }
        func rule(_ name: String) -> CleanDevMacRule? { bundled.rules.first { $0.name == name } }
        assertEqual(bundled.source, .bundled, "The snapshot is the bundled source")
        assertEqual(rule("Xcode derived data & device support")?.method, .rm, "Xcode caches are deleted")
        assertEqual(rule("Xcode derived data & device support")?.isDefault, true, "Xcode caches are a safe default")
        assertEqual(rule("Xcode archives")?.isDefault, false, "Archives are opt-in")
        assertEqual(rule("Go module cache")?.method, .rmforce, "The read-only Go module cache is made writable first")
        assertEqual(rule("Empty the Trash")?.method, .emptytrash, "Emptying the Trash keeps its own method")
        let images = rule("Unused Android system images")
        assertEqual(images?.kind, .androidImages, "Android images keep their kind")
        assertTrue(images?.patterns.allSatisfy { $0.contains("system-images") } == true, "Android image candidates come from `images`")
        assertTrue(rule("Browser caches")?.procs.contains("Google Chrome") == true, "A rule's procs are read")
        let idle = rule("Idle AVD image")
        assertEqual(idle?.kind, .androidIdleImages, "Idle AVDs' images keep their kind")
        assertEqual(idle?.idleDays, 60, "...and go by 60 days")
        assertTrue(idle?.patterns.allSatisfy { $0.contains("system-images") } == true, "...from `images`")
        let older = rule("Older Android build-tools & platforms")
        assertEqual(older?.kind, .olderVersions, "Older SDK versions keep their kind")
        assertTrue(older?.patterns.contains("~/Library/Android/sdk/build-tools/*") == true, "...from `candidates`")
        let transcripts = rule("Claude Code transcripts older than 30 days")
        assertEqual(transcripts?.kind, .claudeTranscripts, "Old Claude Code transcripts keep their kind")
        assertEqual(transcripts?.patterns, ["~/.claude/projects/*"], "...from `candidates`")
        assertEqual(transcripts?.idleDays, 30, "...go by 30 days")
        assertEqual(transcripts?.method, .trash, "...go to the Trash")
        assertEqual(transcripts?.isDefault, false, "...and are never ticked")
        assertEqual(rule("PlatformIO platforms & toolchains")?.isDefault, false, "Installed toolchains are opt-in")
        assertTrue(bundled.rules.allSatisfy { $0.patterns.allSatisfy { pattern in
            pattern.hasPrefix("~/") || CleanDevMacEngine.userFolderTokens.contains { pattern.hasPrefix($0.token) }
        } }, "Every bundled pattern is under the home folder or in the user's own temp folders")
        let clones = rule("Leftover Chrome app copies")
        assertEqual(clones?.kind, .codeSignClones, "Chrome's leftover copies keep their kind")
        assertEqual(clones?.patterns, ["@boot-temp/*.code_sign_clone/code_sign_clone.*"], "...from `candidates`, in the user folder's X")
        assertEqual(clones?.isDefault, true, "...and are ticked: nothing comes back for them")
        assertEqual(rule("Clang module cache")?.patterns, ["@cache/clang/ModuleCache"], "Clang's module cache is in the user folder's C")
        assertTrue(rule("Node / npm cache")?.patterns.contains("@temp/node-compile-cache") == true, "Node's compile cache, in its T")
        assertEqual(bundled.terminalOnly, ["Rust toolchain", "Rust offline docs", "Docker / Podman reclaimable data", "Orphaned app data"],
                    "Rust toolchains and their docs, Docker / Podman and orphaned app data are left to cdm in the terminal")
        for name in ["node_modules folders", "Git-ignored files (all repos)", "Docker / Podman reclaimable data", "Orphaned app data",
                     "Rust toolchain", "Rust offline docs"] {
            assertTrue(rule(name) == nil, "'\(name)' is not a cache rule")
        }
        let projects = bundled.projects
        assertEqual(projects.roots, ["~"], "The repo scan starts at the home folder")
        assertEqual(projects.maxDepth, 6, "...goes six levels down")
        assertEqual(projects.maxRepos, 400, "...asks git about at most 400 repos")
        assertEqual(projects.groups, ["~/.gemini/antigravity/brain"], "...and groups an agent's session repos")
        assertTrue(projects.prune.contains("Library") && projects.prune.contains(".npm"), "...never entering Library or tool caches")
        assertEqual(projects.method(forName: "node_modules"), .rm, "node_modules is deleted")
        assertEqual(projects.method(forName: "__pycache__"), .rm, "__pycache__ is deleted")
        assertTrue(projects.method(forName: "src") == nil, "a name the rules do not list is not junk")
        assertEqual(projects.gitignoreMethod, .trash, "other git-ignored files go to the Trash")
        assertTrue(projects.categoryNames.contains("node_modules folders") && projects.categoryNames.contains("Git-ignored files (all repos)"),
                   "The repo scan's categories are named")

        // cdm's defaults for missing fields, and what is left out.
        let file = Data("""
        {"categories": [
          {"icon": "🧪", "name": "No method", "paths": ["~/a"], "default": true},
          {"name": "Unknown method", "method": "shred", "paths": ["~/b"]},
          {"name": "Unknown kind", "kind": "future", "method": "rm", "paths": ["~/c"], "images": ["~/x"]},
          {"name": "Images", "kind": "android-images", "method": "rm", "paths": ["~/everything"], "images": ["~/img/*"]},
          {"name": "No paths", "method": "rm"},
          {"name": "Repo junk", "kind": "project", "method": "rm", "dirs": ["node_modules", "build*"]},
          {"name": "Ignored", "kind": "gitignore", "method": "trash"},
          {"name": "Docker", "kind": "container", "method": "prune", "engines": ["docker"]},
          {"name": "Procs", "method": "trash", "paths": ["~/d"], "procs": ["Code", ""]}
        ]}
        """.utf8)
        let parsed = CleanDevMacRules.parsePatternFile(file)
        assertEqual(parsed?.rules.map(\.name), ["No method", "Unknown kind", "Images", "Procs"], "Only categories cdm would act on are kept")
        assertEqual(parsed?.rules.first?.method, .rm, "A missing method is rm")
        assertEqual(parsed?.rules.first?.isDefault, true, "default is read")
        assertEqual(parsed?.rules.first?.kind, .paths, "A missing kind is paths")
        assertEqual(parsed?.rules[1].kind, .paths, "An unknown kind is read as paths, as cdm reads it")
        assertEqual(parsed?.rules[1].patterns, ["~/c"], "...from `paths`, never another field")
        assertEqual(parsed?.rules[2].patterns, ["~/img/*"], "Android images never fall back to `paths`")
        assertEqual(parsed?.rules[3].method, .trash, "trash is read")
        assertEqual(parsed?.rules[3].procs, ["Code"], "Empty process names are dropped")
        assertEqual(parsed?.terminalOnly, ["Docker"], "A container category is left to cdm")
        assertEqual(parsed?.projects.dirs, [CleanDevMacProjectRules.JunkName(name: "node_modules", method: .rm)],
                    "A project category's names feed the repo scan; a name with a wildcard is dropped, as cdm drops it")
        assertEqual(parsed?.projects.gitignoreMethod, .trash, "A gitignore category turns on the git-ignored pass")
        assertEqual(parsed?.projects.categoryNames, ["Repo junk", "Ignored"], "...and both are named")
        let scanOnly = Data(#"{"scan": {"roots": ["~/code"], "maxDepth": "deep", "maxRepos": 12, "prune": ["vendor"]}}"#.utf8)
        let scanFile = CleanDevMacRules.parsePatternFile(scanOnly)
        assertEqual(scanFile?.projects.roots, ["~/code"], "scan.roots are read")
        assertEqual(scanFile?.maxDepth, 6, "A maxDepth that is not a number falls back to 6, as in cdm")
        assertEqual(scanFile?.maxRepos, 12, "maxRepos is read")
        assertTrue(CleanDevMacRules.parsePatternFile(Data("not json".utf8)) == nil, "A broken file does not parse")

        // The kinds that work out their offer read their globs from a field of their own,
        // and the idle ones need an age.
        let kinds = Data("""
        {"categories": [
          {"name": "Older", "kind": "older-versions", "method": "rm", "paths": ["~/all"], "candidates": ["~/sdk/build-tools/*"]},
          {"name": "Idle", "kind": "android-idle-images", "method": "rm", "idleDays": 60, "paths": ["~/all"], "images": ["~/img/*"]},
          {"name": "Idle, as text", "kind": "android-idle-images", "idleDays": "7", "images": ["~/img/*"]},
          {"name": "Idle, no age", "kind": "android-idle-images", "images": ["~/img/*"]},
          {"name": "Idle, bad age", "kind": "android-idle-images", "idleDays": 6.5, "images": ["~/img/*"]},
          {"name": "Talks", "kind": "claude-transcripts", "method": "rm", "default": true, "idleDays": 30, "candidates": ["~/.claude/projects/*"]},
          {"name": "Talks, no age", "kind": "claude-transcripts", "method": "trash", "idleDays": -1, "candidates": ["~/p/*"]},
          {"name": "Rust", "kind": "rust-toolchains", "method": "rustup", "candidates": ["~/.rustup/toolchains/*"]}
        ]}
        """.utf8)
        let parsedKinds = CleanDevMacRules.parsePatternFile(kinds)
        assertEqual(parsedKinds?.rules.map(\.name), ["Older", "Idle", "Idle, as text", "Talks"],
                    "An idle kind without a whole number of days, 0 or more, offers nothing")
        assertEqual(parsedKinds?.rules[0].kind, .olderVersions, "older-versions is read")
        assertEqual(parsedKinds?.rules[0].patterns, ["~/sdk/build-tools/*"], "...from `candidates`, never `paths`")
        assertEqual(parsedKinds?.rules[1].patterns, ["~/img/*"], "android-idle-images is read from `images`")
        assertEqual(parsedKinds?.rules[1].idleDays, 60, "...with its age")
        assertEqual(parsedKinds?.rules[2].idleDays, 7, "An age written as digits is read, as cdm reads it")
        assertEqual(parsedKinds?.rules[3].method, .trash, "Transcripts go to the Trash, whatever the rule says")
        assertEqual(parsedKinds?.rules[3].isDefault, false, "...and are never ticked, whatever the rule says")
        assertEqual(parsedKinds?.terminalOnly, ["Rust"], "rust-toolchains is left to cdm, which removes them with rustup")
        assertTrue(parsedKinds?.rules.allSatisfy { $0.patterns != ["~/all"] } == true, "No new kind ever reads `paths`")

        // index.json names files that get joined onto a folder or a URL.
        for name in ["dev-caches.json", "app_caches.json", "rules2.json"] {
            assertTrue(CleanDevMacRules.isSafeFileName(name), "'\(name)' is a rule file name")
        }
        for name in ["../secrets.json", "/etc/x.json", "a/b.json", ".hidden.json", "rules.txt", "x..json", ".json",
                     "ünicode.json", "a b.json", "a%2F.json"] {
            assertTrue(!CleanDevMacRules.isSafeFileName(name), "'\(name)' is refused")
        }
        let index = Data(#"{"patternFiles": ["dev.json", "../escape.json", 7, "app.json"], "orphanConfig": "orphans.json"}"#.utf8)
        assertEqual(CleanDevMacRules.patternFileNames(fromIndex: index), ["dev.json", "app.json"], "Unsafe and non-string names are dropped")
        assertTrue(CleanDevMacRules.patternFileNames(fromIndex: Data("[".utf8)) == nil, "A broken index does not parse")

        // One parsed file at least: a load failure must not look like a clean Mac.
        let dev = Data(#"{"categories": [{"name": "Dev", "method": "rm", "paths": ["~/dev"]}]}"#.utf8)
        let set = CleanDevMacRules.ruleSet(index: index, files: ["dev.json": dev, "app.json": Data("{oops".utf8)], source: .remote)
        assertEqual(set?.rules.map(\.name), ["Dev"], "A broken file is skipped, the rest kept")
        assertEqual(set?.terminalOnly, ["Orphaned app data"], "An orphan config is left to cdm")
        assertTrue(CleanDevMacRules.ruleSet(index: index, files: [:], source: .remote) == nil, "No file at all is a failure")

        // Fetched over HTTPS from GitHub's raw host only, before and after any redirect.
        assertTrue(CleanDevMacRules.isAllowedRemoteURL(CleanDevMacRules.remoteBase.appendingPathComponent("index.json")),
                   "cdm's raw rules are allowed")
        for bad in ["http://raw.githubusercontent.com/x.json", "https://raw.githubusercontent.com.evil.example/x.json",
                    "https://github.com/cleandevmac/cdm", "https://evil.example/raw.githubusercontent.com/x.json"] {
            assertTrue(!CleanDevMacRules.isAllowedRemoteURL(URL(string: bad)!), "\(bad) is refused")
        }
        assertEqual(CleanDevMacRules.localDirectory(home: "/Users/test").path, "/Users/test/.cleandevmac/rules", "cdm's local rules folder")

        print("✅ CleanDevMac rules passed all tests!\n")
    }

    // MARK: - Test 36: cdm's engine — expansion, sizing, the safety gate, deletion

    static func testCleanDevMacEngine() {
        print("Testing CleanDevMac engine...")
        let fm = FileManager.default
        // The home is reached through a symlink, as a relocated home would be, so the
        // lexical and the physical checks of the safety gate see different paths.
        let realHome = NSTemporaryDirectory() + "lightspot-cdm-real-\(getpid())"
        let home = NSTemporaryDirectory() + "lightspot-cdm-home-\(getpid())"
        let outside = NSTemporaryDirectory() + "lightspot-cdm-outside-\(getpid())"
        for path in [home, realHome, outside] { try? fm.removeItem(atPath: path) }
        try? fm.createDirectory(atPath: realHome, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: outside, withIntermediateDirectories: true)
        try? fm.createSymbolicLink(atPath: home, withDestinationPath: realHome)
        defer {
            CleanDevMacEngine.makeWritable(realHome)
            chmod(outside, 0o755)
            for path in [home, realHome, outside] { try? fm.removeItem(atPath: path) }
        }
        let physicalHome = CleanDevMacEngine.physicalPath(home)
        assertTrue(physicalHome != home && physicalHome.hasSuffix("/lightspot-cdm-real-\(getpid())"), "The home resolves through its symlink")

        @discardableResult
        func make(_ relative: String, bytes: Int = 1) -> String {
            let path = home + "/" + relative
            try? fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            fm.createFile(atPath: path, contents: Data(repeating: 0x61, count: bytes))
            return path
        }
        @discardableResult
        func write(_ path: String, _ text: String) -> String {
            try? fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            fm.createFile(atPath: path, contents: Data(text.utf8))
            return path
        }
        @discardableResult
        func mkdir(_ relative: String) -> String {
            let path = home + "/" + relative
            try? fm.createDirectory(atPath: path, withIntermediateDirectories: true)
            return path
        }

        // 1. Paths
        assertEqual(CleanDevMacEngine.expandTilde("~/.npm/_cacache", home: "/Users/a"), "/Users/a/.npm/_cacache", "~/ resolves against home")
        assertEqual(CleanDevMacEngine.expandTilde("~", home: "/Users/a"), "/Users/a", "~ alone is home")
        assertEqual(CleanDevMacEngine.expandTilde("~other/x", home: "/Users/a"), "~other/x", "~user is not expanded")
        assertEqual(CleanDevMacEngine.expandTilde("/abs", home: "/Users/a"), "/abs", "An absolute pattern is kept")
        assertTrue(CleanDevMacEngine.endsWithAny("/sdk/system-images/android-34/x", ["system-images/android-34/x"]), "A suffix after / matches")
        assertTrue(!CleanDevMacEngine.endsWithAny("/sdk/system-images/android-34/x", ["roid-34/x"]), "Part of a component does not")
        assertTrue(!CleanDevMacEngine.endsWithAny("/a", [""]), "An empty entry matches nothing")
        assertTrue(CleanDevMacEngine.isOutOfScope(home + "/Library/Containers/*/Data", home: home), "Sandbox containers are not read")
        assertTrue(CleanDevMacEngine.isOutOfScope(home + "/Library/Group Containers", home: home), "...nor group containers")
        assertTrue(!CleanDevMacEngine.isOutOfScope(home + "/Library/ContainersX/a", home: home), "...and nothing else by prefix")

        make(".cache/vite/deps/chunk.js", bytes: 5000)
        mkdir(".cache/empty")
        make("Library/Application Support/Code/Code Cache/js/0", bytes: 3000)
        make("Library/Application Support/Slack/Code Cache/js/0", bytes: 3000)
        make("Library/Application Support/Slack/.hidden")
        make(".zcompdump-host-5.9")
        make("Library/Containers/com.example.sandboxed/Data/Library/Caches/blob")
        make("Documents/project/build/out.o")
        let matched = CleanDevMacEngine.matchedPaths(patterns: [
            "~/.cache/vite", "~/.cache/empty", "~/.cache/missing",
            "~/Library/Application Support/*/Code Cache", "~/.zcompdump*",
            "~/Library/Containers/*/Data/Library/Caches", "~/Documents/project/build", "~/.cache/vite",
        ], home: home, physicalHome: physicalHome)
        assertEqual(matched, [
            home + "/.cache/vite",
            home + "/Library/Application Support/Code/Code Cache",
            home + "/Library/Application Support/Slack/Code Cache",
            home + "/.zcompdump-host-5.9",
        ], "Existing, non-empty, safe matches in pattern order, once each; empty, missing, sandboxed and protected left out")
        assertEqual(CleanDevMacEngine.expandGlob(home + "/Library/Application Support/Slack/*"),
                    [home + "/Library/Application Support/Slack/Code Cache"], "* never matches a leading dot, as in the shell")

        // 2. Android system images an AVD boots from are never offered.
        let sdk = "Library/Android/sdk/system-images"
        make("\(sdk)/android-34/google_apis/arm64-v8a/system.img", bytes: 100)
        make("\(sdk)/android-33/default/x86_64/system.img", bytes: 100)
        make("\(sdk)/android-35/google_apis_playstore/arm64-v8a/system.img", bytes: 100)
        make("\(sdk)/android-36/default/arm64-v8a/system.img", bytes: 100)
        write(home + "/.android/avd/Pixel_8.avd/config.ini", "hw.cpu.arch=arm64\r\nimage.sysdir.1 = system-images/android-34/google_apis/arm64-v8a/\r\n")
        write(home + "/.android/avd/Tablet.ini", "avd.ini.encoding=UTF-8\npath=\(outside)/Tablet.avd\n")
        write(outside + "/Tablet.avd/config.ini", "image.sysdir.1=system-images/android-35/google_apis_playstore/arm64-v8a/")
        write(outside + "/avdhome/Wear.avd/config.ini", "image.sysdir.1=system-images/android-36/default/arm64-v8a\n")
        let refs = CleanDevMacEngine.avdImageRefs(home: home, environment: ["ANDROID_AVD_HOME": outside + "/avdhome"])
        assertEqual(Set(refs), ["system-images/android-34/google_apis/arm64-v8a", "system-images/android-35/google_apis_playstore/arm64-v8a",
                                "system-images/android-36/default/arm64-v8a"],
                    "Images in use: an AVD's own config, one an .ini points at elsewhere, and one under ANDROID_AVD_HOME")
        assertEqual(CleanDevMacEngine.matchedPaths(patterns: ["~/\(sdk)/*/*/*"], home: home, physicalHome: physicalHome, skip: refs),
                    [home + "/\(sdk)/android-33/default/x86_64"], "Only the image no AVD uses is offered")

        // 2b. An image only idle AVDs boot is offered, naming them (cdm's android-idle-images).
        //     config.ini is written today, as Android Studio rewrites it without booting.
        @discardableResult
        func age(_ path: String, days: Double) -> String {
            try? fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -days * 86_400)], ofItemAtPath: path)
            return path
        }
        let idleAVDs = outside + "/idle-avds"
        func avd(_ name: String, image: String, ranDaysAgo days: Double) {
            let folder = idleAVDs + "/\(name).avd"
            write(folder + "/config.ini", "image.sysdir.1=system-images/\(image)/\n")
            write(idleAVDs + "/\(name).ini", "path=\(folder)\n")
            for file in ["hardware-qemu.ini", "userdata-qemu.img.qcow2"] { age(write(folder + "/" + file, "x"), days: days) }
        }
        make("\(sdk)/android-30/android-tv/arm64-v8a/system.img", bytes: 100)
        make("\(sdk)/android-31/google_apis/arm64-v8a/system.img", bytes: 100)
        avd("atv", image: "android-30/android-tv/arm64-v8a", ranDaysAgo: 81)
        avd("pixel", image: "android-31/google_apis/arm64-v8a", ranDaysAgo: 3)
        let idleEnvironment = ["ANDROID_AVD_HOME": idleAVDs]
        let now = Int(Date().timeIntervalSince1970)
        func idle(_ days: Int) -> [CleanDevMacEngine.IdleImage] {
            CleanDevMacEngine.idleImages(patterns: ["~/\(sdk)/*/*/*"], users: CleanDevMacEngine.avdImageUsers(home: home, environment: idleEnvironment),
                                         days: days, now: now, home: home, physicalHome: physicalHome)
        }
        let atvLast = CleanDevMacEngine.avdLastStarted(idleAVDs + "/atv.avd")
        assertTrue((now - atvLast) / 86_400 == 81, "An AVD last ran when its newest file but config.ini was written")
        assertEqual(idle(60).map(\.path), [home + "/\(sdk)/android-30/android-tv/arm64-v8a"], "Only the image only an idle AVD boots is offered")
        assertEqual(idle(60).first?.avds, ["atv"], "...naming the AVD once, though it is found twice")
        assertEqual(idle(60).first?.lastStarted, atvLast, "...and when it last ran")
        assertEqual(idle(90), [], "At 90 days, an AVD last run 81 days ago is not idle")
        avd("tv2", image: "android-30/android-tv/arm64-v8a", ranDaysAgo: 1)
        assertEqual(idle(60), [], "One recently run AVD keeps the image, however idle the others")
        try? fm.removeItem(atPath: idleAVDs + "/tv2.avd")
        try? fm.removeItem(atPath: idleAVDs + "/tv2.ini")
        avd("tv3", image: "android-30/android-tv/arm64-v8a", ranDaysAgo: 200)
        assertEqual(idle(60).first?.avds, ["atv", "tv3"], "Every idle AVD on the image is named")
        let neverRun = age(write(idleAVDs + "/new.avd/config.ini", "image.sysdir.1=x/\n"), days: 5)
        let configDate = (try? fm.attributesOfItem(atPath: neverRun)[.modificationDate] as? Date)?.map { Int($0.timeIntervalSince1970) }
        assertEqual(CleanDevMacEngine.avdLastStarted(idleAVDs + "/new.avd"), configDate, "An AVD that never ran is as old as its config.ini")
        assertEqual(CleanDevMacEngine.avdLastStarted(home + "/no-such.avd"), 0, "No folder: 0")

        // 2c. All but the newest version of each family (cdm's older-versions).
        func newest(_ names: [String]) -> String? {
            CleanDevMacEngine.newestVersion(names.map { "/x/" + $0 }).map { ($0 as NSString).lastPathComponent }
        }
        assertEqual(newest(["34.0.0", "37.0.0", "36.1.0", "35.0.0", "36.0.0"]), "37.0.0", "The highest build-tools version")
        assertEqual(newest(["9.0.0", "10.0.0"]), "10.0.0", "10 is newer than 9: numbers, not strings")
        assertEqual(newest(["android-35", "android-37.0", "android-36.1"]), "android-37.0", "37.0 above 36.1 above 35")
        assertEqual(newest(["android-36.1", "android-36"]), "android-36.1", "android-36.1 is newer than android-36")
        assertEqual(newest(["36.0.0-rc1", "36.0.0"]), "36.0.0", "A release outranks its own pre-release")
        assertEqual(newest(["36.0.0", "36.0.1-rc1"]), "36.0.1-rc1", "A pre-release of a later version still wins")
        assertEqual(newest(["android-UpsideDownCake", "android-34"]), "android-34", "A codename with no number is oldest")
        assertEqual(newest(["6.9", "07.1"]), "07.1", "A leading zero does not make a field smaller")
        for version in ["34.0.0", "35.0.0", "36.1.0", "37.0.0"] { make("sdk2/build-tools/\(version)/aapt", bytes: 10) }
        for platform in ["android-35", "android-36.1"] { make("sdk2/platforms/\(platform)/android.jar", bytes: 10) }
        make("sdk2/ndk/25.2.9519653/source.properties", bytes: 10)
        mkdir("sdk2/build-tools/38.0.0")
        let olderPaths = CleanDevMacEngine.olderVersionPaths(
            patterns: ["~/sdk2/build-tools/*", "~/sdk2/platforms/*", "~/sdk2/ndk/*", "~/sdk2/build-tools/3*"],
            home: home, physicalHome: physicalHome)
        assertEqual(Set(olderPaths), Set(["build-tools/34.0.0", "build-tools/35.0.0", "build-tools/36.1.0", "platforms/android-35"].map { home + "/sdk2/" + $0 }),
                    "All but the newest of each family; a family of one and an empty folder offer nothing")
        assertEqual(olderPaths.count, Set(olderPaths).count, "A version two patterns reach is offered once")

        // 2d. Old Claude Code sessions (cdm's claude-transcripts): each transcript with its
        //     folder; never a running session, a fresh one, or anything but a session id.
        let project = home + "/.claude/projects/-Users-me-app"
        let oldID = "11111111-1111-4111-8111-111111111111", liveID = "33333333-3333-4333-8333-333333333333"
        age(write(project + "/\(oldID).jsonl", "{}"), days: 45)
        write(project + "/\(oldID)/subagents/agent-a.jsonl", "{}")
        age(write(project + "/\(liveID).jsonl", "{}"), days: 45)
        age(write(project + "/44444444-4444-4444-8444-444444444444.jsonl", "{}"), days: 2)
        age(write(project + "/notes.jsonl", "{}"), days: 45)
        age(write(project + "/memory/MEMORY.md", "note"), days: 45)
        write(home + "/.claude/sessions/4242.json", #"{"pid":4242,"sessionId":"\#(liveID)","kind":"interactive"}"#)
        func transcripts(_ days: Int) -> CleanDevMacEngine.OldTranscripts {
            CleanDevMacEngine.oldTranscripts(patterns: ["~/.claude/projects/*"], days: days, now: now, home: home, physicalHome: physicalHome)
        }
        assertEqual(transcripts(30).paths, [project + "/\(oldID).jsonl", project + "/\(oldID)"],
                    "The old session's transcript and folder; not the running one, the fresh one, notes or memory/")
        assertEqual(transcripts(30).sessions, 1, "One session")
        assertEqual(transcripts(60).sessions, 0, "At 60 days, a 45-day-old session is kept")
        assertEqual(CleanDevMacEngine.runningSessionIDs(claudeFolder: home + "/.claude"), [liveID], "Running sessions are read from sessions/")
        try? fm.removeItem(atPath: home + "/.claude/sessions/4242.json")
        assertEqual(transcripts(30).sessions, 2, "Once its process has gone, the old session is offered too")
        assertTrue(CleanDevMacEngine.isSessionID(oldID) && !CleanDevMacEngine.isSessionID("memory")
                   && !CleanDevMacEngine.isSessionID(String(repeating: "ア", count: 36)), "A session id is a UUID")

        // "Older than 30 days" is what cdm's `find -mtime +30` says: whole days, so 31.
        let ages = outside + "/find-ages"
        for (name, seconds) in [("29d", 29 * 86_400), ("30d1h", 30 * 86_400 + 3_600), ("30d23h", 30 * 86_400 + 82_800), ("31d1m", 31 * 86_400 + 60)] {
            try? fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: TimeInterval(now - seconds))],
                                  ofItemAtPath: write(ages + "/" + name, "x"))
        }
        let byFind = CleanDevMacEngine.output(of: "/usr/bin/find", [ages, "-type", "f", "-mtime", "+30"], timeout: 10)
            .split(separator: "\n").map { URL(fileURLWithPath: String($0)).lastPathComponent }.sorted()
        let byAge = ((try? fm.contentsOfDirectory(atPath: ages)) ?? []).filter { name in
            var info = stat()
            return lstat(ages + "/" + name, &info) == 0 && CleanDevMacEngine.isOlder(mtime: Int(info.st_mtimespec.tv_sec), than: 30, now: now)
        }.sorted()
        assertEqual(byAge, byFind, "Older than 30 days is what find -mtime +30 says")
        assertEqual(byFind, ["31d1m"], "...which is 31 whole days, not 30 and 23 hours")
        assertTrue(!CleanDevMacEngine.isOlder(mtime: now + 3_600, than: 0, now: now), "A file dated in the future is not old")
        let edge = home + "/edge/.claude/projects/-Users-me-app"
        age(write(edge + "/55555555-5555-4555-8555-555555555555.jsonl", "{}"), days: 30.9)
        age(write(edge + "/66666666-6666-4666-8666-666666666666.jsonl", "{}"), days: 31.05)
        assertEqual(CleanDevMacEngine.oldTranscripts(patterns: ["~/edge/.claude/projects/*"], days: 30, now: now, home: home, physicalHome: physicalHome).paths,
                    [edge + "/66666666-6666-4666-8666-666666666666.jsonl"], "A session 30.9 days old waits a few hours more, as cdm's does")

        // 3. The safety gate: cdm's own test cases. Every refused path exists, so a
        //    refusal can only come from the rule under test.
        for folder in CleanDevMacEngine.protectedFolders { mkdir(folder) }
        let cache = mkdir("Library/Caches/com.example.app")
        let blob = make("Library/Caches/com.example.app/blob")
        write(outside + "/precious", "keep")
        try? fm.createSymbolicLink(atPath: home + "/escape-hatch", withDestinationPath: outside)
        try? fm.createSymbolicLink(atPath: outside + "/into-home", withDestinationPath: home + "/Library/Caches")
        func safe(_ path: String) -> Bool { CleanDevMacEngine.isSafeTarget(path, home: home, physicalHome: physicalHome) }
        assertTrue(safe(cache), "A cache folder under home is reachable")
        assertTrue(safe(blob), "A file under home is reachable")
        assertTrue(safe(physicalHome + "/Library/Caches/com.example.app") == false, "Lexically outside home, through the resolved path, is refused")
        for (path, why) in [("", "an empty path"), ("/", "root"), (home, "home itself"), (home + "/", "home with a slash"),
                            (physicalHome, "the resolved home"), (physicalHome + "/", "the resolved home with a slash"),
                            ("Library/Caches", "a relative path"), ("./Library/Caches", "a dot-relative path"),
                            (home + "/Library/../../etc", "parent traversal"), (home + "/Library/Caches/../Caches", ".. even when it stays home"),
                            (home + "/Library/Caches/nope-xyzzy", "a missing path"), ("/etc", "a system folder"),
                            (outside, "a folder outside home"), (outside + "/precious", "a file outside home"),
                            (home + "/escape-hatch/precious", "a symlinked component that escapes home"),
                            (outside + "/into-home/com.example.app", "a path outside home that resolves into it")] {
            assertTrue(!safe(path), "Refused: \(why)")
        }
        for folder in CleanDevMacEngine.protectedFolders {
            assertTrue(!safe(home + "/" + folder), "Protected: ~/\(folder)")
            assertTrue(!safe(mkdir(folder + "/child")), "Protected child: ~/\(folder)/child")
        }
        assertTrue(safe(home + "/escape-hatch"), "A symlink in home is itself reachable: only the link is ever removed")

        // 4. Sizing matches du -sk: hard links counted once, symlinks not followed.
        let tree = mkdir("sizing")
        make("sizing/a.bin", bytes: 10_000)
        make("sizing/nested/b.bin", bytes: 200_000)
        try? fm.linkItem(atPath: tree + "/a.bin", toPath: tree + "/nested/hardlink.bin")
        try? fm.createSymbolicLink(atPath: tree + "/to-outside", withDestinationPath: outside)
        /// What one `du -sk` over `paths` prints for each of them; 0 for one it prints nothing for.
        func du(_ paths: [String]) -> [Int] {
            let du = Process()
            du.executableURL = URL(fileURLWithPath: "/usr/bin/du")
            du.arguments = ["-sk"] + paths
            let pipe = Pipe()
            du.standardOutput = pipe
            du.standardError = FileHandle.nullDevice
            try? du.run()
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            du.waitUntilExit()
            var printed: [String: Int] = [:]
            for line in output.split(separator: "\n") {
                let fields = line.split(separator: "\t", maxSplits: 1)
                if fields.count == 2, let kb = Int(fields[0]) { printed[String(fields[1])] = kb }
            }
            return paths.map { printed[$0] ?? 0 }
        }
        let duKB = du([tree]).first
        assertTrue((duKB ?? 0) > 200, "du measured the fixture")
        assertEqual(CleanDevMacEngine.allocatedKB(tree), duKB, "Sizes match du -sk")
        assertEqual(CleanDevMacEngine.allocatedKB(home + "/nope"), 0, "A missing path is 0")

        // A row is sized as cdm sizes it, with one du over all its paths: a file hard-linked
        // into two of them counts in the first; once every link has been met du forgets the
        // file, so a folder and then a folder inside it both count it; and a file du has
        // already counted prints nothing.
        make("rows/a/big.bin", bytes: 300_000)
        make("rows/b/own.bin", bytes: 5_000)
        mkdir("rows/c")
        try? fm.linkItem(atPath: home + "/rows/a/big.bin", toPath: home + "/rows/b/big-link.bin")
        try? fm.linkItem(atPath: home + "/rows/a/big.bin", toPath: home + "/rows/c/big-link.bin")
        func row(_ paths: [String]) -> [Int] {
            CleanDevMacEngine.allocatedKB(paths.map { CleanDevMacEngine.usage($0) ?? CleanDevMacEngine.Usage() })
        }
        for order in [["rows/a", "rows/b", "rows/c"], ["rows/b", "rows/a"], ["rows/c", "rows/b", "rows/a"], ["rows", "rows/a"],
                      ["rows/a", "rows/a/big.bin", "rows/b"], ["rows/a/big.bin", "rows/b/big-link.bin"], ["rows/b", "rows/c"]] {
            let paths = order.map { home + "/" + $0 }
            assertEqual(row(paths), du(paths), "A row's sizes are what one du over its paths prints: \(order)")
        }
        let sharedKB = CleanDevMacEngine.allocatedKB(home + "/rows/a/big.bin")
        assertTrue(sharedKB >= 290, "The shared file is measured")
        assertEqual(row([home + "/rows/a", home + "/rows/b"]), [sharedKB, CleanDevMacEngine.allocatedKB(home + "/rows/b") - sharedKB],
                    "The second path leaves out the file the first counted")
        assertEqual(row([home + "/rows/b"]), du([home + "/rows/b"]), "...which a path on its own counts")
        assertTrue(CleanDevMacEngine.usage(home + "/rows", until: .distantPast) == nil,
                   "A walk past its deadline gives up, as cdm's bounded du does")
        assertEqual(CleanDevMacEngine.usage(home + "/rows", oneFileSystem: true).map { CleanDevMacEngine.allocatedKB([$0]) },
                    du([home + "/rows"]), "Staying on one file system changes nothing within one")

        // 5. Deletion, each method, through the gate.
        func delete(_ path: String, _ method: CleanDevMacRule.Method) -> CleanDevMacEngine.DeleteOutcome {
            CleanDevMacEngine.delete(path, method: method, home: home, physicalHome: physicalHome) { url in
                try fm.moveItem(atPath: url.path, toPath: home + "/.Trash/" + url.lastPathComponent)
            }
        }
        let rmTarget = mkdir("Library/Caches/rm-me")
        make("Library/Caches/rm-me/x")
        assertEqual(delete(rmTarget, .rm), .deleted, "rm deletes")
        assertTrue(!fm.fileExists(atPath: rmTarget), "...and the folder is gone")
        assertEqual(delete(rmTarget, .rm), .alreadyGone, "A second pass finds nothing to do")

        // A read-only tree, like Go's module cache.
        let modules = home + "/go/pkg/mod"
        make("go/pkg/mod/example.com/m@v1.0.0/m.go", bytes: 100)
        for file in [modules + "/example.com/m@v1.0.0/m.go"] { chmod(file, 0o444) }
        for dir in [modules + "/example.com/m@v1.0.0", modules + "/example.com", modules] { chmod(dir, 0o555) }
        if case .failed = delete(modules, .rm) {} else { assertTrue(false, "rm cannot delete a read-only tree") }
        assertEqual(delete(modules, .rmforce), .deleted, "rmforce makes it writable, then deletes it")
        assertTrue(!fm.fileExists(atPath: modules), "...all of it")

        mkdir(".Trash")
        let trashTarget = make("Library/Caches/trash-me.log")
        assertEqual(delete(trashTarget, .trash), .trashed, "trash moves to the Trash")
        assertTrue(!fm.fileExists(atPath: trashTarget) && fm.fileExists(atPath: home + "/.Trash/trash-me.log"), "...where it can be restored")

        make(".Trash/old.txt")
        mkdir(".Trash/old folder/sub")
        make(".Trash/.DS_Store")
        assertEqual(delete(home + "/.Trash", .emptytrash), .deleted, "The Trash is emptied")
        assertEqual((try? fm.contentsOfDirectory(atPath: home + "/.Trash")) ?? ["?"], [], "...of everything, hidden files too")
        assertTrue(fm.fileExists(atPath: home + "/.Trash"), "...and the Trash itself stays")
        let notTrash = mkdir("Library/Caches/not-the-trash")
        make("Library/Caches/not-the-trash/keep")
        assertEqual(delete(notTrash, .emptytrash), .unsafe, "emptytrash empties the Trash and nothing else")
        assertTrue(fm.fileExists(atPath: notTrash + "/keep"), "...whatever path its rule names")

        let protectedFile = make("Documents/keep.txt")
        assertEqual(delete(protectedFile, .rm), .unsafe, "The gate refuses a protected file")
        assertTrue(fm.fileExists(atPath: protectedFile), "...which stays")
        assertEqual(delete(home + "/escape-hatch/precious", .rmforce), .unsafe, "...and a path that leaves home through a symlink")
        assertTrue(fm.fileExists(atPath: outside + "/precious"), "...whose target stays")

        // A symlink is removed, never followed: rmforce must not chmod its target either.
        chmod(outside, 0o555)
        try? fm.createSymbolicLink(atPath: home + "/Library/Caches/link-out", withDestinationPath: outside)
        assertEqual(delete(home + "/Library/Caches/link-out", .rmforce), .deleted, "A symlink is deleted")
        var outsideInfo = stat()
        stat(outside, &outsideInfo)
        assertEqual(outsideInfo.st_mode & 0o777, 0o555, "...without making its target writable")
        assertTrue(fm.fileExists(atPath: outside + "/precious"), "...or touching what it points at")
        chmod(outside, 0o755)

        // 6. Formatting, as cdm prints it.
        assertEqual(CleanDevMacEngine.humanKB(0), "0 KB", "Zero")
        assertEqual(CleanDevMacEngine.humanKB(1023), "1023 KB", "Under a MiB stays in KB")
        assertEqual(CleanDevMacEngine.humanKB(1024), "1 MB", "A MiB")
        assertEqual(CleanDevMacEngine.humanKB(1536), "2 MB", "Whole MB, rounded as cdm's awk rounds")
        assertEqual(CleanDevMacEngine.humanKB(1_048_576), "1.00 GB", "A GiB with two decimals")
        assertEqual(CleanDevMacEngine.humanKB(239_356_416), "228.27 GB", "A disk's worth")
        let disk = CleanDevMacEngine.DiskStats(totalKB: 239_356_416, freeKB: 69_782_323)
        assertEqual(disk.usedPercent, 71, "Used share, rounded")
        assertEqual(disk.line, "228.27 GB total · 161.72 GB used (71%) · 66.55 GB free", "cdm's disk line")
        let live = CleanDevMacEngine.diskStats(path: home)
        assertTrue((live?.totalKB ?? 0) > 0 && (live?.freeKB ?? -1) >= 0 && (live?.freeKB ?? 0) <= (live?.totalKB ?? 0), "The home volume is measured")
        assertEqual(CleanDevMacEngine.displayPath(home + "/Library/Caches", home: home), "~/Library/Caches", "home shows as ~")
        assertEqual(CleanDevMacEngine.displayPath(home, home: home), "~", "home itself is ~")
        assertEqual(CleanDevMacEngine.displayPath(home + "-other/x", home: home), home + "-other/x", "A sibling of home is not ~")

        // 7. The clean log, shared with cdm and capped like cdm caps it.
        assertTrue(CleanDevMacEngine.rotatedLog(Data("one\ntwo\n".utf8), now: Date()) == nil, "Under the cap the log is kept whole")
        var big = Data()
        var line = 0
        while big.count <= CleanDevMacEngine.logMaxBytes {
            big.append(contentsOf: "entry \(line) \(String(repeating: "x", count: line % 90))\n".utf8)
            line += 1
        }
        let rotated = CleanDevMacEngine.rotatedLog(big, now: Date()) ?? Data()
        let rotatedLines = String(decoding: rotated, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
        assertTrue(rotatedLines.count > 3 && rotatedLines[1].hasPrefix("Truncated "), "A rotated log says so at the top")
        assertTrue(rotated.count <= CleanDevMacEngine.logKeepBytes + 200, "...and keeps the newest 256 KiB")
        assertTrue(rotatedLines[3].hasPrefix("entry "), "...starting on a whole line")
        assertTrue(rotated.suffix(2000) == big.suffix(2000), "...through the very end")
        CleanDevMacEngine.appendToLog("first\n", home: home)
        CleanDevMacEngine.appendToLog("second\n", home: home)
        assertEqual(try? String(contentsOfFile: home + "/.cleandevmac/clean.log", encoding: .utf8), "first\nsecond\n", "Runs are appended to ~/.cleandevmac/clean.log")

        // 8. Running apps, by the names a rule's procs use.
        let me = String(URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent.prefix(31))
        assertTrue(CleanDevMacEngine.runningProcessNames().contains(me), "The process list includes this runner")

        // 9. What a restart would free: cdm's test_restart.sh cases.
        typealias Volume = CleanDevMacEngine.Volume
        let data = Volume(device: "/dev/disk3s5", mountPoint: "/System/Volumes/Data", usedKB: 201_326_592)
        let vm = Volume(device: "/dev/disk3s6", mountPoint: "/System/Volumes/VM", usedKB: 14_680_064)
        assertEqual(CleanDevMacEngine.swapKB(home: data, vm: vm), 14_680_064, "Swap is the VM volume's Used column, in KiB")
        assertEqual(CleanDevMacEngine.swapKB(home: Volume(device: "/dev/disk5s1", mountPoint: "/Volumes/Work", usedKB: 1), vm: vm), 0,
                    "A VM volume in another container is not this disk's swap")
        assertEqual(CleanDevMacEngine.swapKB(home: Volume(device: "/dev/disk12s5", mountPoint: "/System/Volumes/Data", usedKB: 1),
                                             vm: Volume(device: "/dev/disk1s6", mountPoint: "/System/Volumes/VM", usedKB: 14_680_064)), 0,
                    "disk12s5 and disk1s6 are different containers")
        assertEqual(CleanDevMacEngine.swapKB(home: data, vm: Volume(device: "/dev/disk3s1s1", mountPoint: "/", usedKB: 12_582_912)), 0,
                    "A volume mounted anywhere else is not swap")
        assertEqual(CleanDevMacEngine.swapKB(home: data, vm: nil), 0, "No VM volume, no swap")
        assertEqual(CleanDevMacEngine.swapKB(home: Volume(device: "map auto_home", mountPoint: "/System/Volumes/Data/home", usedKB: 0), vm: vm), 0,
                    "A home that is not on a disk has no swap of its own")
        assertEqual(CleanDevMacEngine.swapKB(home: Volume(device: "devfs", mountPoint: "/dev", usedKB: 0),
                                             vm: Volume(device: "devfs", mountPoint: "/System/Volumes/VM", usedKB: 5)), 0,
                    "...even when the VM row names the same thing")
        assertEqual(CleanDevMacEngine.container(of: "/dev/disk3s1s1"), "/dev/disk3", "A snapshot's device is in its disk's container")
        assertEqual(CleanDevMacEngine.container(of: "/dev/disk12s1"), "/dev/disk12", "...and the whole disk number is kept")

        let tempA = make("temp-a/one.bin", bytes: 50_000)
        make("temp-b/deep/two.bin", bytes: 20_000)
        let homeDevice = CleanDevMacEngine.volume(of: home)?.device ?? "?"
        assertTrue(homeDevice.hasPrefix("/dev/"), "The home volume's device is read")
        assertEqual(CleanDevMacEngine.tempKB(homeDevice: homeDevice, folders: [home + "/temp-a", "", home + "/temp-b", home + "/temp-none", tempA]),
                    CleanDevMacEngine.allocatedKB(home + "/temp-a") + CleanDevMacEngine.allocatedKB(home + "/temp-b"),
                    "Both temp folders are summed; a missing one, a file or no folder at all counts 0")
        assertEqual(CleanDevMacEngine.tempKB(homeDevice: "/dev/disk99s9", folders: [home + "/temp-a"]), 0,
                    "A temp folder on another volume is left out")
        let tempFolders = CleanDevMacEngine.bootTempFolders()
        let getconf = CleanDevMacEngine.output(of: "/usr/bin/getconf", ["DARWIN_USER_TEMP_DIR"], timeout: 5)
        assertEqual(tempFolders, [getconf.trimmingCharacters(in: .newlines), "/private/tmp"],
                    "The temp folders a boot empties: getconf's DARWIN_USER_TEMP_DIR, then /private/tmp")

        // lsof -F output in the order the real one prints it: one plist cache shared by two
        // processes; Chrome holding one deleted 3 GiB file on two descriptors, and a deleted
        // folder; node holding a 1 GiB file.
        let lsofFields = """
        p1317
        cloginwindow
        ftxt
        tREG
        D0x1000010
        s72984
        i98761291
        n/Library/Preferences/Logging/.plist-cache.Cj6gIpVn
        p1355
        cdistnoted
        ftxt
        tREG
        D0x1000010
        s72984
        i98761291
        n/Library/Preferences/Logging/.plist-cache.Cj6gIpVn
        p2001
        cGoogle Chrome
        f41
        tREG
        D0x1000010
        s3221225472
        i555
        n/private/var/folders/xx/T/blob
        f42
        tREG
        D0x1000010
        s3221225472
        i555
        n/private/var/folders/xx/T/blob
        f7
        tDIR
        D0x1000010
        s4096
        i556
        n/private/tmp/gone
        p3003
        cnode
        f19
        tREG
        D0x1000010
        s1073741824
        i777
        n/private/tmp/task.output
        """
        let held = CleanDevMacEngine.heldOpen(lsofFields: lsofFields)
        assertEqual(held.kb, 4_194_375, "Each deleted file counts once, folders not at all")
        assertEqual(held.apps, ["Google Chrome", "node", "loginwindow"], "...and the three biggest holders come biggest first")
        assertEqual(CleanDevMacEngine.heldOpen(lsofFields: "").kb, 0, "No deleted files is 0...")
        assertEqual(CleanDevMacEngine.heldOpen(lsofFields: "").apps, [], "...and no holders")
        assertEqual(CleanDevMacEngine.heldOpen(lsofFields: lsofFields.replacingOccurrences(of: "D0x1000010\ns3221225472\ni555\nn/private/var/folders/xx/T/blob\nf42\ntREG\nD0x1000010",
                                                                                        with: "D0x1000010\ns3221225472\ni555\nn/private/var/folders/xx/T/blob\nf42\ntREG\nD0x2000020")).kb,
                    4_194_375 + 3_145_728, "The same inode on another device is another file")

        assertEqual(CleanDevMacEngine.output(of: "/bin/echo", ["hello"], timeout: 5), "hello\n", "A command's output is read whole")
        var started = Date()
        assertEqual(CleanDevMacEngine.output(of: "/bin/sh", ["-c", "echo first; sleep 30"], timeout: 0.5), "first\n",
                    "A command that runs too long is stopped, and what it printed is kept")
        assertTrue(Date().timeIntervalSince(started) < 3, "...within its time")
        started = Date()
        _ = CleanDevMacEngine.output(of: "/bin/sh", ["-c", "(sleep 30) & sleep 30"], timeout: 0.5)
        assertTrue(Date().timeIntervalSince(started) < 3, "Stopping a command stops its process group, and the pipe closes")
        if fm.isExecutableFile(atPath: "/usr/bin/perl") {
            started = Date()
            _ = CleanDevMacEngine.output(of: "/bin/sh", ["-c", "/usr/bin/perl -e 'setpgrp(0, 0); sleep 10' & sleep 30"], timeout: 0.5)
            assertTrue(Date().timeIntervalSince(started) < 4, "A child that left the group and keeps the pipe open is not waited for")
        }
        // df's Used is the volume's own; statfs's free blocks are the whole APFS container's.
        let dfRows = CleanDevMacEngine.output(of: "/bin/df", ["-Pk", "/System/Volumes/VM", home], timeout: 10)
            .split(separator: "\n").map { $0.split(separator: " ", omittingEmptySubsequences: true).map(String.init) }
        for (row, path) in zip(dfRows.dropFirst(), ["/System/Volumes/VM", home]) where row.count >= 6 {
            let dfUsed = Int(row[2]) ?? -1
            let used = CleanDevMacEngine.volume(of: path)?.usedKB ?? -1
            assertTrue(abs(used - dfUsed) <= max(dfUsed / 100, 4096), "Used is df's for \(row.last ?? path): \(used) KB, df \(dfUsed) KB")
        }

        var estimate = CleanDevMacEngine.RestartEstimate(swapKB: 14_680_064, tempKB: 21_076_377, heldKB: 2_202_010, heldApps: ["Google Chrome", "node"])
        assertEqual(estimate.line(freeKB: 445_644),
                    "A restart would free about 36.20 GB: 14.00 GB of swap, 20.10 GB of temp files, 2.10 GB of deleted files still held open by Google Chrome, node — quitting them frees that part now",
                    "The note names every part, and the apps holding deleted files")
        estimate.heldKB = 43_442
        estimate.heldApps = ["linkd", "sharingd", "Google Chrome"]
        assertEqual(estimate.line(freeKB: 445_644),
                    "A restart would free about 34.14 GB: 14.00 GB of swap, 20.10 GB of temp files, 42 MB of deleted files still held open",
                    "A small held part names no apps")
        estimate.heldKB = 524_288
        assertEqual(estimate.line(freeKB: 445_644),
                    "A restart would free about 34.60 GB: 14.00 GB of swap, 20.10 GB of temp files, 512 MB of deleted files still held open",
                    "A held part under 1 GiB names no apps, whatever the note's floor")
        estimate.heldKB = 1_048_576
        assertEqual(estimate.line(freeKB: 445_644),
                    "A restart would free about 35.10 GB: 14.00 GB of swap, 20.10 GB of temp files, 1.00 GB of deleted files still held open by linkd, sharingd, Google Chrome — quitting them frees that part now",
                    "A held part of exactly 1 GiB names its apps")
        assertEqual(CleanDevMacEngine.RestartEstimate(swapKB: 14_680_064, tempKB: 12).line(freeKB: 445_644),
                    "A restart would free about 14.00 GB: 14.00 GB of swap", "Parts under 1 MiB are left out")
        assertEqual(CleanDevMacEngine.RestartEstimate(swapKB: 102_399).line(freeKB: 0), nil, "Quiet below 100 MiB")
        assertTrue(CleanDevMacEngine.RestartEstimate(swapKB: 102_400).line(freeKB: 0) != nil, "...and speaks at exactly 100 MiB")
        assertEqual(CleanDevMacEngine.RestartEstimate(swapKB: 5_242_956).line(freeKB: 5_242_957), nil, "Quiet while the disk has more free")
        assertTrue(CleanDevMacEngine.RestartEstimate(swapKB: 5_242_956).line(freeKB: 5_242_956) != nil, "...and speaks once it matches the free space")
        let thisMac = CleanDevMacEngine.restartEstimate(home: NSHomeDirectory())
        assertTrue(thisMac.swapKB >= 0 && thisMac.tempKB >= 0 && thisMac.heldKB >= 0 && thisMac.heldApps.count <= 3, "This Mac's own estimate is measured")

        // 10. Claude Code's history note: cdm's test_claude_history.sh cases, in a Claude
        //     Code folder of their own (2d's ~/.claude has sessions of its own).
        let claude = home + "/claude-config"
        let projects = claude + "/projects/-Users-me-app"
        func session(_ number: Int) -> String { String(format: "%08d-0000-4000-8000-000000000000", number) }
        for number in 1...3 { age(write(projects + "/\(session(number)).jsonl", "{}\n"), days: 45) }
        write(projects + "/\(session(4)).jsonl", "{}\n")
        age(write(projects + "/\(session(8)).jsonl", "{}\n"), days: 30.9)
        age(write(projects + "/notes.jsonl", "{}\n"), days: 45)
        age(write(projects + "/sub/\(session(5)).jsonl", "{}\n"), days: 45)
        write(projects + "/memory/MEMORY.md", "# memory\n")
        age(write(outside + "/linked-project/\(session(6)).jsonl", "{}\n"), days: 45)
        try? fm.createSymbolicLink(atPath: claude + "/projects/-linked", withDestinationPath: outside + "/linked-project")
        try? fm.createSymbolicLink(atPath: projects + "/\(session(7)).jsonl", withDestinationPath: projects + "/\(session(1)).jsonl")
        let nowSeconds = now
        let history = CleanDevMacEngine.claudeHistory(folder: claude, now: nowSeconds)
        assertEqual(history?.oldTranscripts, 3,
                    "Sessions past 30 days, right inside a project folder: no other name, no deeper file, no link, not one 30.9 days old")
        assertEqual(history?.keepDays, 30, "...against Claude Code's default limit")
        assertEqual(history?.sizeKB, CleanDevMacEngine.allocatedKB(claude + "/projects"), "...with what projects/ holds")
        assertEqual(history?.note(home: home), nil, "Under 1 GiB of history: no note")
        assertEqual(CleanDevMacEngine.claudeHistory(folder: home + "/.claude", now: nowSeconds)?.oldTranscripts, 2,
                    "2d's two old sessions count; its fresh one, notes and memory/ do not")
        let note = CleanDevMacEngine.ClaudeHistory(folder: home + "/.claude", sizeKB: 11_117_312, oldTranscripts: 3, keepDays: 30).note(home: home)
        assertEqual(note?.summary, "10.60 GB of session history in ~/.claude/projects, 3 transcripts older than 30 days.", "The note says how big, how many old")
        assertEqual(note?.advice,
                    "Claude Code keeps Claude Desktop and Cowork sessions at any age; to have it delete them after 30 days too, add \"desktopSessionCleanupPeriodDays\": 30 to ~/.claude/settings.json",
                    "...and the exact setting")
        assertTrue(CleanDevMacEngine.ClaudeHistory(folder: claude, sizeKB: 1_048_576, oldTranscripts: 1, keepDays: 30).note(home: home) != nil, "Exactly 1 GiB: the note")
        assertEqual(CleanDevMacEngine.ClaudeHistory(folder: claude, sizeKB: 1_048_575, oldTranscripts: 1, keepDays: 30).note(home: home), nil, "...and not a KiB less")
        assertEqual(CleanDevMacEngine.ClaudeHistory(folder: claude, sizeKB: 9_999_999, oldTranscripts: 0, keepDays: 30).note(home: home), nil, "No old transcript: no note")

        write(claude + "/settings.json", "{\n  \"theme\": \"dark\",\n  \"cleanupPeriodDays\" : 40\n}\n")
        assertEqual(CleanDevMacEngine.claudeHistory(folder: claude, now: nowSeconds).map { [$0.oldTranscripts, $0.keepDays] }, [3, 40],
                    "cleanupPeriodDays 40: 45-day-old transcripts still count")
        assertTrue(CleanDevMacEngine.ClaudeHistory(folder: claude, sizeKB: 1_048_576, oldTranscripts: 3, keepDays: 40).note(home: home)?.advice
                    .contains("after 40 days too, add \"desktopSessionCleanupPeriodDays\": 40 to") == true, "The advice uses the user's limit")
        write(claude + "/settings.json", "{ \"cleanupPeriodDays\": 50 }\n")
        assertTrue(CleanDevMacEngine.claudeHistory(folder: claude, now: nowSeconds) == nil, "cleanupPeriodDays 50: nothing older, no note")
        write(claude + "/settings.json", "{ \"desktopSessionCleanupPeriodDays\": 30 }\n")
        assertTrue(CleanDevMacEngine.claudeHistory(folder: claude, now: nowSeconds) == nil, "desktopSessionCleanupPeriodDays set: no note")
        try? fm.removeItem(atPath: claude + "/settings.json")
        assertEqual(CleanDevMacEngine.cleanupPeriodDays(settings: "{\"cleanupPeriodDays\": 0}"), nil, "A limit under a day is ignored")
        assertEqual(CleanDevMacEngine.cleanupPeriodDays(settings: "{\"cleanupPeriodDays\":\n 40}"), nil, "...and so is one split across lines, as grep reads it")
        assertEqual(CleanDevMacEngine.cleanupPeriodDays(settings: "{\"cleanupPeriodDays\": 7, \"cleanupPeriodDays\": 9}"), 7, "The first one counts")
        assertEqual(CleanDevMacEngine.cleanupPeriodDays(settings: "{\"cleanupPeriodDays\": \"40\"}"), nil, "A string is not a number of days")
        write(claude + "/settings.json", "{ \"cleanupPeriodDays\": 99999999999999999 }\n")
        assertTrue(CleanDevMacEngine.claudeHistory(folder: claude, now: nowSeconds) == nil, "A limit too long to count in seconds finds nothing older")
        try? fm.removeItem(atPath: claude + "/settings.json")

        assertEqual(CleanDevMacEngine.claudeFolder(home: home, environment: [:]), home + "/.claude", "Claude Code's folder is ~/.claude")
        assertEqual(CleanDevMacEngine.claudeFolder(home: home, environment: ["CLAUDE_CONFIG_DIR": home + "/alt"]), home + "/alt",
                    "...or CLAUDE_CONFIG_DIR")
        assertEqual(CleanDevMacEngine.claudeFolder(home: home, environment: ["CLAUDE_CONFIG_DIR": ""]), home + "/.claude", "...unless it is empty")
        let alt = CleanDevMacEngine.ClaudeHistory(folder: home + "/alt", sizeKB: 1_048_576, oldTranscripts: 1, keepDays: 30).note(home: home)
        assertEqual(alt?.summary, "1.00 GB of session history in ~/alt/projects, 1 transcript older than 30 days.", "CLAUDE_CONFIG_DIR moves the note")
        assertTrue(alt?.advice.hasSuffix("to ~/alt/settings.json") == true, "...and its own settings.json")
        assertTrue(CleanDevMacEngine.claudeHistory(folder: home + "/alt", now: nowSeconds) == nil, "No projects folder: no note")

        print("✅ CleanDevMac engine passed all tests!\n")
    }

    // MARK: - Test 36b: cdm's user folder — its temp folders, the gate's second branch, Chrome's clones

    static func testCleanDevMacUserFolder() {
        print("Testing CleanDevMac user folder & clones...")
        let fm = FileManager.default

        // 1. The real folders: this user's own is accepted; a folder below it, its parent,
        //    the unresolved /var spelling, the home folder and root's folder are not.
        guard let real = CleanDevMacEngine.userFolder() else {
            print("❌ FAIL: this user's /private/var/folders folder was not found")
            exit(1)
        }
        assertTrue(CleanDevMacEngine.isUserFolder(real), "This user's folder has the shape and owner it must")
        assertTrue(!CleanDevMacEngine.isUserFolder(real + "/C"), "A folder below it is not the folder")
        assertTrue(!CleanDevMacEngine.isUserFolder((real as NSString).deletingLastPathComponent), "Its parent is not the folder")
        assertTrue(!CleanDevMacEngine.isUserFolder("/var/folders/" + real.dropFirst("/private/var/folders/".count)),
                   "The unresolved /var spelling is refused")
        assertTrue(!CleanDevMacEngine.isUserFolder(NSHomeDirectory()), "The home folder is not a per-user folder")
        let rootFolder = ((try? fm.contentsOfDirectory(atPath: "/private/var/folders/zz")) ?? []).sorted()
            .map { "/private/var/folders/zz/" + $0 }
            .first { path -> Bool in
                var info = stat()
                return lstat(path, &info) == 0 && info.st_uid == 0 && info.st_mode & S_IFMT == S_IFDIR
            }
        assertTrue(rootFolder != nil, "Premise: root's own folder exists")
        assertTrue(!CleanDevMacEngine.isUserFolder(rootFolder ?? ""), "A folder that is not this user's is refused")

        // 2. A sandbox: a home folder and, outside it, a user folder written resolved, as cdm
        //    resolves USER_FOLDER, so an acceptance can only come from the new branch.
        let base = NSTemporaryDirectory() + "lightspot-cdm-uf-\(getpid())"
        try? fm.removeItem(atPath: base)
        defer { try? fm.removeItem(atPath: base) }
        let home = base + "/home"
        try? fm.createDirectory(atPath: home + "/.Trash", withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: base + "/uf/ab/cdef", withIntermediateDirectories: true)
        let physicalHome = CleanDevMacEngine.physicalPath(home)
        let uf = CleanDevMacEngine.physicalPath(base + "/uf/ab/cdef")
        @discardableResult
        func put(_ path: String, bytes: Int = 2) -> String {
            try? fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            fm.createFile(atPath: path, contents: Data(repeating: 0x78, count: bytes))
            return path
        }
        func expand(_ pattern: String, _ folder: String? = nil) -> String {
            CleanDevMacEngine.expandTilde(pattern, home: home, userFolder: folder)
        }
        assertEqual(expand("@cache/clang/ModuleCache", uf), uf + "/C/clang/ModuleCache", "@cache/ is the folder's C")
        assertEqual(expand("@temp/node-compile-cache", uf), uf + "/T/node-compile-cache", "@temp/ is its T")
        assertEqual(expand("@boot-temp/a.code_sign_clone/b", uf), uf + "/X/a.code_sign_clone/b", "@boot-temp/ is its X")
        assertEqual(expand("~/.npm", uf), home + "/.npm", "~ is still the home folder")
        assertEqual(expand("@cachex/y", uf), "@cachex/y", "A near-miss is no token")
        assertEqual(expand("@cache/clang"), "@cache/clang", "No folder: the token stays as written, a relative path")

        // 3. The gate's second branch: cdm's own test cases. Every refused path exists, so a
        //    refusal can only come from the rule under test.
        put(uf + "/C/clang/ModuleCache/abc.pcm")
        put(uf + "/T/node-compile-cache/v26/x")
        put(uf + "/X/org.x.App.code_sign_clone/code_sign_clone.AbCdEf/App.app.bundle/f")
        put(uf + "/0/com.apple.x/state")
        put(uf + "/Z/other/x")
        put(base + "/outside/precious")
        try? fm.createSymbolicLink(atPath: uf + "/T/link", withDestinationPath: base + "/outside")
        try? fm.createSymbolicLink(atPath: base + "/into-c", withDestinationPath: uf + "/C")
        func safe(_ path: String) -> Bool {
            CleanDevMacEngine.isSafeTarget(path, home: home, physicalHome: physicalHome, userFolder: uf)
        }
        for (path, why) in [(uf + "/C/clang/ModuleCache", "a cache folder in C"), (uf + "/C/clang/ModuleCache/abc.pcm", "a file in C"),
                            (uf + "/T/node-compile-cache", "a folder in T"),
                            (uf + "/X/org.x.App.code_sign_clone/code_sign_clone.AbCdEf", "a clone in X"),
                            (uf + "/T/link", "a symlink in T, itself")] {
            assertTrue(safe(path), "Reachable: \(why)")
        }
        for (path, why) in [(uf, "the folder itself"), (uf + "/C", "C itself"), (uf + "/C/", "C/ with a slash"),
                            (uf + "/C/.", "C/., which is C"), (uf + "/C/./clang", "a ./ segment"),
                            (uf + "/0/com.apple.x", "its 0, which is not a temp folder"), (uf + "/Z/other", "any other folder in it"),
                            (uf + "/C/clang/../clang", "a .. segment"), (uf + "/C/nope", "a missing path"),
                            (uf + "/T/link/precious", "a symlinked component that escapes T"),
                            (base + "/into-c/clang", "a path outside that resolves into C")] {
            assertTrue(!safe(path), "Refused: \(why)")
        }
        assertTrue(!CleanDevMacEngine.isSafeTarget(uf + "/C/clang/ModuleCache", home: home, physicalHome: physicalHome),
                   "No folder: nothing in it is reachable")
        assertEqual(CleanDevMacEngine.delete(uf + "/0/com.apple.x", method: .rm, home: home, physicalHome: physicalHome, userFolder: uf),
                    .unsafe, "Outside C, T and X a delete is refused")
        assertTrue(fm.fileExists(atPath: uf + "/0/com.apple.x/state"), "...and nothing is removed")
        assertEqual(CleanDevMacEngine.matchedPaths(patterns: ["@cache/clang/ModuleCache", "@temp/node-compile-cache"], home: home,
                                                   physicalHome: physicalHome, userFolder: uf),
                    [uf + "/C/clang/ModuleCache", uf + "/T/node-compile-cache"], "Token patterns match in the user folder")
        assertEqual(CleanDevMacEngine.matchedPaths(patterns: ["@cache/clang/ModuleCache"], home: home, physicalHome: physicalHome), [],
                    "No folder: a token pattern matches nothing")
        assertEqual(CleanDevMacEngine.delete(uf + "/C/clang/ModuleCache", method: .rm, home: home, physicalHome: physicalHome,
                                             userFolder: uf), .deleted, "A folder in C is deleted through the gate")

        // 4. Chrome's clones, as cdm's test_code_sign_clones: Fakium has run for 6000 s, its
        //    version 2.0 is installed and 1.0 is gone. Birth times are set as creation dates.
        let now = Int(Date().timeIntervalSince1970)
        let cl = uf + "/X/org.fakium.Fakium.code_sign_clone"
        func clone(_ suffix: String, _ version: String, age: Int) {
            let copy = cl + "/code_sign_clone." + suffix
            let versioned = copy + "/Fakium.app.bundle/Contents/Frameworks/Fakium Framework.framework/Versions/" + version
            // Big enough that the blocks a removed version holds never round to nothing.
            put(versioned + "/Resources/resources.pak", bytes: 65_536)
            put(copy + "/Fakium.app.bundle/Contents/MacOS/Fakium")
            try? fm.setAttributes([.creationDate: Date(timeIntervalSince1970: TimeInterval(now - age))], ofItemAtPath: copy)
        }
        try? fm.createDirectory(atPath: home + "/Applications/Fakium.app/Contents/Frameworks/Fakium Framework.framework/Versions/2.0",
                                withIntermediateDirectories: true)
        clone("aaaaaa", "2.0", age: 5_998)    // born 2 s after the running Fakium started: its copy
        clone("bbbbbb", "2.0", age: 7_200)    // from an earlier launch
        clone("cccccc", "2.0", age: 172_800)  // two days old
        clone("dddddd", "1.0", age: 90_000)   // a version no longer installed
        clone("eeeeee", "1.0", age: 95_000)
        clone("ffffff", "2.0", age: 60)       // a launch still in progress
        put(cl + "/code_sign_clone.hhhhhh/stray")
        try? fm.setAttributes([.creationDate: Date(timeIntervalSince1970: TimeInterval(now - 7_200))], ofItemAtPath: cl + "/code_sign_clone.hhhhhh")
        var born = stat()
        lstat(cl + "/code_sign_clone.dddddd", &born)
        assertEqual(Int(born.st_birthtimespec.tv_sec), now - 90_000, "Premise: a clone's birth time can be set")
        assertEqual(CleanDevMacEngine.entryCount(cl + "/code_sign_clone.bbbbbb"), 11, "A Fakium copy has 11 entries, as find counts them")
        let running = [CleanDevMacEngine.AppProcess(app: "Fakium", started: now - 6_000),
                       CleanDevMacEngine.AppProcess(app: "Other", started: now - 93_600)]

        assertEqual(CleanDevMacEngine.appName(ofExecutable: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
                    "Google Chrome", "A process's app is its bundle name")
        assertEqual(CleanDevMacEngine.appName(ofExecutable: "/A/B b.app/Contents/Frameworks/F.framework/Helpers/B b Helper.app/Contents/MacOS/B b Helper"),
                    "B b Helper", "...a helper is an app of its own")
        assertEqual(CleanDevMacEngine.appName(ofExecutable: "/usr/bin/ssh"), nil, "...and a plain binary is none")
        let live = CleanDevMacEngine.runningAppProcesses()
        assertTrue(!live.isEmpty && live.allSatisfy { !$0.app.isEmpty && $0.started > 0 && $0.started <= now + 1 },
                   "This user's running apps are read, each with its start")
        assertTrue(CleanDevMacEngine.cloneVersionShared(app: "Fakium", version: "2.0", home: home), "An installed version is shared")
        assertTrue(!CleanDevMacEngine.cloneVersionShared(app: "Fakium", version: "1.0", home: home), "...a removed one is not")
        assertTrue(!CleanDevMacEngine.cloneVersionShared(app: "Nopium", version: "2.0", home: home), "...nor an app nobody installed")

        let pattern = ["@boot-temp/*.code_sign_clone/code_sign_clone.*"]
        func clones(_ processes: [CleanDevMacEngine.AppProcess], _ folder: String?) -> CleanDevMacEngine.Clones {
            CleanDevMacEngine.codeSignClones(patterns: pattern, processes: processes, now: now, home: home,
                                             physicalHome: physicalHome, userFolder: folder)
        }
        let found = clones(running, uf)
        assertEqual(found.paths, ["bbbbbb", "cccccc", "dddddd", "eeeeee", "hhhhhh"].map { cl + "/code_sign_clone." + $0 },
                    "Offered: every leftover copy; kept: the running app's and a launch in progress")
        // Two 2.0 copies and two 1.0 copies hold 22/3 KiB of metadata a version; only 1.0's
        // blocks, once, are held by its copies alone; the stray copy's 2 entries round to 0.
        let want = 2 * 11 / 3 + 2 * 11 / 3 + CleanDevMacEngine.allocatedKB(cl + "/code_sign_clone.dddddd")
        assertEqual(found.sizes.reduce(0, +), want, "Sized by what the copies alone hold, not by du")
        assertTrue(want < CleanDevMacEngine.allocatedKB(cl), "...which du would count again for every copy")
        assertEqual(clones([], uf).paths, [], "No process list: nothing offered")
        assertEqual(clones(running, nil).paths, [], "No user folder: nothing offered")

        // 5. Through the provider: the row comes sized, and its clean writes one line.
        let provider = CleanDevMacProvider(environment: CleanDevMacProvider.Environment(
            home: home,
            bundledRules: bundledCdmRules,
            processEnvironment: [:],
            fetchRemoteRules: { $0(nil) },
            moveToTrash: { url in try FileManager.default.moveItem(atPath: url.path, toPath: home + "/.Trash/" + url.lastPathComponent) },
            userFolder: uf,
            appProcesses: { running }
        ))
        let rules = CleanDevMacRuleSet(rules: [
            CleanDevMacRule(kind: .codeSignClones, icon: "👥", name: "Copies", desc: "D.", method: .rm, isDefault: true,
                            patterns: pattern, procs: []),
        ], terminalOnly: [], source: .bundled)
        let scan = provider.scanEntries(rules, now: Date(timeIntervalSince1970: TimeInterval(now)))
        assertEqual(scan.entries.map(\.rule.name), ["Copies"], "The clone row is found")
        assertEqual(scan.entries.first?.rule.desc, "5 copies. D.", "...says how many copies it holds")
        assertEqual(scan.entries.first?.sizes, found.sizes, "...and comes sized rather than measured")
        let receipt = provider.performClean(scan.entries)
        assertEqual(((try? fm.contentsOfDirectory(atPath: cl)) ?? []).sorted(), ["code_sign_clone.aaaaaa", "code_sign_clone.ffffff"],
                    "The leftovers are gone; the running app's copy and the new one stay")
        assertEqual(receipt.removedCount, 5, "Five copies removed")
        let log = (try? String(contentsOfFile: home + "/.cleandevmac/clean.log", encoding: .utf8)) ?? ""
        assertTrue(log.contains("  deleted: 5 copies\n") && !log.contains("code_sign_clone.bbbbbb"), "One receipt line for the lot")

        // 6. The rule format: a clone rule reads `candidates`, never `paths`, and Rust's offline
        //    docs, which rustup removes, are left to cdm.
        let parsed = CleanDevMacRules.parsePatternFile(Data(#"""
            {"categories": [
              {"kind": "rust-docs", "name": "Docs", "method": "rustup", "candidates": ["~/.rustup/toolchains/*"]},
              {"kind": "code-sign-clones", "name": "Clones", "candidates": ["@boot-temp/*.code_sign_clone/code_sign_clone.*"]},
              {"kind": "code-sign-clones", "name": "Paths only", "paths": ["@boot-temp/*.code_sign_clone/code_sign_clone.*"]}
            ]}
            """#.utf8))
        assertEqual(parsed?.terminalOnly, ["Docs"], "Rust's offline docs are left to cdm")
        assertEqual(parsed?.rules.map(\.name), ["Clones"], "A clone rule reads `candidates`, never `paths`")
        assertEqual(parsed?.rules.first?.kind, .codeSignClones, "...and keeps its kind")

        print("✅ CleanDevMac user folder & clones passed all tests!\n")
    }

    // MARK: - Test 37: cdm in Lightspot — rule sources, scan, clean, search row

    static func testCleanDevMacProvider() {
        print("Testing CleanDevMacProvider...")
        let fm = FileManager.default
        let home = NSTemporaryDirectory() + "lightspot-cdm-provider-\(getpid())"
        try? fm.removeItem(atPath: home)
        try? fm.createDirectory(atPath: home + "/.Trash", withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: home) }
        @discardableResult
        func make(_ relative: String, bytes: Int) -> String {
            let path = home + "/" + relative
            try? fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            fm.createFile(atPath: path, contents: Data(repeating: 0x61, count: bytes))
            return path
        }
        func environment(remote: CleanDevMacRuleSet?) -> CleanDevMacProvider.Environment {
            CleanDevMacProvider.Environment(
                home: home,
                bundledRules: bundledCdmRules,
                processEnvironment: [:],
                fetchRemoteRules: { completion in completion(remote) },
                moveToTrash: { url in try FileManager.default.moveItem(atPath: url.path, toPath: home + "/.Trash/" + url.lastPathComponent) }
            )
        }
        func rule(_ name: String, _ method: CleanDevMacRule.Method, _ patterns: [String], isDefault: Bool = true, procs: [String] = []) -> CleanDevMacRule {
            CleanDevMacRule(kind: .paths, icon: "🧪", name: name, desc: "", method: method, isDefault: isDefault, patterns: patterns, procs: procs)
        }
        let fixture = CleanDevMacRuleSet(rules: [
            rule("Big", .rm, ["~/big", "~/shared"], procs: ["Xcode"]),
            rule("Small", .trash, ["~/small", "~/shared"], isDefault: false),
            rule("Nothing", .rm, ["~/absent"]),
            rule("Sandboxed", .rm, ["~/Library/Containers/*/Data/Library/Caches"]),
            rule("Trash", .emptytrash, ["~/.Trash", "~/big"], isDefault: false),
        ], terminalOnly: ["node_modules folders"], source: .remote)

        // 1. Where the rules come from: cdm's local folder, else GitHub, else the app's copy.
        func resolve(_ provider: CleanDevMacProvider) -> Result<CleanDevMacRuleSet, CleanDevMacProvider.LoadFailure>? {
            let done = DispatchSemaphore(value: 0)
            let box = ResultBox<Result<CleanDevMacRuleSet, CleanDevMacProvider.LoadFailure>>()
            provider.resolveRules { result in
                box.value = result
                done.signal()
            }
            _ = done.wait(timeout: .now() + 10)
            return box.value
        }
        assertEqual(try? resolve(CleanDevMacProvider(environment: environment(remote: nil)))?.get().source, .bundled,
                    "Offline, the app's own copy is used")
        assertEqual(try? resolve(CleanDevMacProvider(environment: environment(remote: fixture)))?.get(), fixture,
                    "Online, cdm's live rules are used")
        let local = home + "/.cleandevmac/rules"
        try? fm.createDirectory(atPath: local, withIntermediateDirectories: true)
        fm.createFile(atPath: local + "/index.json", contents: Data(#"{"patternFiles": ["mine.json"]}"#.utf8))
        fm.createFile(atPath: local + "/mine.json", contents: Data(#"{"categories": [{"name": "Mine", "paths": ["~/mine"]}]}"#.utf8))
        let localRules = try? resolve(CleanDevMacProvider(environment: environment(remote: fixture)))?.get()
        assertEqual(localRules?.source, .local, "cdm's local rules folder wins over GitHub, as it does for cdm")
        assertEqual(localRules?.rules.map(\.name), ["Mine"], "...and is read whole")
        fm.createFile(atPath: local + "/index.json", contents: Data("{".utf8))
        if case .failure = resolve(CleanDevMacProvider(environment: environment(remote: fixture))) {} else {
            assertTrue(false, "Broken local rules are an error, never a reason to use other rules")
        }
        try? fm.removeItem(atPath: home + "/.cleandevmac/rules")

        // 2. Scanning: biggest first, a shared path counted once, what is left to cdm named.
        let bigPath = make("big/blob", bytes: 400_000)
        let sharedPath = make("shared/blob", bytes: 100_000)
        let smallPath = make("small/blob", bytes: 40_000)
        make(".Trash/old", bytes: 8_000)
        make("Library/Containers/com.example/Data/Library/Caches/blob", bytes: 1_000)
        let provider = CleanDevMacProvider(environment: environment(remote: fixture))
        let scan = provider.scanEntries(fixture)
        assertEqual(scan.entries.map(\.rule.name), ["Big", "Small", "Trash"], "Found categories, biggest first; empty ones dropped")
        assertEqual(scan.entries.map(\.id), [0, 1, 4], "An entry keeps its rule's position as its ID")
        assertEqual(scan.terminalOnly, ["node_modules folders", "Sandboxed"], "A rule that only reads sandbox containers is left to cdm")
        assertEqual(scan.entries[2].paths, [home + "/.Trash"], "Emptying the Trash only ever names the Trash")
        assertEqual(scan.entries[0].sizes, [CleanDevMacEngine.allocatedKB(home + "/big"), CleanDevMacEngine.allocatedKB(home + "/shared")],
                    "Each path is measured, aligned with the paths")
        let unique = CleanDevMacProvider.uniqueKB(scan.entries)
        assertEqual(unique, scan.entries.reduce(0) { $0 + $1.sizeKB } - CleanDevMacEngine.allocatedKB(home + "/shared"),
                    "A path two categories share is counted once")
        assertEqual(CleanDevMacProvider.runningApps(for: scan.entries, running: ["Xcode", "Finder"]), ["Xcode"], "Running owners are named")
        assertEqual(CleanDevMacProvider.runningApps(for: scan.entries, running: []), [], "...and only running ones")

        // A row is sized as one du over its paths: a file hard-linked into two of them is
        // counted, and freed, once.
        let linkedBig = make("linked/a/big", bytes: 300_000)
        make("linked/b/own", bytes: 5_000)
        try? fm.linkItem(atPath: linkedBig, toPath: home + "/linked/b/big-link")
        let linkedRow = provider.scanEntries(CleanDevMacRuleSet(rules: [rule("Linked", .rm, ["~/linked/a", "~/linked/b"])],
                                                                terminalOnly: [], source: .remote)).entries.first
        let bigKB = CleanDevMacEngine.allocatedKB(linkedBig)
        assertEqual(linkedRow?.sizes, [CleanDevMacEngine.allocatedKB(home + "/linked/a"), CleanDevMacEngine.allocatedKB(home + "/linked/b") - bigKB],
                    "The hard-linked file counts in the first path only")
        let linkedFreed = linkedRow.map { provider.performClean([$0]).freedKB }
        assertEqual(linkedFreed, linkedRow?.sizeKB, "...and the receipt frees it once")
        assertTrue(!fm.fileExists(atPath: home + "/linked/a") && !fm.fileExists(atPath: home + "/linked/b"), "...having removed both paths")

        // Android images an AVD boots from are left out by the scan itself.
        let imageRules = CleanDevMacRuleSet(rules: [
            CleanDevMacRule(kind: .androidImages, icon: "💿", name: "Images", desc: "", method: .rm, isDefault: false,
                            patterns: ["~/sdk/system-images/*/*/*"], procs: []),
        ], terminalOnly: [], source: .remote)
        make("sdk/system-images/android-34/default/arm64-v8a/system.img", bytes: 4_000)
        make("sdk/system-images/android-33/default/arm64-v8a/system.img", bytes: 4_000)
        try? fm.createDirectory(atPath: home + "/.android/avd/Phone.avd", withIntermediateDirectories: true)
        fm.createFile(atPath: home + "/.android/avd/Phone.avd/config.ini",
                      contents: Data("image.sysdir.1=system-images/android-34/default/arm64-v8a/\n".utf8))
        assertEqual(provider.scanEntries(imageRules).entries.first?.paths, [home + "/sdk/system-images/android-33/default/arm64-v8a"],
                    "Only the image no AVD uses is offered")

        // The kinds that work out their offer: an idle AVD's image (one row per image, IDs
        // from itemIDBase), old Claude Code sessions, and all but the newest version.
        func aged(_ relative: String, days: Double) {
            try? fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -days * 86_400)], ofItemAtPath: home + "/" + relative)
        }
        make("sdk/system-images/android-35/android-tv/arm64-v8a/system.img", bytes: 4_000)
        try? fm.createDirectory(atPath: home + "/.android/avd/TV.avd", withIntermediateDirectories: true)
        fm.createFile(atPath: home + "/.android/avd/TV.avd/config.ini",
                      contents: Data("image.sysdir.1=system-images/android-35/android-tv/arm64-v8a/\n".utf8))
        make(".android/avd/TV.avd/userdata-qemu.img.qcow2", bytes: 100)
        aged(".android/avd/TV.avd/userdata-qemu.img.qcow2", days: 90)
        let session = "11111111-1111-4111-8111-111111111111"
        make(".claude/projects/-Users-me-app/\(session).jsonl", bytes: 2_000)
        aged(".claude/projects/-Users-me-app/\(session).jsonl", days: 40)
        make("sdk2/build-tools/36.0.0/aapt", bytes: 3_000)
        make("sdk2/build-tools/37.0.0/aapt", bytes: 3_000)
        let computed = CleanDevMacRuleSet(rules: [
            CleanDevMacRule(kind: .androidIdleImages, icon: "💿", name: "Idle AVD image", desc: "D.", method: .rm, isDefault: false,
                            patterns: ["~/sdk/system-images/*/*/*"], procs: [], idleDays: 60),
            CleanDevMacRule(kind: .claudeTranscripts, icon: "💬", name: "Old transcripts", desc: "T.", method: .trash, isDefault: false,
                            patterns: ["~/.claude/projects/*"], procs: [], idleDays: 30),
            CleanDevMacRule(kind: .olderVersions, icon: "🤖", name: "Older build-tools", desc: "", method: .rm, isDefault: false,
                            patterns: ["~/sdk2/build-tools/*"], procs: []),
        ], terminalOnly: [], source: .remote)
        let computedScan = provider.scanEntries(computed).entries
        func entry(_ name: String) -> CleanDevMacProvider.Entry? { computedScan.first { $0.rule.name == name } }
        let tvRow = entry("Idle AVD image: android-35/android-tv/arm64-v8a")
        assertEqual(tvRow?.id, CleanDevMacProvider.itemIDBase, "An idle image is its own row, numbered from itemIDBase")
        assertEqual(tvRow?.paths, [home + "/sdk/system-images/android-35/android-tv/arm64-v8a"], "...deleting that image only")
        assertTrue(tvRow?.rule.desc.hasPrefix("Booted only by TV, last started ") == true, "...naming the AVD it would stop booting")
        assertTrue(tvRow?.rule.desc.hasSuffix("D. Reinstall: sdkmanager \"system-images;android-35;android-tv;arm64-v8a\"") == true,
                   "...and the package to reinstall")
        assertTrue(computedScan.allSatisfy { !$0.paths.contains(home + "/sdk/system-images/android-34/default/arm64-v8a") },
                   "An image a recently used AVD boots is never offered")
        let talkRow = entry("Old transcripts")
        assertEqual(talkRow?.paths, [home + "/.claude/projects/-Users-me-app/\(session).jsonl"], "The old session's transcript")
        assertEqual(talkRow?.methods, [.trash], "...goes to the Trash")
        assertEqual(talkRow?.rule.isDefault, false, "...unticked")
        assertEqual(talkRow?.rule.desc, "1 session. T.", "...and its row counts the sessions")
        assertEqual(entry("Older build-tools")?.paths, [home + "/sdk2/build-tools/36.0.0"], "All but the newest version")

        // 3. Cleaning: each method, a shared path removed and counted once, a receipt and a log.
        let receipt = provider.performClean(Array(scan.entries.prefix(2)))
        assertTrue(!fm.fileExists(atPath: bigPath) && !fm.fileExists(atPath: sharedPath), "rm deleted Big's paths")
        assertTrue(!fm.fileExists(atPath: home + "/small") && fm.fileExists(atPath: home + "/.Trash/small"), "trash moved Small to the Trash")
        assertEqual(receipt.removedCount, 3, "big, shared and small; shared only once")
        assertEqual(receipt.freedKB, scan.entries[0].sizeKB + scan.entries[1].sizes[0], "Freed counts the shared path once")
        assertTrue(receipt.movedToTrash, "The receipt says something went to the Trash")
        assertEqual(receipt.problems, [], "Nothing was refused")
        let log = (try? String(contentsOfFile: home + "/.cleandevmac/clean.log", encoding: .utf8)) ?? ""
        for expected in ["CleanDevMac run (Lightspot): ", "▸ Big\n  deleted: ~/big\n  deleted: ~/shared\n", "▸ Small\n  trashed: ~/small\n", "Finished: "] {
            assertTrue(log.contains(expected), "The log records '\(expected)'")
        }
        _ = smallPath
        let refused = provider.performClean([CleanDevMacProvider.Entry(id: 9, rule: fixture.rules[0], paths: ["/etc/hosts"], sizes: [4])])
        assertEqual(refused.problems, ["Skipped (unsafe): /etc/hosts"], "A path outside home is refused at clean time too")
        assertEqual(refused.freedKB, 0, "...and frees nothing")

        // 4. The state machine behind the overlay: scan, a recent scan stands, clean, rescan.
        make("big/blob", bytes: 400_000)
        make("shared/blob", bytes: 100_000)
        assertTrue(environment(remote: fixture).restartEstimate() == nil, "A test home's provider never measures the whole machine")
        var measuredEnvironment = environment(remote: fixture)
        measuredEnvironment.restartEstimate = { CleanDevMacEngine.RestartEstimate(swapKB: 2_000_000, heldApps: ["node"]) }
        let machine = CleanDevMacProvider(environment: measuredEnvironment)
        func wait(_ phase: CleanDevMacProvider.Phase) -> CleanDevMacProvider.Snapshot {
            let deadline = Date().addingTimeInterval(20)
            while Date() < deadline {
                let snapshot = machine.snapshot
                if snapshot.phase == phase { return snapshot }
                usleep(10_000)
            }
            print("❌ FAIL: the cleaner never reached \(phase); it is at \(machine.snapshot.phase)")
            exit(1)
        }
        assertEqual(machine.snapshot.phase, .idle, "A new provider has not scanned")
        machine.startScan()
        let ready = wait(.ready)
        assertEqual(ready.entries.map(\.rule.name), ["Big", "Small", "Trash"], "The scan finds what is there again")
        assertEqual(ready.source, .remote, "...with the rules it was given")
        assertEqual(ready.generation, 1, "...and counts the scan")
        assertTrue(ready.disk != nil && ready.scannedAt != nil, "...with the disk line and the time")
        assertEqual(ready.restart, CleanDevMacEngine.RestartEstimate(swapKB: 2_000_000, heldApps: ["node"]), "...what a restart would free")
        assertEqual(ready.claudeHistory.map { [$0.oldTranscripts, $0.keepDays] }, [1, 30], "...and Claude Code's history in the home it scans")
        assertEqual(ready.claudeHistory?.folder, home + "/.claude", "...read from ~/.claude")
        machine.startScan()
        assertEqual(machine.snapshot.generation, 1, "A recent scan stands")
        machine.clean([0])
        let finished = wait(.finished)
        assertTrue((finished.receipt?.freedKB ?? 0) > 0 && finished.entries.isEmpty, "Cleaning ends on a receipt")
        assertTrue(!fm.fileExists(atPath: home + "/big"), "...having deleted what was ticked")
        assertTrue(fm.fileExists(atPath: home + "/.Trash/old"), "...and nothing that was not")
        machine.clean([4])
        assertEqual(machine.snapshot.phase, .finished, "A finished scan cannot be cleaned again")
        machine.startScan()
        assertEqual(wait(.ready).generation, 2, "After a clean, opening the cleaner measures again")

        // 5. The search row.
        let rows = CleanDevMacProvider.shared.search(SearchQuery("cdm"))
        assertEqual(rows.first?.id, CleanDevMacProvider.resultID, "'cdm' finds Clean Dev Mac")
        assertEqual(rows.first?.score, 95, "...as an exact keyword")
        if case .runQuickAction(let script, let usesOsascript) = rows.first?.action {
            assertEqual(script, CleanDevMacProvider.openScript, "The row opens the cleaner")
            assertTrue(!usesOsascript, "...and runs nothing itself")
        } else {
            assertTrue(false, "The row's action is the cleaner's sentinel")
        }
        assertEqual(CleanDevMacProvider.shared.search(SearchQuery("clean dev mac")).first?.score, 100, "The full name is exact")
        assertEqual(CleanDevMacProvider.shared.search(SearchQuery("derived data")).first?.title, "Clean Dev Mac", "A cache name finds it")
        assertTrue(CleanDevMacProvider.shared.search(SearchQuery("zzqx")).isEmpty, "Unrelated queries do not")
        let engine = SearchEngine.shared.searchImmediate(SearchQuery("cdm"))
        assertTrue(((engine[.topHit] ?? []) + (engine[.quickActions] ?? [])).contains { $0.id.hasSuffix(CleanDevMacProvider.resultID) },
                   "Search shows the row")
        assertEqual(SearchHistoryManager.persistableSubtitle(itemId: CleanDevMacProvider.resultID, subtitle: "12.00 GB reclaimable"),
                    CleanDevMacProvider.fixedSubtitle, "Search history never keeps a scan's sizes")

        var snapshot = CleanDevMacProvider.Snapshot()
        assertTrue(CleanDevMacProvider.subtitle(for: snapshot).contains("↵ Scan"), "Before a scan the row offers one")
        snapshot.phase = .measuring(done: 3, total: 9)
        assertEqual(CleanDevMacProvider.subtitle(for: snapshot), "Measuring reclaimable space… 3 of 9", "A scan shows its progress")
        snapshot.phase = .ready
        snapshot.entries = scan.entries
        assertTrue(CleanDevMacProvider.subtitle(for: snapshot).hasPrefix("\(CleanDevMacEngine.humanKB(unique)) reclaimable in 3 categories"),
                   "A scan's total shows on the row")
        snapshot.entries = []
        assertTrue(CleanDevMacProvider.subtitle(for: snapshot).hasPrefix("Nothing to reclaim"), "A clean Mac says so")

        print("✅ CleanDevMacProvider passed all tests!\n")
    }

    // MARK: - Test 38: Installers for setup-zsh, MacStats and setup-zsh's dev tools menu

    /// Exit status of `shell -n -c script`: whether it parses, without running it.
    static func parses(_ script: String, shell: String = "/bin/sh") -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-n", "-c", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    static func testToolInstallers() {
        print("Testing ToolInstallersProvider...")
        let installers = ToolInstallersProvider.installers
        assertEqual(installers.map(\.id), ToolInstaller.ID.allCases, "One row per tool, in order")
        assertEqual(Set(installers.map(\.script)).count, installers.count, "Each row has its own action")
        assertEqual(Set(installers.map(\.resultID)).count, installers.count, "Each row has its own ID")
        for installer in installers {
            assertEqual(ToolInstallersProvider.installer(forScript: installer.script), installer, "\(installer.title) is found by its action")
            assertTrue(!QuickActionsProvider.requiresAdministratorPrivileges(script: installer.script), "\(installer.title) never asks for admin")
            assertTrue(installer.repository.absoluteString.hasPrefix("https://github.com/openhoangnc/"), "\(installer.title) links its repository")
            assertEqual(SearchHistoryManager.persistableSubtitle(itemId: installer.resultID, subtitle: "Installed · live"), installer.summary,
                        "Search history keeps \(installer.title)'s description, not its install state")
        }
        assertTrue(ToolInstallersProvider.installer(forScript: "internal:install:nothing") == nil, "An unknown installer is not run")

        // The commands each tool's README gives, over HTTPS from the author's repositories.
        let none = ToolInstallState()
        let both = ToolInstallState(setupZsh: true, macStats: true)
        let setupZsh = ToolInstallersProvider.installer(.setupZsh)
        let macStats = ToolInstallersProvider.installer(.macStats)
        let devTools = ToolInstallersProvider.installer(.devTools)
        assertEqual(ToolInstallersProvider.command(for: setupZsh, state: none),
                    "curl -fsSL https://raw.githubusercontent.com/openhoangnc/setup-zsh/main/setup.sh | bash && exec zsh -l",
                    "setup-zsh runs its setup, then starts a zsh that loads it")
        assertEqual(ToolInstallersProvider.command(for: setupZsh, state: both), ToolInstallersProvider.command(for: setupZsh, state: none),
                    "Updating setup-zsh is running its setup again")
        assertEqual(ToolInstallersProvider.command(for: macStats, state: none),
                    "curl -fsSL https://raw.githubusercontent.com/openhoangnc/mac-stats/main/install.sh | bash", "MacStats runs its install.sh")
        assertEqual(ToolInstallersProvider.command(for: devTools, state: both), "~/.zsh/setup-zsh/bin/install-dev-tool",
                    "With setup-zsh, the dev tools menu runs as a file, so it reads keys from the terminal")
        let devFirst = ToolInstallersProvider.command(for: devTools, state: none)
        assertTrue(devFirst.hasPrefix(ToolInstallersProvider.command(for: setupZsh, state: none).replacingOccurrences(of: " && exec zsh -l", with: "")),
                   "Without setup-zsh, the dev tools menu installs it first")
        assertTrue(devFirst.contains("exec zsh -lic '~/.zsh/setup-zsh/bin/install-dev-tool; exec zsh -l'"), "...then opens the menu in a zsh that has it")
        for state in [none, both] {
            for installer in installers {
                let command = ToolInstallersProvider.command(for: installer, state: state)
                assertTrue(parses(command, shell: "/bin/zsh"), "\(installer.title)'s command parses in zsh: \(command)")
                assertTrue(!command.contains("http://"), "\(installer.title) downloads over HTTPS only")
            }
        }

        // What is installed is read off the disk, in the background, never on the keystroke path.
        let fm = FileManager.default
        let home = NSTemporaryDirectory() + "lightspot-installers-\(getpid())"
        try? fm.removeItem(atPath: home)
        try? fm.createDirectory(atPath: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: home) }
        assertTrue(!ToolInstallersProvider.readInstallState(home: home).setupZsh, "No setup-zsh in an empty home")
        let menu = ToolInstallersProvider.devToolPath(home: home)
        try? fm.createDirectory(atPath: (menu as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        fm.createFile(atPath: menu, contents: Data("#!/bin/bash\n".utf8), attributes: [.posixPermissions: 0o755])
        assertTrue(ToolInstallersProvider.readInstallState(home: home).setupZsh, "setup-zsh is installed once its dev tools menu is")
        let macStatsInstalled = fm.fileExists(atPath: ToolInstallersProvider.macStatsPath)
            || NSWorkspace.shared.urlForApplication(withBundleIdentifier: ToolInstallersProvider.macStatsBundleID) != nil
        assertEqual(ToolInstallersProvider.readInstallState(home: home).macStats, macStatsInstalled, "MacStats is found where macOS finds it")
        let provider = ToolInstallersProvider(home: home)
        assertEqual(provider.installState, ToolInstallState(), "The first read returns at once, before the disk has answered")
        let deadline = Date().addingTimeInterval(5)
        while !provider.installState.setupZsh && Date() < deadline { usleep(10_000) }
        assertTrue(provider.installState.setupZsh, "...and the background read lands")

        // The rows.
        assertTrue(ToolInstallersProvider.subtitle(for: setupZsh, state: none).contains("↵ Install in Terminal"), "Not installed: offers the install")
        assertTrue(ToolInstallersProvider.subtitle(for: setupZsh, state: both).hasPrefix("Installed"), "Installed: says so")
        assertTrue(ToolInstallersProvider.subtitle(for: macStats, state: both).hasPrefix("Installed"), "MacStats installed: says so")
        assertTrue(ToolInstallersProvider.subtitle(for: devTools, state: none).hasPrefix("Comes with setup-zsh"), "The menu says it needs setup-zsh")
        func top(_ query: String) -> SearchResult? { provider.search(SearchQuery(query)).max { $0.score < $1.score } }
        assertEqual(top("setup-zsh")?.id, setupZsh.resultID, "'setup-zsh' finds its installer")
        assertEqual(top("macstats")?.id, macStats.resultID, "'macstats' finds its installer")
        assertEqual(top("install go")?.id, devTools.resultID, "'install go' finds the dev tools menu")
        assertEqual(top("install node")?.id, devTools.resultID, "'install node' finds the dev tools menu")
        assertEqual(Set(provider.search(SearchQuery("install")).map(\.id)), Set(installers.map(\.resultID)), "'install' lists all three")
        if case .runQuickAction(let script, let usesOsascript) = top("setup-zsh")?.action {
            assertEqual(script, setupZsh.script, "The row's action is its installer's sentinel")
            assertTrue(!usesOsascript, "...run by Lightspot, not as AppleScript")
        } else {
            assertTrue(false, "The installer row is a quick action")
        }
        assertTrue(provider.search(SearchQuery("zzqx")).isEmpty, "Unrelated queries find no installer")

        print("✅ ToolInstallersProvider passed all tests!\n")
    }

    // MARK: - Test 39: macOS tweaks

    static func testMacTweaks() {
        print("Testing MacTweaks...")
        let all = QuickActionsProvider.defaultActions
        for tweak in MacTweaks.actions {
            assertTrue(all.contains { $0.id == tweak.id }, "\(tweak.name) is a quick action")
            assertTrue(!tweak.requiresAdmin && !QuickActionsProvider.requiresAdministratorPrivileges(script: tweak.script),
                       "\(tweak.name) needs no administrator password")
            if !tweak.usesOsascript {
                assertTrue(parses(tweak.script), "\(tweak.name) parses: \(tweak.script)")
            }
        }
        assertEqual(Set(all.map(\.id)).count, all.count, "Quick action IDs are unique")
        assertEqual(MacTweaks.actions.first { $0.name == "Clear Dock Icons" }?.script,
                    "defaults write com.apple.dock persistent-apps -array && killall Dock", "Clear Dock Icons is the requested one-liner")

        // The toggles, run for real against a scratch domain: never the user's settings.
        let domain = "com.lightspot.test.tweaks"
        @discardableResult
        func sh(_ script: String) -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", script]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try? process.run()
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func read(_ key: String) -> String { sh("defaults read \(domain) \(key) 2>/dev/null") }
        sh("defaults delete \(domain) 2>/dev/null")
        defer {
            sh("defaults delete \(domain) 2>/dev/null")
            try? FileManager.default.removeItem(atPath: NSHomeDirectory() + "/Library/Preferences/\(domain).plist")
        }

        let offByDefault = MacTweaks.toggleScript(domain: domain, keys: ["Shown"], defaultValue: false)
        sh(offByDefault)
        assertEqual(read("Shown"), "1", "Unset and off by default: the first toggle turns it on")
        sh(offByDefault)
        assertEqual(read("Shown"), "0", "...and the next turns it off")

        let onByDefault = MacTweaks.toggleScript(domain: domain, keys: ["Enabled"], defaultValue: true)
        sh(onByDefault)
        assertEqual(read("Enabled"), "0", "Unset and on by default: the first toggle turns it off")
        sh(onByDefault)
        assertEqual(read("Enabled"), "1", "...and the next turns it back on")

        sh("defaults write \(domain) Typed -string YES")
        sh(MacTweaks.toggleScript(domain: domain, keys: ["Typed"], defaultValue: false))
        assertEqual(read("Typed"), "0", "A YES written as a string counts as on")

        let pair = MacTweaks.toggleScript(domain: domain, keys: ["Quotes", "Dashes"], defaultValue: true)
        sh(pair)
        assertEqual([read("Quotes"), read("Dashes")], ["0", "0"], "Paired keys turn off together")
        sh("defaults write \(domain) Dashes -bool true")
        sh(pair)
        assertEqual([read("Quotes"), read("Dashes")], ["1", "1"], "...and follow the first key's state back on")

        let instant = MacTweaks.instantDockScript(domain: domain, restart: nil)
        sh(instant)
        assertEqual([read("autohide-delay"), read("autohide-time-modifier")], ["0", "0.15"], "Instant auto-hide sets the delay and the slide")
        sh(instant)
        assertEqual([read("autohide-delay"), read("autohide-time-modifier")], ["", ""], "...and toggling it back hands both to macOS")
        assertTrue(MacTweaks.instantDockScript().hasSuffix("; killall Dock"), "The real one restarts the Dock")

        // Finding them, without taking over the words other actions own.
        let quick = QuickActionsProvider.shared
        for (query, title) in [("clear dock", "Clear Dock Icons"), ("hidden files", "Toggle Hidden Files in Finder"),
                               ("file extensions", "Toggle File Extensions in Finder"), ("smart quotes", "Toggle Smart Quotes & Dashes"),
                               ("key repeat", "Toggle Press-and-Hold Accents"), ("ds_store", "Toggle .DS_Store on Network & USB Drives"),
                               ("restart finder", "Restart Finder"), ("instant dock", "Toggle Instant Dock Auto-Hide"),
                               ("desktop", "Show Desktop"), ("screenshot", "Take Screenshot")] {
            assertEqual(quick.search(SearchQuery(query)).first?.title, title, "'\(query)' finds \(title)")
        }

        print("✅ MacTweaks passed all tests!\n")
    }

    // MARK: - Test 40: cdm's repo scan — cdm's own fixtures, plus Lightspot's guards

    static func testCleanDevMacRepoScan() {
        print("Testing CleanDevMac repo scan...")
        guard let git = CleanDevMacProjects.gitExecutable() else {
            print("⚠️ No git: skipping the repo scan tests, as cdm's suite does.\n")
            return
        }
        // The fixtures' own repos decide what is ignored, not the developer's global
        // excludes file: that is what cdm's tests get from their sandboxed HOME.
        setenv("GIT_CONFIG_GLOBAL", "/dev/null", 1)
        setenv("GIT_CONFIG_NOSYSTEM", "1", 1)
        defer {
            unsetenv("GIT_CONFIG_GLOBAL")
            unsetenv("GIT_CONFIG_NOSYSTEM")
        }
        let fm = FileManager.default
        let home = NSTemporaryDirectory() + "lightspot-repos-\(getpid())"
        try? fm.removeItem(atPath: home)
        try? fm.createDirectory(atPath: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: home) }

        func run(_ arguments: [String], in folder: String) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: git)
            process.arguments = arguments
            process.currentDirectoryURL = URL(fileURLWithPath: folder)
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
        func file(_ path: String, _ text: String = "x") {
            try? fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            fm.createFile(atPath: path, contents: Data(text.utf8))
        }
        func repo(_ path: String, ignoring: [String]) {
            try? fm.createDirectory(atPath: path, withIntermediateDirectories: true)
            run(["init", "-q"], in: path)
            file(path + "/.gitignore", ignoring.joined(separator: "\n") + "\n")
        }
        func commitAll(_ path: String) {
            run(["add", "-A"], in: path)
            run(["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "init"], in: path)
        }
        func rules(dirs: [String], gitignore: Bool = false, groups: [String] = []) -> CleanDevMacProjectRules {
            var rules = CleanDevMacProjectRules()
            rules.roots = ["~"]
            rules.maxDepth = 6
            rules.groups = groups
            rules.dirs = dirs.map { CleanDevMacProjectRules.JunkName(name: $0, method: .rm) }
            rules.gitignoreMethod = gitignore ? .trash : nil
            return rules
        }
        func offered(_ rules: CleanDevMacProjectRules) -> [CleanDevMacProjects.Project] {
            CleanDevMacProjects.scan(rules, home: home, git: git).projects
        }
        func paths(_ projects: [CleanDevMacProjects.Project]) -> Set<String> {
            Set(projects.flatMap(\.paths))
        }

        // 1. cdm's ignored proof: a name match only nominates, git decides.
        let a = home + "/code/repoA"            // dist ignored; build tracked; out untracked but not ignored
        repo(a, ignoring: ["dist"])
        file(a + "/dist/bundle.js"); file(a + "/build/release.sh"); file(a + "/out/generated.txt")
        commitAll(a)
        let b = home + "/code/repoB"            // dist ignore-listed but holding a tracked file
        repo(b, ignoring: ["dist", "node_modules"])
        file(b + "/dist/committed.js"); file(b + "/node_modules/pkg.js")
        run(["add", "-A"], in: b); run(["add", "-f", "dist/committed.js"], in: b)
        commitAll(b)
        let c = home + "/code/repoC"            // a candidate under a wholly ignored folder
        repo(c, ignoring: ["tmpstuff"])
        file(c + "/tmpstuff/dist/x.js")
        commitAll(c)
        file(home + "/notarepo/node_modules/pkg.js")
        let e = home + "/code/repoE"            // an outer repo ignoring a nested checkout
        repo(e, ignoring: ["node_modules", "inner"])
        file(e + "/node_modules/pkg.js"); file(e + "/inner/build/release.sh")
        run(["init", "-q"], in: e + "/inner")
        commitAll(e + "/inner")
        commitAll(e)
        let proof = paths(offered(rules(dirs: ["node_modules", "dist", "build", "out"])))
        assertEqual(proof, [a + "/dist", b + "/node_modules", c + "/tmpstuff/dist", e + "/node_modules"],
                    "Exactly the four proven items: no tracked build/, unignored out/, committed dist/, stray node_modules or nested build/")

        // 2. cdm's grouping: a named group root is one row, counting its repos; others keep theirs.
        for name in ["aaaaaaaa-1111", "bbbbbbbb-2222"] {
            repo(home + "/store/" + name, ignoring: ["node_modules", "dist"])
            file(home + "/store/\(name)/node_modules/pkg.js")
        }
        file(home + "/store/aaaaaaaa-1111/dist/x.js")
        for name in ["projA", "projB"] {
            repo(home + "/work/" + name, ignoring: ["node_modules", "dist"])
            file(home + "/work/\(name)/node_modules/pkg.js")
        }
        let grouped = offered(rules(dirs: ["node_modules", "dist"], groups: ["~/store"]))
        let store = grouped.first { $0.key == home + "/store" }
        assertEqual(store?.paths.count, 3, "Every item under the group root lands in its one row")
        assertTrue(store?.summary.hasPrefix("2 repos · ") == true, "...which counts repos, not items")
        let projA = grouped.first { $0.key == home + "/work/projA" }
        assertTrue(projA != nil && grouped.contains { $0.key == home + "/work/projB" }, "Sibling repos not named as a group keep their own rows")
        assertEqual(projA?.summary, "node_modules", "...with no repo count")
        assertTrue(grouped.map(\.key) == grouped.map(\.key).sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }, "Rows come in byte order")

        // 3. cdm's .env* exception, with the git-ignored pass on.
        let env = home + "/proj"
        repo(env, ignoring: [".env", ".env.*", ".envrc", "*.log", "secret.conf"])
        for name in [".env", ".env.local", ".env.production", ".envrc", "debug.log", "secret.conf"] { file(env + "/" + name) }
        let gitignored = offered(rules(dirs: [], gitignore: true))
        let envRow = gitignored.first { $0.key == env }
        assertTrue(!paths(gitignored).contains { ($0 as NSString).lastPathComponent.hasPrefix(".env") }, "No .env* file is ever offered")
        assertEqual(Set(envRow?.paths ?? []), [env + "/debug.log", env + "/secret.conf"], "...while the rest of what git ignores is")
        assertEqual(Set(envRow?.methods ?? []), [.trash], "...and goes to the Trash")

        // 4. Lightspot's guards.
        assertTrue(!paths(gitignored).contains(e + "/inner"), "An outer repo ignoring a whole nested checkout cannot offer it")
        let mixed = offered(rules(dirs: ["node_modules"], gitignore: true)).first { $0.key == e }
        assertEqual(mixed?.paths, [e + "/node_modules"], "The outer repo still offers its own junk")
        assertEqual(mixed?.methods, [.rm], "A regenerable folder found by the git-ignored pass is still deleted")
        repo(home + "/Documents/docsrepo", ignoring: ["node_modules"])
        file(home + "/Documents/docsrepo/node_modules/pkg.js")
        repo(home + "/Library/librepo", ignoring: ["node_modules"])
        file(home + "/Library/librepo/node_modules/pkg.js")
        repo(home + "/a/b/c/d/e/deep", ignoring: ["node_modules"])
        file(home + "/a/b/c/d/e/deep/node_modules/pkg.js")
        file(home + "/worktree/.git", "gitdir: /elsewhere")
        file(home + "/worktree/node_modules/pkg.js")
        let walk = CleanDevMacProjects.walk(rules(dirs: ["node_modules"]), home: home)
        assertTrue(!walk.repos.contains { $0.hasPrefix(home + "/Documents") }, "Documents is never entered (no macOS prompt, and cdm refuses it anyway)")
        assertTrue(!walk.repos.contains { $0.hasPrefix(home + "/Library") }, "Library is never entered")
        assertTrue(!walk.repos.contains(home + "/a/b/c/d/e/deep"), "A repo deeper than maxDepth is not reached")
        assertTrue(!walk.repos.contains(home + "/worktree"), "A .git file (a worktree) does not make a repo")
        assertTrue(walk.repos.contains(a) && walk.candidates.contains(b + "/node_modules"), "...while ordinary repos and candidates are found")
        run(["init", "-q"], in: home)
        file(home + "/.gitignore", "notarepo\n")
        let homeRepo = CleanDevMacProjects.walk(rules(dirs: ["node_modules"]), home: home)
        assertTrue(!homeRepo.repos.contains(home), "The home folder is never a project, even with its own .git")
        assertTrue(!paths(offered(rules(dirs: ["node_modules"], gitignore: true))).contains(home + "/notarepo"),
                   "...so a dotfiles repo cannot offer what it ignores")
        try? fm.removeItem(atPath: home + "/.git")
        try? fm.removeItem(atPath: home + "/.gitignore")
        var capped = rules(dirs: ["node_modules", "dist"])
        capped.maxRepos = 1
        assertEqual(CleanDevMacProjects.reposToList(CleanDevMacProjects.walk(capped, home: home), rules: capped).count, 1,
                    "maxRepos caps how many repos git is asked about")

        // 5. In the cleaner: offered after the cache scan, added unticked, cleaned per path.
        let trash = home + "/.Trash"
        try? fm.createDirectory(atPath: trash, withIntermediateDirectories: true)
        var ruleSet = CleanDevMacRuleSet(rules: [], terminalOnly: [], source: .remote)
        ruleSet.projects = rules(dirs: ["node_modules"], gitignore: true)
        ruleSet.projects.categoryNames = ["node_modules folders", "Git-ignored files (all repos)"]
        let withProjects = ruleSet
        var environment = CleanDevMacProvider.Environment(
            home: home, bundledRules: nil, processEnvironment: [:],
            fetchRemoteRules: { $0(withProjects) },
            moveToTrash: { url in try FileManager.default.moveItem(atPath: url.path, toPath: trash + "/" + url.lastPathComponent) }
        )
        environment.git = nil
        let noGit = CleanDevMacProvider(environment: environment)
        assertEqual(noGit.scanEntries(withProjects).terminalOnly, ["node_modules folders", "Git-ignored files (all repos)"],
                    "Without git, the repo scan's categories are left to cdm")
        environment.git = git
        let cleaner = CleanDevMacProvider(environment: environment)
        func wait(_ phase: CleanDevMacProvider.Phase) -> CleanDevMacProvider.Snapshot {
            let deadline = Date().addingTimeInterval(30)
            while Date() < deadline {
                let snapshot = cleaner.snapshot
                if snapshot.phase == phase { return snapshot }
                usleep(10_000)
            }
            print("❌ FAIL: the cleaner never reached \(phase); it is at \(cleaner.snapshot.phase)")
            exit(1)
        }
        cleaner.startScan()
        let caches = wait(.ready)
        assertEqual(caches.repos, .offered, "With project rules and git, the repo scan is offered after the cache scan")
        assertTrue(caches.entries.isEmpty, "...and nothing was scanned before it is accepted")
        cleaner.scanRepos()
        let scanned = wait(.ready)
        guard case .scanned(let repoCount) = scanned.repos else {
            assertTrue(false, "The repo scan reports what it found")
            return
        }
        assertTrue(repoCount >= 9, "Every fixture repo was found (\(repoCount))")
        assertEqual(scanned.generation, caches.generation, "Adding repo rows keeps the ticks the user made")
        let envEntry = scanned.entries.first { $0.rule.name == "~/proj" }
        assertEqual(envEntry?.rule.kind, .project, "A repo's row is a project row")
        assertTrue(envEntry?.rule.isDefault == false, "...unticked, as cdm leaves it")
        assertTrue(scanned.entries.allSatisfy { $0.id >= CleanDevMacProvider.projectIDBase }, "Repo rows have IDs of their own")
        let receipt = cleaner.performClean(scanned.entries.filter { $0.rule.name == "~/proj" || $0.rule.name == "~/code/repoE" })
        assertTrue(!fm.fileExists(atPath: e + "/node_modules"), "A regenerable folder is deleted")
        assertTrue(fm.fileExists(atPath: trash + "/debug.log") && !fm.fileExists(atPath: env + "/debug.log"), "Another ignored file goes to the Trash")
        assertTrue(fm.fileExists(atPath: env + "/.env") && fm.fileExists(atPath: e + "/inner/build/release.sh"), "Secrets and nested checkouts are untouched")
        assertTrue(receipt.movedToTrash && receipt.problems.isEmpty, "The receipt says so")
        let log = (try? String(contentsOfFile: home + "/.cleandevmac/clean.log", encoding: .utf8)) ?? ""
        assertTrue(log.contains("▸ ~/proj\n") && log.contains("  trashed: ~/proj/debug.log\n") && log.contains("  deleted: ~/code/repoE/node_modules\n"),
                   "The log records each path's own method")

        print("✅ CleanDevMac repo scan passed all tests!\n")
    }
}

/// Carries a completion handler's value out to the test waiting on it.
final class ResultBox<Value>: @unchecked Sendable {
    var value: Value?
}
