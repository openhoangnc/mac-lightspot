# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Lightspot is a macOS Spotlight replacement written in pure Swift with SwiftPM — **no Xcode project, no XCTest, no third-party dependencies**. It ships as a background agent (`LSUIElement = 1`) with a menu bar item and a global Carbon hotkey.

## Commands

```bash
./build.sh      # or: make build    — swift build -c release, then package/strip/ad-hoc-sign build/Lightspot.app
./run.sh        # or: make run      — killall Lightspot, rebuild, open build/Lightspot.app
./install.sh    # or: make install  — build, kill running instance, copy to /Applications (falls back to ~/Applications)
                #                     ./install.sh --user forces ~/Applications, --system forces /Applications
./uninstall.sh  # or: make uninstall
make clean      # rm -rf build .build
./scripts/generate_icon.sh  # or: make icon — regenerates Resources/AppIcon.icns via Core Graphics + iconutil
```

`swift build` alone produces the bare binary; it will not run correctly as an app (no bundle, no `Info.plist`, so no `LSUIElement`). Always go through `build.sh` or `install.sh`.

Write `@ViewState`, never `@State` (`UI/ViewState.swift`). From the macOS 27 SDK on,
`@State` resolves to a SwiftUI macro whose implementation ships with Xcode only, so a
Command Line Tools build fails on it; `ViewState` is the same property wrapper under a
name no macro claims. Xcode, and so CI, compiles `@State` fine, which is why `build.sh`
refuses it up front.

The app is single-instance via `System/SingleInstanceGuard.swift`, checked in `main()` after the uninstall helper flags: an `flock` on `~/Library/Application Support/Lightspot/<bundle id>.lock`. Launching the same build again asks the running copy to show its panel and exits; launching a different build (reinstalled, rebuilt, or at another path such as `build/`) asks the running copy to quit, then takes over. `run.sh` and `install.sh` still kill first, but that kill is refused from a sandboxed shell (EPERM), which is how duplicate instances used to pile up. The lock is per user, and so are the scripts: every `pgrep`/`pkill` takes `-u "$(id -u)"`, because another account on the same Mac runs its own Lightspot, which this user may not signal; unscoped, `install.sh` waited on those copies, tried to force-kill them and reported a failure. An in-app update is the exception to "asks the running copy to quit": the old copy starts the new build with `--replacing <old pid>` and quits once it has finished launching, so that launch waits for the old PID to release the lock (`claimReplacing`) and shows nothing until then (see invariant 10).

### Tests

There is no XCTest target. Two standalone `@main` Swift files under `scripts/` are compiled ad hoc against the `Core` sources plus the few `System/` files each one needs (`test_engine` needs `AutoStartManager`, `SpotlightManager` and `FirstRunManager` too):

```bash
swiftc -o /tmp/test_engine scripts/test_engine.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift Sources/Lightspot/System/AutoStartManager.swift Sources/Lightspot/System/SpotlightManager.swift Sources/Lightspot/System/FirstRunManager.swift Sources/Lightspot/System/UpdateManager.swift Sources/Lightspot/System/SingleInstanceGuard.swift Sources/Lightspot/System/LegacyNetworkStores.swift Sources/Lightspot/System/HotkeyManager.swift Sources/Lightspot/System/SystemShortcutConflicts.swift && /tmp/test_engine
swiftc -o /tmp/deep_verify scripts/deep_verify.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift && /tmp/deep_verify
```

- `test_engine.swift`: 42 test blocks (each prints a `Testing …` header; `WebSearchProvider` has two) verifying math, relaxed conversions, fuzzy matcher, shell history parsing and ranking, pinned commands, custom commands, multi-IDE project discovery, process killer, web search prefixes, dev tools, default browser URL parsing, clipboard manager, snippets, system HUD, privileged execution, first-run onboarding, search-history privacy, Spotlight symbolic-hotkey entry handling, system shortcuts that collide with the Lightspot hotkey, the updater (version maths, release parsing, download allowlist, bundle validation, swap script; the hand-over run for real against fake bundles: swap while running, rollback on request, a failed copy, and a replacing launch that waits instead of asking the old copy to quit), the launch-time removal of the HTTP cache and cookies that versions up to 1.2.0 left behind, System Settings' own search terms (read from a fixture extension folder: sections, languages, tie-breaks), Clean Dev Mac (cdm's rule format, its safety gate against cdm's own test cases, `du`-exact sizing (a row's paths checked against one `du` over all of them), the kinds that work out their offer (idle AVDs' images, older versions, old Claude Code sessions), every delete method, the clean log, cdm's restart estimate and Claude Code note against cdm's own test cases, rule sources and the scan → clean state machine, all in a fake home; the repo scan against cdm's own git fixtures: the ignored proof, grouping, `.env*`, plus Lightspot's guards), the tool installers (their commands, the install state read off the keystroke path, the rows) and the macOS tweaks (every script parses; each toggle runs for real against a scratch `defaults` domain, never the user's).
- `deep_verify.swift`: 11 sections of live system checks (140 on a fully equipped machine; the shell-history and VS Code checks are skipped when there is no zsh history or VS Code, the live cdm rules check when GitHub is unreachable, the repo scan checks without git) verifying that every settings deep link names an installed pane, the real System Settings search terms, AppleScript and shell quick-action syntax, terminal commands, applications scan, system invariants, and a Clean Dev Mac scan of the real home folder, caches and repos, each category with several paths against one `du` over them, plus cdm's two notes measured on this Mac (measures only; it never deletes).

