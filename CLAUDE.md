# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Lightspot is a macOS Spotlight replacement written in pure Swift with SwiftPM — **no Xcode project, no XCTest, no third-party dependencies**. It ships as a background agent (`LSUIElement = 1`) with a menu bar item and a global Carbon hotkey.

Code ported from other projects, and their licenses: [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) (Mac Tweaks ports RemoveMacAI's logic, MIT).

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

- `test_engine.swift`: 72 test blocks (each prints a `Testing …` header; `WebSearchProvider` has two) verifying math, relaxed conversions, fuzzy matcher, shell history parsing and ranking, pinned commands, custom commands, multi-IDE project discovery, process killer, web search prefixes, dev tools, default browser URL parsing, clipboard manager, snippets, system HUD, privileged execution, first-run onboarding, search-history privacy, Spotlight symbolic-hotkey entry handling, system shortcuts that collide with the Lightspot hotkey, the updater (version maths, release parsing, download allowlist, bundle validation, swap script; the hand-over run for real against fake bundles: swap while running, rollback on request, a failed copy, and a replacing launch that waits instead of asking the old copy to quit), the launch-time removal of the HTTP cache and cookies that versions up to 1.2.0 left behind, System Settings' own search terms (read from a fixture extension folder: sections, languages, tie-breaks), the System Settings opener against a fake LaunchServices record list and clock (dead records, a quitting or live instance, the error then the retry, the 5 s timeout, the fallback, the order of two opens), Clean Dev Mac (cdm's rule format, its safety gate against cdm's own test cases, `du`-exact sizing (a row's paths checked against one `du` over all of them), the kinds that work out their offer (idle AVDs' images, older versions, old Claude Code sessions, Chrome's leftover copies), the user's own temp folders and the gate's second branch against cdm's own test cases, every delete method, the clean log, cdm's restart estimate and Claude Code note against cdm's own test cases, rule sources and the scan → clean state machine, all in a fake home; the repo scan against cdm's own git fixtures: the ignored proof, grouping, `.env*`, plus Lightspot's guards), the tool installers (their commands, the install state read off the keystroke path, the rows), the macOS tweaks (every script parses; each toggle runs for real against a scratch `defaults` domain, never the user's), and Mac Tweaks' Free Up Space against a fake system root and home with fake `xcode-select`, `simctl` and `tmutil` scripts: the gate (each refusal, the never-touched folders), every row of the table, Clean Dev Mac's caches left out, the clean (the Trash, protected items, the administrator batch with batch-unique names, simctl, tmutil, a cancelled or refused prompt, a step that fails, an item gone or its folder swapped for a symlink during the prompt or after the guard's checks, verification, the capped receipts log), the batch exact for hostile file names under `/bin/sh -c` and `do shell script`, the Touch ID verdict on synthetic pty transcripts, no xcrun and no simulator row with the Command Line Tools alone, and the sections, the search row and the scan → apply state machine, and Mac Tweaks' Apple Intelligence (the feature and model-set catalog, and no section without a feature; feature state: Siri off from its deciding `Assistant Enabled` alone and never from a secondary preference, Managed for any key another profile forces, on or off or partly, Mail's unreadable domain judged by its forced value only; the profile as data — structure, stable UUIDs, kept keys absent (Siri's preferences too), a hidden Spatial Photos never forced or blocked, download overrides only for removed sets, tweaks preserved, the marker read back, stale detection, the removal as one step of the administrator batch with its own status; the `--asset-service` helper's inventory JSON, unknown sizes when the inventory call fails, a mismatched type not known, its reset refusals for an unknown, empty or mismatched set, nothing sent for a set with no bytes and no files, the request in an NSArray; the client failing closed on a crash, timeout, non-zero exit or undecodable output, and its live runner against a real child; the scan hiding Spatial Photos while its set is retired (26.7.2's report) and showing it, with the models sized and their deletion planned, once known again (27.2's), its turn-on, finish, stale and RemoveMacAI-coexistence modes, and removing the profile file once installed; the plan built from memory without reading the inventory, saying exactly what apply does; and the apply flow against a fake clock, bridge and profile: the order present → approved → reset, cancel and resume, a kept feature kept whatever apply reads, no reset when the sets total 0 bytes, the finish row sending nothing without the marker, the 5 s/15 s lock retries, the 3 s polling stopping after ten, the 600 one-second approval polls, an unknown set never reset, a failed check never read as deleted, coexistence changing nothing, turn-on through the batch and stopping at a cancelled prompt; and, against the real provider, each section's own wait, stopped only by its own Esc, the action rows applied alone, and the search phrases with System Settings' row first), and Mac Tweaks' Settings (the catalog as data: unique IDs and keys, all-profile or all-local tweaks, the presets, the pinned profile tweak IDs, no MDM-only key, the `since` floors; preference values: types kept exactly, a 32-bit real as a property list, booleans matching 0/1 and the strings macOS reads, never int 2 for true; the journal: first previous value, write-ahead, Background Items' raw JSON and unknown kinds kept byte for byte, an unreadable file reported by a scan and moved aside only by a write, two bad files both kept, an unmovable one blocking every change and never overwritten; writes that fail: a journal that can't be saved stopping a job's disable, the Dock's write and the Library flag, an entry left only for a change made (chflags or the Dock refused, a write that didn't take, removed only while the user's value is unchanged), a failed restore keeping its entry for a retry, the first previous value kept through a change by hand; each tweak's state: Partly, managed for any forced key not Lightspot's, "already off but not locked", Safari judged by its forced value, not on this macOS, the Dock with nothing to put back, rcd still loaded; the plan: directions, a Partly row finished only, the profile keeping Apple Intelligence as in force, a stale one included, removal when nothing is left, restarts once each; apply and undo through the live cfprefsd code on scratch `com.lightspot.test.*` domains with prefixed keys: exact values and types back, an unset key unset again, Undo everything restoring only what Lightspot wrote, the domains removed; Music's label from a fake bundle's inodes and its RemoveMacAI lifecycle, rcd's refused bootout counted as off from the next login and a refused bootstrap as back from it, a job off before Lightspot left as it was, each command its own plan item, all through a fake launchctl; Clear and Restore Dock Icons with the backup first, the merge, a second Clear keeping the first backup, a refused Restore keeping it, the rows' subtitles and the 1.3.x one-liner; the Dock tweak (an app removed twice journaled once, put back once) and the Library flag on a temp folder; the receipt one line per kind; the profile's tweak payloads, the shared install-or-remove routine, a marker ID this version doesn't know dropped and said (Apple Intelligence's turn-off included), and the profile file removed by Settings' scan; Undo everything in one administrator batch with Background Items' hook, that batch alone without the profile or when it went before the batch, a damaged entry kept and said; and, against the real provider, presets, the full rescan, the profile sibling's scan dropped, and the search phrases).
- `deep_verify.swift`: 14 sections of live system checks (179 on this Mac's macOS 27.2; Settings' four checks of report C's facts run only while their inputs still hold; the shell-history and VS Code checks are skipped when there is no zsh history or VS Code, the live cdm rules check when GitHub is unreachable, the repo scan checks without git, Mac Tweaks' two no-simctl checks when Xcode's simctl is there, its folder checks for folders the Mac lacks, and a System Settings search-term check whose pane no longer ships that term: 27.2's Wi-Fi pane ships no `.searchTerms` file, so "known networks" is skipped) verifying that every settings deep link names an installed pane, the real System Settings search terms, AppleScript and shell quick-action syntax, terminal commands, applications scan, system invariants, and a Clean Dev Mac scan of the real home folder, caches and repos, each category with several paths against one `du` over them, plus cdm's two notes measured on this Mac, and Mac Tweaks' Free Up Space scanning this Mac: every offered path through the gate again, macOS's and Clean Dev Mac's caches left out, the programs it runs, no xcrun, no simulator row without Xcode's simctl, its SF Symbols (measures only; it never deletes, moves or asks for a password), and Mac Tweaks' Apple Intelligence read through the in-process asset-service bridge: the features with the states this Mac reports (Spatial Photos shown exactly while the service knows its set, Siri from `Assistant Enabled` unless a profile forces its keys), the summary and the plan, three checks on the models whatever their state (at 0 bytes no reset, no folder mention and no finish row; with bytes on disk a removal, the plan's size and a finish row; with the service silent no reset), the turn-on row exactly while Lightspot's profile turns Apple Intelligence off, nothing reset or presented, the profile well-formed (`plutil -lint`) with its marker read back, and its SF Symbols, and Mac Tweaks' Settings read on this Mac with every writer refusing (no preference written, no launchctl verb but `print-disabled` and `print`, nothing restarted, no journal or Dock backup created): the 41 tweaks with the states a direct read gives (CFPreferences, launchctl's own output, `stat`), report C's facts checked only while their inputs still hold (smart quotes and dashes Partly, Improve Search off but "not locked", Safari never claiming off from its stub, desktop widgets On, the Dock tweak On and read-only with nothing to put back), Music's label from its two inodes, launchctl's disabled list, rcd's plist, the profile with every Settings tweak well-formed with its marker read back, and its SF Symbols.

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
├── THIRD-PARTY-NOTICES.md        # RemoveMacAI's MIT notice (Mac Tweaks ports its logic)
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
│   ├── test_engine.swift         # Automated test runner (72 test blocks)
│   └── deep_verify.swift         # Live-system verification (14 sections; checks vary with the system)
└── Sources/
    └── Lightspot/
        ├── AppMain.swift         # @main entry point, CLI flags & NSApplicationDelegate
        ├── Core/
        │   ├── AppIconCache.swift       # In-memory async app icon caching
        │   ├── AppleAssetService.swift  # UnifiedAssetFramework bridge, the --asset-service helper child & its client
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
        │   ├── MacTweaks.swift          # `defaults` tweaks (Dock, Finder, keyboard…) as quick actions; Clear/Restore Dock Icons (`MacTweaksDock`)
        │   ├── MacTweaksIntelligence.swift # Apple Intelligence: feature/model catalog, state, scan, profile+model-removal flow
        │   ├── MacTweaksJournal.swift   # Preference values, cfprefsd store (live/scratch), the undo journal file
        │   ├── MacTweaksProfile.swift   # The Mac Tweaks configuration profile: builder, marker, the shared install/remove routine
        │   ├── MacTweaksProvider.swift  # "Mac Tweaks" row, sections, per-section scan/apply state machine, ticks, receipts
        │   ├── MacTweaksSettings.swift  # Settings: state, rows, plan, apply/undo, Undo everything, Music, rcd
        │   ├── MacTweaksSettingsCatalog.swift # Settings: the 41 tweaks, groups and presets, as data
        │   ├── MacTweaksStorage.swift   # Free Up Space: catalog, gate, scan, Trash / admin batch / simctl / tmutil, verify
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
        │   ├── SystemSettingsOpener.swift # Every System Settings open, past LaunchServices' dead records (invariant 15)
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
            ├── CleanDevMacView.swift    # Clean Dev Mac (cdm) overlay: list, plan, receipt; card, key hint, tag shared with Mac Tweaks
            ├── CustomCommandsView.swift # Custom command manager overlay
            ├── LazyAppIconView.swift    # Asynchronous non-blocking app icon loader
            ├── MacTweaksModel.swift     # Mac Tweaks overlay state: section, ticks, cursor, plan confirmation
            ├── MacTweaksView.swift      # Mac Tweaks overlay: section tabs, rows, plan, steps, receipt
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
  `older-versions`, `claude-transcripts` and `code-sign-clones` categories with the methods
  `rm`, `rmforce`, `trash` and `emptytrash` run here, and so do `project` and `gitignore`
  ones through the repo scan below. `container` categories (Docker / Podman),
  `rust-toolchains` and `rust-docs` (their cleans are `rustup toolchain uninstall` and
  `rustup component remove rust-docs`, commands, like a container prune), cdm's
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
- **The user's own temp folders.** A pattern may start with `@cache/`, `@temp/` or
  `@boot-temp/`: the C, T and X of `/private/var/folders/<xx>/<hash>`, cdm's `USER_FOLDER`
  (`CleanDevMacEngine.userFolder()`, the resolved parent of `DARWIN_USER_CACHE_DIR`, kept
  only with exactly that shape, not a symlink and owned by the user: `isUserFolder`). It
  reaches the engine through `Environment.userFolder`, nil in every test environment that
  does not set one, and with none a token stays relative and matches nothing. The safety
  gate's second branch (`inUserFolder`, cdm's `in_user_folder`) is the only way off the
  home folder: strictly inside C, T or X, as written and with the parent's symlinks
  resolved, never a `.` segment, the folder itself or its `0`.
- **Chrome's leftover copies** (`code-sign-clones`, `codeSignClones`, cdm's
  `register_clones`): a Chromium browser clones its app bundle into X at every launch and
  deletes the copy only on a clean exit. Offered: every copy but one born within five
  minutes after a running process of its app started, one younger than five minutes, one
  of unknown age; nothing at all without a process list. Processes come from the process
  table (`runningAppProcesses`: `proc_pidinfo`'s start time and `proc_pidpath`, the app
  being the bundle name before `.app/Contents/MacOS/`), through `Environment.appProcesses`.
  The row comes sized, never measured: du counts each copy's shared blocks again (730 MB
  for a 248 KB copy of Chrome), so it is each version's entries over `cloneEntriesPerKB`,
  plus the blocks of a version no installed app carries any more, spread over its copies
  so they add up to cdm's figure. Its clean writes one receipt line for the lot.
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
  shell's rules and `expand_tilde`'s tokens, `is_nonempty`, `du -sk`-exact sizing over
  fts(3), the AVD image skip list and idle check, `newest_version`, `register_transcripts`,
  `register_clones`, `is_safe_target` with `in_user_folder`, `delete_path`,
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
- **`MacTweaks`** (not the Mac Tweaks overlay below, which is `MacTweaksProvider`) adds `defaults` one-liners to the quick actions. All but the Dock's icons are toggles built by
  `toggleScript`, which reads the current value, treats an unset key as macOS's default, and
  writes the opposite. **Clear Dock Icons** and **Restore Dock Icons** are `internal:clear-dock`
  and `internal:restore-dock`, resolved by `QuickActionsProvider.execute` (`MacTweaksDock.action`)
  through cfprefsd: Clear writes `persistent-apps` to
  `~/Library/Application Support/Lightspot/dock-backup.plist` first and clears nothing if it can't
  (an empty Dock leaves an earlier backup alone, and a second Clear before a Restore keeps the
  backup's icons, adding only the apps it lacks); Restore puts the icons back exactly into an empty
  Dock, else the missing apps at their old positions keeping icons added since, then deletes the
  backup, which stays when the Dock refuses the write; each restarts the Dock once. With no backup,
  Restore Dock Icons' subtitle says so, and a run that failed says why on its row until the next
  (`MacTweaksDock.Status`: a snapshot, the backup's existence read on a background queue once a
  search shows the rows, invariant 0). Search history from 1.3.x holds Clear's old one-liner
  (`defaults write com.apple.dock persistent-apps -array && killall Dock`) and replays it, so
  `execute` maps that exact string to the new Clear. Get a new toggle's default right: `ApplePressAndHoldEnabled` is on while
  unset, `AppleShowAllFiles` is off, and a wrong one makes the first press do nothing. Keep
  destructive ones off bare words ("clean", "dock") that other rows answer to.

### Mac Tweaks

The "Mac Tweaks" row (`mac tweaks`, `tweaks`, `debloat`, `free up space`, `remove garageband`, …)
and the menu bar's **Mac Tweaks...** open an overlay drawn like Clean Dev Mac's, in sections:
**Free Up Space**, **Apple Intelligence** and **Settings** now; Background Items is modelled in
`MacTweaksSection` and appears once a release builds it (`MacTweaksSection.built`). Free Up
Space, Apple Intelligence and Settings port RemoveMacAI's Storage, asset-service and tweak work
(MIT, see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md); the asset-service calls and the profile
follow pared, MIT); the gate, the batch, the helper process, the journal's format and the copy are
Lightspot's.

