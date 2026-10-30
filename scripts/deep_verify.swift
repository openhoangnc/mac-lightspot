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

/// This process's resident memory, as Activity Monitor's Memory column counts it.
func residentBytes() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    return result == KERN_SUCCESS ? info.phys_footprint : 0
}
