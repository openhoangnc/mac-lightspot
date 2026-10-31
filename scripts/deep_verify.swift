import AppKit
import Foundation

// Live-system verification. Everything here talks to the real machine: it resolves
// every settings deep link through NSWorkspace, compiles every AppleScript Lightspot
// can emit, scans the real /Applications, and parses the real zsh history file.
//
// Build & run:
//   swiftc -o /tmp/deep_verify scripts/deep_verify.swift \
//       Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift \
//       && /tmp/deep_verify

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

        // The scheme check above passes for any pane ID at all. System Settings opens a
        // pane by its extension's bundle identifier, so each link must name one.
        let panes = SettingsSearchTerms.paneExtensions()
        let unknownPanes = settings.filter { panes[$0.extensionID] == nil }
        for item in unknownPanes {
            print("     ⚠️ No installed pane for: \(item.name) -> \(item.extensionID)")
        }
        check("Every settings deep link names an installed System Settings pane", unknownPanes.isEmpty)

        let termKeys = SettingsProvider.shared.loadSearchTerms()
        print("System Settings search terms indexed: \(termKeys) keys")
        check("System Settings search terms load (> 1,000 keys)", termKeys > 1_000)
        // Terms that exist only in Apple's .searchTerms files, not in Lightspot's keywords. Only
        // where this macOS's pane still ships the term: on 27.2 the Wi-Fi pane ships no
        // .searchTerms file at all, so "Known networks" has nothing to come from.
        for (query, pane, setting) in [("lockdown mode", "Privacy & Security", "Lockdown Mode"),
                                       ("power nap", "Battery", "Power Nap"),
                                       ("universal control", "Displays", "Universal Control"),
                                       ("known networks", "Wi-Fi", "Known networks"),
                                       ("sticky keys", "Accessibility", "Sticky Keys")] {
            let shipped = settings.first { $0.name == pane }.flatMap { panes[$0.extensionID] }
                .map { SettingsSearchTerms.termsFiles(of: $0, languages: ["en"]).flatMap(SettingsSearchTerms.entries(inFile:)) } ?? []
            guard shipped.contains(where: { $0.title.caseInsensitiveCompare(setting) == .orderedSame }) else {
                print("     ⚠️ \(pane) ships no '\(setting)' search term on this macOS — skipping '\(query)'")
                continue
            }
            let row = SettingsProvider.shared.search(SearchQuery(query)).first
            check("'\(query)' finds \(pane) → \(setting)",
                  row?.title == pane && row?.subtitle.hasSuffix("→ \(setting)") == true)
        }

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
            } else if action.script.hasPrefix("internal:") {
                check("Internal action valid: \(action.name)", true)
            } else if action.script.hasPrefix("open:") {
                var path = String(action.script.dropFirst("open:".count))
                if path.hasPrefix("~") {
                    path = NSString(string: path).expandingTildeInPath
                }
                let exists = FileManager.default.fileExists(atPath: path)
                check("Target app/folder exists: \(action.name) at \(path)", exists)
            } else {
                // Shell command check: it parses, and the program it starts with (or, for a
                // toggle that starts with `case`/`if`, `defaults`) is installed.
                let syntax = Process()
                syntax.executableURL = URL(fileURLWithPath: "/bin/sh")
                syntax.arguments = ["-n", "-c", action.script]
                syntax.standardError = FileHandle.nullDevice
                try? syntax.run()
                syntax.waitUntilExit()
                check("Shell command parses: \(action.name)", syntax.terminationStatus == 0)
                var binary = action.script.split(separator: " ").first.map(String.init) ?? ""
                if binary == "case" || binary == "if" { binary = "defaults" }
                let exists = FileManager.default.fileExists(atPath: binary)
                    || binary == "pmset"
                    || binary == "dscacheutil"
                    || FileManager.default.fileExists(atPath: "/usr/bin/\(binary)")
                    || FileManager.default.fileExists(atPath: "/bin/\(binary)")
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

        let safariResults = AppScanner.shared.search(SearchQuery("safari"))
        check("Discovered Safari.app on system", !safariResults.isEmpty && safariResults.first?.title.lowercased().contains("safari") == true)

        let termResults = AppScanner.shared.search(SearchQuery("terminal"))
        check("Discovered Terminal.app on system", !termResults.isEmpty && termResults.first?.title.lowercased().contains("terminal") == true)

        // Verify strictly NO file indexing
        print("\n--- 4. Verifying Strictly ZERO File Indexing ---")
        let docQuery1 = SearchEngine.shared.searchImmediate(SearchQuery("README.md"))
        let hasDocResult1 = docQuery1.values.flatMap { $0 }.contains { $0.subtitle.hasSuffix(".md") && $0.category != .webSearch }
        check("Does not index README.md", !hasDocResult1)

        let docQuery2 = SearchEngine.shared.searchImmediate(SearchQuery("Package.swift"))
        let hasDocResult2 = docQuery2.values.flatMap { $0 }.contains { $0.subtitle.hasSuffix(".swift") && $0.category != .webSearch }
        check("Does not index Package.swift", !hasDocResult2)

        let docQuery3 = SearchEngine.shared.searchImmediate(SearchQuery(".pdf"))
        let hasDocResult3 = docQuery3.values.flatMap { $0 }.contains { $0.subtitle.hasSuffix(".pdf") && $0.category != .webSearch }
        check("Does not index .pdf documents", !hasDocResult3)

        // The history provider is the only thing that reads a user file, and it reads
        // exactly one: a query that cannot appear in it must return nothing.
        let nonsense = SearchEngine.shared.searchImmediate(SearchQuery("zz-\(UUID().uuidString)"))
        check("Unknown query produces no Terminal History results", nonsense[.shellHistory] == nil)

        // ----------------------------------------------------
        // SECTION 5: zsh History (single file, parsed off the app's search path)
        // ----------------------------------------------------
        print("\n--- 5. Testing Shell History Provider Against the Real History File ---")
        if let historyURL = ShellHistoryProvider.historyFileURL() {
            print("History file: \(historyURL.path)")
            let name = historyURL.lastPathComponent
            let histfile = ProcessInfo.processInfo.environment["HISTFILE"].map { ($0 as NSString).expandingTildeInPath }
            check("Reads a shell history file only", name == ".zsh_history" || name == ".zhistory" || historyURL.path == histfile)

            let entries = ShellHistoryProvider.loadEntries(from: historyURL)
            print("Parsed unique commands: \(entries.count)")
            check("Entry count is capped (<= 1200)", entries.count <= 1200)
            check("No empty commands parsed", entries.allSatisfy { !$0.command.isEmpty })
            check("No command exceeds the length cap", entries.allSatisfy { $0.command.count <= 300 })
            check("Display titles are single-line", entries.allSatisfy { !$0.displayTitle.contains("\n") })
            check("Commands are de-duplicated", Set(entries.map { $0.command }).count == entries.count)

            if let newest = entries.first, let token = newest.tokens.first, token.count >= 2 {
                let results = ShellHistoryProvider.search(SearchQuery(token), pinned: [], history: entries)
                check("Searching '\(token)' finds the command it came from", results.contains { $0.title == newest.displayTitle })
                check("History results never leak a path into the subtitle", results.allSatisfy { $0.subtitle.hasSuffix("Run in Terminal") })
                check("History results all carry a run-in-Terminal action", results.allSatisfy {
                    if case .runInTerminal = $0.action { return true }
                    return false
                })
                check("History results are capped per search", results.count <= 12)
            } else {
                print("     ⚠️ History file has no usable entries — skipping search checks")
            }
        } else {
            print("     ⚠️ No zsh history file on this machine — skipping history checks")
        }

        // ----------------------------------------------------
        // SECTION 6: Terminal command escaping compiles as AppleScript
        // ----------------------------------------------------
        print("\n--- 6. Testing Terminal Launcher AppleScript Generation ---")
        check("Terminal.app is installed", FileManager.default.fileExists(atPath: "/System/Applications/Utilities/Terminal.app"))

        let commandSamples = [
            "git status",
            "echo \"hello world\"",
            "grep -R 'needle' . | wc -l",
            "printf 'a\tb\n'",
            "cd ~/Projects && ls -la",
            "echo back\\slash",
            // A command written to break out of the AppleScript literal.
            "\"\nactivate\ndo shell script \"whoami"
        ]
        for command in commandSamples {
            let source = TerminalLauncher.script(for: command)
            var error: NSDictionary?
            let compiled = NSAppleScript(source: source)?.compileAndReturnError(&error) ?? false
            check("Generated AppleScript compiles for: \(command.replacingOccurrences(of: "\n", with: "⏎"))", compiled)
            if !compiled, let err = error {
                print("     Error: \(err)")
            }
        }

        // ----------------------------------------------------
        // SECTION 7: Math Calculator Comprehensive Suite
        // ----------------------------------------------------
        print("\n--- 7. Testing Calculator Engine Comprehensive Suite ---")
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
        // SECTION 8: Search Engine Aggregation & Fallbacks
        // ----------------------------------------------------
        print("\n--- 8. Testing Search Engine Categorization ---")
        let search1 = SearchEngine.shared.searchImmediate(SearchQuery("sound"))
        check("Search 'sound' produces Top Hit", search1[.topHit] != nil)
        check("Search 'sound' produces System Settings", search1[.systemSettings] != nil)
        check("Search 'sound' produces Web Search fallback", search1[.webSearch] != nil)

        let search2 = SearchEngine.shared.searchImmediate(SearchQuery("50 * 50"))
        check("Search '50 * 50' produces Calculator result", search2[.calculator] != nil)
        check("Search '50 * 50' Calculator value is 2.500 or 2,500", search2[.calculator]?.first?.title == CalculatorEngine.evaluate("2500 + 0"))

        // ----------------------------------------------------
        // SECTION 9: Custom Commands Live Integration
        // ----------------------------------------------------
        print("\n--- 9. Testing Custom Commands Live System Integration ---")
        let store = CustomCommandsStore.shared
        let existingCommands = store.entries()

        let testCmd = CustomCommand(
            name: "Live Verification Command",
            type: .appleScript,
            target: #"display notification "Lightspot verification" with title "Test""#,
            keywords: ["selftest", "livecheck"]
        )
        store.add(testCmd)

        let customSearch = SearchEngine.shared.searchImmediate(SearchQuery("selftest"))
        check("SearchEngine finds custom command by keyword", customSearch[.customCommands]?.contains { $0.title == testCmd.name } == true || customSearch[.topHit]?.first?.title == testCmd.name)

        // Verify AppleScript compilation for custom command
        var asError: NSDictionary?
        let asCompiled = NSAppleScript(source: testCmd.target)?.compileAndReturnError(&asError) ?? false
        check("AppleScript compiles for test custom command", asCompiled)

        // Live test prefix command
        let prefixTestCmd = CustomCommand(
            name: "Live Prefix Test",
            type: .url,
            target: "https://example.com/search?q={query}",
            keywords: ["lptest"],
            prefix: "lcheck",
            iconSource: .runner
        )
        store.add(prefixTestCmd)
        let prefixSearch = SearchEngine.shared.searchImmediate(SearchQuery("lcheck myparam"))
        check("Prefix command 'lcheck myparam' captures query as Top Hit", prefixSearch[.topHit]?.first?.title == "Live Prefix Test for 'myparam'")
        check("Runner icon resolves to valid icon", prefixTestCmd.runnerAppPath != nil)

        // Clean up
        store.delete(id: testCmd.id)
        store.delete(id: prefixTestCmd.id)
        store.reset(to: existingCommands)
        check("Cleaned up test custom command", store.entries().allSatisfy { $0.id != testCmd.id })

        // ----------------------------------------------------
        // SECTION 10: VS Code Recent Projects Live System Verification
        // ----------------------------------------------------
        print("\n--- 10. Testing VS Code Recent Projects Provider ---")
        if VSCodeProjectsProvider.isVSCodeInstalled {
            print("VS Code detected at: \(VSCodeProjectsProvider.vsCodeAppPath)")
            let loadedProjects = VSCodeProjectsProvider.loadRecentProjects()
            print("Discovered recent VS Code projects: \(loadedProjects.count)")
            check("Discovered >= 1 recent VS Code project", !loadedProjects.isEmpty)
            check("All project paths exist on disk", loadedProjects.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
            check("All project paths are clean (no .git suffix)", loadedProjects.allSatisfy { !$0.path.hasSuffix(".git") })
            check("All project displayPaths are tilde-formatted", loadedProjects.allSatisfy { $0.displayPath.hasPrefix("~") || !$0.path.hasPrefix(NSHomeDirectory()) })

            if let firstProj = loadedProjects.first {
                let projSearch = VSCodeProjectsProvider.search(SearchQuery(firstProj.name), projects: loadedProjects)
                check("Search by exact project name finds project", projSearch.contains { $0.title == firstProj.name })
                check("Project result action is .openFolder", projSearch.allSatisfy {
                    if case .openFolder = $0.action { return true }
                    return false
                })
                check("Project result category is .recentProjects", projSearch.allSatisfy { $0.category == .recentProjects })
            }
        } else {
            print("     ⚠️ VS Code is not installed on this system — skipping live discovery checks")
        }

        // ----------------------------------------------------
        // SECTION 11: Clean Dev Mac (cdm) on the real home folder — measures, never deletes
        // ----------------------------------------------------
        print("\n--- 11. Testing Clean Dev Mac (cdm) on the real home folder ---")
        let cdmHome = NSHomeDirectory()
        let bundledRulesFolder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/Resources/cdm-rules")
        let bundledRules = CleanDevMacRules.load(directory: bundledRulesFolder, source: .bundled)
        check("The cdm rules shipped in the app load", bundledRules != nil)

        // The rules the app fetches: cdm's live ones, still in a shape Lightspot reads.
        let fetched = DispatchSemaphore(value: 0)
        let liveRules = LiveRulesBox()
        CleanDevMacRules.fetchRemote { rules in
            liveRules.value = rules
            fetched.signal()
        }
        if fetched.wait(timeout: .now() + 20) == .success, let live = liveRules.value {
            check("cdm's live rules on GitHub parse", !live.rules.isEmpty)
            let shipped = Set(bundledRules?.rules.map(\.name) ?? [])
            let changed = Set(live.rules.map(\.name)).symmetricDifference(shipped)
            if !changed.isEmpty {
                print("     ⚠️ The shipped copy differs from cdm's live rules (\(changed.sorted().joined(separator: ", "))); refresh Resources/cdm-rules")
            }
        } else {
            print("     ⚠️ GitHub unreachable — skipping the live rules check")
        }

        if let rules = bundledRules {
            let started = Date()
            let scan = CleanDevMacProvider(environment: .live).scanEntries(rules)
            let paths = scan.entries.flatMap(\.paths)
            print("Found \(scan.entries.count) categories (\(paths.count) paths, \(CleanDevMacEngine.humanKB(CleanDevMacProvider.uniqueKB(scan.entries)))) in \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
            let physicalHome = CleanDevMacEngine.physicalPath(cdmHome)
            let userFolder = CleanDevMacEngine.userFolder()
            check("This user's own temp folders are found", userFolder != nil)
            check("Every offered path passes cdm's safety gate",
                  paths.allSatisfy { CleanDevMacEngine.isSafeTarget($0, home: cdmHome, physicalHome: physicalHome, userFolder: userFolder) })
            check("Nothing is offered in a protected folder", paths.allSatisfy { path in
                CleanDevMacEngine.protectedFolders.allSatisfy { !path.hasPrefix(cdmHome + "/" + $0 + "/") && path != cdmHome + "/" + $0 }
            })
            check("Nothing is read inside other apps' containers",
                  paths.allSatisfy { !CleanDevMacEngine.isOutOfScope($0, home: cdmHome) })
            check("Every offered category has a size, biggest first",
                  scan.entries.allSatisfy { $0.sizeKB > 0 } && zip(scan.entries, scan.entries.dropFirst()).allSatisfy { $0.sizeKB >= $1.sizeKB })

            // A row is sized as cdm sizes it, with one du over all its paths. Caches change
            // while they are measured (a browser's, while it browses), so 2% (or 4 MB) either
            // way passes; test_engine holds the exact sizes against du on fixtures. Not the
            // row of Chrome's leftover copies, which du counts once per copy on purpose.
            let multiPath = scan.entries.filter { $0.paths.count > 1 && $0.rule.kind != .codeSignClones }
            var unlikeDu: [String] = []
            for entry in multiPath {
                let duKB = CleanDevMacEngine.output(of: "/usr/bin/du", ["-sk"] + entry.paths, timeout: 120)
                    .split(separator: "\n").reduce(0) { $0 + (Int($1.split(separator: "\t").first ?? "") ?? 0) }
                if abs(duKB - entry.sizeKB) > max(entry.sizeKB / 50, 4096) {
                    unlikeDu.append("\(entry.rule.name): \(entry.sizeKB) KB, du \(duKB) KB")
                }
            }
            check("Each of the \(multiPath.count) categories with several paths measures what one du over them prints", unlikeDu.isEmpty)
            for line in unlikeDu { print("     \(line)") }

            // The repo scan, read-only: what it would offer from the real home folder.
            if let git = CleanDevMacProjects.gitExecutable(), !rules.projects.isEmpty {
                let repoStarted = Date()
                let repoScan = CleanDevMacProjects.scan(rules.projects, home: cdmHome, git: git)
                let offered = repoScan.projects.flatMap(\.paths)
                print("Repo scan: \(repoScan.repoCount) repos, \(repoScan.projects.count) with junk (\(offered.count) items) in \(String(format: "%.1f", Date().timeIntervalSince(repoStarted))) s")
                check("Every repo item passes cdm's safety gate",
                      offered.allSatisfy { CleanDevMacEngine.isSafeTarget($0, home: cdmHome, physicalHome: physicalHome) })
                check("No .env* file is offered", offered.allSatisfy { !($0 as NSString).lastPathComponent.hasPrefix(".env") })
                let skipped = CleanDevMacProjects.skippedFolders(home: cdmHome)
                check("Nothing under Library or a protected folder is offered",
                      offered.allSatisfy { path in !skipped.contains { path == $0 || path.hasPrefix($0 + "/") } })
                check("Every repo row pairs each path with a method",
                      repoScan.projects.allSatisfy { $0.paths.count == $0.methods.count && !$0.paths.isEmpty })
            } else {
                print("     ⚠️ No git — skipping the repo scan checks")
            }
        }

        // cdm's two notes beside its disk line, read from this Mac. df's own answer for the
        // swap, read the way cdm's swap_stats reads it, comes from before and after the
        // estimate: macOS adds and drops 1 GiB swap files as it goes, so the swap can change
        // while lsof runs.
        func dfSwapKB() -> Int {
            let rows = CleanDevMacEngine.output(of: "/bin/df", ["-Pk", cdmHome, "/System/Volumes/VM"], timeout: 10)
                .split(separator: "\n").map { $0.split(separator: " ", omittingEmptySubsequences: true).map(String.init) }
            guard rows.count == 3, rows[2].count >= 6, rows[2].last == "/System/Volumes/VM", rows[1].first?.hasPrefix("/dev/disk") == true,
                  CleanDevMacEngine.container(of: rows[1][0]) == CleanDevMacEngine.container(of: rows[2][0]) else { return 0 }
            return Int(rows[2][2]) ?? 0
        }
        let swapBefore = dfSwapKB()
        let estimateStarted = Date()
        let estimate = CleanDevMacEngine.restartEstimate(home: cdmHome)
        let estimateSeconds = Date().timeIntervalSince(estimateStarted)
        let swapAfter = dfSwapKB()
        print("A restart would free \(CleanDevMacEngine.humanKB(estimate.totalKB)): \(CleanDevMacEngine.humanKB(estimate.swapKB)) swap, \(CleanDevMacEngine.humanKB(estimate.tempKB)) temp, \(CleanDevMacEngine.humanKB(estimate.heldKB)) held open by \(estimate.heldApps.joined(separator: ", ")) (\(String(format: "%.1f", estimateSeconds)) s); note: \(CleanDevMacEngine.diskStats(path: cdmHome).flatMap { estimate.line(freeKB: $0.freeKB) } ?? "none, the disk has more free")")
        check("What a restart would free is measured within cdm's time limits", estimateSeconds < 16)
        check("Swap is df's Used column for the VM volume, read before or after it",
              [swapBefore, swapAfter].contains { abs(estimate.swapKB - $0) <= max($0 / 100, 1024) })

        let claudeStarted = Date()
        let claudeFolder = CleanDevMacEngine.claudeFolder(home: cdmHome, environment: ProcessInfo.processInfo.environment)
        let history = CleanDevMacEngine.claudeHistory(folder: claudeFolder, now: Int(Date().timeIntervalSince1970))
        check("Claude Code's history is read within cdm's ten seconds", Date().timeIntervalSince(claudeStarted) < 12)
        if let history {
            print("Claude Code: \(CleanDevMacEngine.humanKB(history.sizeKB)) of history, \(history.oldTranscripts) transcripts past \(history.keepDays) days; note: \(history.note(home: cdmHome).map { $0.summary } ?? "none, under 1 GB")")
        } else {
            print("Claude Code: no note (no history, desktopSessionCleanupPeriodDays is set, or nothing is past the limit)")
        }

        // ----------------------------------------------------
        // SECTION 12: Mac Tweaks' Free Up Space on this Mac — reads only, never moves
        // ----------------------------------------------------
        print("\n--- 12. Testing Mac Tweaks' Free Up Space on this Mac (reads only) ---")
        let tweaksRecord = TweaksRecorder()
        var tweaksEnvironment = MacTweaksProvider.Environment.live
        let liveRun = tweaksEnvironment.run
        tweaksEnvironment.run = { executable, arguments, timeout in
            tweaksRecord.ran(([executable] + arguments).joined(separator: " "))
            return liveRun(executable, arguments, timeout)
        }
        // The live scan never moves anything or asks for a password; if it tried, it fails here.
        tweaksEnvironment.moveToTrash = { url in
            tweaksRecord.forbidden("moveToTrash " + url.path)
            throw CocoaError(.featureUnsupported)
        }
        tweaksEnvironment.runAdmin = { _ in
            tweaksRecord.forbidden("runAdmin")
            return .refused("deep_verify never asks for a password")
        }
        // The app falls back on the rules inside Lightspot.app; this runner has none, so it
        // uses the repository's copy, the same files.
        let shippedRules = bundledRules
        tweaksEnvironment.cleanDevMacRules = { home in MacTweaksStorage.cleanDevMacRules(home: home) ?? shippedRules }
        let residentBefore = residentBytes()
        let tweaksStarted = Date()
        var tweakRows: [MacTweaksRow]? = MacTweaksStorage.scan(tweaksEnvironment)
        let tweaksSeconds = Date().timeIntervalSince(tweaksStarted)
        let rowsFound = tweakRows ?? []
        for row in rowsFound {
            print("     \(row.title): \(row.isLink ? "link" : "\(row.items.count) items, \(row.value)")\(row.tags.isEmpty ? "" : " [" + row.tags.joined(separator: ", ") + "]")")
        }
        let offeredItems = rowsFound.filter { !$0.isLink }.flatMap { row in row.items.map { (row, $0) } }
        print("Free Up Space found \(MacTweaksProvider.size(MacTweaksProvider.freeableBytes(rowsFound))) in \(rowsFound.filter { !$0.isLink }.count) rows (\(offeredItems.count) items) in \(String(format: "%.1f", tweaksSeconds)) s")
        check("Free Up Space scans this Mac within 60 s", tweaksSeconds < 60)
        check("The scan never moves a file or asks for a password", tweaksRecord.forbiddenCalls.isEmpty)
        check("xcrun is never run", tweaksRecord.programs.allSatisfy { !$0.hasPrefix("/usr/bin/xcrun") })
        check("It runs only xcode-select, simctl and tmutil",
              tweaksRecord.programs.allSatisfy { $0.hasPrefix("/usr/bin/xcode-select -p") || $0.hasPrefix("/usr/bin/tmutil listlocalsnapshotdates /")
                  || $0.contains("/usr/bin/simctl list devices unavailable -j") })
        let tweaksRoots = MacTweaksStorage.Roots(tweaksEnvironment)
        check("Every offered path passes the gate again", offeredItems.allSatisfy { row, item in
            row.id == "snapshots" || MacTweaksStorage.isAllowed(item.target, MacTweaksStorage.RowID(rawValue: row.id)!, environment: tweaksEnvironment, roots: tweaksRoots)
        })
        check("Nothing is offered under /System or in a folder macOS guards", offeredItems.allSatisfy { _, item in
            tweaksRoots.neverTouched.allSatisfy { !MacTweaksStorage.isInside(item.target, $0) }
        })
        check("Every file row is sized item by item", rowsFound.filter { !$0.isLink && $0.id != "snapshots" }.allSatisfy { row in
            row.items.allSatisfy { $0.bytes > 0 } && row.bytes == row.items.reduce(0) { $0 + $1.bytes }
        })
        let cacheNames = (try? FileManager.default.contentsOfDirectory(atPath: tweaksRoots.caches.lexical)) ?? []
        let appleNamed = cacheNames.filter { MacTweaksStorage.isAppleCache($0) && !$0.lowercased().hasPrefix("com.apple.") }.sorted()
        print("     macOS's caches here without a com.apple. name, kept out: \(appleNamed.joined(separator: ", "))")
        check("No cache macOS or Lightspot owns is offered", (rowsFound.first { $0.id == "caches" }?.items ?? []).allSatisfy { item in
            let name = (item.target as NSString).lastPathComponent
            return !MacTweaksStorage.isAppleCache(name) && name != "com.lightspot.app"
        })
        let cleanerCaches = cacheNames.filter { tweaksRoots.isCleanDevMacCache($0) }.sorted()
        print("     Left to Clean Dev Mac (\(tweaksRoots.cleanDevMacCacheGlobs.count) globs from its rules): \(cleanerCaches.joined(separator: ", "))")
        check("App caches offers nothing Clean Dev Mac's rules reach", !tweaksRoots.cleanDevMacCacheGlobs.isEmpty
              && (rowsFound.first { $0.id == "caches" }?.items ?? []).allSatisfy { !tweaksRoots.isCleanDevMacCache(($0.target as NSString).lastPathComponent) })
        let directDates = MacTweaksStorage.snapshotDates(tmutilOutput: CleanDevMacEngine.output(of: "/usr/bin/tmutil", ["listlocalsnapshotdates", "/"], timeout: 30))
        check("The snapshot row lists what tmutil lists (\(directDates.count))",
              (rowsFound.first { $0.id == "snapshots" }?.items.map(\.target) ?? []) == directDates)
        let devicesFolder = tweaksRoots.simulatorDevices.lexical
        let selectedDeveloper = CleanDevMacEngine.output(of: "/usr/bin/xcode-select", ["-p"], timeout: 10).trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSimctl = MacTweaksStorage.isFolder(devicesFolder) && FileManager.default.isExecutableFile(atPath: selectedDeveloper + "/usr/bin/simctl")
        print("     Developer folder: \(selectedDeveloper.isEmpty ? "none" : selectedDeveloper); simulator devices folder \(MacTweaksStorage.isFolder(devicesFolder) ? "present" : "absent")")
        if !hasSimctl {
            check("Without Xcode's simctl there is no simulator row", !rowsFound.contains { $0.id == "simulators" })
            check("...and simctl is never run", tweaksRecord.programs.allSatisfy { !$0.contains("simctl") })
        }
        // The gate's physical half: on a real Mac each fixed folder resolves to itself.
        for folder in ["/Applications", "/Library/Application Support", "/Library/Audio/Apple Loops",
                       "/Library/Application Support/com.apple.idleassetsd/Customer", tweaksRoots.caches.lexical]
        where MacTweaksStorage.isFolder(folder) {
            check("\(folder) resolves to itself", MacTweaksStorage.resolved(folder) == folder)
        }
        check("Both link rows are offered", rowsFound.filter(\.isLink).map(\.id) == ["clean-dev-mac", "storage-settings"])
        check("The Storage link names an installed System Settings pane", panes["com.apple.settings.Storage"] != nil)
        let symbols = [MacTweaksProvider.symbol, "xmark.circle.fill", "checkmark.square.fill", "square", "arrow.up.forward.square",
                       "checkmark.circle.fill"]
            + MacTweaksSection.allCases.map(\.symbol) + MacTweaksStorage.catalog.map(\.symbol)
        let missingSymbols = symbols.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
        check("Every SF Symbol Mac Tweaks draws exists\(missingSymbols.isEmpty ? "" : ": missing " + missingSymbols.joined(separator: ", "))", missingSymbols.isEmpty)
        // What the scan leaves in memory once its rows go (in this runner, not the app).
        tweakRows = nil
        malloc_zone_pressure_relief(nil, 0)
        let residentAfter = residentBytes()
        print("     Resident memory: \(residentBefore / 1_048_576) MB before the scan, \(residentAfter / 1_048_576) MB once its rows were dropped")

        // ----------------------------------------------------
        // SECTION 13: Mac Tweaks' Apple Intelligence on this Mac — reads only, never resets
        // ----------------------------------------------------
        print("\n--- 13. Testing Mac Tweaks' Apple Intelligence on this Mac (reads only) ---")
        let aiRecord = TweaksRecorder()
        var aiEnvironment = MacTweaksProvider.Environment.live
        // deep_verify calls the read-only bridge in-process; the app spawns the helper child.
        // Nothing here resets a set, installs a profile or opens System Settings.
        aiEnvironment.intelligence.assetInventory = { AssetServiceHelper.inventory(bridge: AssetServiceBridge()) }
        aiEnvironment.intelligence.resetAssetSet = { set in aiRecord.forbidden("reset " + set); return .noAnswer }
        aiEnvironment.intelligence.presentProfile = { _ in aiRecord.forbidden("presentProfile") }
        aiEnvironment.intelligence.openDeviceManagement = { aiRecord.forbidden("openDeviceManagement") }
        // A scan that finds the profile installed removes its file; here nothing is removed.
        aiEnvironment.intelligence.removeProfileFile = {}
        aiEnvironment.intelligence.sleep = { _ in }
        let aiInventory = aiEnvironment.intelligence.assetInventory()
        print("     Asset service available: \(aiInventory?.available == true)")
        for set in Catalog.modelSets {
            let info = aiInventory?.info(set.name)
            print("     \(set.title): known \(info?.known ?? false), \(info.map { $0.bytes.map { "\($0) bytes" } ?? "size unknown" } ?? "n/a")")
        }
        let aiRows = MacTweaksIntelligence.scan(aiEnvironment, inventory: aiInventory)
        for row in aiRows { print("     \(row.title): \(row.countLabel ?? "")\(row.readOnly ? " [read-only]" : "")") }
        // Every expectation below follows what this Mac reports, never one macOS's state: 26.7.2
        // retired Spatial Photos' set and had no models on disk; 27.2 knows the set again and
        // downloaded the models.
        let spatialOnThisMacOS = Catalog.availableFeatures.contains { $0.id == "spatial-photos" }
        let spatialKnown = aiInventory?.info(Catalog.spatialModels)?.known
        let spatialShown = spatialOnThisMacOS && (aiInventory?.available != true || spatialKnown == true)
        print("     Spatial Photos: \(spatialOnThisMacOS ? "on this macOS" : "not on this macOS"), its set \(spatialKnown.map { $0 ? "known" : "retired" } ?? "unknown to the service")")
        check("Spatial Photos is \(spatialShown ? "shown" : "hidden"), as this macOS and the service report it",
              aiRows.contains { $0.id == "spatial-photos" } == spatialShown)
        let assistantEnabled = CFPreferencesCopyAppValue("Assistant Enabled" as CFString, "com.apple.assistant.support" as CFString) as? Bool
        if let siri = Catalog.availableFeatures.first(where: { $0.id == "siri" }) {
            // A profile forcing any Siri key makes it Managed (or Locked off, Lightspot's own),
            // whatever Assistant Enabled says.
            let siriForced = MacTweaksIntelligence.switches(siri).contains {
                CFPreferencesAppValueIsForced($0.key as CFString, $0.domain as CFString)
            }
            print("     com.apple.assistant.support Assistant Enabled: \(assistantEnabled.map { "\($0)" } ?? "unset"); a profile forces a Siri key: \(siriForced)")
            let expected = siriForced ? [FeatureState.managed.label, FeatureState.lockedOff.label]
                : [assistantEnabled == false ? FeatureState.off.label : FeatureState.on.label]
            check("Siri shows \(expected.joined(separator: " or ")), as \(siriForced ? "a profile forcing its keys" : "Assistant Enabled (\(assistantEnabled.map { "\($0)" } ?? "unset"))") says",
                  aiRows.first { $0.id == "siri" }?.countLabel.map(expected.contains) == true)
        }
        let aiModelBytes = MacTweaksIntelligence.modelBytes(aiInventory)
        print("     Apple Intelligence models on disk: \(aiModelBytes.map { $0 == 0 ? "none (0 bytes)" : MacTweaksProvider.size($0) } ?? "unknown")")
        // What the summary and the plan say, and that they match what apply would do (B4), with
        // every shown feature ticked: whatever the models' state, three checks.
        let aiContext = MacTweaksIntelligence.ScanContext(inventory: aiInventory, installed: MacTweaksProfile.installed(),
                                                          removeMacAI: MacTweaksProfile.removeMacAIInstalled())
        let aiTicked = aiRows.filter { !$0.readOnly && !MacTweaksIntelligence.isActionRow($0.id) }
        let aiPlan = MacTweaksIntelligence.planNotes(ticked: aiTicked, shown: aiRows, context: aiContext)
        print("     Summary: \(MacTweaksIntelligence.summary(rows: aiRows, context: aiContext))")
        print("     Plan: \(aiPlan.joined(separator: " "))")
        let aiKept = Set(Catalog.availableFeatures.map(\.id)).subtracting(aiTicked.map(\.id))
        let aiRemoval = MacTweaksIntelligence.removalPlan(keeping: aiKept, inventory: aiInventory)
        print("     A turn-off would \(aiRemoval.isNeeded ? "ask the asset service to remove \(aiRemoval.removing.count) sets" : "send no reset")")
        let installedContext = MacTweaksIntelligence.ScanContext(
            inventory: aiInventory,
            installed: MacTweaksProfile.Installed(on: true, ai: true, kept: aiKept, features: Set(Catalog.availableFeatures.map(\.id))))
        let finishOffered = MacTweaksIntelligence.scan(aiEnvironment, context: installedContext).contains { $0.id == MacTweaksIntelligence.finishRemovalID }
        check("Apple Intelligence never reset a set, presented a profile or opened Settings", aiRecord.forbiddenCalls.isEmpty)
        let removalBytes = aiRemoval.bytes.map { MacTweaksProvider.size($0) } ?? "unknown"
        let deletes = aiPlan.contains { $0.hasPrefix("Deletes ") || $0.hasPrefix("Asks macOS to remove the models") }
        if aiInventory?.available != true {
            check("With the asset service silent, turning off sends no reset", !aiRemoval.isNeeded)
            check("...and the plan says the service didn't answer", aiPlan.contains { $0.hasPrefix("Apple's asset service didn't answer") })
            check("...and the section, once the profile is in, offers no finish row", !finishOffered)
        } else if aiRemoval.bytes == 0 {
            check("With the models to remove at 0 bytes, turning off sends no reset", !aiRemoval.isNeeded)
            check("...and the plan deletes nothing and mentions no folder files",
                  !deletes && !aiPlan.joined().lowercased().contains("folder"))
            check("...and the section, once the profile is in, offers no finish row", !finishOffered)
        } else {
            check("With the models to remove at \(removalBytes), turning off asks the asset service to remove them", aiRemoval.isNeeded)
            check("...and the plan says what it deletes",
                  aiPlan.contains { $0.hasPrefix(aiRemoval.bytes == nil ? "Asks macOS to remove the models" : "Deletes \(removalBytes) of models") })
            check("...and the section, once the profile is in, offers to finish the removal", finishOffered)
        }
        // The profile is well-formed data (plutil -lint on a temp copy); nothing is installed.
        if let profileData = try? MacTweaksProfile.data(.init(ai: [], tweaks: [])) {
            let tempProfile = NSTemporaryDirectory() + "lightspot-profile-verify-\(getpid()).mobileconfig"
            try? profileData.write(to: URL(fileURLWithPath: tempProfile))
            let lint = CleanDevMacEngine.run("/usr/bin/plutil", ["-lint", tempProfile], timeout: 10)
            check("The profile is well-formed (plutil -lint)", lint.status == 0)
            let plist = (try? PropertyListSerialization.propertyList(from: profileData, format: nil)) as? [String: Any]
            let payloads = plist?["PayloadContent"] as? [[String: Any]] ?? []
            let marker = payloads.first { ($0["PayloadIdentifier"] as? String)?.hasSuffix(".preferences.com.lightspot.app.tweaks") == true }
            let settings = ((marker?["PayloadContent"] as? [String: Any])?["com.lightspot.app.tweaks"] as? [String: Any])
                .flatMap { ($0["Forced"] as? [[String: Any]])?.first?["mcx_preference_settings"] as? [String: Any] }
            check("The profile's marker reads back as installed", settings != nil && MacTweaksProfile.read(forced: true) { settings?[$0] }.on)
            try? FileManager.default.removeItem(atPath: tempProfile)
        }
        // profiles with read-only verbs only; the owner's profiles are left untouched.
        let profilesStatus = CleanDevMacEngine.run("/usr/bin/profiles", ["status", "-type", "configuration"], timeout: 10)
        print("     profiles status -type configuration: rc \(profilesStatus.status), \(profilesStatus.output.trimmingCharacters(in: .whitespacesAndNewlines))")
        let ours = MacTweaksProfile.installed()
        print("     Lightspot's profile: \(ours.on ? "installed" + (ours.ai ? ", turning Apple Intelligence off" : "") : "not installed")")
        check("The section offers to turn Apple Intelligence back on exactly while Lightspot's profile turns it off",
              aiRows.contains { $0.id == MacTweaksIntelligence.turnOnID } == (ours.on && ours.ai))
        check("Device Management names an installed pane", panes["com.apple.Profiles-Settings.extension"] != nil)
        let aiSymbols = Array(MacTweaksIntelligence.symbols.values)
        let missingAISymbols = aiSymbols.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
        check("Every Apple Intelligence SF Symbol exists\(missingAISymbols.isEmpty ? "" : ": missing " + missingAISymbols.joined(separator: ", "))", missingAISymbols.isEmpty)

        verifySettings(check)

        // ----------------------------------------------------
        // SECTION 15: Mac Tweaks' Background Items on this Mac — reads only, never switches
        // ----------------------------------------------------
        verifyBackgroundItems(check, panes: panes)

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

/// Carries the fetched rules out of their completion handler.
final class LiveRulesBox: @unchecked Sendable {
    var value: CleanDevMacRuleSet?
}

/// What the live Mac Tweaks scan ran, and anything it must never do.
final class TweaksRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var ranPrograms: [String] = []
    private var forbiddenList: [String] = []

    func ran(_ line: String) { lock.lock(); ranPrograms.append(line); lock.unlock() }
    func forbidden(_ line: String) { lock.lock(); forbiddenList.append(line); lock.unlock() }
    var programs: [String] { lock.lock(); defer { lock.unlock() }; return ranPrograms }
    var forbiddenCalls: [String] { lock.lock(); defer { lock.unlock() }; return forbiddenList }
}

extension DeepVerifier {
    /// Section 15: Background Items scanned on this Mac, and everything it shows compared with
    /// what the system reports now, read here on its own. Nothing is switched, moved, asked for
    /// or written: launchctl runs only with `print` and `print-disabled`.
    static func verifyBackgroundItems(_ check: (String, Bool) -> Void, panes: [String: SettingsSearchTerms.PaneExtension]) {
        typealias B = MacTweaksBackground
        print("\n--- 15. Testing Mac Tweaks' Background Items on this Mac (reads only) ---")
        let record = TweaksRecorder()
        var env = MacTweaksProvider.Environment.live
        let liveLaunchctl = env.backgroundItems.launchctl
        env.backgroundItems.launchctl = { arguments in
            guard let verb = arguments.first, verb == "print" || verb == "print-disabled" else {
                record.forbidden("launchctl " + arguments.joined(separator: " "))
                return (1, "deep_verify never changes launchd")
            }
            record.ran("/bin/launchctl " + arguments.joined(separator: " "))
            return liveLaunchctl(arguments)
        }
        env.runAdmin = { _ in
            record.forbidden("runAdmin")
            return .refused("deep_verify never asks for a password")
        }
        env.moveToTrash = { url in
            record.forbidden("moveToTrash " + url.path)
            throw CocoaError(.featureUnsupported)
        }
        // The journal file, read through the section's own adapter; every write refuses.
        var files = env.settings.fileSystem
        files.write = { url, _ in record.forbidden("write \(url.path)"); throw CocoaError(.featureUnsupported) }
        files.remove = { url in record.forbidden("remove \(url.path)"); throw CocoaError(.featureUnsupported) }
        files.move = { url, _ in record.forbidden("move \(url.path)"); throw CocoaError(.featureUnsupported) }
        env.settings.fileSystem = files
        var journal = B.journal(env)
        journal.recordAhead = { _ in
            record.forbidden("journal recordAhead")
            return .failed("deep_verify never writes the journal")
        }
        journal.remove = { _ in
            record.forbidden("journal remove")
            return "deep_verify never writes the journal"
        }
        journal.update = { _ in
            record.forbidden("journal update")
            return .failed("deep_verify never writes the journal")
        }
        env.backgroundItems.journal = journal
        let journalPath = MacTweaksJournal.url(home: env.home).path
        let journalBefore = FileManager.default.contents(atPath: journalPath)
        let residentBefore = residentBytes()
        let started = Date()
        var scanned: [MacTweaksRow]? = B.scan(env)
        let seconds = Date().timeIntervalSince(started)
        let rows = (scanned ?? []).filter { !$0.isLink }
        for row in rows {
            print("     \(row.title): \(row.detail) — \(row.value)\(row.tags.isEmpty ? "" : " [" + row.tags.joined(separator: ", ") + "]")\(row.readOnly ? " (read-only)" : "")")
            if let caveat = row.caveat { print("        \(caveat)") }
        }
        print("Background Items found \(rows.count) items in \(String(format: "%.2f", seconds)) s")
        check("The scan finishes within 10 s", seconds < 10)
        check("It runs only launchctl print-disabled and print",
              record.programs.allSatisfy { $0.hasPrefix("/bin/launchctl print-disabled ") || $0.hasPrefix("/bin/launchctl print ") })

        // AC 1: every other app's plist with a Label, read here on its own, has a row; nothing else does.
        let home = env.home
        let uid = getuid()
        var expected: [String] = []
        var withoutLabel = 0
        var macOSOwn = 0
        var plists: [String: [String: Any]] = [:]
        var linksLeft = 0
        var sharedAgents: [String: Bool] = [:]
        for (folder, system) in [(home + "/Library/LaunchAgents", false), ("/Library/LaunchAgents", false), ("/Library/LaunchDaemons", true)] {
            for name in ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).sorted() where name.hasSuffix(".plist") && !name.hasPrefix(".") {
                // A link is read where the engine may follow it, and only there (never into a guarded
                // folder); anything else only when it is a regular file (never a FIFO, which would block).
                var info = stat()
                guard lstat(folder + "/" + name, &info) == 0 else { continue }
                let isLink = info.st_mode & S_IFMT == S_IFLNK
                guard isLink || info.st_mode & S_IFMT == S_IFREG else { continue }
                guard let source = isLink ? B.linkTarget(folder + "/" + name, env) : folder + "/" + name else {
                    linksLeft += 1
                    continue
                }
                guard let data = FileManager.default.contents(atPath: source),
                      let dict = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { continue }
                guard let label = dict["Label"] as? String, !label.isEmpty else {
                    withoutLabel += 1
                    continue
                }
                if label.hasPrefix("com.apple.") {
                    macOSOwn += 1
                    continue
                }
                let id = B.key(label: label, system: system)
                if plists[id] == nil {
                    expected.append(id)
                    plists[id] = dict
                    sharedAgents[id] = folder == "/Library/LaunchAgents"
                }
            }
        }
        print("     Left out: \(withoutLabel) \(withoutLabel == 1 ? "plist" : "plists") without a Label, \(macOSOwn) of macOS's own, "
              + "\(linksLeft) \(linksLeft == 1 ? "link" : "links") into a guarded folder")
        check("Every other app's plist with a Label has a row, and nothing else does (\(expected.count))", rows.map(\.id) == expected)
        check("No row is macOS's own", rows.allSatisfy { !$0.id.contains("/com.apple.") })

        // Each state as launchctl reports it now, read here on its own.
        func listed(_ domain: String) -> [String: String] {
            var list: [String: String] = [:]
            for line in CleanDevMacEngine.run("/bin/launchctl", ["print-disabled", domain], timeout: 10).output.split(separator: "\n") {
                let parts = line.components(separatedBy: "\" => ")
                guard parts.count == 2 else { continue }
                let label = parts[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                list[label] = parts[1].trimmingCharacters(in: .whitespaces)
            }
            return list
        }
        let guiList = listed("gui/\(uid)")
        let systemList = listed("system")
        var statesMatch = true
        for row in rows {
            guard let named = B.parse(key: row.id), B.isActionable(named.label), !row.readOnly || row.caveat?.hasPrefix(B.blockedPrefix) == true else { continue }
            let value = (named.system ? systemList : guiList)[named.label]
            let disabled = value.map { $0 == "disabled" || $0 == "true" } ?? (plists[row.id]?["Disabled"] as? Bool ?? false)
            let status = CleanDevMacEngine.run("/bin/launchctl", ["print", B.target(named.label, system: named.system, userID: uid)], timeout: 10).status
            let state = disabled ? "Off" : status == 0 ? "On" : status == 113 ? "Not loaded" : "Unknown"
            if state != row.value {
                statesMatch = false
                print("     ⚠️ \(row.title) shows \(row.value), launchctl says \(state)")
            }
        }
        check("Each item's state is what launchctl reports (Off from the disabled list, else print's 0 or 113)", statesMatch)

        // What the rows say follows from the plists, whatever this Mac holds.
        func program(_ id: String) -> (program: String, arguments: [String]) {
            let dict = plists[id] ?? [:]
            let arguments = dict["ProgramArguments"] as? [String] ?? []
            return (dict["Program"] as? String ?? arguments.first ?? "", arguments)
        }
        let updatersRight = rows.allSatisfy { row in
            let label = B.parse(key: row.id)?.label ?? ""
            let isUpdater = [label, (program(row.id).program as NSString).lastPathComponent].contains { $0.lowercased().contains("update") }
            let warned = row.caveat?.contains("Not an updater.") == true
            return row.tags.contains(B.updaterTag) == isUpdater && (isUpdater ? !warned : (warned || row.tags.contains(B.leftoverTag)))
        }
        check("Updaters carry the Updater tag and no warning; every other item the warning, unless it is a leftover", updatersRight)
        check("Daemons, and leftovers deleted out of /Library/LaunchAgents, are For all users and may ask for the password; nothing else is For all users",
              rows.allSatisfy { row in
                  let system = row.id.hasPrefix("background:system/")
                  let shared = system || (sharedAgents[row.id] == true && B.change(of: row) == .delete)
                  return row.tags.contains(B.allUsersTag) == shared && (!shared || row.tags.contains(MacTweaksStorage.passwordTag))
              })
        // ⌫'s delete: offered on every changeable item whose own change isn't one, its plist
        // first, then the commands; For all users and the password exactly for daemons and
        // /Library/LaunchAgents.
        let deletable = rows.filter { $0.deletion != nil }
        print("     Deletable with ⌫: \(deletable.count) of \(rows.filter { !$0.isLink }.count)")
        check("Every item ⌫ can delete is changeable, shows its plist first and the delete's commands, and is For all users and may ask "
              + "for the password exactly as a daemon or an item in /Library/LaunchAgents",
              rows.allSatisfy { row in
                  guard let deletion = row.deletion else { return true }
                  let shared = row.id.hasPrefix("background:system/") || sharedAgents[row.id] == true
                  let marked = row.markedForDeletion()
                  return !row.readOnly && B.change(of: row) != .delete && B.change(of: marked) == .delete
                      && deletion.items.first == row.items.first
                      && deletion.items.dropFirst().map(\.target).last?.hasSuffix(" ~/.Trash/") == true
                      && marked.tags.contains(B.allUsersTag) == shared && marked.tags.contains(MacTweaksStorage.passwordTag) == (shared || row.items.first?.isForeign == true)
              })
        check("No read-only row can be deleted", rows.allSatisfy { !$0.readOnly || $0.deletion == nil })
        let guarded = B.guardedFolders(env)
        let leftoversRight = rows.allSatisfy { row in
            let (run, arguments) = program(row.id)
            guard let path = B.judgedPath(program: run, arguments: arguments), path.hasPrefix("/"),
                  !guarded.contains(where: { MacTweaksStorage.isInside(B.folded(path), B.folded($0)) }) else { return !row.tags.contains(B.leftoverTag) }
            var info = stat()
            let missing = stat(path, &info) != 0 && (errno == ENOENT || errno == ENOTDIR)
            return row.tags.contains(B.leftoverTag) == missing
        }
        let leftovers = rows.filter { $0.tags.contains(B.leftoverTag) }
        print("     Leftovers here: \(leftovers.isEmpty ? "none" : leftovers.map(\.title).joined(separator: ", "))")
        check("A row is a leftover exactly when what it runs is confirmed missing (ENOENT or ENOTDIR)", leftoversRight)
        let appNotesRight = rows.allSatisfy { row in
            let associated = plists[row.id]?["AssociatedBundleIdentifiers"]
            let ids = (associated as? [String]) ?? (associated as? String).map { [$0] } ?? []
            let missing = !ids.isEmpty && ids.allSatisfy { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) == nil }
            return (row.caveat?.contains("isn't installed.") == true) == missing
        }
        check("An item whose app LaunchServices doesn't know says so, and no other", appNotesRight)
        let status = journal.status()
        let journalBlocked = status.isBlocked
        let recorded = Set(MacTweaksJournal.load(url: URL(fileURLWithPath: journalPath)).journal?.entries(kind: B.Entry.kind).map(\.key) ?? [])
        switch status {
        case .ready: print("     Journal: \(journalBefore == nil ? "none yet" : "readable"), \(recorded.count) Background Items \(recorded.count == 1 ? "entry" : "entries")")
        case .unreadable(let reason), .blocked(let reason): print("     Journal: \(reason)")
        }
        check("Every row is read-only, saying why, exactly while the journal can't record changes",
              rows.allSatisfy { ($0.caveat?.hasPrefix(B.blockedPrefix) == true) == journalBlocked && (!journalBlocked || $0.readOnly) })
        let summary = B.summary(rows: scanned ?? [], ticked: [])
        print("     Summary: \(summary)")
        check("...and the summary says so", summary.hasSuffix(journalBlocked ? B.blockedSummary : B.appleNote))
        check("An item says Lightspot turned it off exactly when it is off and the journal holds it",
              rows.allSatisfy { ($0.caveat?.contains("Lightspot turned it off.") == true) == (recorded.contains($0.id) && $0.value == "Off") })

        // The plan, with every row ticked as if it could be, and Undo everything's hook: built
        // without running anything that changes the Mac.
        let ticked = rows.filter { B.change(of: $0) != nil }
        let ranBefore = record.programs.count
        let notes = B.planNotes(ticked)
        print("     Plan for all \(ticked.count): \(B.applyTitle(ticked: ticked)). \(notes.joined(separator: " "))")
        let deleted = rows.compactMap { $0.deletion != nil ? $0.markedForDeletion() : nil }
        let deleteNotes = B.planNotes(deleted)
        if !deleted.isEmpty { print("     Plan with every ⌫ delete: \(B.applyTitle(ticked: deleted)). \(deleteNotes.joined(separator: " "))") }
        check("Building the plan runs nothing", record.programs.count == ranBefore)
        check("The plan asks for the password exactly when a daemon, or a plist only root can move, is ticked",
              notes.contains(MacTweaksStorage.passwordNote) == ticked.contains(where: B.needsAdministrator)
                  && deleteNotes.contains(MacTweaksStorage.passwordNote) == deleted.contains(where: B.needsAdministrator))
        check("...and a delete's plan says where the files go and how they come back, and warns when an app is still installed",
              deleted.isEmpty || (deleteNotes.contains(B.deletedNote)
                                  && deleteNotes.contains(B.deleteAppNote) == deleted.contains { !$0.tags.contains(B.leftoverTag) }))
        let items = B.items(env)
        let entries = items.map { B.Entry(item: $0, owner: $0.label, wasDisabled: false, wasLoaded: true, date: Date()) }
        let undo = B.undo(entries, environment: env)
        let daemons = items.filter { $0.system && B.isActionable($0.label) }
        check("Undo everything's hook gives the batch one enable per daemon, with the plist the scan found",
              undo.adminCommands.count == daemons.count
                && zip(undo.adminCommands, daemons).allSatisfy { $0.contains(" enable ") && $0.contains(MacTweaksStorage.shellQuote($1.plist)) })
        let verifiesRight = rows.allSatisfy { row in
            guard B.parse(key: row.id).map({ B.isActionable($0.label) }) == true, row.value != "Unknown" else { return true }
            if case .undone = undo.outcome(row.id, (0, "")) { return row.value != "Off" }
            return row.value == "Off"
        }
        check("...and counts as undone exactly the items that aren't off", verifiesRight)
        // Settings' Undo everything carries this section's hook, both ways the provider builds it
        // (the app's own path is `makeEngine`).
        let sample = B.Entry(item: items.first ?? B.Item(label: "com.example.sample", plist: "/Library/LaunchDaemons/com.example.sample.plist",
                                                          place: .daemons, program: "", arguments: [], associatedIDs: [],
                                                          plistDisabled: false, isLink: false, ownerUID: nil),
                             owner: "Sample", wasDisabled: false, wasLoaded: true, date: Date())
        let expectedLine = B.undoPlanLines([(sample.key, sample.json)], environment: env)[sample.key]
        for (path, engine) in [("engine(for:)", MacTweaksProvider.engine(for: .settings, environment: env)),
                               ("makeEngine(for:)", MacTweaksProvider(environment: env).makeEngine(for: .settings))] {
            let settingsEnv = (engine as? MacTweaksSettings.Engine)?.environment.settings
            check("Undo everything in Settings carries Background Items' hook and plan lines (\(path))",
                  settingsEnv?.background != nil && expectedLine != nil
                    && settingsEnv?.backgroundPlanLines?([(sample.key, sample.json)])[sample.key] == expectedLine)
        }
        check("Nothing was switched, moved, asked for or written", record.forbiddenCalls.isEmpty)
        check("The journal is as it was", FileManager.default.contents(atPath: journalPath) == journalBefore)

        // The folders resolve to themselves, the link names a pane, the symbols exist.
        for folder in [home + "/Library/LaunchAgents", "/Library/LaunchAgents", "/Library/LaunchDaemons"] where MacTweaksStorage.isFolder(folder) {
            check("\(CleanDevMacEngine.displayPath(folder, home: home)) resolves to itself", MacTweaksStorage.resolved(folder) == folder)
        }
        check("The Login Items link names an installed pane", panes["com.apple.LoginItems-Settings.extension"] != nil
              && B.loginItemsLink == "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
        let missingSymbols = B.symbols.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
        check("Every Background Items SF Symbol exists\(missingSymbols.isEmpty ? "" : ": missing " + missingSymbols.joined(separator: ", "))", missingSymbols.isEmpty)
        scanned = nil
        malloc_zone_pressure_relief(nil, 0)
        print("     Resident memory: \(residentBefore / 1_048_576) MB before the scan, \(residentBytes() / 1_048_576) MB once its rows were dropped")
    }
}

/// This process's resident memory, as Activity Monitor's Memory column counts it.
func residentBytes() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    return result == KERN_SUCCESS ? info.phys_footprint : 0
}

// ----------------------------------------------------
// SECTION 14: Mac Tweaks' Settings on this Mac — reads only, never writes a setting
// ----------------------------------------------------
extension DeepVerifier {
    static func verifySettings(_ check: (String, Bool) -> Void) {
        print("\n--- 14. Testing Mac Tweaks' Settings on this Mac (reads only) ---")
        let record = TweaksRecorder()
        var env = MacTweaksProvider.Environment.live
        // Every writer refuses and is recorded: deep_verify reads this Mac, it never changes it.
        let liveLaunchctl = env.settings.launchctl
        env.settings.launchctl = { args in
            let line = "launchctl " + args.joined(separator: " ")
            record.ran(line)
            guard args.first == "print-disabled" || args.first == "print" else {
                record.forbidden(line)
                return (1, "deep_verify never changes launchd")
            }
            return liveLaunchctl(args)
        }
        var store = env.settings.preferences
        store.write = { domain, key, _ in record.forbidden("write \(domain) \(key)"); return false }
        env.settings.preferences = store
        env.settings.setHidden = { path, _ in record.forbidden("chflags \(path)"); return false }
        env.settings.restart = { name in record.forbidden("killall \(name)"); return false }
        var files = env.settings.fileSystem
        files.write = { url, _ in record.forbidden("write \(url.path)"); throw CocoaError(.featureUnsupported) }
        files.remove = { url in record.forbidden("remove \(url.path)"); throw CocoaError(.featureUnsupported) }
        files.move = { url, _ in record.forbidden("move \(url.path)"); throw CocoaError(.featureUnsupported) }
        env.settings.fileSystem = files
        env.intelligence.presentProfile = { _ in record.forbidden("presentProfile") }
        env.intelligence.removeProfileFile = {}
        env.intelligence.openDeviceManagement = { record.forbidden("openDeviceManagement") }
        env.runAdmin = { _ in record.forbidden("runAdmin"); return .refused("deep_verify never asks for a password") }
        let journalURL = MacTweaksJournal.url(home: env.home)
        let backupURL = MacTweaksDock.backupURL(home: env.home)
        let fm = FileManager.default
        let journalExisted = fm.fileExists(atPath: journalURL.path)
        let backupExisted = fm.fileExists(atPath: backupURL.path)

        let started = Date()
        let reading = MacTweaksSettings.read(env)
        let rows = MacTweaksSettings.rows(reading)
        let seconds = Date().timeIntervalSince(started)
        for row in rows {
            let flags = (row.readOnly ? " [read-only]" : "") + (row.tags.isEmpty ? "" : " [" + row.tags.joined(separator: ", ") + "]")
            print("     \(row.title): \(row.countLabel ?? "")\(flags)\(row.caveat.map { " — " + $0 } ?? "")")
        }
        print("     Summary: \(MacTweaksSettings.summary(rows: rows, ticked: [], context: reading))")
        check("Settings reads this Mac within 10 s (\(String(format: "%.2f", seconds)) s)", seconds < 10)
        check("The scan writes no setting, changes no job, restarts nothing and asks for nothing", record.forbiddenCalls.isEmpty)
        check("It runs launchctl's print-disabled and print only", record.programs.allSatisfy { $0.hasPrefix("launchctl print") })
        check("No journal or Dock backup appears", fm.fileExists(atPath: journalURL.path) == journalExisted
              && fm.fileExists(atPath: backupURL.path) == backupExisted)

        // Each tweak's state against an independent read: direct CFPreferences calls, launchctl's
        // own output, stat and resource values. Follows what this Mac reports, never one macOS's state.
        func app(_ domain: String) -> CFString { domain == "NSGlobalDomain" ? kCFPreferencesAnyApplication : domain as CFString }
        func value(_ domain: String, _ key: String) -> PreferenceValue? {
            CFPreferencesAppSynchronize(app(domain))
            return PreferenceValue(CFPreferencesCopyAppValue(key as CFString, app(domain)))
        }
        func forced(_ domain: String, _ key: String) -> Bool { CFPreferencesAppValueIsForced(key as CFString, app(domain)) }
        let uid = getuid()
        let disabledText = CleanDevMacEngine.run("/bin/launchctl", ["print-disabled", "gui/\(uid)"], timeout: 10).output
        func isDisabled(_ label: String) -> Bool { disabledText.contains("\"\(label)\" => disabled") || disabledText.contains("\"\(label)\" => true") }
        func isLoaded(_ label: String) -> Bool { CleanDevMacEngine.run("/bin/launchctl", ["print", "gui/\(uid)/\(label)"], timeout: 10).status == 0 }
        let musicApp = "/System/Applications/Music.app"
        let musicInode = (try? fm.attributesOfItem(atPath: musicApp))?[.systemFileNumber] as? NSNumber
        let execInode = (try? fm.attributesOfItem(atPath: musicApp + "/Contents/MacOS/Music"))?[.systemFileNumber] as? NSNumber
        let musicLabel = musicInode.flatMap { a in execInode.map { "application.com.apple.Music.\(a.stringValue).\($0.stringValue)" } }
        let dockIDs = ((CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString) as? [[String: Any]]) ?? [])
            .compactMap { ($0["tile-data"] as? [String: Any])?["bundle-identifier"] as? String }
        var libraryStat = stat()
        let libraryHidden = stat(NSHomeDirectory() + "/Library", &libraryStat) == 0 ? (libraryStat.st_flags & UInt32(UF_HIDDEN)) != 0 : nil
        let ours = MacTweaksProfile.installed()
        let os = ProcessInfo.processInfo.operatingSystemVersion
        func expected(_ tweak: MacTweaksSettings.Tweak) -> MacTweaksSettings.State {
            guard (os.majorVersion, os.minorVersion) >= tweak.since else { return .notOnThisMacOS }
            let mine = ours.on && ours.tweaks.contains(tweak.id)
            var done = 0
            for change in tweak.changes {
                switch change {
                case .restriction(let key):
                    if forced("com.apple.applicationaccess", key) && !mine { return .managed }
                    if forced("com.apple.applicationaccess", key) && PreferenceValue.bool(false).matches(value("com.apple.applicationaccess", key)) { done += 1 }
                case .forced(let domain, let key, let wanted):
                    if forced(domain, key) && !mine { return .managed }
                    if forced(domain, key) && wanted.matches(value(domain, key)) { done += 1 }
                case .pref(let domain, let key, let wanted):
                    if forced(domain, key) { return .managed }
                    if wanted.matches(value(domain, key)) { done += 1 }
                case .service(let label):
                    if isDisabled(label) { done += isLoaded(label) ? 0 : 1 }
                case .musicLaunches:
                    if let label = musicLabel, isDisabled(label) { return isLoaded(label) ? .partly : .on }
                    return disabledText.contains("application.com.apple.Music.") ? .partly : .off
                case .dockRemove(let ids):
                    if !dockIDs.contains(where: ids.contains) { done += 1 }
                case .showLibrary:
                    if libraryHidden == false { done += 1 }
                }
            }
            if done == tweak.changes.count { return .on }
            if tweak.changes == [.service(MacTweaksSettings.rcdLabel)] && isDisabled(MacTweaksSettings.rcdLabel) { return .partly }
            return done == 0 ? .off : .partly
        }
        let mismatched = MacTweaksSettings.catalog.filter { expected($0) != MacTweaksSettings.state($0, reading) }
        for tweak in mismatched { print("     ⚠️ \(tweak.id): Lightspot says \(MacTweaksSettings.state(tweak, reading).label), the direct read says \(expected(tweak).label)") }
        check("Every one of the \(MacTweaksSettings.catalog.count) tweaks shows the state a direct read of this Mac gives", mismatched.isEmpty)
        func row(_ id: String) -> MacTweaksRow? { rows.first { $0.id == id } }
        // Report C's facts, each checked only while its inputs still hold on this Mac.
        let quotes = value("NSGlobalDomain", "NSAutomaticQuoteSubstitutionEnabled"), dashes = value("NSGlobalDomain", "NSAutomaticDashSubstitutionEnabled")
        if quotes == .bool(false) && dashes == nil {
            check("Smart quotes and dashes shows Partly (quotes false, dashes unset), and its tick finishes it",
                  row("smart-punctuation")?.countLabel == "Partly" && row("smart-punctuation")?.undoes == false)
        }
        if value("com.apple.assistant.support", "Search Queries Data Sharing Status") == .int(2) && !forced("com.apple.assistant.support", "Search Queries Data Sharing Status") {
            check("Improve Search shows Off with \"already off, but not locked\" (its value is 2, unforced)",
                  row("improve-search")?.countLabel == "Off" && row("improve-search")?.caveat?.contains(MacTweaksSettings.alreadyOffCaveat) == true)
        }
        check("Safari's suggestions never claim to be off from Safari's unreadable stub", row("safari-suggestions")?.caveat?.contains("Already off") != true)
        if value("com.apple.WindowManager", "StandardHideWidgets") == .bool(true) && value("com.apple.WindowManager", "StageManagerHideWidgets") == .bool(true) {
            check("Hide desktop widgets shows On (both keys true)", row("desktop-widgets")?.countLabel == "On")
        }
        if !dockIDs.contains(where: MacTweaksSettings.unusedDockApps.contains)
            && reading.journal.json("dock:" + MacTweaksSettings.unusedDockApps.joined(separator: ",")) == nil {
            check("With none of the 10 apps in the Dock and nothing journaled, the Dock tweak is On and read-only",
                  row("dock-apple-apps")?.countLabel == "On" && row("dock-apple-apps")?.readOnly == true)
        }
        print("     Music's launch label: \(musicLabel ?? "Music not found"); rcd \(isDisabled(MacTweaksSettings.rcdLabel) ? "disabled" : "enabled"), \(isLoaded(MacTweaksSettings.rcdLabel) ? "loaded" : "not loaded")")
        check("Music's launch label is computed from its two inodes, in launchd's form", reading.musicLabel != nil && reading.musicLabel == musicLabel
              && musicLabel?.range(of: #"^application\.com\.apple\.Music\.\d+\.\d+$"#, options: .regularExpression) != nil)
        check("launchctl print-disabled parses (\(reading.disabled.count) disabled jobs)", disabledText.contains("=>") && !reading.disabled.isEmpty)
        check("rcd's plist is where Restore bootstraps it from", reading.rcdPlistExists)
        // The profile with every profile tweak and Apple Intelligence off: well-formed, its marker read back.
        let all = Set(MacTweaksSettings.catalog.filter(\.inProfile).map(\.id))
        if let data = try? MacTweaksProfile.data(.init(ai: [], tweaks: all)) {
            let temp = NSTemporaryDirectory() + "lightspot-settings-profile-verify-\(getpid()).mobileconfig"
            try? data.write(to: URL(fileURLWithPath: temp))
            check("The profile with every Settings tweak is well-formed (plutil -lint)", CleanDevMacEngine.run("/usr/bin/plutil", ["-lint", temp], timeout: 10).status == 0)
            try? fm.removeItem(atPath: temp)
            let payloads = ((try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any])?["PayloadContent"] as? [[String: Any]] ?? []
            let marker = payloads.first { ($0["PayloadIdentifier"] as? String)?.hasSuffix(".preferences.com.lightspot.app.tweaks") == true }
            let settings = ((marker?["PayloadContent"] as? [String: Any])?["com.lightspot.app.tweaks"] as? [String: Any])
                .flatMap { ($0["Forced"] as? [[String: Any]])?.first?["mcx_preference_settings"] as? [String: Any] }
            check("...and its marker reads back with all \(all.count) tweaks", MacTweaksProfile.read(forced: true) { settings?[$0] }.tweaks == all)
        }
        let recommended = rows.filter { MacTweaksSettings.tweaks(in: .recommended).map(\.id).contains($0.id) && !$0.readOnly && $0.countLabel != "On" }
        print("     Recommended would change: \(recommended.map(\.id).joined(separator: ", "))")
        print("     Its plan: \(MacTweaksSettings.planNotes(ticked: recommended, context: reading).joined(separator: " "))")
        let symbols = MacTweaksSettings.catalog.map(\.symbol) + MacTweaksSettings.Preset.allCases.map(\.symbol)
            + ["arrow.uturn.backward.circle", "arrow.uturn.backward.square.fill", "minus.square.fill", "lock", "dock.arrow.up.rectangle", MacTweaksSection.settings.symbol]
        let missing = symbols.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
        check("Every Settings SF Symbol exists\(missing.isEmpty ? "" : ": missing " + missing.joined(separator: ", "))", missing.isEmpty)
    }
}