- **Sections share everything but their engine.** `MacTweaksProvider` keeps one `SectionState`
  per section (phase, rows, receipt, generation) on its own serial queue and publishes a
  `Snapshot`; `search()` and `MacTweaksModel` only read it. Rows, items, plan notes, progress
  lines and receipts are shared types (`MacTweaksRow`, `MacTweaksItem`, `MacTweaksReceipt`), and
  a section is an engine conforming to `MacTweaksSectionEngine` (scan, apply, plan notes)
  returned by `MacTweaksProvider.engine(for:environment:)`. A new section adds its case to
  `built`, its engine, and the system access it needs as `Environment` fields; the overlay, the
  model and the key routing take it as it is.
- **Nothing runs until it opens.** `Environment.live` builds closures only, the row is static
  keywords plus the last scan's total (`Snapshot.freeableBytes`), and `SearchViewModel.tweaks`
  is made on first open: no scan, file read, subprocess or timer at launch or while closed. The
  row comes before Clean Dev Mac's in `SearchEngine`, so a phrase both answer to
  ("free up space") is Mac Tweaks' Top Hit; its keywords are phrases, so an app's name, "clean",
  "dock" or "storage" stays with its own row.
- **Free Up Space's rows** (`MacTweaksStorage.catalog`, in that order): macOS installers, iPhone
  and iPad updates, unavailable simulators, Time Machine local snapshots, aerial videos,
  GarageBand and its sound library, iMovie, Keynote, Numbers, Pages, App caches, and two links
  (Clean Dev Mac; Storage in System Settings). Installers, updates and simulators are ticked. A
  row with nothing to offer is hidden, and an item measuring 0 allocated bytes is never offered:
  an empty root-owned folder (`TVIdleScreenStrings.bundle`) or an unreadable one (a root-owned
  `*.ShipIt`) would put a password prompt in the plan for nothing. Sizes are Clean Dev Mac's
  du-exact walk (`CleanDevMacProvider.measure`) in allocated bytes, shown in Finder's decimal
  units; snapshots have no size and show their count.
