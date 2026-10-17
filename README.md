# Lightspot 🔍

[English](README.md) | [简体中文](README_zh-CN.md) | [Español](README_es.md) | [日本語](README_ja.md) | [Français](README_fr.md)

> **A lightweight, pixel-perfect replacement for macOS Spotlight built in pure Swift — designed for developers and power users who want instant speed without the file indexing bloat.**

Lightspot faithfully reproduces the modern floating pill design and translucent glass aesthetic of macOS Spotlight (`NSVisualEffectView`). Under the hood, it delivers sub-millisecond responsiveness (< 1.0 ms search) with **zero background file indexing**. While idle its only recurring work is a lightweight clipboard check every 0.6 s, and it uses under **25 MB of RAM**.

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
To completely remove Lightspot, unregister auto-start, clear preferences, delete the app bundle, and turn Apple Spotlight back on if Lightspot switched it off (re-enabling indexing asks for your administrator password, or prints the `sudo mdutil -a -i on` command to run later):

```bash
curl -fsSL https://raw.githubusercontent.com/openhoangnc/mac-lightspot/main/uninstall.sh | bash
```

*(Optional: `curl -fsSL https://raw.githubusercontent.com/openhoangnc/mac-lightspot/main/uninstall.sh | bash -s -- --dry-run` shows what would change without changing anything; pass `--keep-spotlight-disabled` instead to leave Spotlight off.)*

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

Instead of aggressively crawling your entire hard drive, Lightspot focuses strictly on what power users actually search for: Applications, IDE Projects, Browser Tabs, Bookmarks & History, Developer Utilities, and Custom Commands.

### Comparison Matrix

| Metric | Apple Spotlight | Raycast / Alfred | Lightspot 🔍 |
|:---|:---|:---|:---|
| **File Indexing** | Uncontrolled background crawling | Optional / Configurable | **Never** (By architectural guarantee) |
| **Idle CPU Usage** | Spikes to 100%+ during operations | 1% – 5% background | **Minimal** (no indexing; only a 0.6 s clipboard check) |
| **Disk Storage** | 10 GB – 200 GB+ hidden cache | 100 MB – 1 GB | **No index or cache** (your settings in `UserDefaults` and a lock file) |
| **RAM Footprint** | 500 MB – 2 GB+ | 200 MB – 500 MB | **~15 – 25 MB** (Pure Swift) |
| **App Launching** | Frequently breaks; requires rebuilds | Reliable | **100% Reliable** (Direct scanning) |
| **Search Latency** | Debounced (50 – 200 ms) | 10 – 30 ms | **< 1.0 ms** (instant synchronous) |
| **Offline Privacy** | Sends Siri telemetry to Apple | Account required for sync | **Local & Telemetry-Free** (network only for an optional update check and an IP lookup you ask for) |

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
  - Give a command your own prefix, then type `<prefix> <query>` (e.g. `c <url>` to curl headers, `png <host>` to ping). The editor's **Presets** menu offers nine ready-made commands: `gh`, `g`, `yt`, `so`, `ddg`, `wiki`, `npm`, `png` and `c`.
- **Custom Keywords & Icons**:
  - Add fuzzy keywords for instant discovery. A command's icon defaults to its runner's app icon (your browser, terminal or Script Editor); you can switch to the runner's built-in symbol or pick your own image or app file.

### 2. 💬 Dynamic Text Snippets
Lightspot ships with five text snippets — `date`, `iso`, `uuid`, `shrug` and `flip` — and expands dynamic variables at the moment you copy one:
- `{{date}}`: Current date (`YYYY-MM-DD`)
- `{{time}}`: Current time (`HH:mm:ss`)
- `{{iso}}`: ISO 8601 UTC timestamp (`2026-09-05T14:30:00Z`)
- `{{uuid}}`: Random UUID v4
- `{{clipboard}}`: Current contents of your clipboard

Type a snippet keyword (e.g. `iso`, `uuid`, `date`) or part of its name and press **`↵`** to copy the evaluated string straight to your clipboard.

