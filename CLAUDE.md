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

`swift build` alone produces the bare binary; it will not run correctly as an app (no bundle, no `Info.plist`, so no `LSUIElement`). Always go through `build.sh`.

The app is a singleton by hotkey registration: a second instance fails to grab the hotkey. `run.sh` and `install.sh` kill the running process first — do the same manually if launching by other means.

### Tests

There is no test target. Two standalone `@main` Swift files under `scripts/` are compiled ad hoc against the `Core` sources:

```bash
swiftc -o /tmp/test_engine scripts/test_engine.swift Sources/Lightspot/Core/*.swift && /tmp/test_engine
swiftc -o /tmp/deep_verify scripts/deep_verify.swift Sources/Lightspot/Core/*.swift && /tmp/deep_verify
```

`test_engine.swift` is pure logic (calculator, fuzzy matcher, providers). `deep_verify.swift` hits the live system: it resolves every settings deep link through `NSWorkspace`, compiles every quick-action AppleScript, scans real `/Applications`, and asserts that no file paths ever leak into results.

**Both scripts are currently stale and do not compile.** They call `FuzzyMatcher.score(query:target:)` and pass `String` to `search`/`searchImmediate`, but those APIs now take a `SearchQuery` and `FuzzyMatcher.score` takes pre-tokenized `targetLower:targetTokens:targetInitials:`. Fix the call sites when you touch the engines rather than deleting the coverage.

## Architecture

`AppMain.swift` is the only wiring point. `AppDelegate.setup()` constructs `SearchViewModel`, `SpotlightPanel`, `HotkeyManager`, and `MenuBarController`, then connects them with closures — there is no DI container or notification bus. To follow any interaction end to end, start there.

Three source layers under `Sources/Lightspot/`:

- **`Core/`** — pure search logic, `AppKit`-only, no SwiftUI. Every provider is a `shared` singleton.
- **`System/`** — macOS integration: Carbon hotkey, menu bar, launch-at-login, and control of *Apple's* Spotlight.
- **`UI/`** — SwiftUI views plus the AppKit bridges (`NSPanel`, `NSTextField`, `NSVisualEffectView`).

### Search pipeline

`SearchViewModel.performSearch` → `SearchEngine.searchImmediate(SearchQuery)` → fan-out to every provider → merge.

`SearchEngine` is **fully synchronous and in-memory** (`searchQueue`, `debounceInterval`, `currentWorkItem`, and the completion-based `search(_:completion:)` are all dead code). This is deliberate: a full search across every provider measures ~0.5 ms, so debouncing would only delay results without reducing input latency. Providers must stay allocation-light and fast enough to run on every keystroke on the main thread. It then:
1. Picks the single highest-scoring non-calculator/non-web result as `.topHit` and re-issues it with id `top-<originalID>`.
2. Groups the rest by category, excluding the promoted original so it is not shown twice.
3. Caps each category at `maxResultsPerCategory` (4).

`SearchQuery` pre-computes `trimmed`/`lowercased` once. `AppInfo`/`SettingsItem`/`QuickAction` pre-compute their lowercased names, tokens, and initials at init. `FuzzyMatcher.score` consumes only these pre-computed forms so scoring allocates nothing — **do not add a `String`-taking convenience overload**; it would reintroduce per-keystroke lowercasing.

Scoring tiers are fixed and load-bearing (tests and the Top Hit `>= 60` threshold depend on them): exact 100, prefix 95, word-boundary prefix 85, initials 80, substring 65, subsequence 40.

### Adding a search provider

1. Add a case to `ResultCategory` (its `rawValue` order is the on-screen display order) and a `displayName`.
2. Add a case to `SearchAction` if the activation is a new kind of side effect.
3. Write the provider in `Core/` as a `shared` singleton exposing `search(_ query: SearchQuery) -> [SearchResult]`.
4. Call it from `SearchEngine.performSearch`.
5. Handle the new `SearchAction` case in `SearchViewModel.activateSelected` (the `switch` is exhaustive).

### Two view modes

`SearchViewModel.viewMode` is derived purely from whether the query is blank:
- **`.applications`** — a 7-column grid (`gridSelectedIndex`, `gridColumns = 7`) of recent apps followed by category sections; arrow keys move in 2D and Tab/⇧Tab cycle `AppCategory`.
- **`.searchResults`** — a flat wrapping list (`searchSelectedIndex`) over `SearchEngine.flatResults`; ←/→ are remapped to ↑/↓.

Two separate selection indices exist so switching modes does not scramble the other view's cursor. Both reset to 0 on every query change.

### Keyboard event routing