- **The gate** (`MacTweaksStorage.isAllowed`) runs when a path is offered and again just before
  it moves: absolute, with no `.`, `..` or empty segment; a direct child of one of the row's
  folders, fixed in code (`Roots`, `scopes`), never the folder itself; its parent resolving to
  where that folder must be, so no symlink on the way leads out (the lexical and physical pair
  of cdm's `is_safe_target`); the last component itself not a symlink; nothing under `/System`
  or a folder macOS guards (Desktop, Documents, Downloads, iCloud Drive, Containers, Group
  Containers, Mail, Messages, MobileSync, Pictures, Movies, Music); and an app or installer
  must be Apple's by the `CFBundleIdentifier` in its Info.plist (`com.apple.InstallAssistant*`,
  `com.apple.garageband10`, `com.apple.iMovieApp`, `com.apple.iWork.*`): a non-Apple `Pages.app`
  stays. GarageBand's three library folders go only while LaunchServices knows no Logic Pro or
  MainStage. Aerials skip the strings bundle macOS installs beside the videos.
- **macOS's own caches stay**: names starting `com.apple.` or `AAProfilePicture`, RemoveMacAI's
  `appleCaches`, plus `Brushes`, `MiniLauncher` and `mbuseragent`, found on this Mac
  (`appleCacheNames`), and Lightspot's `com.lightspot.app`. **And so do Clean Dev Mac's**: App
  caches leaves out every entry a cleaner rule reaches into, as a glob of the pattern's first
  name below `~/Library/Caches` (`cacheGlobs`), so the two overlays never count one folder.
  The rules are the ones the cleaner holds in memory (`CleanDevMacProvider.heldRules`), else
  `~/.cleandevmac/rules`, else the app's copy; Mac Tweaks never fetches them.