Both runners read `Resources/cdm-rules`, so run them from the repository root.

These scripts are the primary test coverage — when you modify engines, keep tests updated.

The runners are bare executables, so `SMAppService.mainApp` inside them is the runner
itself: before `AutoStartManager.canRegisterLoginItem`, the first-run test put
`test_engine` under Login Items on every run. Anything else that registers with the
system on the app's behalf needs the same `.app` check.

## Project Structure

```
mac-lightspot/
├── Package.swift                 # SPM manifest (Swift 6, macOS 13+)
├── Makefile                      # make build / run / install / uninstall / clean
├── build.sh                      # Release build & .app packager script
├── run.sh                        # Build & launch helper
├── install.sh                    # Install to /Applications or ~/Applications (local or remote)
├── uninstall.sh                  # Clean removal script
├── README.md                     # Documentation & rationale (with 4 translations)
├── CLAUDE.md                     # Architecture, invariants & developer guide
├── screenshot.png                # Visual preview for documentation
├── .github/
│   └── workflows/
│       └── release.yml           # GitHub Actions CI for multi-arch releases
├── Resources/
│   ├── Info.plist                # LSUIElement=1, permissions, bundle metadata
│   ├── AppIcon.icns              # Multi-size macOS application icon
│   └── cdm-rules/                # Copy of cdm's rules/ folder, the cleaner's offline fallback
├── scripts/
│   ├── generate_icon.sh          # Programmatic icon generator (Core Graphics + iconutil)
│   ├── test_engine.swift         # Automated test runner (42 test blocks)
│   └── deep_verify.swift         # Live-system verification (11 sections, 140 checks)
└── Sources/
    └── Lightspot/
        ├── AppMain.swift         # @main entry point, CLI flags & NSApplicationDelegate
        ├── Core/
        │   ├── AppIconCache.swift       # In-memory async app icon caching
        │   ├── AppScanner.swift         # Fast async app scanner & memory icon cache
        │   ├── BrowserIntegrationProvider.swift # Default browser bookmarks, tabs & history
        │   ├── CalculatorEngine.swift   # Math parser & conversion dispatcher
        │   ├── CleanDevMacEngine.swift  # cdm ported: glob, du-exact sizing, safety gate, deletion, clean log
        │   ├── CleanDevMacProjects.swift # cdm's repo scan ported: find pass, git-ignored proof, grouping
        │   ├── CleanDevMacProvider.swift # "Clean Dev Mac" row, scan/clean state machine, cdm in Terminal
        │   ├── CleanDevMacRules.swift   # cdm's rule files: parsing, local / GitHub / bundled sources
        │   ├── ClipboardHistoryManager.swift    # In-memory ephemeral clipboard ring buffer
        │   ├── ConversionEngine.swift   # Unit, currency, base, & temperature engine
        │   ├── CustomCommandsStore.swift# Custom user commands model & persistence
        │   ├── CustomIconCache.swift    # Base64 custom command icon decoding/cache
        │   ├── DevToolsProvider.swift   # UUID, Base64, Hash, JWT, JSON, Color Swatch
        │   ├── MacTweaks.swift          # `defaults` tweaks (Dock, Finder, keyboard…) as quick actions
        │   ├── Models.swift             # SearchResult, ResultCategory, SearchAction, FuzzyMatcher
        │   ├── NetworkInfoProvider.swift# Local IPv4 & public internet IP address
        │   ├── ProcessKillerProvider.swift # Name, PID, and port process terminator
        │   ├── QuickActionsProvider.swift# Focused system actions & Terminal in Finder
        │   ├── RecentAppsManager.swift  # Recently launched applications tracking
        │   ├── RecentProjectsProvider.swift # Multi-IDE project scanner (VS Code, Cursor, Zed, JetBrains, Sublime)
        │   ├── SearchEngine.swift       # Synchronous search aggregator & ranking
        │   ├── SearchHistoryManager.swift # Search query & selection history
        │   ├── SettingsBackup.swift     # Settings export & import backup
        │   ├── SettingsProvider.swift   # 46 macOS System Settings deep links
        │   ├── SettingsSearchTerms.swift # System Settings' own .searchTerms vocabulary, indexed at launch
        │   ├── ShellHistoryProvider.swift # zsh history parser & pinned commands
        │   ├── SnippetsStore.swift      # Text expansion snippets with variable interpolation
        │   ├── SystemInfoProvider.swift # Zero-subprocess Mach/IOKit hardware dashboard
        │   ├── ToolInstallersProvider.swift # Install rows for setup-zsh, MacStats & install-dev-tool
        │   ├── VSCodeProjectsProvider.swift # VS Code state.vscdb recent project extractor
        │   └── WebSearchProvider.swift  # Multi-engine search & prefix shortcuts
        ├── System/
        │   ├── AutoStartManager.swift   # SMAppService login item management & caching
        │   ├── FirstRunManager.swift    # Onboarding: auto launch-at-login & Spotlight disable prompt
        │   ├── HotkeyManager.swift      # Carbon global hotkey
        │   ├── LegacyNetworkStores.swift # Removes the HTTP cache & cookies URLSession.shared left (≤ 1.2.0)
        │   ├── MenuBarController.swift  # Menu bar status item & preferences
        │   ├── SettingsBackupController.swift # Settings import/export controller
        │   ├── SingleInstanceGuard.swift # flock instance lock; hand-off / take-over between launches
        │   ├── SpotlightManager.swift   # macOS Spotlight disable/restore automations
        │   ├── SystemShortcutConflicts.swift # Symbolic hotkeys sitting on the Lightspot combination
        │   ├── TerminalLauncher.swift   # Launcher for 7 terminal emulators & Finder detection
        │   └── UpdateManager.swift      # GitHub release check, verified download & self-replacement
        └── UI/
            ├── AppGridView.swift        # Compact 5-column app launcher grid
            ├── CleanDevMacModel.swift   # Cleaner overlay state: ticks, cursor, plan confirmation
            ├── CleanDevMacView.swift    # Clean Dev Mac (cdm) overlay: list, plan, receipt
            ├── CustomCommandsView.swift # Custom command manager overlay
            ├── LazyAppIconView.swift    # Asynchronous non-blocking app icon loader
            ├── PinnedCommandsView.swift # Pinned command manager overlay
            ├── PreviewPaneView.swift    # Rich details card & live previews
            ├── ResultRowView.swift      # Individual search result row
            ├── ResultsListView.swift    # Scrollable search results list
            ├── SearchFieldView.swift    # NSTextField bridge & custom field editor
            ├── SearchHistoryView.swift  # Search history manager overlay
            ├── SearchViewModel.swift    # Reactive view model & key event router
            ├── SpotlightComponents.swift# Search result rows, buttons, & category headers
            ├── SpotlightPanel.swift     # Floating borderless NSPanel with vibrancy
            ├── SpotlightView.swift      # Root SwiftUI view
            ├── ViewState.swift          # @ViewState: SwiftUI State without the macOS 27 SDK macro
            └── VisualEffectBlur.swift   # NSVisualEffectView glass vibrancy wrapper
```

