# Lightspot 🔍

[English](README.md) | [简体中文](README_zh-CN.md) | [Español](README_es.md) | [日本語](README_ja.md) | [Français](README_fr.md)

> **A lightweight, pixel-perfect replacement for macOS Spotlight built in pure Swift — designed for developers and power users who want instant speed without the file indexing bloat.**

Lightspot faithfully reproduces the modern floating pill design and translucent glass aesthetic of macOS Spotlight (`NSVisualEffectView`). Under the hood, it delivers sub-millisecond responsiveness (< 1.0 ms search) with **zero background file indexing**, consuming **0.0% idle CPU** and under **25 MB of RAM**.

![Lightspot Screenshot](screenshot.png)

---

## ⚡ Quick Start

### 📦 One-Line Download & Install
Run this in your Terminal to download, extract, and install the latest **Lightspot** into `/Applications`:

```bash
curl -fsSL https://raw.githubusercontent.com/openhoangnc/mac-lightspot/main/install.sh | bash
```

*(Optional: Pass `--user` to install into `~/Applications` instead: `curl -fsSL https://raw.githubusercontent.com/openhoangnc/mac-lightspot/main/install.sh | bash -s -- --user`)*

---

### 🗑️ Complete Uninstallation
To completely remove Lightspot, unregister auto-start, clear preferences, and delete the app bundle:

```bash
curl -fsSL https://raw.githubusercontent.com/openhoangnc/mac-lightspot/main/uninstall.sh | bash
```

---

## 💡 Why Lightspot?

Apple's built-in Spotlight was designed for casual file searching. But for developers and power users, Spotlight's background processes often create severe system friction. **Lightspot is built to solve this.**

### The Problem: Apple Spotlight

1. **CPU & Battery Drain:** Background daemons (`mds`, `mdworker`) aggressively index files. A simple `npm install` or `git checkout` can peg your CPU at 100%, spinning up fans and killing battery life.
2. **Missing Applications:** Spotlight's index frequently corrupts, causing it to fail at its most basic job: finding apps like Terminal or Slack. Fixing it requires running obscure `mdutil` commands to rebuild the index from scratch.
3. **Bloated Disk Usage:** Spotlight silently caches metadata in a hidden `/.Spotlight-V100` folder. On developer machines, this index regularly balloons to **50GB–200GB**, wasting expensive SSD storage.
4. **Memory Hoarding:** Spotlight processes frequently leak and consume gigabytes of unified RAM—memory that should be available for your IDE, Docker, or local LLMs.
5. **Unwanted File Crawling:** Excluding massive folders like `node_modules`, `.git`, or `.venv` via System Settings is notoriously clunky, slow, and often resets during macOS updates.