- **simctl without the trap.** Never `/usr/bin/xcrun`, which opens the Command Line Tools
  installer on a Mac without them: `<xcode-select -p>/usr/bin/simctl`, and only once
  `~/Library/Developer/CoreSimulator/Devices` exists and that file is executable. With the
  Command Line Tools alone there is no simctl: no row, nothing run, no prompt.
- **Clean**, in this order. (1) Each ticked path that still passes the gate goes to
  `FileManager.trashItem`, all of them first. When one can't: gone already, skipped; refused
  by a folder's permissions (EACCES, which root overrides), or refused and another user's,
  kept for the administrator; refused by macOS itself (EPERM) and this user's, an app
  (`isAppBundle`, by its row, never by a name ending in `.app`) gets the App Management advice (from macOS 13 moving another developer's app needs
  that permission, which an ad-hoc signed Lightspot doesn't have) and anything else is
  "protected by macOS", counted with its size; any other error is reported in macOS's words.
  (2) Only then is a Trash name reserved for each of the administrator's items
  (`uniqueTrashName`, unique in the Trash and in the batch; the Trash can't be listed, a name
  in it can be looked up), each item through the gate once more, so no Trash move in the same
  apply can take the name first; snapshots join the batch as `tmutil deletelocalsnapshots
  <date>`. (3) Simulators go through `simctl delete unavailable` as this user, after the
  batch: nothing slow sits between the checks and the prompt. (4) Then everything is looked at
  again: an administrator move counts only when the batch ran, its step reported no error,
  the item is gone and its Trash name is there; an item gone any other way, even into the
  Trash under that name (Finder during the prompt), is listed ("It was gone before Lightspot
  moved it.") and never counted. Freed is only what Lightspot moved or deleted (the Trash's
  moves, the administrator's that check out, simulator folders there before simctl and gone
  after) less whatever has grown back at the same path, measured again (never a fresh scan,
  whose gate may answer differently by now: Logic Pro installed meanwhile keeps GarageBand's
  library); snapshots by asking tmutil again. The receipt says what stayed and why, and ⌥↵
  on it shows an app macOS kept.
- **The administrator batch** (`adminScript`) is one `/bin/sh` script, run once through
  `QuickActionsProvider.runPrivilegedScript` (invariant 7) and only when it has something to
  do: `exec </dev/null`, then each command in its own subshell followed by
  `printf '\n%s %d %d\n' <random tag> <n> $?` on a line of its own (`batchResults`), then
  `exit 0`, so a failed step is never taken for a failed prompt. Why an item stayed is the
  reason after the last `: ` of what its step printed (`reason`), never a search of that
  output, which holds both paths: a file named `Operation not permitted.ipsw` is not
  "protected by macOS". Each root `mv -n` is guarded as it runs (`guardedMove`): it goes into
  the item's folder (`cd -P`), goes on only if `pwd -P` is where the gate found it, and moves
  `./<name>`, so root moves the entry from the folder it just verified even if the path is
  swapped for a symlink after the checks (and a name starting with `-` never reads as an
  option); the Trash still a real folder, the item not a symlink, nothing yet at its Trash
  name (onto a folder `mv -n` would move the item inside it; onto a file it skips and still
  exits 0). Every argument is single-quoted (`'` as `'\''`), every program is absolute, and
  so is every path but `./<name>`, which the guard's own `cd` anchors: neither backend
  promises a working folder or a `HOME`, so the Trash is expanded in Swift.
- **State.** A scan stands for five minutes, and reopening within them shows it again. An apply
  runs on the provider's queue, keeps running if the panel hides (a password prompt takes the
  focus), and reopening shows its steps, then its receipt; ↵ on the receipt scans again.
  Closing the overlay drops an older scan's rows, and the rows behind a receipt, keeping only
  the row's total; a scan that still stands is kept, so the five-minute reuse holds.
- **Receipts** go to `~/Library/Application Support/Lightspot/mac-tweaks.log`, written only when
  the user applies something and capped like cdm's clean.log
  (`CleanDevMacEngine.appendToLog(_:url:now:)`).
