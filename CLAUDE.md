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

There is no XCTest target. Two standalone `@main` Swift files under `scripts/` are compiled ad hoc against the `Core` and `System/TerminalLauncher` sources:

```bash
swiftc -o /tmp/test_engine scripts/test_engine.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift && /tmp/test_engine
swiftc -o /tmp/deep_verify scripts/deep_verify.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift && /tmp/deep_verify
```

- `test_engine.swift`: 24 automated test suites verifying math, relaxed conversions, fuzzy matcher, shell history parsing and ranking, pinned commands, custom commands, multi-IDE project discovery, process killer, web search prefixes, dev tools, default browser URL parsing, clipboard manager, snippets, system HUD, and privileged execution.
- `deep_verify.swift`: 88 live system checks verifying real settings deep links, AppleScript syntax, terminal commands, applications scan, and system invariants.

These scripts are the primary test coverage — when you modify engines, keep tests updated.

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

   Known remaining exception: `ProcessKillerProvider.findProcessesOnPort` shells out to
   `lsof` (~55 ms) inline, but only for `kill <port>` queries. Its sibling `ps -axo`
   snapshot is *not* an exception — it refreshes on a background queue behind a
   staleness check and in-flight flag, primed by `warmUp()` when the panel is shown.

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
7. **Privileged Commands & Headless Touch ID Execution**:
   Privileged operations (`requiresAdmin`, `sudo`, `mDNSResponder`, `purge`) execute via `QuickActionsProvider.executePrivilegedWithTouchID`. This runs `/usr/bin/sudo` attached to a headless pseudo-terminal (`openpty`), triggering native macOS Touch ID (`pam_tid.so`) directly without opening a Terminal window. If Touch ID fails or is unavailable, it automatically falls back to AppleScript Authorization Services (`do shell script ... with administrator privileges`) displaying the native password dialog. A bare leading or chained `sudo` token is stripped before execution (both backends already run as root), but a `sudo` carrying its own options (`sudo -u postgres psql`) is left intact — stripping it there would promote the flags to the command. `QuickActionsProvider.isTouchIdForSudoEnabled` is a cached, non-blocking snapshot of `/etc/pam.d/sudo_local` because `search()` reads it on the keystroke path.
