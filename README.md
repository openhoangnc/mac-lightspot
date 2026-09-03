# Lightspot 🔍

A lightweight, pixel-perfect replacement for macOS Spotlight built in pure Swift (no Xcode required).

Lightspot brings the modern floating pill design and translucent glass aesthetic of macOS Spotlight with instant responsiveness (< 1.0 ms search) and a strictly focused, developer-friendly search scope — **never indexing user files**.

---

## ✨ Features

- **Exact macOS Spotlight UI**: Floating translucent glass window (`NSVisualEffectView`), continuous squircle corners, compact pill search bar when empty, expanding into an animated two-column results and preview layout.
- **Multi-IDE Recent Projects**: Auto-detects and fuzzy searches recently opened workspaces across **VS Code**, **Cursor**, **Zed**, **JetBrains Suite** (IntelliJ IDEA, PyCharm, WebStorm, etc.), and **Sublime Text**.
  - `↵` (Return): Open in associated IDE
  - `⌘↵` (Command + Return): Open project directory in your preferred terminal
  - `⌥↵` (Option + Return): Reveal project directory in Finder
- **Process Killer & Port Terminator**: Interactive process manager triggered by `kill`.
  - Kill by port: `kill :3000` (auto-detects listening PID)
  - Kill by PID or app name: `kill 14205` or `kill safari`
  - `↵` Graceful termination (`SIGTERM`) · `⌥↵` Force kill (`SIGKILL`)
- **Default Browser Bookmarks & Open Tabs**: Direct, zero-redundancy integration for your default browser only (**Google Chrome**, **Safari**, **Firefox**, **Arc**, **Brave**, **Microsoft Edge**).
  - Shows full detail URLs (e.g. `partners.shopify.com/12345/stores`) with middle truncation.
  - Search by page title, domain, or URL path slugs (e.g. `dashboard`, `stores`, `issues`).
- **In-Memory Ephemeral Clipboard History**: Volatile RAM-only ring buffer (up to 50 items) accessed via `clip <query>`.
  - Zero disk writes for maximum security.
  - Automatically filters password manager concealed types (`1Password`, `Bitwarden`, etc.).
  - 1-click clipboard purge from the menu bar.
- **Quick Text Snippets**: Reusable text templates with variable expansion (`{{date}}`, `{{time}}`, `{{iso}}`, `{{uuid}}`, `{{clipboard}}`).
- **Mach / IOKit Hardware HUD**: Instant, zero-subprocess hardware diagnostics (`sys`, `cpu`, `ram`, `battery`, `uptime`):
  - CPU load % (normalized across all cores)
  - Memory usage (Active, Wired, Compressed, and Total Physical RAM)
  - Boot SSD free and total storage
  - Battery capacity % and AC charging state
  - System uptime via `sysctl`
- **Smart Math & Relaxed Conversions**: Full recursive-descent math evaluator with relaxed unit, currency, and number base conversions:
  - Temperature: `72F`, `20C`
  - Distance & Weight: `10km in mi`, `150lbs in kg`
  - Digital Storage: `16GB in MB`, `1TB in GB`
  - Currency: `$100 in EUR`, `50 GBP in USD`
  - Number bases: `0xFF in dec`, `255 in hex`, `0b1010 in dec`
- **Developer Utilities**: Offline generators, formatters, and encoders:
  - `uuid`: Generate UUID v4
  - `b64 <text>` / `b64d <hash>`: Base64 encode & decode
  - `urlencode <url>` / `urldecode <url>`: URL component encoding
  - `epoch` / `now`: Current Unix timestamps and human-readable dates
  - `hash sha256 <text>`: Instant SHA-256, SHA-1, and MD5 hashing
  - `#3498db`: Live color preview swatch with RGB / HSL / Hex copying
  - `jwt <token>`: Decodes and formats JWT header & payload
  - `json <raw>`: Pretty-prints and formats minified JSON
- **Modern Terminal Launcher Support**: Choose your preferred terminal from the menu bar:
  - **Apple Terminal**, **iTerm2**, **Ghostty**, **Warp**, **Kitty**, **WezTerm**, and **Alacritty**.
  - Context-aware **"Terminal in Finder Folder"** action detects the active Finder directory.