## Architecture

`AppMain.swift` is the single wiring point. `AppDelegate.setup()` constructs `SearchViewModel`, `SpotlightPanel`, `HotkeyManager`, and `MenuBarController`, connecting them via closures — there is no DI container or notification bus.

Three source layers under `Sources/Lightspot/`:

- **`Core/`** — pure search logic and stores, `AppKit`/`Foundation`-only, no SwiftUI. Every provider is a `shared` singleton or static engine.
- **`System/`** — macOS integration: Carbon hotkey, menu bar, launch-at-login, terminal launchers, and system Spotlight manager.
- **`UI/`** — SwiftUI views plus AppKit bridges (`SpotlightPanel`, `SearchFieldView`, `VisualEffectBlur`).

### Search Pipeline

`SearchViewModel.performSearch` → `SearchEngine.searchImmediate(SearchQuery)` → synchronous fan-out to providers → merge.

`SearchEngine` is **fully synchronous and in-memory**, with no debounce. A complete
fan-out across every provider costs a few milliseconds on the main thread — measured at
**~2.8 ms** with 7 days of browser history (1,499 entries) plus 337 bookmarks and 1,200
shell-history commands resident, and well under 1 ms without the browser corpus. The
browser provider dominates whatever the total is; measure with a benchmark rather than
assuming, and see invariant 0 before adding work to a `search()`.

Display order is `ResultCategory.displayOrder` — an explicit list, deliberately *not*
`allCases` (which follows declaration order, so moving a case would silently reshuffle
the panel). A test asserts it stays complete and duplicate-free. Raw values are separate
and must stay stable: they are persisted in search history.

1. `topHit` (promoted highest non-exempt match)
2. `calculator` (math calculations and relaxed unit/currency conversions)
3. `devTools` (UUID, Base64, Hash, JWT, JSON, Epoch, Color Swatch)
4. `applications` (Installed macOS apps)
5. `recentProjects` (VS Code, Cursor, Zed, JetBrains, Sublime Text)
6. `snippets` (Text expansion templates)
7. `clipboard` (In-memory clipboard history via `clip`)
8. `browser` (Default browser bookmarks, history and open tabs)
9. `systemSettings` (macOS System Settings deep links)
10. `quickActions` — also carries the Hardware HUD (`sys`) and the process/port killer (`kill`)
11. `customCommands` (User-defined shell/AppleScript commands)
12. `shellHistory` (zsh command history)
13. `webSearch` (Multi-engine search and prefixes `gh`, `yt`, `so`, etc.)

Calculator and dev tools lead because they only produce a row when the query actually
parses as one, so when they fire they are almost certainly the intent. Web search trails
because it is the fallback that is always present.

Scoring tiers: exact 100, prefix 95, word-boundary prefix 85, initials 80, substring 65, subsequence 40.

The substring tier goes through `containsSubstring` (Models.swift), not `String.contains`:
the latter is a Foundation extension that forwards to `range(of:)` and collates, costing
~3.3 µs against a 90-character haystack versus ~0.11 µs byte-wise. It runs once per
candidate per keystroke across every provider, so the difference is the search.

System Settings rows also match what System Settings' own search matches. Each pane's
extension ships a `.searchTerms` plist of entries, a `title` ("Night Shift options") plus
comma-separated `index` words ("warm, sunset"); `SettingsSearchTerms` reads them for the
user's languages plus English at launch (~13k keys, 0.2 s, background) into one sorted
array the keystroke path binary-searches (~2 µs). Only the exact, prefix and word-boundary
tiers apply. Titles score ×0.9; index words score ×0.55, which caps them at 55, under the
60 a Top Hit needs, because many are generic ("show", "top", "word"). A row matched
this way names the setting in its subtitle.

### Clean Dev Mac (cdm)