*(See community reports: [High CPU](https://www.reddit.com/r/MacOS/comments/1p10c3f/pages_caused_insane_cpu_spikes_on_macos_i_think_i/), [Missing Apps](https://www.reddit.com/r/MacOS/comments/1gjhiha/spotlight_not_looking_for_apps/), [Storage Waste](https://dev.to/vvo/how-to-avoid-spotlight-using-hundreds-of-gbs-and-rebuild-its-index-4kki), [Memory Leaks](https://discussions.apple.com/thread/256167358?sortBy=rank))*

---

## ⚡ The Solution: Zero-Indexing Architecture

Lightspot fixes these problems by taking a fundamentally different approach: **Zero background file indexing.** 

Instead of aggressively crawling your entire hard drive, Lightspot focuses strictly on what power users actually search for: Applications, IDE Projects, Browser Tabs, Developer Utilities, and Custom Commands.

### Comparison Matrix

| Metric | Apple Spotlight | Raycast / Alfred | Lightspot 🔍 |
|:---|:---|:---|:---|
| **File Indexing** | Uncontrolled background crawling | Optional / Configurable | **Never** (By architectural guarantee) |
| **Idle CPU Usage** | Spikes to 100%+ during operations | 1% – 5% background | **0.0%** (sleeps completely) |
| **Disk Storage** | 10 GB – 200 GB+ hidden cache | 100 MB – 1 GB | **0 KB** (Zero disk footprint) |
| **RAM Footprint** | 500 MB – 2 GB+ | 200 MB – 500 MB | **~15 – 25 MB** (Pure Swift) |
| **App Launching** | Frequently breaks; requires rebuilds | Reliable | **100% Reliable** (Direct scanning) |
| **Search Latency** | Debounced (50 – 200 ms) | 10 – 30 ms | **< 1.0 ms** (instant synchronous) |
| **Offline Privacy** | Sends Siri telemetry to Apple | Account required for sync | **100% Local, Offline & Telemetry-Free** |

---

## 🛠️ Developer-First Customization & Power User Workflows

Lightspot was designed from the ground up as a developer\'s primary command center. Every aspect can be molded to your exact terminal, editor, script, and workflow needs:

### 1. ⚡ Custom Commands & Script Runners (`⌘⇧C`)
Open the interactive Custom Command Editor with **`⌘⇧C`** to create and organize custom shortcuts:
- **4 Runner Engines**:
  - `terminal`: Executes the command directly in your preferred terminal emulator.
  - `shell`: Executes headless in the background via `/bin/zsh`.
  - `applescript`: Executes native macOS AppleScript automations.
  - `url`: Opens templated URLs in your default browser.
- **Dynamic Parameter Expansion**:
  - Use `{query}`, `%s`, or `%@` to substitute whatever arguments you type after the command.
- **Prefix Triggers**:
  - Bind custom 1-3 letter prefixes (e.g. `dlog <container>` to follow docker logs, `c <url>` to curl headers, `png <host>` to ping).
- **Custom Keywords & Icons**:
  - Add fuzzy keywords for instant discovery and customize icons using SF Symbols or base64 app icons.

### 2. 💬 Dynamic Text Snippets (`⌘P` / `snippets`)
Define reusable text snippets with automatic dynamic variable expansion:
- `{{date}}`: Current date (`YYYY-MM-DD`)
- `{{time}}`: Current time (`HH:mm:ss`)
- `{{iso}}`: ISO 8601 UTC timestamp (`2026-09-05T14:30:00Z`)
- `{{uuid}}`: Random UUID v4
- `{{clipboard}}`: Current contents of your clipboard

Type any snippet keyword (e.g. `iso`, `uuid`, `date`) and press **`↵`** to copy the evaluated string straight to your clipboard.

### 3. 💻 Choose From 7 Modern Terminal Emulators
Lightspot integrates with your favorite terminal emulator. Switch anytime via the menu bar:
- **Ghostty**, **Warp**, **Alacritty**, **iTerm2**, **Kitty**, **WezTerm**, and **Apple Terminal**.
- **"Terminal in Finder Folder"**: Type `term` or press the action to instantly launch your preferred terminal inside the directory currently open in Finder.

### 4. 📂 Multi-IDE Recent Projects Discovery
Lightspot automatically monitors recent workspaces across:
- **VS Code**, **Cursor**, **Zed**, **JetBrains Suite** (IntelliJ IDEA, WebStorm, PyCharm, CLion, GoLand, Rider, etc.), and **Sublime Text**.
- **Keyboard Modifiers**:
  - `↵` (Return): Open workspace in its associated IDE.
  - `⌘↵` (Command + Return): Launch your preferred terminal at the project root directory.
  - `⌥↵` (Option + Return): Reveal the project folder in Finder.

### 5. 🔌 Process Killer & Port Terminator (`kill`)
Quickly terminate lingering dev servers, stuck background tasks, or rogue processes:
- **Kill by port:** `kill :3000`, `kill :8080`, `kill :5173` (automatically resolves the listening PID via `lsof`).
- **Kill by process name or PID:** `kill node`, `kill python`, `kill 14205`.
- **Termination levels:**
  - `↵` (Return): Graceful termination (`SIGTERM`).
  - `⌥↵` (Option + Return): Force kill (`SIGKILL`).

### 6. 🛠️ Built-in Offline Developer Utilities (DevTools)
Perform common developer operations in milliseconds without opening web utilities or installing CLI packages:
- **`uuid`**: Generates a cryptographically random UUID v4.
- **`b64 <text>`** / **`b64d <hash>`**: Base64 encode and decode.
- **`urlencode <url>`** / **`urldecode <url>`**: URL percent-encoding.
- **`hash sha256 <text>`** / **`sha1`** / **`md5`**: Instant cryptographic checksums.
- **`jwt <token>`**: Decodes and pretty-prints JWT headers and payload.
- **`json <raw>`**: Formats, indents, and validates minified JSON.
- **`epoch`** / **`now`**: Unix timestamp conversion to human dates and vice-versa.
- **`#3498db`**: Live color preview swatch with 1-click Hex, RGB, and HSL copying.

### 7. 🔐 Headless Touch ID for Sudo & Privileged Actions
Execute privileged maintenance actions (`Flush DNS Cache`, `Purge Inactive Memory`) with biometric fingerprint authentication:
- **No Terminal Popups**: Runs via a background pseudo-terminal (PTY) invoking macOS `pam_tid.so` for instant Touch ID authentication.
- **Toggle Touch ID for Sudo in Terminal**: 1-click menu action to configure `/etc/pam.d/sudo_local` so your regular terminal `sudo` commands can also use Touch ID.

### 8. 📜 zsh History & Pinned Commands (`⌘P` / `⌘⇧P`)
- Search your local `~/.zsh_history` (or custom `$HISTFILE`) with instant sub-millisecond ranking.
- Press **`⌘P`** on any history command to pin it to the top of your launcher.
- Press **`⌘⇧P`** to manage, reorder, or delete pinned commands.

### 9. 📦 Settings Backup & Cross-Machine Sync
- Export your entire configuration (custom commands, pinned items, snippets, hotkeys) to a clean JSON file.
- Automatic path sanitization replaces `/Users/username` with `~` so configurations can be shared seamlessly across work and personal Macs.

---

## ✨ Additional Built-in Capabilities

- **Exact macOS Spotlight UI**: Floating translucent squircle pill with animated expansion and preview pane (`NSVisualEffectView`).
- **Mach / IOKit Hardware HUD**: Instant, zero-subprocess hardware diagnostics (`sys`, `cpu`, `ram`, `battery`, `uptime`):
  - Normalized multi-core CPU load %
  - Active, Wired, Compressed, and Total Physical RAM
  - Boot SSD free and total storage
  - Battery percentage and charging status
- **Smart Math & Relaxed Conversions**: Full recursive-descent math parser supporting units, currencies, and number bases:
  - Math: `(25 * 4) + sqrt(144)`, `2^16`, `log(1000)`
  - Units: `100km in mi`, `72F in C`, `16GB in MB`
  - Currency: `$100 in EUR`, `50 GBP in USD`
  - Number bases: `0xFF in dec`, `255 in hex`, `0b1010 in dec`
- **Default Browser Bookmarks & Tabs**: Zero-redundancy bookmark and open tab integration for your active default browser only (**Chrome**, **Safari**, **Firefox**, **Arc**, **Brave**, **Edge**).
- **In-Memory Ephemeral Clipboard**: Volatile RAM-only ring buffer (up to 50 items) accessed via `clip <query>`. Never writes to disk and strictly filters password managers (`1Password`, `Bitwarden`).
- **macOS System Settings Deep Links**: 35+ direct deep links opening specific macOS settings panes (`x-apple.systempreferences:...`).
- **Multi-Engine Web Search**: Built-in prefix shortcuts: `gh` (GitHub), `so` (StackOverflow), `npm`, `crates`, `wiki`, `mdn`, `brew`, `yt`, `ddg`.

---

## 🛑 Complete macOS Spotlight Management

Lightspot includes built-in automations in the menu bar to disable or re-enable Apple\'s built-in Spotlight:

1. **Spotlight Shortcut (`⌘Space`)**: Disables or restores Apple\'s default `⌘Space` hotkey in macOS symbolic hotkeys without requiring root.
2. **Background Process (`com.apple.Spotlight`)**: Disables or enables the Spotlight GUI background agent via `launchctl`.
3. **File Indexing (`mdutil`)**: Completely shuts down filesystem metadata indexing (`mds` / `mds_stores`) across all mounted volumes.
4. **1-Click Master Actions**:
   - **`Disable Everything (Shortcut + Process + Indexing)...`**: Completely shuts down Apple Spotlight to reclaim CPU, RAM, disk space, and `⌘Space`.
   - **`Restore Default Spotlight...`**: Reverts every setting back to factory macOS defaults at any time.

---

## 🚀 Building & Installing (No Xcode Required)

### 📦 Option A: One-Line Install (Recommended)
Download and install the latest prebuilt release directly:
```bash
curl -fsSL https://raw.githubusercontent.com/openhoangnc/mac-lightspot/main/install.sh | bash
```

### 🛠️ Option B: Build from Source (Local Checkout)
```bash
# 1. Build release bundle
./build.sh
# or: make build

# 2. Run directly
./run.sh
# or: make run

# 3. Install to /Applications (or ~/Applications with --user)
./install.sh
# or: make install

# 4. Uninstall
./uninstall.sh
# or: make uninstall
```

### 4. Tests & Verification
Lightspot includes 112 automated test suites and live-system runtime checks:
```bash
# Core logic & engine tests (24 test suites)
swiftc -o /tmp/test_engine scripts/test_engine.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift && /tmp/test_engine

# Live system checks (88 verification checks)
swiftc -o /tmp/deep_verify scripts/deep_verify.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift && /tmp/deep_verify
```

---

## ⌨️ Shortcuts & Navigation

| Key | Action |
|---|---|
| **`⌘Space`** / **`⌘⇧Space`** | Summon or dismiss Lightspot anywhere (configurable in menu bar) |
| **`↓` / `↑`** | Navigate through search results |
| **`Return` (`↵`)** | Open selected app, project in IDE, run command, or copy calculation |
| **`⌘Return` (`⌘↵`)** | Open selected project in preferred Terminal |
| **`⌥Return` (`⌥↵`)** | Reveal project in Finder / Force kill selected process (`SIGKILL`) |
| **`⌘P`** | Pin or unpin selected Terminal History command |
| **`⌘⇧P`** | Open pinned commands manager overlay |
| **`⌘⇧C`** | Open custom commands manager overlay |
| **`⌘Y` / `⌘⇧H`** | Open search history manager overlay |
| **`Escape`** | Dismiss overlays, clear search field, or close Lightspot |
| **Click Outside** | Automatically dismisses the floating panel |

---

## 🔒 Privacy & Security Guarantees

- **Zero File Indexing**: Lightspot never indexes your personal files, documents, downloads, or code repositories.
- **RAM-Only Ephemeral Clipboard**: Clipboard history stays exclusively in volatile memory (never written to disk) and actively ignores concealed/password manager types (`org.nspasteboard.ConcealedType`, `1Password`, `Bitwarden`).
- **Default Browser Isolation**: Bookmarks and tabs are read solely from your configured default browser, avoiding cross-browser scraping.
- **Sandboxed Subprocesses**: Commands and scripts run only upon explicit user action (`Return` or `⌘↵`).
- **Zero Telemetry & 100% Offline**: No network requests, no remote analytics, no tracking.
