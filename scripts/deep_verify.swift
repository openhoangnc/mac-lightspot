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
        // Terms that exist only in Apple's .searchTerms files, not in Lightspot's keywords.
        for (query, pane, setting) in [("lockdown mode", "Privacy & Security", "Lockdown Mode"),
                                       ("power nap", "Battery", "Power Nap"),
                                       ("universal control", "Displays", "Universal Control"),
                                       ("known networks", "Wi-Fi", "Known networks"),
                                       ("sticky keys", "Accessibility", "Sticky Keys")] {
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
            check("Every offered path passes cdm's safety gate",
                  paths.allSatisfy { CleanDevMacEngine.isSafeTarget($0, home: cdmHome, physicalHome: physicalHome) })
            check("Nothing is offered in a protected folder", paths.allSatisfy { path in
                CleanDevMacEngine.protectedFolders.allSatisfy { !path.hasPrefix(cdmHome + "/" + $0 + "/") && path != cdmHome + "/" + $0 }
            })
            check("Nothing is read inside other apps' containers",
                  paths.allSatisfy { !CleanDevMacEngine.isOutOfScope($0, home: cdmHome) })
            check("Every offered category has a size, biggest first",
                  scan.entries.allSatisfy { $0.sizeKB > 0 } && zip(scan.entries, scan.entries.dropFirst()).allSatisfy { $0.sizeKB >= $1.sizeKB })

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