CleanDevMac (`cdm`, https://github.com/cleandevmac/cdm) is a bash TUI that reclaims disk from
dev caches. Lightspot runs its cache categories and its per-repo project scan natively:
the "Clean Dev Mac" row (`cdm`, `clean dev mac`, `derived data`, …) opens an overlay that
measures, ticks cdm's safe defaults, offers to scan code repos, shows an itemized plan,
cleans and prints a receipt.

- **The rules are cdm's.** `CleanDevMacRules` reads cdm's own `rules/` format (`index.json`
  plus pattern files), from cdm's local override `~/.cleandevmac/rules` if it exists, else
  cdm's live rules on GitHub (`raw.githubusercontent.com/cleandevmac/cdm/main/rules/`, the
  same files piped `cdm` reads), else `Resources/cdm-rules`, which build.sh copies into the
  bundle. A rule added to cdm reaches Lightspot without a release; the bundled copy only
  covers being offline. Refresh it by copying cdm's `rules/*.json` over `Resources/cdm-rules/`
  (deep_verify names the categories where they differ).
- **Native vs. terminal.** `paths`, `android-images`, `android-idle-images`,
  `older-versions` and `claude-transcripts` categories with the methods `rm`, `rmforce`,
  `trash` and `emptytrash` run here, and so do `project` and `gitignore` ones through the
  repo scan below. `container` categories (Docker / Podman), `rust-toolchains` (its clean
  is `rustup toolchain uninstall`, a command, like a container prune), cdm's
  orphaned-app-data scan, and rules that only read other apps' sandbox containers are named
  in the overlay and left to cdm itself: ⌘↵ runs `curl -fsSL …/releases/latest/download/cdm | bash`
  in the preferred terminal (`CleanDevMacProvider.openInTerminal`). Without a real git
  binary (`CleanDevMacProjects.gitExecutable`; never `/usr/bin/git`, which opens the
  Command Line Tools installer when they are missing) the repo scan is cdm's too.
- **The kinds that work out their offer** read their globs from `images` or `candidates`,
  never `paths` (`CleanDevMacRules.patternField`), so an interpreter that does not know a
  kind offers nothing; the idle ones also need `idleDays`, or the rule is dropped.
  `android-idle-images` offers each image only AVDs idle that long boot, one row per image
  (IDs from `itemIDBase`), naming the AVDs and the sdkmanager package; an AVD's age is its
  folder's newest file but `config.ini`, which Android Studio rewrites without booting
  anything. `older-versions` keeps the newest of each glob's family by cdm's version order
  (`versionKey`: numeric fields, a release above its own pre-release). `claude-transcripts`
  offers `<uuid>.jsonl` sessions untouched that long, with their `<uuid>/` folders, never one
  `~/.claude/sessions/*.json` names as running, and is always `trash` and unticked, whatever
  the rule says: a transcript is the one record of a conversation. "That long" is counted in
  whole days, as macOS's `find -mtime +30` in cdm counts it (`isOlder`): 31 days, not 30 and
  23 hours, whatever find's man page says about rounding up. The AVD check is cdm's
  arithmetic in seconds instead.
- **The repo scan is cdm's `scan_projects`, ported** (`CleanDevMacProjects`), and like cdm
  it is asked, not run: after the cache scan the overlay asks "Also scan your code repos
  for build/dependency junk?" and ⇥ (or the button) starts it. One fts pass over the rules'
  `scan.roots` (home only) finds folders holding a `.git` directory and nominates
  directories named in the `project` categories; each repo's own
  `git ls-files --others --ignored --exclude-standard --directory` then proves a nominee
  ignored (it or an ancestor below its own repo root), and with a `gitignore` category every
  other ignored entry is offered too, except `.env*`. Rows are per repo, or per `scan.groups`
  root; each path keeps its method (regenerable folders `rm`, other ignored files `trash`),
  which is why `Entry.methods` exists. Two guards are Lightspot's own: the walk never enters
  `~/Library` or cdm's protected folders (cdm's gate refuses every path there anyway, and
  reading Documents, Desktop or Downloads would raise a macOS prompt that an ad-hoc signed
  app sees again after every update), and nothing that holds a repo the walk found is
  offered, so an outer repo that ignores a nested clone cannot put it in the Trash. A
  git-ignored folder holding a worktree (its `.git` is a file) or a clone under a pruned name
  such as `.claude` is offered like any other ignored folder, on purpose: 1.3.2 refused those
  too, and 1.3.3 reverted that at the owner's request, because such folders mostly hold junk,
  a checkout is easy to make again, and they go to the Trash. Don't add that guard back
  without asking. On a real home folder it offers what cdm's own `scan_projects` does, except
  a folder holding a nested repo, which cdm offers.
- **The engine is cdm's bash, ported** (`CleanDevMacEngine`): glob(3) expansion with the
  shell's rules, `is_nonempty`, `du -sk`-exact sizing over fts(3), the AVD image skip list
  and idle check, `newest_version`, `register_transcripts`, `is_safe_target`, `delete_path`,
  `human_kb`, the disk line with its restart estimate, the Claude Code note and the log cap.
  Keep the two in step: when cdm changes one of these, port the change and its test.
- **A row is sized as cdm's `paths_kb` sizes it**, with one `du -sk` over all its paths, so
  a file hard-linked into two of them counts in the first. Each path is still walked on its
  own and in parallel (`usage`), its files with more than one link kept apart; once a row's
  last path is in, `allocatedKB(_:)` counts them the way du does across its operands, down
  to du forgetting a file once it has met every link (a folder, then a folder inside it,
  both count it). The per-path sizes are what that du prints for each path, and the receipt
  sums them, so a clean of the whole row frees a shared file once.
