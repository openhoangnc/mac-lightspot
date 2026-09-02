# Lightspot 🔍

A lightweight, pixel-perfect replacement for macOS Spotlight built in pure Swift (no Xcode required).

Lightspot brings the modern floating pill design and translucent glass aesthetic of macOS Spotlight with instant responsiveness and a strictly focused search scope: **Applications, System Settings, Quick Actions, Math Calculations, and Web Search** — **never indexing user files**.

---

## ✨ Features

- **Exact macOS Spotlight UI**: Floating translucent glass window (`NSVisualEffectView`), continuous squircle corners, compact pill search bar when empty, expanding into a two-column results/preview view when typing.
- **Strict Search Scope (Zero File Indexing)**:
  - 🚀 **Applications**: Fast scanner for installed apps in `/Applications`, `/System/Applications`, `~/Applications`, and Utilities.
  - ⚙️ **macOS System Settings**: 30+ deep links (`x-apple.systempreferences:...`) directly opening settings panes with authentic SF Symbols.
  - ⚡️ **Quick Actions**: Lock Screen, Sleep, Restart, Shut Down, Empty Trash, Toggle Dark Mode, Mute/Unmute Volume, Screenshot, Activity Monitor, Force Quit.
  - 🔢 **Instant Calculator**: Safe, crash-free math evaluation (`+`, `-`, `*`, `/`, `^`, `%`, `sqrt`, `abs`, `sin`, `cos`, `tan`, `log`, `ln`, `pi`, `e`, parentheses) with live preview and clipboard copy.
  - 🌐 **Google Web Search**: Seamless fallback opening search queries in your default web browser.
- **Global Hotkey**: Supports **`⌘Space`** (Command + Space) as a direct replacement for Spotlight, or **`⌘⇧Space`** / **`⌥Space`** (configurable from menu bar). Zero Accessibility permissions required.
- **Multi-Monitor Aware**: Automatically opens on the display currently containing your mouse cursor.
- **Menu Bar Companion**: Discreet magnifying glass icon in the menu bar with status, hotkey selector, and quick options.
- **Simultaneous Typing & Navigation**: Continue typing in the search field while using `↑` and `↓` arrow keys to browse results. Press `Return` to activate, or `Escape` to clear/dismiss.

---

## ⌨️ Using `⌘Space` as Spotlight Replacement

To have Lightspot fully replace macOS Spotlight on **`⌘Space`**:

1. Open **System Settings** → **Keyboard** → **Keyboard Shortcuts...**
2. Click **Spotlight** in the left sidebar.
3. Uncheck **"Show Spotlight search"** (or change its shortcut).
4. In Lightspot's menu bar icon → **Shortcut** → select **`⌘Space (Command + Space)`**.

Now pressing **`⌘Space`** opens Lightspot instantly!

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
| **`Return` (Enter)** | Open selected application, settings pane, or execute action |
| **`Escape`** | Clear search field, or dismiss Lightspot if empty |
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
│   └── test_engine.swift         # Automated test runner for core search & math engines
└── Sources/
    └── Lightspot/
        ├── AppMain.swift         # @main entry point & NSApplicationDelegate
        ├── Core/
        │   ├── Models.swift      # SearchResult, ResultCategory, FuzzyMatcher
        │   ├── AppScanner.swift  # Fast async app scanner & memory icon cache
        │   ├── SettingsProvider.swift # 30+ macOS System Settings deep links
        │   ├── QuickActionsProvider.swift # Async system actions
        │   ├── CalculatorEngine.swift # Safe recursive-descent math parser
        │   ├── WebSearchProvider.swift # Google search query builder
        │   └── SearchEngine.swift # Fuzzy scoring, ranking, & top-hit aggregator
        ├── System/
        │   ├── HotkeyManager.swift # Carbon global hotkey (⌘⇧Space)
        │   └── MenuBarController.swift # Menu bar status item
        └── UI/
            ├── SearchViewModel.swift # Reactive view model
            ├── SpotlightPanel.swift # Floating borderless NSPanel with vibrancy
            ├── SpotlightView.swift # Root SwiftUI container
            ├── SearchFieldView.swift # AppKit NSTextField bridge with custom field editor
            ├── ResultsListView.swift # Grouped categories list view
            ├── ResultRowView.swift # Individual result row with accent highlight
            └── PreviewPaneView.swift # Rich preview details card
```

---

## 🔒 Privacy & Security

- **No File Indexing**: Lightspot never reads, indexes, or searches your documents, downloads, desktop files, or personal data.
- **Zero Network Tracking**: Lightspot has no analytics or background network requests. Web searches are only performed when explicitly opened in your default browser.