- **Multi-Engine Web Search**: Instant web search with built-in prefix shortcuts:
  - `gh <repo>` (GitHub), `yt <video>` (YouTube), `so <query>` (StackOverflow), `ddg <query>` (DuckDuckGo), `npm <pkg>`, `crates <crate>`, `wiki <article>`, `mdn <api>`, `brew <formula>`.
- **zsh History & Pinned Commands**: Search your `~/.zsh_history` (or `$HISTFILE`) with instant Terminal execution. Pin frequently used commands (`⌘P`) to keep them at the top.
- **macOS System Settings**: 30+ deep links (`x-apple.systempreferences:...`) directly opening settings panes.
- **Custom Commands**: Create and organize custom URL, Terminal, AppleScript, or shell actions with full parameter expansion (`⌘⇧C`).
- **Global Hotkey**: Configurable **`⌘Space`**, **`⌘⇧Space`**, or **`⌥Space`**.
- **Multi-Monitor Aware**: Automatically opens centered on the display containing your mouse cursor.

---

## 🛠️ Complete macOS Spotlight Management

Lightspot provides granular controls directly from the menu bar to disable or re-enable Apple's built-in Spotlight:

1. **Spotlight Shortcut (`⌘Space`)**: Disables/enables the built-in `⌘Space` shortcut in macOS symbolic hotkeys without root.
2. **Background Process (`com.apple.Spotlight`)**: Disables/enables the Spotlight GUI background agent via `launchctl`.
3. **File Indexing (`mdutil`)**: Disables/enables filesystem metadata indexing (`mds` / `mds_stores`) across all mounted volumes.
4. **1-Click Master Actions**:
   - **`Disable Everything (Shortcut + Process + Indexing)...`**: Completely shuts down all system Spotlight components.
   - **`Restore Default Spotlight...`**: Re-enables all components back to macOS factory defaults.

---

## 🚀 Building & Installing (No Xcode Required)

Lightspot is built with standard Swift tools and simple shell scripts.

### 1. Build
```bash
./build.sh
# or: make build
```
Compiles the release binary with `-Osize -wmo`, strips debug symbols, bundles `Info.plist` and high-res icons, and codesigns `build/Lightspot.app`.

### 2. Run
```bash
./run.sh
# or: make run
```

### 3. Install to `/Applications`
```bash
./install.sh
# or: make install
# (Use --user to install to ~/Applications)
```

### 4. Tests & Verification
```bash
# Core logic & engine tests (24 test suites)
swiftc -o /tmp/test_engine scripts/test_engine.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift && /tmp/test_engine

# Live system checks (84 checks)
swiftc -o /tmp/deep_verify scripts/deep_verify.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift && /tmp/deep_verify
```

---

## ⌨️ Shortcuts & Navigation

| Key | Action |
|---|---|
| **`⌘Space`** / **`⌘⇧Space`** | Summon or dismiss Lightspot anywhere (configurable) |
| **`↓` / `↑`** | Navigate through results |
| **`Return` (`↵`)** | Open selected application, project in IDE, run command, or copy calculation |
| **`⌘Return` (`⌘↵`)** | Open selected project in preferred Terminal |
| **`⌥Return` (`⌥↵`)** | Reveal project in Finder / Force kill selected process (`SIGKILL`) |
| **`⌘P`** | Pin / unpin selected Terminal History command |
| **`⌘⇧P`** | Open pinned commands manager overlay |
| **`⌘⇧C`** | Open custom commands manager overlay |
| **`⌘Y` / `⌘⇧H`** | Open search history manager overlay |
| **`Escape`** | Close overlays, clear search field, or dismiss Lightspot |
| **Click Outside** | Automatically dismisses the floating panel |

---

## 📁 Project Structure