- **Binary size.** `build.sh` strips debug symbols only (`strip -S`), so every local symbol
  name stays in the binary, and SwiftUI spells a view's whole nested type into each name it
  generates: one long `body` made names of 2,000 characters by the hundred. The overlay is
  therefore small view structs that take plain values (`MacTweaksHeader`, `MacTweaksList`,
  `MacTweaksRowView`, …), per-section state lives in arrays rather than dictionaries keyed by
  the section, and `scan`/`apply` take an optional progress closure (a closure argument made
  the compiler copy each function once per call site). Measure each phase with `./build.sh`
  and `stat`, against `./build.sh` at the previous release, and compare `otool -L`: one Swift
  overlay method links a new library (`NSSound.beep()` is the AppKit overlay's and pulls in
  `libswiftAppKit.dylib`, and Swift can't see `NSBeep()`).

#### Apple Intelligence

Turns Apple Intelligence off for every account on this Mac — a System-scope configuration profile
switches the features off and blocks the model downloads, then the downloaded models are removed —
and turns it back on by removing the profile. `MacTweaksIntelligence` is the engine (catalog, state,
scan, apply), `MacTweaksProfile` the profile, `AppleAssetService` the asset-service bridge, helper
and client. All three port RemoveMacAI (MIT); the asset-service calls and the download block are
pared's.

- **The asset service runs in a short-lived child, never in Lightspot's own process.** AppKit
  already loads `UnifiedAssetFramework` at launch, but *calling* it costs 9–11 MB of resident
  memory that never comes back (platform report A7), which would break the "RSS returns after
  close" rule. So every asset-service read, and the reset, runs in the Lightspot binary started as
  `Lightspot --asset-service <verb> [set]`, handled in `main()` before `SingleInstanceGuard` and
  any `NSApplication` setup (next to the uninstall flags), printing one JSON object and exiting;
  the cost dies with the child. `AppleAssetService.AssetServiceBridge` (the framework calls) is
  reached only from that flag and, read-only, from deep_verify. The app talks to the child through
  `AssetServiceClient` (Clean Dev Mac's runner: stdin from /dev/null, the pipe read as it comes,
  30 s for the inventory and 150 s for a reset; a crash, a timeout, a non-zero exit or output that
  doesn't decode fails closed). `latestStatusForClients:` is never called (it takes locks and
  reports 0 here); sizes come from the inventory only, and a failed inventory call reports them
  unknown (`AssetSetInfo.bytes` nil), never 0, which would read as "deleted". The `inventory` verb
  reads no folders; `reset <set>` checks RemoveMacAI's `present` first (tracked bytes, else files
  in the set's `/System/Library/AssetsV2` folder) and sends nothing for an empty set (`.notPresent`).
  The request is UAF.m's: one set, in an NSArray.
- **The catalog is data** (`Catalog`): the features with their `since` versions, the model sets,
  which sets to remove given the kept features. The section exists only on Apple silicon with a
  macOS that has a feature (15.1 on; `MacTweaksSection.built`). A feature is hidden when the
  running macOS lacks its version *or* the service has retired every model set it needs (Spatial
  Photos on 26.7.2, where `getAssetSet:` returns nil; 27.2 knows its set again). Feature state
  (`FeatureState`: locked off, off, on, unknown, managed): any key a profile forces makes the
  feature **managed** — unless it is Lightspot's profile, which covers the feature and forces
  every key to its off value (**locked off**); with nothing forced, a model-only feature follows
  its models and another reads **off** from its deciding preference (Siri's `Assistant Enabled`;
  else its only readable one), so a secondary preference alone can't make it read off.
  Preferences in domains a non-sandboxed app can't read (Mail's, notifications', Safari's) are
  judged by their forced value only.
- **The profile** (`MacTweaksProfile`, identifier `com.lightspot.app.tweaks`, display name
  "Lightspot Mac Tweaks", System scope, removable): a `com.apple.applicationaccess` restrictions
  payload (only when an `allow…` key is set), one `com.apple.ManagedClient.preferences` payload per
  forced domain including the download block (`DownloadServerBaseURLOverride-<asset type>` =
  `https://127.0.0.1:9/lightspot-blocked/` for each removed set), and a marker domain holding
  `installed`, `ai`, `kept`, `tweaks` (phase 3's) and `features`. Payload UUIDs are stable (SHA-1
  of the identifier, CryptoKit). Everything left unticked is kept, a hidden feature included, so
  the profile never touches a feature the user didn't choose. The file is written to
  `~/Library/Application Support/Lightspot/`, opened, and a second later Device Management is
  opened (RemoveMacAI's order; `SettingsProvider.deviceManagementLink`; both through
  `SystemSettingsOpener`, invariant 15); the marker is polled once
  a second for up to 10 minutes, and the file is removed once the profile is installed (after the
  wait, and by any scan that finds it installed). It is removed by `profiles remove -identifier …
  -forced` as one step of the administrator batch in Free Up Space's form, judged by the marker.
  The profile is tested as data (structure, stable UUIDs, the marker read back, stale detection,
  `plutil -lint` on a temp copy); it is never installed, opened or removed in tests or deep_verify,
  and the real `profiles` only ever runs with read-only verbs.
