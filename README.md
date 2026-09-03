# Lightspot 🔍

A lightweight, pixel-perfect replacement for macOS Spotlight built in pure Swift (no Xcode required).

Lightspot brings the modern floating pill design and translucent glass aesthetic of macOS Spotlight with instant responsiveness and a strictly focused search scope: **Applications, System Settings, Quick Actions, Math Calculations, zsh History, and Web Search** — **never indexing user files**.

---

## ✨ Features

- **Exact macOS Spotlight UI**: Floating translucent glass window (`NSVisualEffectView`), continuous squircle corners, compact pill search bar when empty, expanding into a two-column results/preview view when typing.
- **Strict Search Scope (Zero File Indexing)**:
  - 🚀 **Applications**: Fast scanner for installed apps in `/Applications`, `/System/Applications`, `~/Applications`, and Utilities.
  - ⚙️ **macOS System Settings**: 30+ deep links (`x-apple.systempreferences:...`) directly opening settings panes with authentic SF Symbols.
  - ⚡️ **Quick Actions**: Lock Screen, Sleep, Restart, Shut Down, Empty Trash, Toggle Dark Mode, Mute/Unmute Volume, Screenshot, Activity Monitor, Force Quit.
  - 🖥️ **zsh History**: Searches your own `~/.zsh_history` (or `$HISTFILE`) — press `Return` to run the matching command in a new Terminal window. Pin the commands you use most with `⌘P` so they always rank first, and manage them in the pinned-commands sheet (`⌘⇧P`). Only that one file is ever read; no directory is scanned.
  - 🛠️ **Custom Commands**: Create, edit, and organize custom commands across 4 types — Open Web URLs in your browser, launch interactive commands in Terminal.app, execute AppleScript automations, or run background shell scripts. Manage them via the built-in sheet (`⌘⇧C`) or search and run them directly with Top Hit promotion.
  - 🔢 **Instant Calculator**: Safe, crash-free math evaluation (`+`, `-`, `*`, `/`, `^`, `%`, `sqrt`, `abs`, `sin`, `cos`, `tan`, `log`, `ln`, `pi`, `e`, parentheses) with live preview and clipboard copy.
  - 🌐 **Google Web Search**: Seamless fallback opening search queries in your default web browser.
- **Global Hotkey**: Supports **`⌘Space`** (Command + Space) as a direct replacement for Spotlight, or **`⌘⇧Space`** / **`⌥Space`** (configurable from menu bar). Zero Accessibility permissions required.
- **Multi-Monitor Aware**: Automatically opens on the display currently containing your mouse cursor.
- **Menu Bar Companion**: Discreet magnifying glass icon in the menu bar with status, hotkey selector, and quick options.
- **Simultaneous Typing & Navigation**: Continue typing in the search field while using `↑` and `↓` arrow keys to browse results. Press `Return` to activate, or `Escape` to clear/dismiss.

---

## 🛠️ Complete macOS Spotlight Management

Lightspot provides granular and 1-click controls directly from the menu bar to disable or re-enable all parts of macOS Spotlight:

1. **Spotlight Shortcut (`⌘Space`)**: Disables/enables the built-in `⌘Space` shortcut in macOS symbolic hotkeys without needing root.
2. **Background Process (`com.apple.Spotlight`)**: Disables/enables the Spotlight GUI background agent via `launchctl` and terminates running instances.
3. **File Indexing (`mdutil`)**: Disables/enables filesystem metadata indexing (`mds` / `mds_stores`) across all mounted volumes to eliminate background CPU and disk usage (prompts macOS Touch ID / admin password).
4. **1-Click Master Actions**:
   - **`Disable Everything (Shortcut + Process + Indexing)...`**: Completely shuts down all Spotlight components.
   - **`Restore Default Spotlight...`**: Re-enables all components back to macOS factory defaults.

To access these, click the **Lightspot magnifying glass icon** in your menu bar → **System Spotlight**.

---

## 🚀 Building & Running (No Xcode Required)

Lightspot is built with standard Swift tools and simple shell scripts.

### 1. Build
```bash
./build.sh
# or
make build
```
This compiles the release binary, packages `build/Lightspot.app`, bundles the icon and `Info.plist` (with `LSUIElement = 1` for background agent mode), and codesigns the app bundle.

### 2. Run
```bash
./run.sh
# or
make run
```

### 3. Install to `~/Applications`
```bash
./install.sh
# or
make install
```