- **cdm's two notes come with each scan**, measured on another queue while the caches are.
  What a restart would free (`restartEstimate`): the VM volume's Used column when it shares
  the home volume's container, the two temp folders a boot empties (five seconds each), and
  deleted files still held open, from `lsof -a -nP +L1` (five seconds, through `output(of:)`,
  which never waits on a pipe a child keeps open). Used is df's, `ATTR_VOL_SPACEUSED`, never
  statfs's blocks in use: on APFS those are the whole container's, and put the swap at 177 GB
  where df said 7 (`volume(of:)`). The overlay shows it under the list's summary row, as cdm
  does under its status row, only from 100 MiB and once it is at least the free space,
  naming the holders from 1 GiB. It reads the whole machine, so only
  `Environment.live` measures it; any other environment returns nil, which keeps
  test_engine off the real machine. The Claude Code note (`claudeHistory`): nothing once
  settings.json names `desktopSessionCleanupPeriodDays`, else the `<uuid>.jsonl` sessions
  past `cleanupPeriodDays` (30 by default, read the way cdm's grep reads it) and `projects/`
  measured within ten seconds; shown at the top of the list from 1 GiB of history. Both
  notes also show on "Nothing to reclaim", and neither shows after a clean, until a rescan.
  Advice only: nothing writes settings.json.
- **State.** `CleanDevMacProvider` runs scans and cleans on its own queue and publishes a
  `Snapshot`; `search()` and `CleanDevMacModel` (the overlay) only read it. A scan stands
  for five minutes; a clean ends in `.finished` and the next open rescans. Ticks reset to
  each rule's `default` on every scan, as cdm's menu does; the repo scan only adds rows
  (unticked, IDs from `projectIDBase`) and keeps the ticks. A rescan after a clean scans the
  repos again if they were scanned, as cdm's rescan does once the user said yes.
- **Receipts** go to `~/.cleandevmac/clean.log`, cdm's own log, marked
  `CleanDevMac run (Lightspot)`, so one file records every clean either tool ran.

### Installers & macOS tweaks

- **`ToolInstallersProvider`** offers three rows: **Install setup-zsh**, **Install MacStats** and
  **Install Dev Tools** (setup-zsh's `install-dev-tool` menu). Each runs the tool's own
  documented installer in the preferred terminal (`curl -fsSL …/setup.sh | bash && exec zsh -l`,
  `curl -fsSL …/install.sh | bash`, `~/.zsh/setup-zsh/bin/install-dev-tool`), so its output and
  prompts stay in front of the user. The action is an `internal:install:<id>` sentinel resolved
  by `QuickActionsProvider.execute` when it runs, so search history keeps the row rather than a
  command that depended on what was installed then. `install-dev-tool` reads keys from the
  terminal (never pipe it) and writes into setup-zsh's `env.zsh`, so without setup-zsh the row
  installs it first. Whether each tool is installed is a cached snapshot read on a background
  queue (invariant 0), primed when the panel opens; ⌥↵ opens the tool's GitHub page.
- **`MacTweaks`** adds `defaults` one-liners to the quick actions. All but **Clear Dock Icons**
  (`defaults write com.apple.dock persistent-apps -array && killall Dock`) are toggles built by
  `toggleScript`, which reads the current value, treats an unset key as macOS's default, and
  writes the opposite. Get a new toggle's default right: `ApplePressAndHoldEnabled` is on while
  unset, `AppleShowAllFiles` is off, and a wrong one makes the first press do nothing. Keep
  destructive ones off bare words ("clean", "dock") that other rows answer to.

### Keyboard Shortcuts & Action Modifiers

- **Return (`↵`)**:
  - Apps: Launch application
  - Projects: Open project in its default/associated IDE
  - Settings: Open System Settings pane
  - Process Killer: Graceful terminate (`SIGTERM`)
  - History / Quick Actions: Execute command
  - Calculator / DevTools / Snippets: Copy result to clipboard
  - Web / Browser: Open URL in default browser
- **Command + Return (`⌘↵`)**:
  - Projects: Open project folder in preferred terminal
- **Option + Return (`⌥↵`)**:
  - Projects: Reveal project folder in Finder
  - Process Killer: Force kill process (`SIGKILL`)
  - Apps: Reveal application bundle in Finder
  - Installer rows: Open the tool's GitHub page
- **Management Overlays**:
  - `⌘P`: Pin / unpin selected shell history command
  - `⌘⇧P`: Open pinned commands manager
  - `⌘⇧C`: Open custom commands manager
  - `⌘Y` or `⌘⇧H`: Open search history manager
  - `⌫` (search history manager open): Delete the selected entry
  - `Escape`: Clear search or dismiss panel
- **Clean Dev Mac overlay** (`↵` on its row, or the menu bar's **Clean Dev Mac...**):
  - `Space`: Tick / untick the selected category (`SpotlightFieldEditor.keyDown`
    intercepts it, never mid-composition, so it types nothing)
  - `↵`: Review the itemized plan; `↵` again cleans, `Escape` goes back
  - `⇥`: Scan code repos too, when the overlay offers it (`nextCategory` routes it there)
  - `⌥↵`: Show the selected category's first path in Finder
  - `⌘↵` (also on the row itself): Run cdm in the preferred terminal

### Key Invariants & Safety Rules

0. **Nothing on the keystroke path may block** (violated three times so far, always felt
   as "typing is slow"):
   `SearchEngine.performSearch` fans out to every provider synchronously on the main
   thread on **every keystroke**, and SwiftUI re-evaluates `Menu` content on **every**
   body pass. So a provider's `search()`, and any property a view body reads, must be
   a pure in-memory lookup. Never call from there:
   - `NSAppleScript` / `osascript` (Finder folder ~260 ms, Chrome tabs ~300-465 ms)
   - `Process` + `waitUntilExit` (`launchctl`/`mdutil` ~66 ms, `lsof` ~55 ms)
   - file parsing (337 Chrome bookmarks ~12 ms)
   - `SMAppService.mainApp.status` (~3 ms XPC)

   The established pattern: keep a cached snapshot, return it immediately, and refresh
   on a background queue behind a staleness check *and* an in-flight flag (so a burst
   of keystrokes queues one refresh, not one per character). `NSAppleScript` is not
   thread-safe — give each such refresh its own serial queue. Verified safe: a
   background `NSAppleScript` does not stall the main run loop. Where a blocking call
   is still legitimate (acting on a result, e.g. `TerminalLauncher`
   `activeFinderFolderPath` at launch time), keep it as a separate method from the
   non-blocking one the search path uses (`cachedFinderFolderPath`).

   Also watch for work that is technically in-memory but *scales*: rebuilding a merged,
   de-duplicated corpus (`BrowserIntegrationProvider`), lowercasing an entry's full
   content (`ClipboardHistoryManager`), or building a `DateFormatter` (`SnippetsStore`)
   all ran per keystroke at some point. Pre-compute on write, not on read — `AppInfo`,
   `ShellCommand`, `BrowserItem` and `ClipboardEntry` all cache their lowercased and
   tokenized forms at construction for exactly this reason.

   `ProcessKillerProvider` follows the pattern for both of its subprocesses: the
   `ps -axo` process list and the `lsof -iTCP -sTCP:LISTEN` port → PID map (~55-110 ms)
   are snapshots refreshed on a background queue behind a staleness check and an
   in-flight flag, primed by `warmUp()` when the panel is shown. The port lookup used to
   run `lsof` inline on every `kill <port>` keystroke; it was the last known exception.

1. **Subprocess Pipe Deadlock Prevention**:
   When using `Process` with a `Pipe` on macOS (e.g. `ps`, `lsof`, `sqlite3`, or `osascript`), **always** read data via `pipe.fileHandleForReading.readDataToEndOfFile()` **before** calling `process.waitUntilExit()`. Connecting standardError to `FileHandle.nullDevice` prevents pipe buffer overflow deadlocks.
2. **Swift 6 Concurrency & Page Size**:
   Do not use `vm_kernel_page_size` (it involves mutable global state in Swift 6). Use POSIX `getpagesize()` instead.
3. **No File System Indexing**:
   Lightspot never indexes the filesystem. The only filesystem reads are:
   - Known app directories (`/Applications`, `~/Applications`, `/System/Applications`)
   - The user's zsh history file (last 2 MB only)
   - IDE recent workspace state files (`storage.json`, `recentProjects.xml`, etc.)
   - The user's default browser bookmarks file (default browser only)
   - System Settings' pane bundles, once at launch: each `Info.plist` under
     `/System/Library/ExtensionKit/Extensions`, System Settings.app's `PlugIns` and the
     Safari cryptex's `CoreServices`, and the `.searchTerms` files they name
   - Whether setup-zsh (`~/.zsh/setup-zsh/bin/install-dev-tool`) and MacStats
     (`/Applications/MacStats.app`, or wherever LaunchServices knows it) are installed, for the
     installer rows, on a background queue
   - The cache folders cdm's rules name, and only when the user opens Clean Dev Mac: the
     patterns are expanded and each match measured, on the provider's queue. Nothing is
     kept but the sizes. The idle kinds also read file dates: in each AVD folder, and in the
     Claude Code project folders the rules name, plus the small `~/.claude/sessions/*.json`
     files that name running sessions — never a transcript's contents. For cdm's two notes,
     with the same scan: the swap volume's usage (statfs, getattrlist), the size of the two
     temp folders a boot empties (`DARWIN_USER_TEMP_DIR`, `/private/tmp`) and of Claude Code's
     `projects/`, `lsof -a +L1` on the home volume (kept: the total and the three biggest
     holders' names), and two keys of Claude Code's `settings.json`, never written.
     `~/Library/Containers` and `~/Library/Group Containers` are never
     read (`CleanDevMacEngine.outOfScopeFolders`): inside another app's container macOS asks
     the user whether Lightspot may "access data from other apps", and with an ad-hoc
     signature it would ask again after every update.
   - For Clean Dev Mac's repo scan, and only when the user asks for it (⇥): the folders
     under the home folder to the rules' depth (six), without entering `~/Library`, cdm's
     protected folders, `.git` or the names the rules prune, plus each repo's
     `git ls-files` listing. Nothing is kept but the offered paths and their sizes.
4. **Clipboard History Privacy**:
   `ClipboardHistoryManager` is 100% ephemeral in-memory (max 50 items). It is never written to disk and strictly filters out concealed/password manager types (`org.nspasteboard.ConcealedType`, `1Password`, `Bitwarden`).
5. **AppleScript & Automation Entitlements**:
   `Resources/Info.plist` includes `NSAppleEventsUsageDescription` to permit AppleEvents control for Finder and System Events without TCC blocking.
6. **Persistence**:
   User settings are stored in `UserDefaults` under the `lightspot_` prefix:
   - `lightspot_hotkey_option`
   - `lightspot_preferred_terminal`
   - `lightspot_pinned_commands`
   - `lightspot_custom_commands`
   - `lightspot_snippets`
   - `lightspot_auto_start_enabled`
   - `lightspot_first_run_completed`
   - `lightspot_spotlight_state` (cached Spotlight snapshot, see §0)
   - `lightspot_auto_update_enabled`
   - `lightspot_last_update_check`
   - `lightspot_skipped_version`
7. **Privileged Commands & Headless Touch ID Execution**:
   Privileged operations (`requiresAdmin`, `sudo`, `mDNSResponder`, `purge`) execute via `QuickActionsProvider.executePrivilegedWithTouchID`. This runs `/usr/bin/sudo` attached to a headless pseudo-terminal (`openpty`), triggering native macOS Touch ID (`pam_tid.so`) directly without opening a Terminal window. If Touch ID fails or is unavailable, it automatically falls back to AppleScript Authorization Services (`do shell script ... with administrator privileges`) displaying the native password dialog. A bare leading or chained `sudo` token is stripped before execution (both backends already run as root), but a `sudo` carrying its own options (`sudo -u postgres psql`) is left intact — stripping it there would promote the flags to the command. `QuickActionsProvider.isTouchIdForSudoEnabled` is a cached, non-blocking snapshot of `/etc/pam.d/sudo_local` because `search()` reads it on the keystroke path.
8. **Changing a system symbolic hotkey takes three things, not one**:
   Disabling Spotlight's ⌘Space is `SpotlightManager.setShortcut`, and every part of it
   is load-bearing. Earlier versions wrote the plist directly and the shortcut kept
   working, which is indistinguishable from the app doing nothing:
   - **Write through `cfprefsd`**, i.e. `CFPreferencesSetValue` +
     `CFPreferencesAppSynchronize` against `com.apple.symbolichotkeys`.
     `~/Library/Preferences/com.apple.symbolichotkeys.plist` is the daemon's backing
     store, not the API: it serves reads from its own copy and flushes on its own
     schedule, so a PlistBuddy write reads back stale and can be overwritten wholesale.
     Measured: right after a write through the daemon, the file still showed the old
     value. `defaults read` is **not** a sync — it is a read, and it re-caches the very
     value you were replacing.
   - **Create a missing entry, don't `Set` it.** On a Mac where the user never
     customised the shortcut there is no `64` entry, and PlistBuddy `Set` fails with
     "Does Not Exist". Write `enabled` *and* a `value` dict (`type: standard`,
     `parameters: [32, 49, modifierMask]`); an `enabled`-only entry is inert, so a later
     restore yields a shortcut that does nothing. An entry that already has a `value`
     keeps it — users remap Spotlight (⌥Space is `524288`, ⌘Space `1048576`,
     ⌥⌘Space `1572864`), and clobbering that loses their binding.
   - **Reload the window server** with
     `/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u`
     (~0.4 s, background queues only). Symbolic hotkeys are cached at login; without
     this the preference is correct and the keystroke still opens Spotlight until the
     next logout.

   Both IDs must change together: **64** is "Show Spotlight search", **65** is "Show
   Finder search window" (⌥⌘Space). Touching only 64 leaves half the shortcut
   registered. Every write is read back through the daemon and the verified result is
   what reaches the UI — `ApplyResult` exists so an alert can never again report a
   refused write as success.

9. **Carbon grants a key combination to exactly one owner**:
   `RegisterEventHotKey` fails with `eventHotKeyExistsErr` (-9878) while the system
   Spotlight shortcut still holds ⌘Space, and the only symptom is that the panel never
   opens. `HotkeyManager.isRegistered` records that, `reRegisterIfNeeded()` retries, and
   it is called after anything frees the shortcut (the menu toggle, "Disable
   Everything", first-run onboarding). Freeing the shortcut without re-registering is
   the same bug wearing a different hat: the preference is right and ⌘Space still does
   nothing. `AppDelegate` surfaces an unclaimed hotkey as an alert at launch rather
   than failing silently.

   A **symbolic** hotkey holding the combination is quieter and needs its own handling:
   `RegisterEventHotKey` succeeds, the panel opens, and the system shortcut acts on the
   same keystroke anyway. Measured with ⌃Space, which macOS binds to "Select the
   previous input source" (`AppleSymbolicHotKeys` entry 60, ⌃⌥Space is 61): the panel
   opened *and* the keyboard input source switched. So `isRegistered` cannot see it.
   `SystemShortcutConflicts` reads those entries through `cfprefsd` (invariant 8) and
   the shortcut submenu names the colliding shortcut; it is informational only and
   never rewrites the user's symbolic hotkeys. Read each entry's own `value` rather
   than assuming the factory binding — users remap input-source switching too — and
   treat a missing entry as the factory default, enabled.

10. **The updater swaps the bundle while the app runs, and the old copy hands over**:
   A running `.app` cannot overwrite itself, so `UpdateManager.install` stages the new
   bundle in a temp directory and writes a `/bin/sh` helper **outside** it (the helper
   deletes it). The helper runs while Lightspot is still up: it moves the current bundle
   aside as `.lightspot-old`, copies with `ditto` (not `cp`: bundle metadata), clears
   quarantine, **re-signs ad-hoc** (an ad-hoc signature does not survive a copy) and
   writes `swapped` to its status file. Lightspot then starts the new build itself with
   `NSWorkspace.openApplication` (`createsNewApplicationInstance`, `activates = false`,
   `--replacing <pid>`) and quits only once that copy reports `isFinishedLaunching`. The
   new copy waits for the old PID to exit (a process-exit source plus a 0.1 s poll on the
   lock) before `setup()`, so the menu bar item, panel and hotkey are never doubled.

   Quit-then-relaunch, as up to 1.3.2, left the user with no Lightspot at all: the
   first launch of a just-swapped, just-re-signed bundle goes through LaunchServices'
   "node has changed" path (`launchViaCSUA`) and a Gatekeeper scan, and the process
   sits paused until it ends (measured at 30 s in a sibling app, 0.5 s here; it varies).
   Test a hand-over with a freshly compiled build: one that has run before starts fast
   and hides the gap.

   If the new copy dies or does not finish launching within `handOverTimeout` (180 s),
   Lightspot force-terminates it, drops a `restore` file, and the helper (still waiting
   on the old PID) puts `.lightspot-old` back; the old copy keeps running and reports the
   failure. Otherwise the helper removes the rollback once the old PID has exited. When
   the destination's parent is not user-writable the helper runs through
   `QuickActionsProvider.executePrivilegedWithTouchID` (off the main thread, backgrounded
   inside the privileged shell so `sudo` returns) and `chown`s the bundle back to the
   user before reporting; it never launches anything, so nothing comes back as root.

   **Trust model, stated plainly:** releases are ad-hoc signed — the project ships no
   Developer ID — so there is no signature to verify. The gate is HTTPS, a GitHub host
   allowlist checked before the request *and* against the post-redirect response URL, a
   `CFBundleIdentifier` + executable + exact-version check on the unpacked bundle, and a
   refusal to install anything that is not strictly newer. That is the same trust
   `install.sh` already asks for, and no more. If the project ever gets a Developer ID,
   verify the signature here first.

11. **Input-method composition (marked text) is searched live**:
   `SpotlightFieldEditor.setMarkedText` calls `didChangeText()`. AppKit sends no text-change
   notification for marked text (measured: 0 `controlTextDidChange` over 5 compositions), so
   with an underlining input method (JOKey without Accessibility, Japanese, Chinese, Korean) the
   search waited for each word to be committed, and `SearchFieldView.updateNSView` could wipe the
   composition because the bound query looked empty. Keep the override.

12. **No network request may use `URLSession.shared`, and nothing may touch `URLCache.shared`**:
   The shared session writes every response to `~/Library/Caches/<bundle id>/Cache.db` and
   cookies and HSTS state to `~/Library/HTTPStorages`, which is how the update check (≤ 1.2.0)
   and the public-IP lookup (< 1.2.0) put the user's IP on disk. Use an ephemeral session
   (`UpdateManager.session`, `NetworkInfoProvider.lookupSession`, `CleanDevMacRules.session`). Merely reading
   `URLCache.shared`, even to call `removeAllCachedResponses()`, creates `Cache.db` (measured).
   `LegacyNetworkStores` deletes what older versions left: at every launch, after the
   single-instance guard, off the main thread, by known path and only where the file exists,
   so a fresh install gets nothing and no `UserDefaults` flag is needed. `uninstall.sh`
   removes the same paths.

13. **A settings deep link is an installed pane's bundle identifier**:
   `x-apple.systempreferences:<id>` opens the settings extension whose `CFBundleIdentifier`
   (or `legacyBundleIdentifier`) is `<id>`; a sidebar sub-item adds `:<item>`
   (`com.apple.systempreferences.AppleIDSettings:icloud`). Any other ID still passes a
   URL-scheme check: `com.apple.General-Settings.extension` and
   `com.apple.Privacy-Settings.extension` shipped that way, yet neither is a pane and the
   System Settings binary contains neither string.
   The real IDs are in `/System/Applications/System Settings.app/Contents/Resources/Sidebar*.plist`.
   `deep_verify` checks every link against the installed panes. macOS renames and merges
   panes (Control Center became Menu Bar and Screen Saver moved into Wallpaper in macOS 26),
   so a renamed pane passes `id:` to keep the search-history key it had.

14. **Clean Dev Mac deletes only through cdm's safety gate**:
   `CleanDevMacEngine.isSafeTarget` is cdm's `is_safe_target`, and the whole trust story of
   the cleaner, as it is of cdm: a path must be absolute, exist, carry no `..`, lie outside
   cdm's protected folders (`~/Documents`, `~/Desktop`, `~/Downloads`, `~/Pictures`,
   `~/Movies`, `~/Music`, `~/.ssh`, `~/.gnupg`, iCloud Drive), and sit under the home folder
   both as written and with its parent's symlinks resolved. No rule can opt out of it, and
   rules may come from the network. It is applied twice: a match it refuses is never
   offered (cdm lists it and skips it at clean time), and `delete` checks again before it
   acts, because the plan was shown a while ago. `.emptytrash` only ever empties
   `~/.Trash`, whatever path its rule names; a symlink is removed, never followed, by every
   method. The repo scan adds its own: nothing is offered unless the repo's git lists it as
   ignored and untracked, `.env*` never, and nothing that holds a repo the walk found
   (worktrees and clones under pruned names are offered on purpose, see the repo scan above). Nothing is
   deleted without the itemized plan and a second `↵`. Treat a change to
   any of this as high-risk, and give it a test that fails without it: `test_engine` covers
   each check (mutating one out fails the run), against cdm's own fixtures.