The search field keeps focus at all times; navigation keys are intercepted before the text view sees them. `SpotlightPanel` overrides `fieldEditor(_:for:)` to return a custom `SpotlightFieldEditor` (`NSTextView`) whose `doCommand(by:)` traps arrows, Tab/⇧Tab, Return, and Escape and forwards them as closures: field editor → panel closures → `AppDelegate` → view model. This is why the user can keep typing while arrowing through results.

`SpotlightFieldEditor` also re-implements ⌘A/C/V/X/Z itself in `performKeyEquivalent`, and `AppMain.setupMainMenu()` installs an Edit menu — both are needed because a `.nonactivatingPanel` never becomes the main window, so the responder chain does not deliver these normally.

### Never block the main thread from a view body

`SpotlightView`'s `...` menu and the status-bar menu display macOS Spotlight and
launch-at-login state. Reading that state for real is expensive — `launchctl
print-disabled` and `mdutil -s /` are spawned as subprocesses and waited on (~66 ms
each), and `SMAppService.mainApp.status` is a ~3 ms XPC round trip.

SwiftUI re-evaluates `Menu` content on **every** body pass, so reading them live cost
~136 ms of blocked main thread per keystroke. `SpotlightManager` and `AutoStartManager`
therefore expose an instant cached snapshot; the blocking probes are `nonisolated
private` and run only from `refreshState()` on a background queue. The snapshot is
persisted to `UserDefaults` so the first paint after relaunch is correct, and is
refreshed at launch, on panel show (`AppDelegate.refreshSystemState`), and in
`MenuBarController.menuWillOpen`. Setters update it optimistically and let the next
refresh reconcile.

Keep this shape when adding state to a menu: if a value costs more than a dictionary
lookup, cache it and refresh off-main. Anything read from a body runs on every
keystroke.

### Panel presentation

`SpotlightPanel` is a borderless, non-activating, `.floating` `NSPanel` with a clear background; all glass is drawn in SwiftUI via `VisualEffectBlur`. It positions itself on whichever screen contains the mouse. `updateHeight` animates by moving the origin so the panel grows downward from a fixed top edge.

Note the height constants are not unified: `SpotlightPanel.defaultHeight` is 560 (used for the initial frame and as the fixed `.frame` of `SpotlightView`), while `SearchViewModel.expandedHeight` is 530 and `compactHeight` is 68 drive the animation. Changing one without the others causes clipping or dead space.

The whole UI hardcodes `NSAppearance(named: .darkAqua)` and white-on-black colors — it does not follow the system light/dark setting.

### Memory discipline

Hiding the panel actively releases memory (`AppDelegate.hidePanel`): view model result arrays, the recent-apps cache, and `malloc_zone_pressure_relief`. App metadata is deliberately kept resident for zero-latency launch; icons live in an `NSCache` bounded to 512 entries. `AppScanner` prewarms the first 40 apps' icons at 52pt and 32pt after each scan. `LazyAppIconView` synchronously reads the cache in `init` for a flicker-free first frame and only falls back to async disk load on a miss.

`AppScanner` re-scans in the background when its cache is older than 60s (`refreshIfNeeded`, called on every panel show). It is `@unchecked Sendable` guarded by an `NSLock`; `RecentAppsManager` and `SearchViewModel` are `@MainActor`.

## Invariants

- **Never index user files.** The search scope is exactly: installed apps, the hardcoded System Settings list, quick actions, the calculator, and a Google fallback. `deep_verify.swift` asserts this. Do not add a filesystem or `NSMetadataQuery` provider.
- **No new dependencies and no Xcode project.** `Package.swift` uses `.unsafeFlags` for `-Osize -wmo`, which permanently blocks this package from being consumed as a dependency — that is intentional for an app target.
- Swift 6 language mode, macOS 13+ deployment target.
- `CalculatorEngine.evaluate` returns `nil` for anything that is not an evaluable expression — including a bare number and a bare word — so that typing an app name never produces a calculator card. Preserve this when extending the parser.
- Quick actions execute via `/usr/bin/osascript -e` or `/bin/sh -c` on a background queue, or `open:<path>`. Scripts are literals in `QuickActionsProvider.defaultActions` and never interpolate user input.
- `SpotlightManager` shells out to `PlistBuddy`, `launchctl`, `mdutil`, and `killall` to disable Apple's Spotlight. `setIndexing` prompts for admin via AppleScript. These mutate the user's system state — treat changes here as destructive and verify manually.
- Persisted state lives in `UserDefaults` under the `lightspot_` prefix (`lightspot_hotkey_option`, `lightspot_recent_app_bundle_ids`, `lightspot_auto_start_enabled`).
- Default hotkey is ⌘Space, which collides with system Spotlight unless the user disables it from the menu bar. `HotkeyManager.registerCurrentKey` only logs on failure — a silently non-responding hotkey usually means the collision, not a code bug.