### 4. Uninstall
```bash
./uninstall.sh
# or
make uninstall
```

### 5. Generate / Refresh App Icon
```bash
./scripts/generate_icon.sh
# or
make icon
```

---

## ⌨️ Shortcuts & Navigation

| Key | Action |
|---|---|
| **`⌘Space`** / **`⌘⇧Space`** | Summon or dismiss Lightspot anywhere (configurable) |
| **`↓` (Down Arrow)** | Move to next search result |
| **`↑` (Up Arrow)** | Move to previous search result |
| **`Return` (Enter)** | Open selected application, settings pane, run the selected history command in Terminal, or execute action |
| **`⌘P`** | Pin / unpin the selected Terminal History command |
| **`⌘⇧P`** | Open the pinned-commands manager (↑↓ select, `Return` run, `⌘P` unpin, `Esc` close) |
| **`⌘⇧C`** | Open the custom commands manager (↑↓ select, `Return` run, `+ New`, edit, `⌫` delete, `Esc` close) |
| **`Escape`** | Close overlays, clear search, or dismiss Lightspot |
| **Click Outside** | Auto-dismisses the floating panel |

---

## 📁 Project Structure

```
mac-lightspot/
├── Package.swift                 # SPM manifest (Swift 6, macOS 13+)
├── Makefile                      # make build / run / install / uninstall / clean
├── build.sh                      # Standalone release build & .app packager
├── run.sh                        # Build & launch helper
├── install.sh                    # Install to ~/Applications
├── uninstall.sh                  # Remove from ~/Applications
├── README.md                     # Documentation
├── Resources/
│   ├── Info.plist                # LSUIElement=1, bundle identifier, metadata
│   └── AppIcon.icns              # Generated high-res multi-size macOS app icon
├── scripts/
│   ├── generate_icon.sh          # Programmatic icon generator (Core Graphics + iconutil)
│   ├── test_engine.swift         # Automated test runner for core search & math engines
│   └── deep_verify.swift         # Live-system verification (deep links, AppleScript, history)
└── Sources/
    └── Lightspot/
        ├── AppMain.swift         # @main entry point & NSApplicationDelegate
        ├── Core/
        │   ├── Models.swift      # SearchResult, ResultCategory, FuzzyMatcher
        │   ├── AppScanner.swift  # Fast async app scanner & memory icon cache
        │   ├── SettingsProvider.swift # 30+ macOS System Settings deep links
        │   ├── QuickActionsProvider.swift # Async system actions
        │   ├── CustomCommandsStore.swift # Custom commands model, persistence & search
        │   ├── CalculatorEngine.swift # Safe recursive-descent math parser
        │   ├── ShellHistoryProvider.swift # zsh history parser, ranking & pinned commands
        │   ├── WebSearchProvider.swift # Google search query builder
        │   └── SearchEngine.swift # Fuzzy scoring, ranking, & top-hit aggregator
        ├── System/
        │   ├── HotkeyManager.swift # Carbon global hotkey (⌘⇧Space)
        │   ├── TerminalLauncher.swift # Escaped `do script` runner for Terminal.app
        │   └── MenuBarController.swift # Menu bar status item
        └── UI/
            ├── SearchViewModel.swift # Reactive view model
            ├── SpotlightPanel.swift # Floating borderless NSPanel with vibrancy
            ├── SpotlightView.swift # Root SwiftUI container
            ├── SearchFieldView.swift # AppKit NSTextField bridge with custom field editor
            ├── ResultsListView.swift # Grouped categories list view
            ├── ResultRowView.swift # Individual result row with accent highlight
            ├── PinnedCommandsView.swift # Pinned command manager sheet
            ├── CustomCommandsView.swift # Custom command manager & editor overlay
            └── PreviewPaneView.swift # Rich preview details card
```

---

## 🔒 Privacy & Security

- **No File Indexing**: Lightspot never reads, indexes, or searches your documents, downloads, desktop files, or personal data. The single exception is your own shell history file (`~/.zsh_history`), which powers the Terminal History results — only its last 2 MB are read, they are kept in memory only, and Lightspot never writes to your history file and never sends any of it anywhere.
- **Commands Run Only On Return**: A history result is executed only when you explicitly activate it, in a visible Terminal window, and it is never promoted to the Top Hit so `Return` on a normal search can never run a shell command by accident.
- **Zero Network Tracking**: Lightspot has no analytics or background network requests. Web searches are only performed when explicitly opened in your default browser.