### 3. 💻 Choose From 7 Modern Terminal Emulators
Lightspot integrates with your favorite terminal emulator. Switch anytime via the menu bar:
- **Ghostty**, **Warp**, **Alacritty**, **iTerm2**, **Kitty**, **WezTerm**, and **Apple Terminal**. (Warp opens folders, but it cannot be handed a command from another app, so with Warp selected, history, pinned and custom terminal commands run in Apple Terminal.)
- **"Terminal in Finder Folder"**: Type `term` or press the action to instantly launch your preferred terminal inside the directory currently open in Finder.

### 4. 📂 Multi-IDE Recent Projects Discovery
Lightspot automatically monitors recent workspaces across:
- **VS Code**, **Cursor**, **Zed**, **JetBrains IDEs** (IntelliJ IDEA, PyCharm — Community editions included — WebStorm, GoLand, CLion, RustRover, Rider, PhpStorm, DataGrip, RubyMine, DataSpell), **Android Studio**, and **Sublime Text**.
- **Keyboard Modifiers**:
  - `↵` (Return): Open workspace in its associated IDE.
  - `⌘↵` (Command + Return): Launch your preferred terminal at the project root directory.
  - `⌥↵` (Option + Return): Reveal the project folder in Finder.

### 5. 🔌 Process Killer & Port Terminator (`kill`)
Quickly terminate lingering dev servers, stuck background tasks, or rogue processes:
- **Kill by port:** `kill :3000`, `kill :8080`, `kill :5173` (resolves the process *listening* on the port via `lsof`; clients merely connected to it are not listed).
- **Kill by process name or PID:** `kill node`, `kill python`, `kill 14205`. System processes (`launchd`, `kernel_task`, `WindowServer`, `loginwindow`) and Lightspot itself are never offered.
- **Termination levels:**
  - `↵` (Return): Graceful termination (`SIGTERM`).
  - `⌥↵` (Option + Return): Force kill (`SIGKILL`).

### 6. 🛠️ Built-in Offline Developer Utilities (DevTools)
Perform common developer operations in milliseconds without opening web utilities or installing CLI packages:
- **`uuid`**: Generates a cryptographically random UUID v4.
- **`b64 <text>`** / **`b64d <base64>`** (or **`b64 decode <base64>`**): Base64 encode and decode.
- **`urlencode <url>`** / **`urldecode <url>`**: URL percent-encoding.
- **`hash <text>`** / **`hash sha256|sha1|md5 <text>`**: Instant cryptographic checksums — all three at once, or only the algorithm you name.
- **`jwt <token>`**: Decodes and pretty-prints JWT headers and payload.
- **`json <raw>`**: Formats, indents, and validates minified JSON.
- **`epoch`** / **`now`**: Current Unix timestamp; **`epoch <timestamp>`** converts it to a human date, and **`epoch 2024-01-15 10:30`** converts back (local time, or ISO 8601 with a zone).
- **`#3498db`**: Live color preview swatch with 1-click Hex, RGB, and HSL copying.

### 7. 🔐 Headless Touch ID for Sudo & Privileged Actions
Execute privileged maintenance actions (`Flush DNS Cache`, `Purge Inactive Memory`) with biometric fingerprint authentication:
- **No Terminal Popups**: Runs via a background pseudo-terminal (PTY) invoking macOS `pam_tid.so` for instant Touch ID authentication.
- **Toggle Touch ID for Sudo in Terminal**: A searchable Quick Action (type `touch id` or `sudo`) that edits `/etc/pam.d/sudo_local`, after an administrator authorization prompt, so your regular terminal `sudo` commands can also use Touch ID. Its subtitle shows whether Touch ID for sudo is currently enabled.

### 8. 📜 zsh History & Pinned Commands (`⌘P` / `⌘⇧P`)
- Search your local `~/.zsh_history` (or custom `$HISTFILE`) with instant sub-millisecond ranking.
- Press **`⌘P`** on any history command to pin it to the top of your launcher.
- Press **`⌘⇧P`** to manage, reorder, or delete pinned commands.