- **Apply** (on the provider's queue): the profile first (so the models can't download again), then
  the models under RemoveMacAI's rule (`RemovalPlan`, which the plan uses too, so the plan says
  exactly what apply does): a removal is requested only when the sets to remove total more than 0
  bytes or their size is unknown, and then each known set gets the helper's `reset` — retried
  after 5 s then 15 s while locked — followed by the inventory polled every 3 s for up to 30 s
  until the sizes reach 0. When the inventory knows the sets total 0 nothing is sent and the
  section says "Apple Intelligence's models aren't on this Mac" (26.7.2 had none on disk; 27.2
  downloaded about 8 GB, so a turn-off there sends resets). A set the service doesn't know stays,
  and the receipt says so. "Finish removing the models" (offered only while Lightspot's profile is
  in force, not stale, and the sets it blocks hold bytes or an unknown size) reads the marker
  again first and sends nothing without it. The approval and removal waits survive the panel hiding (System Settings
  takes the focus); Esc stops them, the section's own wait only and only while it waits
  (`MacTweaksProvider.cancelWait`, `SectionState.waiting`, which makes the footer say "Esc Stop
  waiting"), and the pending profile stays in System Settings so the next apply continues once it
  is installed. Turning back on removes the profile through the administrator prompt; a cancelled
  or refused prompt stops there. When RemoveMacAI's marker is installed the section is read-only
  and says RemoveMacAI manages it, though Lightspot's own profile can still be removed. Receipts
  show the green check only for a success.
- **The plan and the summary read nothing.** The provider keeps what the scan read
  (`Snapshot.appleIntelligenceScan`: the inventory and both markers) and hands it, with the rows
  on show, to the engine it builds for the plan (`MacTweaksProvider.makeEngine`), so the plan view
  never starts a child on the main thread (invariant 0). Both say the change is for every account.
- **The rows** are the shared `MacTweaksRow`: one per shown feature (ticked means *turn off*; every
  changeable feature starts ticked, and the plan says one already off "stays off, now locked off";
  a managed or locked-off feature is `readOnly`, drawn with a lock, and Space does nothing; a
  stale profile's features are changeable again, ticked as its marker had them, the new ones
  named), plus two action rows while Lightspot's profile turns it off: "Finish removing the
  models" (ticked) when its sets still hold models, and "Turn Apple Intelligence back on"
  (unticked, so reopening never defaults to undoing the user's choice). Action rows are
  `exclusive`: applied alone (`MacTweaksTicks`). Free Up Space gains an "Apple Intelligence models"
  link row (to this section) when the models are on disk — their size is the last Apple
  Intelligence scan's total, so it shows nothing until that section has been scanned and nothing
  when the models are 0 bytes. The search phrases "turn off apple intelligence", "remove apple
  intelligence" and "delete apple intelligence models" open the section directly
  (`internal:mac-tweaks:apple-intelligence`); a bare "apple intelligence" weighs less than System
  Settings' own row, which stays first.

#### Settings

RemoveMacAI's 41 tweaks (Privacy, Annoyances, Apple apps, Finder, Dock and windows, Typing), each
with its state and a tick that changes it, and an undo journal so everything Lightspot changed can
go back as it was. `MacTweaksSettingsCatalog` is the catalog, `MacTweaksSettings` the engine,
`MacTweaksJournal` the preference values, the cfprefsd store and the journal file. Ports
RemoveMacAI's Tweaks, Engine, Prefs and MusicLaunch (MIT).

- **The catalog is data** (`MacTweaksSettings.catalog`): per tweak its group, changes (a
  restriction or a forced preference, both in the profile; the user's own preference; a launchd job;
  Music's launch entry; Dock tiles; `~/Library`'s flag), the processes that read it only at launch
  (Finder, the Dock, SystemUIServer), its presets and `since`. Lightspot's changes to RemoveMacAI's:
  `.DS_Store` covers USB drives too (both keys, Finder restarted, as the quick action does); the
  Dock-removal tweak is one list of 10 apps; the long-standing Finder, save-dialog, Dock, window,
  screenshot and typing keys go back to macOS 13 (RemoveMacAI's 14.0 is its own minimum), the
  WindowManager, profile and service tweaks keep its floors. IDs are permanent: the profile's marker
  and the journal record them (a test pins the profile ones).
- **Preferences go through cfprefsd** (invariant 8, `PreferenceStore`): `CFPreferencesSetValue` and
  `Synchronize` for the user's own value (current user, any host, as `defaults write`), read back
  before anything counts as done. `PreferenceValue` keeps every type exactly (cfprefsd keeps a
  32-bit real 32-bit, so anything but booleans, integers, 64-bit reals and strings is kept as a
  binary plist). Matching is RemoveMacAI's booleans-and-0/1 plus what `CFPreferencesGetAppBooleanValue`
  accepts ("YES", "true", "no"…, as the toggles already treat "YES"), and an int 2 never matches
  true. Tests write only `com.lightspot.test.<run>.<domain>` with every key prefixed
  (`PreferenceStore.scratch`): a key a scratch domain lacks falls back to the real global domain's
  value through `CopyAppValue` (measured on 26.7.2 and 27.2).
- **The journal** (`~/Library/Application Support/Lightspot/tweaks-journal.json`, `MacTweaksJournal`):
  versioned JSON, one entry per changed thing (`pref:<domain>:<key>`, `service:<label>`,
  `dock:<bundle ids>`, `library`, and Background Items' `background:gui|system/<label>`), each
  holding what its undo needs, so an entry undoes without the catalog that wrote it. The first
  previous value wins; an entry goes once its undo is verified. Saved before each change it records
  (`saveAhead`, atomic): a journal that can't be saved stops that change. Every entry is kept as
  compact JSON with sorted keys and written back as read, so a kind this version doesn't know, and
  Background Items' own fields, are never dropped. A scan only reports an unreadable file
  (`status`); the first write moves it aside as `tweaks-journal-unreadable-<date>-<id>.json`, and
  when it can't be moved nothing changes and the section is read-only. An empty journal leaves no
  file.
- **State** (`MacTweaksSettings.state`): not on this macOS (by `since`), then **managed** when any
  key is forced by a profile that isn't Lightspot's (or any forced key of a user preference, which
  a user write can't beat), then on, off or partly. A forced-type tweak whose own value already
  matches but isn't locked counts as off and says "Already off in your own settings, but not
  locked." (Improve Search here: its value is 2); never for restrictions, or for the domains read
  by their forced value only (Safari's stub, the group containers). A job disabled but still loaded
  is partly (rcd's bootout SIP may refuse: off from the next login). Music follows RemoveMacAI's
  `MusicLaunch.state`. The Dock tweak with none of its apps in the Dock and nothing journaled is On
  and read-only: there is nothing to put back.
- **Rows and ticks**: two presets first (Recommended; Maximum privacy adds Game Center and Safari's
  suggestions; neither touches Apple Intelligence, which has its own section), the tweaks grouped
  under headers (`MacTweaksRow.group`), "Undo everything Lightspot changed" last. Nothing starts
  ticked. A tick changes the row: an Off row turns on, an On row undoes (`undoes`, an undo arrow in
  the box), a Partly row is finished, never undone (the owner's own setting; undoing what
  Lightspot wrote is Undo everything's job). A preset (`ticks`) ticks its rows that aren't on yet,
  and unticks them; Undo everything is exclusive. Profile rows carry a "Profile" tag with a lock.
  The selected row and the plan show each change's command (`defaults write …`, `launchctl …`,
  `profile: …`, `chflags …`; a job's disable and bootout, or enable and bootstrap, as two items). A
  row's undo turns the tweak off: recorded values go back, a matching key Lightspot recorded nothing
  for goes back to macOS's default, and the plan says which; a job journaled as off before Lightspot
  is left as it was, and the plan and the receipt say so.
- **Apply** (on the provider's queue): a fresh reading and plan (`MacTweaksSettings.plan`, which the
  plan view runs on the scan's reading, so it says exactly what apply does), then local changes,
  each journaled first and read back; then Finder, the Dock and SystemUIServer restarted once each,
  for the local changes only; then the profile when its set of tweaks changed
  (`MacTweaksProfile.change`, the routine Apple Intelligence uses too): rebuilt keeping Apple
  Intelligence exactly as in force (`aiInForce`: for a profile made on an older macOS the features
  it didn't know stay on), approved in System Settings with the same 1 s × 10 min wait Esc stops,
  or removed through the administrator batch when nothing would be left. The plan says the profile
  applies to every account on this Mac. A marker ID this version doesn't know (after a downgrade)
  can't be rebuilt, so a profile change drops it and the plan says so. Then everything is read again
  and the receipt says what changed: one wrapped line per kind ("Applied: …", "Finished: …",
  "Undone: …", the restarts, what the profile locks), with lines, problems and notes in one scroll
  view so a long receipt keeps its end. Music's entry is disabled then booted out (Music quits);
  rcd's restore enables it and bootstraps `/System/Library/LaunchAgents/com.apple.rcd.plist`. A
  bootout macOS refuses still counts as done, off from the next login (the row reads Partly until
  then), and a refused bootstrap as undone, back from the next login. A Library flag or Dock write
  that didn't take puts its journal entry back as it was; a preference write that didn't take
  removes only the entry it made, and only while the user's value is unchanged.
- **Undo everything** puts back every journal entry by its own fields (settings, the Library flag,
  Dock tiles, jobs; tweaks no longer in the catalog included), restarts what they need once, and
  removes Lightspot's profile, Background Items' root steps joining the profile's removal in **one**
  administrator batch (`Environment.background`, typed `[(key, json)]`, with a plan-line hook; nil
  until Background Items is built, and then its entries stay); without the profile, or when it went
  before the batch, those steps make the batch alone (`MacTweaksProfile.change`). Kinds it can't undo
  stay, as do entries of a known kind it can't read, and the plan and the receipt say so. Files in the Trash and Clear Dock Icons' backup are not part of it.
- **The plan and the summary read nothing**: the provider keeps the scan's `Reading`
  (`Snapshot.settingsScan`). After an apply in Apple Intelligence or Settings the other one's scan no
  longer stands (they share the profile), and a full rescan replaces every row. The phrases "stop
  music from opening", "turn off apple music", "turn off mac analytics", "turn off personalized
  ads" and "show the library folder" open the section directly (`internal:mac-tweaks:settings`),
  matched exactly or by prefix only, so a word inside one ("library") never brings the row up.

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
- **Mac Tweaks overlay** (`↵` on its row, or the menu bar's **Mac Tweaks...**; the Apple
  Intelligence and Settings search rows open it on their sections):
  - `↑↓`: Select a row; `Space`: Tick / untick it (`SpotlightFieldEditor.keyDown`, as for the
    cleaner; nothing on a link row, or a read-only row the lock marks — a feature another
    profile sets, or one Lightspot's own profile already locks off). An action row ("Finish
    removing the models", "Turn Apple Intelligence back on") is applied alone: ticking it
    unticks the rest. The Space hint and the Defaults/None buttons go when nothing can be ticked
  - `↵`: Review the itemized plan, or open a link row; `↵` again applies, `Escape` goes back,
    then closes
  - In Settings: `Space` on a preset ticks its rows that aren't on yet (again: unticks them); on
    an On row it ticks the undo (an undo arrow); on a Partly row it ticks finishing it; "Undo
    everything Lightspot changed" is applied alone
  - `Escape` while Apple Intelligence or Settings waits for System Settings (the footer says "Stop
    waiting"): stops that wait; the profile stays in System Settings. The close button closes the
    panel and leaves the wait going
  - `⇥` / `⇧⇥`: Next / previous section, once there is more than one
  - `⌥↵`: Show the selected row's first item in Finder; on a receipt, the app macOS kept
  - `⌥↵` and `⌘↵` on the Mac Tweaks row itself open the overlay, as `↵` does

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
   - IDE recent workspace state files: VS Code's and Cursor's `storage.json`, `state.vscdb`
     and `workspaceStorage/*/workspace.json`, Zed's `db/0-<channel>/db.sqlite`, JetBrains'
     `recentProjects.xml`, Sublime Text's two session files. SQLite files are read with
     `RecentProjectsProvider.querySQLite`: `mode=ro` beside a WAL (an `immutable=1` open
     skips it and loses everything since the last checkpoint), `immutable=1` without one
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
     The rules may also name the user's own temp folders under `/private/var/folders`
     (clang's module cache, Node's compile cache, Chrome's leftover copies); for those
     copies the scan reads their creation dates and bundle names, and the start time and
     executable path of the user's own running processes (kept: the app name and start,
     for that scan only). `~/Library/Containers` and `~/Library/Group Containers` are never
     read (`CleanDevMacEngine.outOfScopeFolders`): inside another app's container macOS asks
     the user whether Lightspot may "access data from other apps", and with an ad-hoc
     signature it would ask again after every update.
   - For Clean Dev Mac's repo scan, and only when the user asks for it (⇥): the folders
     under the home folder to the rules' depth (six), without entering `~/Library`, cdm's
     protected folders, `.git` or the names the rules prune, plus each repo's
     `git ls-files` listing. Nothing is kept but the offered paths and their sizes.
   - For Mac Tweaks' Free Up Space, and only when the user opens Mac Tweaks, on its queue: the
     names in `/Applications` and the `Contents/Info.plist` of each `Install macOS*.app` and of
     GarageBand, iMovie, Keynote, Numbers and Pages there; the entries of
     `~/Library/iTunes/iPhone Software Updates` and `iPad Software Updates`; the simctl device
     list (`<xcode-select -p>/usr/bin/simctl list devices unavailable -j`, only once
     `~/Library/Developer/CoreSimulator/Devices` exists); the dates
     `/usr/bin/tmutil listlocalsnapshotdates /` prints; the entries of
     `/Library/Application Support/com.apple.idleassetsd/Customer`; the wallpaper index
     (`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`, only when there
     are aerial videos to offer); the GarageBand library paths (`/Library/Application
     Support/GarageBand` and `Logic`, `/Library/Audio/Apple Loops/Apple`) and whether
     LaunchServices knows Logic Pro or MainStage; the entries of `~/Library/Caches`; Clean Dev
     Mac's rule files (`~/.cleandevmac/rules`, else the app's copy) when the cleaner holds none
     in memory; and every offered item measured and its owner read (`lstat`). Closing the
     overlay drops the paths and sizes, keeping the total the row shows, unless the scan still
     stands (five minutes) or a receipt is still to be read. Every scan and apply also resolves
     each fixed folder (`realpath`, the gate's physical half); an apply puts each item through
     the gate again, looks up names in `~/.Trash` one at a time (`lstat` of a name; the Trash
     itself is never listed), and measures again the items still there.
   - For Mac Tweaks' Apple Intelligence, and only when the user opens that section: the asset
     service's inventory, which reads no folders. Only within a removal (an apply whose sets to
     remove hold bytes or an unknown size), and only for a set the inventory gives no bytes, the
     `reset` child reads the attribute counts of that set's `/System/Library/AssetsV2/<asset
     type>` folder and its `purpose_auto` (`getattrlist`, `lstat`, `stat` — never a listing,
     which macOS refuses). Both run in the short-lived `--asset-service` child, never in
     Lightspot's own process (platform report finding 1); deep_verify runs the inventory
     in-process. Feature state and the profile marker are read through cfprefsd (invariant 8),
     not the file system.
   - For Mac Tweaks' Settings, and only when the user opens that section, on its queue: the
     catalog's preferences and the profile marker through cfprefsd (not the files);
     `launchctl print-disabled gui/<uid>`, and `launchctl print` for com.apple.rcd and Music's
     label when they are disabled; the inodes of `/System/Applications/Music.app` and its
     executable (`lstat`); `~/Library`'s hidden flag; the Dock's `persistent-apps` (cfprefsd);
     the journal (`tweaks-journal.json`); and whether rcd's plist and the Dock backup exist. The
     Dock quick actions read `persistent-apps` and `dock-backup.plist` only when run; their rows'
     subtitles check that the backup exists, on a background queue, once a search shows them.
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

   Files, besides the instance lock: `~/Library/Application Support/Lightspot/mac-tweaks.log`,
   Mac Tweaks' receipts, written only when the user applies something and capped like cdm's
   clean.log (over 1 MiB it keeps the newest 256 KiB); only while an apply changes Lightspot's
   profile (Apple Intelligence off, back on with profile tweaks kept, or a Settings tweak in or
   out), `~/Library/Application Support/Lightspot/LightspotMacTweaks.mobileconfig`, the profile
   written for approval and removed once it is installed: after the approval wait, and by any
   Apple Intelligence or Settings scan that finds the profile installed (never in `~/Downloads`, which is
   TCC-protected); `tweaks-journal.json` beside them, Settings' undo journal, written only by an
   apply that changes a local setting, before the change, removed once empty, never overwritten
   when unreadable (moved aside as `tweaks-journal-unreadable-<date>-<id>.json`); and
   `dock-backup.plist`, written by Clear Dock Icons and removed by Restore Dock Icons once the
   icons are back. `uninstall.sh` keeps the journal, the journals moved aside and the Dock backup,
   and says what stays and how to undo it (Restore Dock Icons for the icons). Settings also writes other apps' preferences (Finder's, the Dock's, the global
   domain's…), only when the user applies something, each one journaled first.
7. **Privileged Commands & Headless Touch ID Execution**:
   Privileged operations (`requiresAdmin`, `sudo`, `mDNSResponder`, `purge`) execute via `QuickActionsProvider.executePrivilegedWithTouchID`. This runs `/usr/bin/sudo` attached to a headless pseudo-terminal (`openpty`), triggering native macOS Touch ID (`pam_tid.so`) directly without opening a Terminal window. If Touch ID fails or is unavailable, it automatically falls back to AppleScript Authorization Services (`do shell script ... with administrator privileges`) displaying the native password dialog. A bare leading or chained `sudo` token is stripped before execution (both backends already run as root), but a `sudo` carrying its own options (`sudo -u postgres psql`) is left intact — stripping it there would promote the flags to the command. `QuickActionsProvider.isTouchIdForSudoEnabled` is a cached, non-blocking snapshot of `/etc/pam.d/sudo_local` because `search()` reads it on the keystroke path.

   **Never a second run.** The pty command first prints a random marker
   (`markedCommand`, written as two quoted halves so sudo echoing the command line can't pass
   for it), then sets stdin to /dev/null (sudo needs the pty only before the marker, and a
   command that asks a question must not wait on it); once the marker reaches the pty, sudo
   has authenticated and the command has started, so it never falls back to the password
   dialog (which would run it again behind a second prompt) and the 60 s cap stops applying.
   A 30-minute one remains, after which sudo gets SIGTERM, which it passes on, then SIGKILL
   five seconds later (`stop`), which it can't: the command may then run on as root, and the
   log says so; the wait itself always ends. The pty is read after exit for at most a second
   or the output cap (`drain`), so a command that starts and fails between two reads is still
   seen, and a child that keeps writing can't keep it reading (`touchIDVerdict`, tested on
   synthetic transcripts). Before the marker, `Password:` or 60 s still fall back. The rule is
   `privilegedCommand` and `privilegedScript`, tested with the two backends faked: a command
   that ran and failed is `false`, with no prompt. Scripts Lightspot builds itself, every argument already
   single-quoted (Mac Tweaks' administrator batch), go through
   `QuickActionsProvider.runPrivilegedScript` instead: no `admin:` or `sudo` stripping (it
   rewrote file names holding `; sudo `), and a `PrivilegedRun` (`.cancelled`, `.refused`,
   `.ran(status, output)`) instead of a Bool. Neither entry point logs a script's text, only
   its outcome: the paths in it would reach the unified log.
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

15. **Everything System Settings opens goes through `SystemSettingsOpener`**:
   On macOS 27.2 launchservicesd can miss System Settings' exit ("ListenForProcessExitFromRunningboard
   … failed twice to find expected application") and keeps its record, a running dot in the Dock,
   until it notices late (67 s measured) or its ten-minute sweep drops it ("Forcibly removing
   application … missed a death notification"). Meanwhile every open goes to the dead PID, even
   with a live instance in front: CoreServicesUIAgent shows "The application "System Settings" is
   not open anymore." (plain `NSWorkspace.open(_:)`) or "The application can't be opened." -600
   (`open(_:configuration:)` prompting), and nothing opens. NSRunningApplication reads the same
   records. So the Settings rows, Free Up Space's Storage link, the profile file and Device
   Management, the System Settings app row, the Keyboard Shortcuts items and any
   `x-apple.systempreferences:` URL (`openAny`) go through `SystemSettingsOpener.open`, never
   `NSWorkspace` directly. It checks each recorded PID (`kill`, `proc_pidpath`); with only dead
   records it opens a new instance (`createsNewApplicationInstance`, the URL passed at launch,
   which reaches the pane); otherwise it opens with `promptsUserIfNeeded = false`, so a failed
   hand-off comes back as an error (Cocoa 256 over OSStatus -600) instead of the alert, and then
   it asks a live instance still showing a window to quit, waits up to 5 s for the live ones to
   exit, retries once quietly and opens a new instance if the retry is handed to a dead record
   too. A prompting open follows only a quiet one that failed another way. It works on its own
   serial queue, so nothing waits on the main thread and the profile still opens before Device
   Management.

14. **Clean Dev Mac deletes only through cdm's safety gate**:
   `CleanDevMacEngine.isSafeTarget` is cdm's `is_safe_target`, and the whole trust story of
   the cleaner, as it is of cdm: a path must be absolute, exist, carry no `..`, lie outside
   cdm's protected folders (`~/Documents`, `~/Desktop`, `~/Downloads`, `~/Pictures`,
   `~/Movies`, `~/Music`, `~/.ssh`, `~/.gnupg`, iCloud Drive), and sit under the home folder
   both as written and with its parent's symlinks resolved — or, the one way off it,
   strictly inside the C, T or X of the user's own `/private/var/folders` folder, checked
   the same two ways (`inUserFolder`). No rule can opt out of it, and
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
