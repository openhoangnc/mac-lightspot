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

The app is a singleton by hotkey registration: a second instance fails to grab the hotkey. `run.sh` and `install.sh` kill the running process first — do the same manually if launching by other means.

### Tests

There is no XCTest target. Two standalone `@main` Swift files under `scripts/` are compiled ad hoc against the `Core` sources plus the few `System/` files each one needs (`test_engine` needs `AutoStartManager`, `SpotlightManager` and `FirstRunManager` too):

```bash
swiftc -o /tmp/test_engine scripts/test_engine.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift Sources/Lightspot/System/AutoStartManager.swift Sources/Lightspot/System/SpotlightManager.swift Sources/Lightspot/System/FirstRunManager.swift Sources/Lightspot/System/UpdateManager.swift && /tmp/test_engine
swiftc -o /tmp/deep_verify scripts/deep_verify.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift && /tmp/deep_verify
```

- `test_engine.swift`: 32 test blocks (each prints a `Testing …` header; `WebSearchProvider` has two) verifying math, relaxed conversions, fuzzy matcher, shell history parsing and ranking, pinned commands, custom commands, multi-IDE project discovery, process killer, web search prefixes, dev tools, default browser URL parsing, clipboard manager, snippets, system HUD, privileged execution, first-run onboarding, search-history privacy, Spotlight symbolic-hotkey entry handling, and the updater (version maths, release parsing, download allowlist, bundle validation, swap script).
- `deep_verify.swift`: 10 sections of live system checks (88 on a fully equipped machine; the shell-history and VS Code checks are skipped when there is no zsh history or VS Code) verifying real settings deep links, AppleScript syntax, terminal commands, applications scan, and system invariants.

These scripts are the primary test coverage — when you modify engines, keep tests updated.

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
│   └── AppIcon.icns              # Multi-size macOS application icon
├── scripts/
│   ├── generate_icon.sh          # Programmatic icon generator (Core Graphics + iconutil)
│   ├── test_engine.swift         # Automated test runner (26 test blocks)
│   └── deep_verify.swift         # Live-system verification (10 sections, 88 checks)
└── Sources/
    └── Lightspot/
        ├── AppMain.swift         # @main entry point, CLI flags & NSApplicationDelegate
        ├── Core/
        │   ├── AppIconCache.swift       # In-memory async app icon caching
        │   ├── AppScanner.swift         # Fast async app scanner & memory icon cache
        │   ├── BrowserIntegrationProvider.swift # Default browser bookmarks, tabs & history
        │   ├── CalculatorEngine.swift   # Math parser & conversion dispatcher
        │   ├── ClipboardHistoryManager.swift    # In-memory ephemeral clipboard ring buffer
        │   ├── ConversionEngine.swift   # Unit, currency, base, & temperature engine
        │   ├── CustomCommandsStore.swift# Custom user commands model & persistence
        │   ├── CustomIconCache.swift    # Base64 custom command icon decoding/cache
        │   ├── DevToolsProvider.swift   # UUID, Base64, Hash, JWT, JSON, Color Swatch
        │   ├── Models.swift             # SearchResult, ResultCategory, SearchAction, FuzzyMatcher
        │   ├── NetworkInfoProvider.swift# Local IPv4 & public internet IP address
        │   ├── ProcessKillerProvider.swift # Name, PID, and port process terminator
        │   ├── QuickActionsProvider.swift# Focused system actions & Terminal in Finder
        │   ├── RecentAppsManager.swift  # Recently launched applications tracking
        │   ├── RecentProjectsProvider.swift # Multi-IDE project scanner (VS Code, Cursor, Zed, JetBrains, Sublime)
        │   ├── SearchEngine.swift       # Synchronous search aggregator & ranking
        │   ├── SearchHistoryManager.swift # Search query & selection history
        │   ├── SettingsBackup.swift     # Settings export & import backup
        │   ├── SettingsProvider.swift   # 35 macOS System Settings deep links
        │   ├── ShellHistoryProvider.swift # zsh history parser & pinned commands
        │   ├── SnippetsStore.swift      # Text expansion snippets with variable interpolation
        │   ├── SystemInfoProvider.swift # Zero-subprocess Mach/IOKit hardware dashboard
        │   ├── VSCodeProjectsProvider.swift # VS Code state.vscdb recent project extractor
        │   └── WebSearchProvider.swift  # Multi-engine search & prefix shortcuts
        ├── System/
        │   ├── AutoStartManager.swift   # SMAppService login item management & caching
        │   ├── FirstRunManager.swift    # Onboarding: auto launch-at-login & Spotlight disable prompt
        │   ├── HotkeyManager.swift      # Carbon global hotkey
        │   ├── MenuBarController.swift  # Menu bar status item & preferences
        │   ├── SettingsBackupController.swift # Settings import/export controller
        │   ├── SpotlightManager.swift   # macOS Spotlight disable/restore automations
        │   ├── TerminalLauncher.swift   # Launcher for 7 terminal emulators & Finder detection
        │   └── UpdateManager.swift      # GitHub release check, verified download & self-replacement
        └── UI/
            ├── AppGridView.swift        # Compact 5-column app launcher grid
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
- **Management Overlays**:
  - `⌘P`: Pin / unpin selected shell history command
  - `⌘⇧P`: Open pinned commands manager
  - `⌘⇧C`: Open custom commands manager
  - `⌘Y` or `⌘⇧H`: Open search history manager
  - `Escape`: Clear search or dismiss panel

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

10. **The updater replaces the bundle from outside the process**:
   A running `.app` cannot overwrite itself, so `UpdateManager.install` stages the new
   bundle in a temp directory, writes a `/bin/sh` helper **outside** that directory (the
   helper deletes it), launches it detached and quits — the helper waits on the old PID,
   moves the current bundle aside as `.lightspot-old` for rollback, copies with `ditto`
   (not `cp`: bundle metadata), clears quarantine, **re-signs ad-hoc** (an ad-hoc
   signature does not survive a copy), relaunches and cleans up. When the destination's
   parent is not user-writable the helper runs through
   `QuickActionsProvider.executePrivilegedWithTouchID`, backgrounded inside the
   privileged shell so `sudo` returns and this process can exit, and relaunches via
   `launchctl asuser <uid>` so Lightspot does not come back as root.

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