### 9. 📦 Settings Backup & Cross-Machine Sync
- Use **Export Settings…** / **Import Settings…** in the menu bar to move your configuration to a clean JSON file and back. It covers custom commands, pinned shell commands, search history and ranking, recent apps, and preferences (global hotkey, launch at login, menu bar icon visibility, browser history window). Text snippets, your preferred terminal and your default web search engine are not included.
- Automatic path sanitization replaces `/Users/username` with `~` so configurations can be shared seamlessly across work and personal Macs.

### 10. 🔄 Built-in Auto-Update
- Checks GitHub Releases in the background (shortly after launch and when you open the menu bar menu) and offers the new version from the menu bar. After a successful check it waits a day before the next one; a failed check (offline, rate-limited) is retried at the next launch or menu open. **Check for Updates...** runs it on demand, and **Automatically Check for Updates** turns automatic checks off entirely.
- Installs in place: Lightspot downloads the release, verifies it, swaps its own bundle and relaunches. **Skip This Version** silences one release without disabling checks.
- Every download is gated: HTTPS only, GitHub hosts only (re-checked after redirects), the unpacked bundle must carry Lightspot's bundle identifier, a runnable executable and exactly the advertised version, and a build older than the one installed is never accepted.
- Releases are ad-hoc signed (this project ships no Developer ID), so there is no code signature to verify — the checks above and HTTPS to GitHub are the whole trust model, the same one `install.sh` already asks for.

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
- **Default Browser Bookmarks, History & Tabs**: Zero-redundancy integration for your active default browser only (**Chrome**, **Safari**, **Firefox**, **Arc**, **Brave**, **Edge**). Bookmarks and recent history are read from the browser's own files (history covers the last 3 or 7 days, 7 by default, or can be turned off via **Browser History** in the menu bar); open tabs are queried from Safari and Chromium-based browsers.
- **In-Memory Ephemeral Clipboard**: Volatile RAM-only ring buffer (up to 50 items) accessed via `clip <query>`. Never writes to disk and strictly filters password managers (`1Password`, `Bitwarden`).
- **macOS System Settings Deep Links**: 35 direct deep links opening specific macOS settings panes (`x-apple.systempreferences:...`).
- **Multi-Engine Web Search**: Built-in prefix shortcuts: `g` (Google), `gh` (GitHub), `so` (StackOverflow), `npm`, `crates`, `wiki`, `mdn`, `yt`, `ddg`, plus `brew <formula>`, which opens that formula's page on formulae.brew.sh rather than running a search.

---

## 🛑 Complete macOS Spotlight Management

Lightspot includes built-in automations in the menu bar to disable or re-enable Apple\'s built-in Spotlight:

1. **Spotlight Shortcut (`⌘Space`)**: Disables or restores Apple's default Spotlight hotkeys — both `⌘Space` ("Show Spotlight search") and `⌥⌘Space` ("Show Finder search window") — without requiring root. The change is written through the preferences daemon, verified by reading it back, and applied immediately (no logout), and Lightspot claims `⌘Space` for itself as soon as macOS lets go of it.
2. **Background Process (`com.apple.Spotlight`)**: Disables or enables the Spotlight GUI background agent via `launchctl`. Enabling also loads and starts the agent, so Spotlight is back without logging out.
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
Lightspot has no XCTest target. Two standalone scripts under `scripts/` are compiled ad hoc against the sources: a logic and engine test runner (33 test blocks) and a live-system verifier (10 sections, 88 checks on a fully equipped machine; a few are skipped if, for example, there is no zsh history or VS Code installation):
```bash
# Core logic & engine tests (33 test blocks)
swiftc -o /tmp/test_engine scripts/test_engine.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift Sources/Lightspot/System/AutoStartManager.swift Sources/Lightspot/System/SpotlightManager.swift Sources/Lightspot/System/FirstRunManager.swift Sources/Lightspot/System/UpdateManager.swift Sources/Lightspot/System/SingleInstanceGuard.swift Sources/Lightspot/System/LegacyNetworkStores.swift && /tmp/test_engine

# Live system checks (10 sections, 88 checks on a fully equipped machine)
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
- **RAM-Only Ephemeral Clipboard**: Clipboard history stays exclusively in volatile memory and actively ignores concealed/password manager types (`org.nspasteboard.ConcealedType`, `1Password`, `Bitwarden`). It is never written to disk, not even into search history, which also never keeps the text you copy from calculator, dev-tool or snippet results.
- **Default Browser Isolation**: Bookmarks, open tabs and recent history are read locally and solely from your configured default browser, avoiding cross-browser scraping.
- **User-Triggered Commands**: Your commands, scripts and quick actions run only upon explicit user action (`Return` or `⌘↵`).
- **No Telemetry, Two Services You Control**: No analytics, no tracking, no accounts. Lightspot itself talks to exactly two services, and you decide on both. The first is GitHub, for updates: an unauthenticated `GET` to the public releases API (`api.github.com/repos/openhoangnc/mac-lightspot/releases/latest`) with `User-Agent: Lightspot/<version> (+https://github.com/openhoangnc/mac-lightspot)`, shortly after launch and when you open the menu bar menu, but no more than once a day after a successful check (a failed check is retried at the next launch or menu open). Switch off **`Automatically Check for Updates`** in the menu bar and it never runs on its own. Installing an update you accepted downloads its zip from GitHub (`User-Agent: Lightspot/<version>`). Both go through an ephemeral session, so no response or cookie is stored on disk. Older versions used macOS's shared session instead (the update check up to 1.2.0, the IP lookup before 1.2.0), which kept the responses in `~/Library/Caches/com.lightspot.app` and cookies in `~/Library/HTTPStorages`; Lightspot deletes those leftovers at launch, and the uninstaller removes them too. The second is ipify: `GET https://api.ipify.org` (a third-party service) to learn your public IP, and only when you ask for it: by typing a query that names it (`ip`, `my ip`, `public ip`, `ipv4`) or by pressing `Return` on the **IP Address** row. ipify sees your IP address and a standard macOS user agent, as any web server would. The answer is kept in memory for 15 minutes and never written to disk. Web searches, URLs and bookmarks are opened by your browser, and only when you press `Return`.
- **What Is Written to Disk**: Lightspot's own preferences (`UserDefaults`, in `~/Library/Preferences/com.lightspot.app.plist`), one lock file, and temporary files while an update installs:
  - Settings: `lightspot_hotkey_option`, `lightspot_terminal_app`, `lightspot_search_engine`, `lightspot_browser_history_days`, `lightspot_hide_menubar_icon`, `lightspot_auto_start_enabled`, `lightspot_first_run_completed`, `lightspot_spotlight_state` (last known Spotlight status, for the menu labels), `lightspot_auto_update_enabled`, `lightspot_last_update_check`, `lightspot_skipped_version` (automatic update checks).
  - What you create: `lightspot_pinned_commands`, `lightspot_custom_commands`, `lightspot_snippets`.
  - Usage: `lightspot_recent_app_bundle_ids` (recently launched apps) and `lightspot_search_history`: the queries you typed and the results you opened (titles, app and project paths, URLs, shell commands), plus selection counts for ranking. Review or clear it in the search history manager (`⌘Y`). Clipboard, calculator and dev-tool selections are never recorded; snippet and hardware-report selections keep only the query and a count, never the copied text.
  - `~/Library/Application Support/Lightspot/com.lightspot.app.lock`, which keeps a second copy from starting. It holds the running process's PID and its executable's path, inode and modification time, so a new launch can tell the same build from a newer one.
  - While an update you accepted installs: the download, the unpacked bundle and a small helper script in the macOS temporary directory (`NSTemporaryDirectory()`, folders `lightspot-update-…` and `lightspot-updater-…`), and the previous version kept as `Lightspot.app.lightspot-old` beside the app until the new one is in place. The helper deletes all of them when it finishes.
  - **Export Settings** writes a JSON backup, search history included, only to a file you choose.