```
mac-lightspot/
├── Package.swift                 # SPM manifest (Swift 6, macOS 13+)
├── Makefile                      # make build / run / install / uninstall / clean
├── build.sh                      # Standalone release build & .app packager
├── run.sh                        # Build & launch helper
├── install.sh                    # Install to /Applications or ~/Applications
├── uninstall.sh                  # Remove from Applications
├── README.md                     # Documentation
├── CLAUDE.md                     # Architecture & developer guide
├── Resources/
│   ├── Info.plist                # LSUIElement=1, AppleEvents permissions, bundle metadata
│   └── AppIcon.icns              # Multi-size macOS application icon
├── scripts/
│   ├── generate_icon.sh          # Programmatic icon generator (Core Graphics + iconutil)
│   ├── test_engine.swift         # Automated test runner (24 test suites)
│   └── deep_verify.swift         # Live-system verification (84 checks)
└── Sources/
    └── Lightspot/
        ├── AppMain.swift         # @main entry point & NSApplicationDelegate
        ├── Core/
        │   ├── Models.swift      # SearchResult, ResultCategory, SearchAction, FuzzyMatcher
        │   ├── AppScanner.swift  # Fast async app scanner & memory icon cache
        │   ├── BrowserIntegrationProvider.swift # Default browser bookmarks & tabs
        │   ├── CalculatorEngine.swift # Math parser & conversion dispatcher
        │   ├── ClipboardHistoryManager.swift    # In-memory ephemeral clipboard ring buffer
        │   ├── ConversionEngine.swift   # Unit, currency, base, & temperature engine
        │   ├── CustomCommandsStore.swift # Custom user commands model & persistence
        │   ├── DevToolsProvider.swift   # UUID, Base64, Hash, JWT, JSON, Color Swatch
        │   ├── NetworkInfoProvider.swift # Local IPv4 & public internet IP address
        │   ├── ProcessKillerProvider.swift # Name, PID, and port process terminator
        │   ├── QuickActionsProvider.swift # Focused system actions & Terminal in Finder
        │   ├── RecentProjectsProvider.swift # Multi-IDE project scanner (VS Code, Cursor, Zed, JetBrains, Sublime)
        │   ├── SearchEngine.swift       # Synchronous search aggregator & ranking
        │   ├── SearchHistoryManager.swift # Search query & selection history
        │   ├── SettingsBackup.swift     # Settings export & import backup
        │   ├── SettingsProvider.swift   # 30+ macOS System Settings deep links
        │   ├── ShellHistoryProvider.swift # zsh history parser & ranking
        │   ├── SnippetsStore.swift      # Text expansion snippets with variable interpolation
        │   ├── SystemInfoProvider.swift # Zero-subprocess Mach/IOKit hardware dashboard
        │   └── WebSearchProvider.swift  # Multi-engine search & prefix shortcuts
        ├── System/
        │   ├── HotkeyManager.swift      # Carbon global hotkey
        │   ├── MenuBarController.swift  # Menu bar status item & preferences
        │   ├── SpotlightManager.swift   # macOS Spotlight disable/restore automations
        │   └── TerminalLauncher.swift   # Launcher for 7 terminal emulators & Finder detection
        └── UI/
            ├── CustomCommandsView.swift # Custom command manager overlay
            ├── HistoryManagerView.swift # Search history manager overlay
            ├── PinnedCommandsView.swift # Pinned command manager overlay
            ├── PreviewPaneView.swift    # Rich details card & live previews
            ├── SearchFieldView.swift    # NSTextField bridge & custom field editor
            ├── SearchViewModel.swift    # Reactive view model & key event router
            ├── SpotlightComponents.swift# Search result rows, buttons, & category headers
            ├── SpotlightPanel.swift     # Floating borderless NSPanel with vibrancy
            └── SpotlightView.swift      # Root SwiftUI view
```

---

## 🔒 Privacy & Security

- **Zero User File Indexing**: Lightspot never indexes your personal documents, desktop, or downloads.
- **RAM-Only Clipboard**: Clipboard history stays exclusively in volatile memory and is never written to disk. Passwords and concealed items are automatically ignored.
- **Default Browser Isolation**: Bookmarks and tabs are read solely from your configured macOS default browser.
- **Sandboxed Subprocesses**: Commands and scripts run only upon explicit user action (`Return` or `⌘↵`).
- **Zero Telemetry**: No analytics, background telemetry, or third-party network requests.
