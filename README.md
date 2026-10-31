# Lightspot 🔍

[English](README.md) | [简体中文](README_zh-CN.md) | [Español](README_es.md) | [日本語](README_ja.md) | [Français](README_fr.md)

> **A lightweight, pixel-perfect replacement for macOS Spotlight built in pure Swift — designed for developers and power users who want instant speed without the file indexing bloat.**

Lightspot faithfully reproduces the modern floating pill design and translucent glass aesthetic of macOS Spotlight (`NSVisualEffectView`). Under the hood, it delivers sub-millisecond responsiveness (< 1.0 ms search) with **zero background file indexing**. While idle its only recurring work is a lightweight clipboard check every 0.6 s, and it uses under **25 MB of RAM**.

![Lightspot Screenshot](screenshot.png)

---

## ⚡ Quick Start

### 📦 One-Line Download & Install
Run this in your Terminal to download, extract, and install the latest **Lightspot** into `/Applications`. It downloads the build for your Mac, about 1.6 MB on Apple silicon or 1.75 MB on Intel, chosen by the Mac's own processor (`sysctl hw.optional.arm64`), so a Terminal running under Rosetta still gets the Apple silicon build:

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

Mac Tweaks' changes stay, the background items it turned off among them (those for all users stay off for every account): the uninstaller keeps its undo journal and Dock backup, and says how to undo what stays: reinstall Lightspot and choose **Undo everything Lightspot changed** in Mac Tweaks' Settings, remove **Lightspot Mac Tweaks** in System Settings › General › Device Management, or run **Restore Dock Icons**.

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
| **Disk Storage** | 10 GB – 200 GB+ hidden cache | 100 MB – 1 GB | **No index or cache** (your settings in `UserDefaults`, a lock file, and small files only when you clean or apply something: receipt logs, Mac Tweaks' undo journal and a Dock backup) |
| **RAM Footprint** | 500 MB – 2 GB+ | 200 MB – 500 MB | **~15 – 25 MB** (Pure Swift) |
| **App Launching** | Frequently breaks; requires rebuilds | Reliable | **100% Reliable** (Direct scanning) |
| **Search Latency** | Debounced (50 – 200 ms) | 10 – 30 ms | **< 1.0 ms** (instant synchronous) |
| **Offline Privacy** | Sends Siri telemetry to Apple | Account required for sync | **Local & Telemetry-Free** (network only for an optional update check, an IP lookup you ask for, and cdm's cleanup rules when you open Clean Dev Mac) |

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
- Installs in place: Lightspot downloads the release's build for this Mac (`Lightspot-arm64.zip` on Apple silicon, `Lightspot-x86_64.zip` on Intel, chosen by the Mac's own processor, so a copy running under Rosetta moves to the native build; `Lightspot.zip`, the universal app, for a release without them), verifies it, swaps its own bundle, starts the new version and quits once it is up, so there is no moment without Lightspot. **Skip This Version** silences one release without disabling checks. The updaters of Lightspot 1.2.0 to 1.3.9 download the universal `Lightspot.zip`, so they bring 1.4.0 as the universal app; the updates after it are the build for your Mac.
- Every download is gated: HTTPS only, GitHub hosts only (re-checked after redirects), the unpacked bundle must carry Lightspot's bundle identifier, a runnable executable with code for this Mac's processor (read from its Mach-O header) and exactly the advertised version, and a build older than the one installed is never accepted.
- Releases are ad-hoc signed (this project ships no Developer ID), so there is no code signature to verify — the checks above and HTTPS to GitHub are the whole trust model, the same one `install.sh` already asks for.

### 11. 🧹 Clean Dev Mac (`cdm`)
[CleanDevMac](https://github.com/cleandevmac/cdm) (`cdm`) finds the dev caches and build artifacts eating your disk; Lightspot runs it in a window of its own, which you can move and which stays open while Finder, a password prompt or cdm in your terminal takes the focus. Type `cdm`, `clean dev mac` or a cache name (`derived data`, `npm cache`) and press **`↵`**:
- **Measured first, nothing ticked blindly**: every category cdm's rules know (Xcode DerivedData, Go, npm/pnpm/Yarn, Gradle, Cargo, pip/uv, CocoaPods, JetBrains, browser and Electron caches, unused Android images, clang's module cache, the copies of Chrome a crashed or killed browser leaves behind, …) is measured like `du`, listed biggest first, and ticked to cdm's safe defaults. The window shows the disk before and after. Like cdm, it adds two notes when they apply: what a restart would free (swap, the temp folders macOS empties at boot, deleted files apps still hold open) once that is more than the disk has free, and, when Claude Code's session history passes 1 GB with transcripts older than its limit, the `desktopSessionCleanupPeriodDays` setting that has Claude Code delete Claude Desktop and Cowork sessions too. Lightspot never changes that setting for you.
- **Installed SDK pieces and old sessions, unticked**: cdm's opt-in rows come along too: PlatformIO's toolchains, the Android NDK, CMake and SDK sources, every Android build-tools and platform version but the newest, the system image of an AVD nobody has started in 60 days (the row names the AVD, which won't boot until the image is reinstalled), and Claude Code sessions untouched for 30 days, which only ever go to the Trash. Each row says how it comes back.
- **Your code repos too**: after the caches, Clean Dev Mac asks, as cdm does, whether to scan your code repos for build and dependency junk; press **`⇥`**. You get one unticked row per repo with its `node_modules`, `dist`, `build`, `target`, `__pycache__` and other git-ignored files. Nothing is offered unless the repo's own git says it ignores it (a tracked `build/` stays), `.env*` files are never offered, and neither is a folder that holds another repo. Regenerable folders are deleted; other ignored files go to the Trash.
- **Keys**: `↑↓` select (the selected row shows its paths and sizes), `Space` ticks, `⇥` scans your code repos, `↵` shows the itemized plan and `↵` again cleans, `⌥↵` shows the selected cache in Finder, `⌘↵` runs cdm in your terminal, `Esc` steps back out of the plan and otherwise closes the window, as `⌘W` does. A scan or a clean keeps running with the window closed.
- **The same rules as cdm**: Lightspot reads cdm's own rule files — your `~/.cleandevmac/rules` if you have one, else cdm's live rules from GitHub, else the copy built into the app — so a cache cdm learns to clean, Lightspot cleans too.
- **The same safety as cdm**: every path passes cdm's safety check before anything happens: it must be under your home folder, or in your own temp folders under `/private/var/folders` where cdm's rules name a cache (symlinks resolved either way), and `~/Documents`, `~/Desktop`, `~/Downloads`, `~/Pictures`, `~/Movies`, `~/Music`, `~/.ssh`, `~/.gnupg` and iCloud Drive are never touched. Before cleaning, the plan names any app still running that would rewrite its caches (quit it first). Every clean is logged to `~/.cleandevmac/clean.log`, the same log cdm keeps.
- **The rest is one key away**: Docker / Podman, Rust toolchains and their offline docs (removed with `rustup`), orphaned app data and sandboxed app caches need a container engine, rustup or a scan of your apps, so `⌘↵` runs the full cdm in your preferred terminal, straight from its latest release.

### 12. 📦 One-Keystroke Installs: setup-zsh, MacStats & Dev Tools
Type `install` (or a tool's name) and press **`↵`**: Lightspot runs the tool's own installer in your preferred terminal, so you see every step.
- **Install setup-zsh** ([setup-zsh](https://github.com/openhoangnc/setup-zsh)): zsh autosuggestions that match anywhere in your history, syntax highlighting and a git-aware prompt. Runs `setup.sh`, then opens a fresh zsh that loads it. Once it is installed, the same row updates it.
- **Install MacStats** ([mac-stats](https://github.com/openhoangnc/mac-stats)): CPU, RAM, network speed and CPU temperature in the menu bar. Runs its `install.sh`, which puts it in `/Applications` and starts it.
- **Install Dev Tools**: setup-zsh's `install-dev-tool` menu: Homebrew, Node.js, Go, Python & uv, Rust, JDK, Bun, Git, VS Code, Chrome, OrbStack, Android Studio and more, plus updates for your global packages. Type `install node`, `install go`, `install rust`…; without setup-zsh, the row installs it first.
- Each row says whether the tool is already installed; **`⌥↵`** opens its GitHub page.

### 13. 🎛️ macOS Tweaks
The `defaults write` one-liners you would otherwise copy from a dotfiles README, as quick actions. Each toggle reads the current setting and flips it, so the same row turns it back:
- **Dock**: **Clear Dock Icons** (saves the Dock's icons to `~/Library/Application Support/Lightspot/dock-backup.plist`, then removes every pinned app and restarts the Dock), **Restore Dock Icons** (puts them back where they were, keeping icons added since, and deletes the backup only once the restarted Dock shows them; both wait for a Dock that has just started to settle and try once more if a restart loses the change), **Toggle Dock Auto-Hide**, **Toggle Instant Dock Auto-Hide** (no delay), **Toggle Dock Recent Apps**, **Restart Dock**.
- **Finder**: **Toggle Hidden Files in Finder**, **Toggle File Extensions in Finder**, **Toggle Finder Path Bar**, **Toggle Desktop Icons** (handy before a screen share), **Toggle .DS_Store on Network & USB Drives**, **Restart Finder**.
- **Typing & screenshots**: **Toggle Press-and-Hold Accents** (hold a key to repeat it), **Toggle Smart Quotes & Dashes**, **Toggle Screenshot Shadows**.

None needs an administrator password. Restore Dock Icons undoes Clear Dock Icons, and each toggle undoes itself. For 41 more settings, each with its state and undo, see Mac Tweaks' Settings (section 14).

### 14. 🧰 Mac Tweaks (`free up space`)
Mac Tweaks frees the space macOS keeps, turns Apple Intelligence off for every account on this Mac, changes 41 macOS settings with undo, and turns off or deletes the launch agents and daemons other apps installed. Type `mac tweaks`, `free up space`, `debloat` or what you want gone (`remove garageband`, `macos installers`, `time machine snapshots`, `app caches`) and press **`↵`**, or choose **Mac Tweaks...** in the menu bar, right under **Clean Dev Mac...**; `turn off apple intelligence` opens it on Apple Intelligence; `stop music from opening`, `turn off apple music`, `turn off mac analytics`, `turn off personalized ads` or `show the library folder` on Settings; and `turn off background items`, `turn off launch agents`, `disable launch agents`, `turn off google updater`, `leftover launch agents` or `launch daemons` on Background Items. It opens in its own window, one tab per section, and every section shows an itemized plan before it changes anything and a receipt after. The window stays open while you switch to System Settings to approve a profile or answer a Touch ID prompt: move it where you like (it remembers the place), and close it with its close button, `⌘W` or `Esc`. (The `defaults` toggles in section 13 are quick actions, not part of Mac Tweaks.)
- **Free Up Space** measures each row the way Clean Dev Mac does; a row with nothing to offer is hidden, nothing of 0 bytes is offered, and the first three rows are ticked:
  - **macOS installers**: old `Install macOS*.app` in `/Applications`, only with Apple's bundle identifier (`com.apple.InstallAssistant…`).
  - **iPhone and iPad updates** Finder downloaded, in `~/Library/iTunes/iPhone Software Updates` and `iPad Software Updates`.
  - **Unavailable simulators**, whose runtime is no longer installed, through Xcode's `simctl`; never `/usr/bin/xcrun`, so a Mac with only the Command Line Tools gets no row and no installer prompt.
  - **Time Machine local snapshots**, shown as a count (macOS gives no size).
  - **Aerial videos** every account on the Mac shares (`/Library/Application Support/com.apple.idleassetsd/Customer`); each account's own copies are a Clean Dev Mac row.
  - **GarageBand and its sound library**; the library stays while Logic Pro or MainStage is installed.
  - **iMovie**, **Keynote**, **Numbers** and **Pages**, only Apple's own: a `Pages.app` that isn't Apple's stays.
  - **App caches** in `~/Library/Caches`, except macOS's own (`com.apple.*` and the other names macOS writes), Lightspot's, and every cache a Clean Dev Mac rule covers, so Mac Tweaks and Clean Dev Mac never count one folder. Mac Tweaks reads those rules from Clean Dev Mac's memory, `~/.cleandevmac/rules` or the app's copy, and never fetches them.
  - Three link rows: **Apple Intelligence models** (their size, shown once that section has been scanned and while they are on disk) opens the Apple Intelligence section, **Developer caches and project junk** opens Clean Dev Mac, **More in System Settings** opens Storage settings.
- **Where Free Up Space's files go**: to the Trash, so you can take them back out until you empty it. Simulators (`simctl delete unavailable`) and snapshots (`tmutil deletelocalsnapshots`) are deleted right away, and their rows say so; backups on your backup disk aren't touched. Its receipt says what was freed, what went to the Trash, what was deleted, and what stayed and why, such as an app macOS won't let Lightspot move without the App Management permission (`⌥↵` shows it in Finder).
- **Apple Intelligence** (Apple silicon, macOS 15.1 or later): one row per feature this macOS has (Siri, ChatGPT and other AI extensions, Writing Tools, Genmoji, Image Playground, the Mail, notification, Messages, Safari and Notes summaries, inline text predictions, Spatial Photos, Photos Clean Up, Xcode predictive code completion), each with its state (On, Off, Locked off, Managed, Unknown) and the models it needs. Every feature starts ticked, which means turn off; untick what to keep. Applying installs one configuration profile, **Lightspot Mac Tweaks**, which you approve in System Settings › General › Device Management (Lightspot opens it and waits up to 10 minutes; `Esc` stops waiting): it switches the ticked features off for every account on this Mac and points their model downloads at a closed local port. Only once the profile is in force does Lightspot ask Apple's asset service to remove the models no kept feature needs, retrying while macOS still uses them and checking the inventory until they're gone. **Finish removing the models** picks up after a restart; **Turn Apple Intelligence back on** removes the profile, or replaces it with one without Apple Intelligence when it also holds Settings tweaks. A feature another profile sets stays as it is, and RemoveMacAI's profile makes the section read-only. Lightspot never calls the private asset framework itself: every read and removal runs in a short-lived `Lightspot --asset-service` child, so the framework's 9–11 MB never stay in Lightspot's memory.
- **Settings**: 41 tweaks in six groups (Privacy, Annoyances, Apple apps, Finder, Dock and windows, Typing), each with its state on this Mac: On, Off, Partly, Managed (another profile sets it, so Lightspot leaves it alone) or Not on this macOS. Nothing starts ticked; the **Recommended** and **Maximum privacy** presets tick their tweaks that are still off. Local settings go through cfprefsd and are read back, and Finder, the Dock or SystemUIServer restart once when a change needs it. Mac Analytics, personalized ads, Improve Siri and Dictation, Improve Search, Spotlight internet results, Look Up and Safari search suggestions, Game Center, iPhone Mirroring, Apple Music and the Book Store go into the same profile, keeping its Apple Intelligence part as it is, and the plan says the profile applies to every account on this Mac. Apple Music at three levels: the Apple Music service, Music's launch entry so nothing can open Music, and the play, pause and skip keys (`com.apple.rcd`). The selected row and the plan show each change as a command (`defaults write …`, `launchctl …`, `chflags …`, `profile: …`).
- **Background Items**: one row per `.plist` in `~/Library/LaunchAgents`, `/Library/LaunchAgents` and `/Library/LaunchDaemons`, except macOS's own (`com.apple.*`), plists without a `Label` (Google's empty Keystone stubs) and dot files. Each row names the app the item belongs to (the `.app` its program is in, what it runs, or the app its `AssociatedBundleIdentifiers` names, so a Docker helper reads "Docker"), its label and what it runs (never its other arguments, which can hold tokens), and its state: On, Off, Not loaded (Login Items & Extensions may have switched it off) or Unknown, read with `launchctl print-disabled` and `launchctl print`. Updaters (`update` in the label or the program's name) are tagged **Updater**; a row that is neither an updater nor a leftover warns that turning it off can stop its app working. `Space` ticks the row's change: off (`launchctl disable`, then `bootout`) or back on (`enable`, then `bootstrap`). `⌫` marks the row for deletion instead, and again unmarks it (the row shows **Delete**): Lightspot stops the item, switches its label off so a copy its app writes again doesn't load, and moves its plist to the Trash, and the plan shows the commands this equals (`launchctl bootout`, `launchctl disable`, `mv … ~/.Trash/`). Deleting a helper of an app that is still installed can stop the app working, and the app may put it back the next time it runs; the row and the plan say so. A **Leftover**, whose program macOS confirms is gone, is deleted the same way and is the only row ticked from the start. A program in a folder macOS guards or on another disk, and an interpreter given inline code (`-c`, `-e`), are never judged gone, and a plist that is a symlink or shares its label with another plist is never moved, so it can't be deleted. Your own agents change as you; every daemon's change, and every move only an administrator can make, share one administrator prompt, and a daemon's change is for every account on this Mac, while turning an item in `/Library/LaunchAgents` off or on is for your account only; deleting a daemon or an item in `/Library/LaunchAgents` is for all users and may ask for your password. Only what launchd confirms counts: the receipt says where each deleted plist went, and what is still running (a daemon until you restart, an agent until you log out) or didn't load. A symlinked plist is followed one folder at a time, never into a folder macOS guards, another disk or `~/Library/CloudStorage`. The last row opens Login Items & Extensions in System Settings.
- **Undo**: before Lightspot first changes a setting it saves the value it found to `~/Library/Application Support/Lightspot/tweaks-journal.json`, and the change happens only once that save worked. Ticking an On row undoes it: back to that value, or to macOS's default when Lightspot saved none, as the plan says. **Undo everything Lightspot changed** puts back every journaled change and removes the profile after one administrator prompt. It also turns back on the background items Lightspot turned off (journaled before they were turned off), starting again only what was running before, with their daemons in that same prompt. An entry whose plist is gone runs nothing and is dropped, and launchd keeps its switch off. It puts back the background items Lightspot deleted too: each plist goes back from the Trash to where it was, switched on and started only as it was before, root's in that same prompt and only a file root owns. It never replaces a file that is there now (if the app wrote one again, Lightspot only switches it back on), and one no longer in the Trash is said and dropped. A partly applied setting is your own and is only ever finished, never undone. Files Free Up Space moved to the Trash and Clear Dock Icons' backup aren't part of it.
- **Password only when an administrator must act**: deleting snapshots, moving an item another user owns or a folder's permissions won't let you move (its row says **May ask for password**), turning a daemon off or on, deleting a daemon or an item in `/Library/LaunchAgents` and putting it back, and removing Lightspot's profile. What an apply needs as administrator is one script that runs once, through Touch ID for sudo or the password dialog. Installing the profile is your own click in System Settings.
- **Keys**: `↑↓` select (the selected row shows its items, models or commands), `Space` ticks (on a preset, its rows; in Background Items, the row's change), `⌫` marks a background item for deletion, `⇥` / `⇧⇥` switch sections, `↵` shows the itemized plan and `↵` again applies, `⌥↵` shows a Free Up Space row's first item, or a background item's plist, in Finder, `Esc` steps back out of the plan or stops a wait for System Settings, and otherwise closes the window, as `⌘W` does.
- **Receipts**: every apply ends with one, with a green check when it did what was asked. Applying keeps running even if you close the window, and reopening Mac Tweaks shows the progress, then the receipt. Each apply is logged to `~/Library/Application Support/Lightspot/mac-tweaks.log`. A section whose scan another section's apply changed scans again: Apple Intelligence and Settings share the profile, and Settings and Background Items the undo journal.
- **Never touched**: Free Up Space never touches anything under `/System`, `~/Desktop`, `~/Documents`, `~/Downloads`, `~/Pictures`, `~/Movies`, `~/Music`, iCloud Drive, `~/Library/Containers`, `~/Library/Group Containers`, Mail, Messages or iPhone backups (`MobileSync`), nor anything inside an app bundle: every path must sit directly in one of its row's fixed folders, as written and with symlinks resolved, must not be a symlink itself, and passes that check again just before it moves. Apple Intelligence and Settings leave alone anything another configuration profile sets. Background Items never lists macOS's own items or changes anything outside its three folders, runs `launchctl` directly, never through a shell, and as root acts only on a label and a plist the scan found. Mac Tweaks reads nothing until you open it and makes no network request.
- **Credit**: Free Up Space, Apple Intelligence, Settings and Background Items port logic from [RemoveMacAI](https://github.com/omlahore/RemoveMacAI) by omlahore (MIT License). Its Apple Intelligence work builds on [pared](https://github.com/4evy/pared) by 4evy (MIT License), which Lightspot's asset-service bridge, model catalog and download block follow. See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

---

## ✨ Additional Built-in Capabilities

- **Exact macOS Spotlight UI**: Floating translucent squircle pill with animated expansion and preview pane (`NSVisualEffectView`).
- **Mach / IOKit Hardware HUD**: Instant, zero-subprocess hardware diagnostics (`sys`, `cpu`, `ram`, `memory`, `disk`, `battery`, `uptime`, `specs`, `resources`):
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
- **macOS System Settings Deep Links**: 46 direct deep links opening specific macOS settings panes (`x-apple.systempreferences:...`), found by the same terms System Settings' own search uses (`night shift`, `lockdown mode`, `sticky keys`), in your system languages. On macOS 27.2, where System Settings can quit without LaunchServices noticing for a minute or more, Lightspot opens the pane in a new System Settings instead of the alert that it is not open anymore.
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
Download and install the latest prebuilt release directly. Each release carries `Lightspot-arm64.zip` (Apple silicon, about 1.6 MB) and `Lightspot-x86_64.zip` (Intel, about 1.75 MB), which the installer and the updater pick for your Mac, `Lightspot.zip`, the universal app (about 2.9 MB), and `Lightspot.app.dSYM.zip`, the symbols for reading crash reports:
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

`./build.sh` compiles each architecture with full link-time optimisation (LTO) and strips the local symbol names, which it keeps in `build/Lightspot.app.dSYM`: the 1.4.0 universal binary is 5.1 MB, 42% smaller than 1.3.9's 8.8 MB, and 2.2 MB for Apple silicon alone (2.9 MB for Intel).

### 4. Tests & Verification
Lightspot has no XCTest target. Three standalone scripts under `scripts/` are compiled ad hoc against the sources, and are run from the repository root: a logic and engine test runner (84 test blocks), a live-system verifier (15 sections, 206 checks on the developer's Mac with macOS 27.2; a few are skipped if, for example, there is no zsh history or VS Code installation, or GitHub cannot be reached), and a window check that builds the real Mac Tweaks and Clean Dev Mac windows offscreen on read-only scans and drives every Mac Tweaks section through rescans and section switches, and both windows through their keys:
```bash
# Core logic & engine tests (84 test blocks)
swiftc -o /tmp/test_engine scripts/test_engine.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift Sources/Lightspot/System/AutoStartManager.swift Sources/Lightspot/System/SpotlightManager.swift Sources/Lightspot/System/FirstRunManager.swift Sources/Lightspot/System/UpdateManager.swift Sources/Lightspot/System/SingleInstanceGuard.swift Sources/Lightspot/System/LegacyNetworkStores.swift Sources/Lightspot/System/HotkeyManager.swift Sources/Lightspot/System/SystemShortcutConflicts.swift && /tmp/test_engine

# Live system checks (15 sections, 206 checks on macOS 27.2)
swiftc -o /tmp/deep_verify scripts/deep_verify.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift && /tmp/deep_verify

# The Mac Tweaks and Clean Dev Mac windows, offscreen (about a minute)
swiftc -parse-as-library -o /tmp/overlay_check scripts/overlay_check.swift $(find Sources/Lightspot -name '*.swift' ! -name AppMain.swift) && /tmp/overlay_check
```

---

## ⌨️ Shortcuts & Navigation

| Key | Action |
|---|---|
| **`⌘Space`** / **`⌘⇧Space`** / **`⌥Space`** / **`⌃Space`** | Summon or dismiss Lightspot anywhere (configurable in menu bar) |
| **`↓` / `↑`** | Navigate through search results |
| **`Return` (`↵`)** | Open selected app, project in IDE, run command, or copy calculation |
| **`⌘Return` (`⌘↵`)** | Open selected project in preferred Terminal |
| **`⌥Return` (`⌥↵`)** | Reveal project in Finder / Force kill selected process (`SIGKILL`) / Open an installer's GitHub page / Show a Mac Tweaks row's first item in Finder |
| **`⌘P`** | Pin or unpin selected Terminal History command |
| **`⌘⇧P`** | Open pinned commands manager overlay |
| **`⌘⇧C`** | Open custom commands manager overlay |
| **`Space`** | Tick or untick a category in Clean Dev Mac or a row in Mac Tweaks |
| **`Delete` (`⌫`)** | Mark or unmark a background item for deletion in Mac Tweaks |
| **`Tab` (`⇥`)** | Scan your code repos too, in Clean Dev Mac / Next section in Mac Tweaks (`⇧⇥` the previous one) |
| **`⌘Y` / `⌘⇧H`** | Open search history manager overlay |
| **`Escape`** | Dismiss overlays, clear search field, or close Lightspot; in the Mac Tweaks and Clean Dev Mac windows, step back, then close the window |
| **`⌘W`** | Close the Mac Tweaks or Clean Dev Mac window |
| **Click Outside** | Automatically dismisses the floating panel |

The summon shortcut is whichever of the four you pick under **Shortcut** in the menu bar. macOS binds `⌃Space` to "Select the previous input source", so choosing it means the keystroke also switches your input source; the **Shortcut** submenu names any system shortcut that already sits on the combination you picked.

---

## 🔒 Privacy & Security Guarantees

- **Zero File Indexing**: Lightspot never indexes your personal files, documents, downloads, or code repositories. Clean Dev Mac measures only the cache folders cdm's rules name and the few places its two notes need (see below), only while you have it open, and keeps nothing but the sizes; it never reads other apps' sandbox containers. For its Android and Claude Code rows it also reads file dates in your AVD folders and in `~/.claude/projects`, and the small `~/.claude/sessions` files that name running sessions; never what a transcript says. For the copies of Chrome a crashed browser leaves, it lists them in your own temp folder and reads when your own running apps started. For cdm's two notes it reads how much swap is in use, measures the temp folders macOS empties at boot and `~/.claude/projects`, asks `lsof` for deleted files your apps still hold open (keeping only their total and the three biggest holders' names), and reads two keys of `~/.claude/settings.json` (`cleanupPeriodDays`, `desktopSessionCleanupPeriodDays`), which it never writes. When you ask it to scan your code repos (`⇥`), it looks for git repos in your home folder, six levels deep, without entering `~/Library`, `~/Documents`, `~/Desktop`, `~/Downloads`, `~/Pictures`, `~/Movies` or `~/Music`, and asks each repo's git which files it ignores. Mac Tweaks reads a fixed list of places, only for the section you open. Free Up Space: the names in `/Applications` and the `Info.plist` of the Install macOS apps and of GarageBand, iMovie, Keynote, Numbers and Pages there; the entries of `~/Library/iTunes/iPhone Software Updates` and `iPad Software Updates`, `/Library/Application Support/com.apple.idleassetsd/Customer` and `~/Library/Caches`, with each offered item's size and owner; GarageBand's three library folders and whether Logic Pro or MainStage is installed; the list of unavailable simulators from Xcode's `simctl` and the local snapshot dates from `tmutil`; the wallpaper index (`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`) when there are aerial videos to offer; and Clean Dev Mac's rules. When it applies, it looks up names in `~/.Trash` one at a time and never lists the Trash. Apple Intelligence: the asset service's inventory of the model sets and their sizes, read by the short-lived helper, which reads no folders (only within a removal, the entry counts of a set's folder in `/System/Library/AssetsV2`, never a listing), and the features' settings and the two profiles' markers through cfprefsd. Settings: the preferences and restrictions of its 41 tweaks, the Dock's icons and the profile's marker through cfprefsd, launchctl's list of disabled services, the inode numbers of Music.app and its executable, the Library folder's hidden flag, and its undo journal. Background Items: the names in `~/Library/LaunchAgents`, `/Library/LaunchAgents` and `/Library/LaunchDaemons` and each `.plist` there, only as a regular file of at most 1 MiB, of which it keeps only the label, program, arguments, associated app identifiers and `Disabled` (the arguments are never shown or logged); `launchctl print-disabled` for your account and the system, and `launchctl print` for each item, keeping only its exit status, since its output lists the job's environment; each program a plist names, or the script an interpreter runs, looked up one folder at a time and never inside a folder macOS guards, another disk or `~/Library/CloudStorage`; each plist's owner; LaunchServices, for the apps a plist names; and the undo journal's background entries. While the journal holds background items, Settings reads the three folders once, for Undo everything's plan. Once a scan is more than five minutes old, closing Mac Tweaks drops what it found, keeping only Free Up Space's total and what Apple Intelligence's scan read about the models.
- **RAM-Only Ephemeral Clipboard**: Clipboard history stays exclusively in volatile memory and actively ignores concealed/password manager types (`org.nspasteboard.ConcealedType`, `1Password`, `Bitwarden`). It is never written to disk, not even into search history, which also never keeps the text you copy from calculator, dev-tool or snippet results.
- **Default Browser Isolation**: Bookmarks, open tabs and recent history are read locally and solely from your configured default browser, avoiding cross-browser scraping.
- **User-Triggered Commands**: Your commands, scripts and quick actions run only upon explicit user action (`Return` or `⌘↵`).
- **Admin Commands Run Once**: A privileged command runs through `sudo` with Touch ID, or through the macOS password dialog, and since 1.4.0 never twice: it first prints a random marker, and once that marker shows sudo has started it, its result is final, so a command that fails under Touch ID is no longer run again behind the password dialog. After the marker its stdin is `/dev/null`, so nothing it runs waits on the hidden terminal. Scripts Lightspot builds itself (Mac Tweaks' administrator batch, every argument single-quoted) go through a separate entry point that leaves them as they are. The system log gets only whether a privileged command ran and its exit status, never its text, which can hold your file paths.
- **No Telemetry, Two Services You Control**: No analytics, no tracking, no accounts. Lightspot itself talks to exactly two services, and you decide on both. The first is GitHub, for updates: an unauthenticated `GET` to the public releases API (`api.github.com/repos/openhoangnc/mac-lightspot/releases/latest`) with `User-Agent: Lightspot/<version> (+https://github.com/openhoangnc/mac-lightspot)`, shortly after launch and when you open the menu bar menu, but no more than once a day after a successful check (a failed check is retried at the next launch or menu open). Switch off **`Automatically Check for Updates`** in the menu bar and it never runs on its own. Installing an update you accepted downloads its zip from GitHub (`User-Agent: Lightspot/<version>`). Both go through an ephemeral session, so no response or cookie is stored on disk. Older versions used macOS's shared session instead (the update check up to 1.2.0, the IP lookup before 1.2.0), which kept the responses in `~/Library/Caches/com.lightspot.app` and cookies in `~/Library/HTTPStorages`; Lightspot deletes those leftovers at launch, and the uninstaller removes them too. The second is ipify: `GET https://api.ipify.org` (a third-party service) to learn your public IP, and only when you ask for it: by typing a query that names it (`ip`, `my ip`, `public ip`, `ipv4`) or by pressing `Return` on the **IP Address** row. ipify sees your IP address and a standard macOS user agent, as any web server would. The answer is kept in memory for 15 minutes and never written to disk. Opening **Clean Dev Mac** also asks GitHub for cdm's rule files (`GET https://raw.githubusercontent.com/cleandevmac/cdm/main/rules/index.json` and the files it lists, with a standard macOS user agent, through an ephemeral session), at most once an hour; they stay in memory, and without a connection the copy built into the app is used. You skip it entirely by keeping your own rules in `~/.cleandevmac/rules`. Mac Tweaks makes no request at all: it reads Clean Dev Mac's rules from memory, `~/.cleandevmac/rules` or the app's copy, and never fetches them. Running cdm in the terminal (`⌘↵`) downloads its script from cdm's GitHub release, as cdm's own instructions do. The installer rows work the same way: each runs its tool's installer in your terminal, and that script, not Lightspot, downloads from GitHub. Web searches, URLs and bookmarks are opened by your browser, and only when you press `Return`.
- **What Is Written to Disk**: Lightspot's own preferences (`UserDefaults`, in `~/Library/Preferences/com.lightspot.app.plist`), one lock file, temporary files while an update installs, a receipt in cdm's log when you clean, and Mac Tweaks' small files when you apply something there:
  - Settings: `lightspot_hotkey_option`, `lightspot_terminal_app`, `lightspot_search_engine`, `lightspot_browser_history_days`, `lightspot_hide_menubar_icon`, `lightspot_auto_start_enabled`, `lightspot_first_run_completed`, `lightspot_spotlight_state` (last known Spotlight status, for the menu labels), `lightspot_auto_update_enabled`, `lightspot_last_update_check`, `lightspot_skipped_version` (automatic update checks).
  - What you create: `lightspot_pinned_commands`, `lightspot_custom_commands`, `lightspot_snippets`.
  - Usage: `lightspot_recent_app_bundle_ids` (recently launched apps) and `lightspot_search_history`: the queries you typed and the results you opened (titles, app and project paths, URLs, shell commands), plus selection counts for ranking. Review or clear it in the search history manager (`⌘Y`). Clipboard, calculator and dev-tool selections are never recorded; snippet and hardware-report selections keep only the query and a count, never the copied text.
  - `~/.cleandevmac/clean.log`, only when you clean with Clean Dev Mac: what each clean deleted or moved to the Trash, appended to the log cdm itself keeps (capped at 1 MiB, like cdm's). What you confirm in the cleaner is deleted for good, except categories marked Trash, which go to the Trash.
  - `~/Library/Application Support/Lightspot/mac-tweaks.log`, only when you apply something in Mac Tweaks: when each apply started and ended, what it changed, moved to the Trash or deleted, what stayed and why, and how much it freed. Over 1 MiB it keeps the newest 256 KiB, as cdm's log does. Files you confirm in Free Up Space go to the Trash; unavailable simulators and Time Machine snapshots are deleted for good.
  - `~/Library/Application Support/Lightspot/tweaks-journal.json`, Mac Tweaks' undo journal: the value each setting had before Lightspot changed it, whether each background item it turned off or deleted was switched off and loaded, and where a deleted one's plist was and where it went in the Trash, saved before the change and removed once undone. A journal Lightspot can't read is never overwritten: it is set aside as `tweaks-journal-unreadable-<date>-<id>.json`. Settings also writes other apps' preferences (Finder's, the Dock's, the global domain's…), only the ones you apply, each journaled first.
  - `~/Library/Application Support/Lightspot/dock-backup.plist`, written by Clear Dock Icons before it clears the Dock and removed by Restore Dock Icons once the icons are back.
  - `~/Library/Application Support/Lightspot/LightspotMacTweaks.mobileconfig`, only while an apply waits for you to approve Lightspot's profile, and removed once it is installed. The profile itself, **Lightspot Mac Tweaks**, is installed by you in System Settings and applies to every account on this Mac; removing it there undoes everything it changed.
  - The uninstaller removes all of these but the journals and the Dock backup, which it keeps so that a reinstalled Lightspot can still undo, and it says what stays and how to undo it; background items for all users that Lightspot turned off stay off for every account.
  - `~/Library/Application Support/Lightspot/com.lightspot.app.lock`, which keeps a second copy from starting. It holds the running process's PID and its executable's path, inode and modification time, so a new launch can tell the same build from a newer one.
  - While an update you accepted installs: the download, the unpacked bundle and a small helper script in the macOS temporary directory (`NSTemporaryDirectory()`, folders `lightspot-update-…` and `lightspot-updater-…`), and the previous version kept as `Lightspot.app.lightspot-old` beside the app until the new one is in place. The helper deletes all of them when it finishes.
  - **Export Settings** writes a JSON backup, search history included, only to a file you choose.
