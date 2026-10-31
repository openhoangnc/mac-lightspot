# Lightspot 🔍

[English](README.md) | [简体中文](README_zh-CN.md) | [Español](README_es.md) | [日本語](README_ja.md) | [Français](README_fr.md)

> **纯粹的Swift构建，macOS Spotlight的轻量级、完美像素替代品 — 专为需要极速响应且免受文件索引臃肿困扰的开发者和高级用户设计。**

Lightspot忠实再现了macOS Spotlight现代的悬浮胶囊设计和半透明玻璃美学（`NSVisualEffectView`）。在底层，它提供亚毫秒级的响应能力（搜索时间 < 1.0毫秒），**完全没有后台文件索引**。空闲时唯一的周期性工作是每0.6秒一次的轻量级剪贴板检查，并且仅占用不到**25MB的RAM**。

![Lightspot 截图](screenshot.png)

---

## ⚡ 快速开始

### 📦 单行下载与安装
只需在终端中复制并粘贴此命令，即可自动下载、解压并将最新的 **Lightspot** 直接安装到 `/Applications` 文件夹中。它下载的是适用于您这台 Mac 的构建：Apple 芯片上约 1.6 MB，Intel 上约 1.75 MB；判断依据是 Mac 本身的处理器（`sysctl hw.optional.arm64`），所以在 Rosetta 下运行的终端也会得到 Apple 芯片版本：

```bash
curl -fsSL https://raw.githubusercontent.com/openhoangnc/mac-lightspot/main/install.sh | bash
```

*(可选：若要安装到 `~/Applications`，请使用：`curl -fsSL https://raw.githubusercontent.com/openhoangnc/mac-lightspot/main/install.sh | bash -s -- --user`)*

---

### 🗑️ 彻底卸载
如需彻底卸载，此命令可安全停止应用、取消开机自启项、清除用户偏好设置并删除应用程序包；如果 Lightspot 曾关闭 Apple Spotlight，还会将其重新启用（重新开启索引需要管理员密码，也可以稍后自行运行打印出的 `sudo mdutil -a -i on` 命令）：

```bash
curl -fsSL https://raw.githubusercontent.com/openhoangnc/mac-lightspot/main/uninstall.sh | bash
```

*(可选：`curl -fsSL https://raw.githubusercontent.com/openhoangnc/mac-lightspot/main/uninstall.sh | bash -s -- --dry-run` 仅显示将要执行的更改而不做任何修改；改用 `--keep-spotlight-disabled` 则保持 Spotlight 关闭。)*

Mac Tweaks 所做的更改会保留，包括它关闭的后台项目（面向所有用户的项目在所有账户中保持关闭）：卸载程序会保留它的撤销日志和程序坞备份，并说明如何撤销保留下来的内容：重新安装 Lightspot 后在 Mac Tweaks 的 Settings 中选择 **Undo everything Lightspot changed**，在系统设置 › 通用 › 设备管理中移除 **Lightspot Mac Tweaks**，或运行 **Restore Dock Icons**。

---

## 💡 为什么选择Lightspot？

Apple内置的Spotlight是为普通文件搜索设计的。但对于开发者和高级用户来说，Spotlight的后台进程经常会造成严重的系统负担。**Lightspot正是为了解决这个问题而诞生的。**

### 问题：Apple Spotlight

1. **CPU和电池消耗：** 后台守护进程（`mds`、`mdworker`）主动对文件进行索引。一个简单的 `npm install` 或 `git checkout` 就能让你的CPU占用率飙升到100%，导致风扇狂转、电池电量锐减。
2. **应用丢失：** Spotlight的索引经常损坏，导致它无法完成最基本的工作：查找Terminal或Slack等应用。修复这个问题需要运行晦涩的 `mdutil` 命令，从头开始重建索引。
3. **磁盘占用膨胀：** Spotlight会悄悄地将元数据缓存到一个隐藏的 `/.Spotlight-V100` 文件夹中。在开发者的机器上，这个索引经常膨胀到 **50GB–200GB**，浪费了昂贵的SSD存储空间。
4. **内存囤积：** Spotlight进程经常出现内存泄漏，消耗数GB的统一内存（RAM）——这些内存本应留给你的IDE、Docker或本地LLM使用。
5. **不必要的文件抓取：** 通过系统设置排除像 `node_modules`、`.git` 或 `.venv` 这样庞大的文件夹不仅笨拙、缓慢，而且在macOS更新期间经常被重置。

*(参见社区报告：[高CPU](https://www.reddit.com/r/MacOS/comments/1p10c3f/pages_caused_insane_cpu_spikes_on_macos_i_think_i/)、[应用丢失](https://www.reddit.com/r/MacOS/comments/1gjhiha/spotlight_not_looking_for_apps/)、[存储浪费](https://dev.to/vvo/how-to-avoid-spotlight-using-hundreds-of-gbs-and-rebuild-its-index-4kki)、[内存泄漏](https://discussions.apple.com/thread/256167358?sortBy=rank))*

---

## ⚡ 解决方案：零索引架构

Lightspot通过采取一种截然不同的方法来解决这些问题：**零后台文件索引。**

Lightspot不主动抓取整个硬盘，而是严格关注高级用户实际搜索的内容：应用程序、IDE项目、浏览器选项卡、书签与历史记录、开发者实用工具和自定义命令。

### 比较矩阵

| 指标 | Apple Spotlight | Raycast / Alfred | Lightspot 🔍 |
|:---|:---|:---|:---|
| **文件索引** | 无法控制的后台抓取 | 可选 / 可配置 | **从不** (通过架构保证) |
| **空闲CPU使用率** | 操作期间峰值超过100% | 1% – 5% (后台) | **极低** (无索引；仅每0.6秒检查一次剪贴板) |
| **磁盘存储** | 10 GB – 200 GB+ 隐藏缓存 | 100 MB – 1 GB | **无索引或缓存** (仅 `UserDefaults` 中的设置、一个锁文件，以及仅在清理或执行操作时写入的小文件：记录日志、Mac Tweaks 的撤销日志和程序坞备份) |
| **RAM占用** | 500 MB – 2 GB+ | 200 MB – 500 MB | **约15 – 25 MB** (纯Swift) |
| **应用启动** | 经常损坏；需要重建 | 可靠 | **100%可靠** (直接扫描) |
| **搜索延迟** | 防抖处理 (50 – 200 ms) | 10 – 30 ms | **< 1.0 ms** (瞬时同步) |
| **离线隐私** | 发送Siri遥测至Apple | 需要同步账号 | **本地运行且无遥测**（仅在可选的更新检查、您主动发起的IP查询，以及打开 Clean Dev Mac 获取 cdm 清理规则时联网） |

---

## 🛠️ 开发者优先的自定义与高级用户工作流

Lightspot从一开始就被设计为开发者的主要控制中心。每一个方面都可以根据你对终端、编辑器、脚本和工作流的具体需求进行塑造：

### 1. ⚡ 自定义命令与脚本运行器 (`⌘⇧C`)
使用 **`⌘⇧C`** 打开交互式自定义命令编辑器，以创建和管理自定义快捷方式：
- **4个运行引擎**：
  - `terminal`：直接在你首选的终端模拟器中执行命令。
  - `shell`：通过 `/bin/zsh` 在后台无头执行。
  - `applescript`：执行原生macOS AppleScript自动化脚本。
  - `url`：在默认浏览器中打开模板化URL。
- **动态参数扩展**：
  - 使用 `{query}`、`%s` 或 `%@` 来替换你在命令后输入的任何参数。
- **前缀触发器**：
  - 为命令设置你自己的前缀，然后输入 `<前缀> <查询>`（例如 `c <url>` 请求curl headers，`png <host>` 进行ping操作）。编辑器的 **Presets** 菜单提供九个现成命令：`gh`、`g`、`yt`、`so`、`ddg`、`wiki`、`npm`、`png` 和 `c`。
- **自定义关键字与图标**：
  - 添加模糊关键字以实现即时发现。命令图标默认使用其运行器的应用图标（浏览器、终端或脚本编辑器）；你也可以切换为运行器的内置符号，或选择自己的图片或应用程序文件。

### 2. 💬 动态文本代码段
Lightspot内置五个文本代码段——`date`、`iso`、`uuid`、`shrug` 和 `flip`——并在你复制时即时展开动态变量：
- `{{date}}`：当前日期 (`YYYY-MM-DD`)
- `{{time}}`：当前时间 (`HH:mm:ss`)
- `{{iso}}`：ISO 8601 UTC 时间戳 (`2026-09-05T14:30:00Z`)
- `{{uuid}}`：随机UUID v4
- `{{clipboard}}`：当前剪贴板的内容

输入代码段关键字（例如 `iso`、`uuid`、`date`）或名称的一部分，并按 **`↵`** 即可将计算后的字符串直接复制到剪贴板。

### 3. 💻 从7种现代终端模拟器中选择
Lightspot与你最喜欢的终端模拟器集成。随时通过菜单栏切换：
- **Ghostty**、**Warp**、**Alacritty**、**iTerm2**、**Kitty**、**WezTerm** 和 **Apple Terminal**。（Warp 可以打开文件夹，但无法接收其他应用传入的命令，因此选择 Warp 时，历史命令、置顶命令和自定义终端命令会在 Apple Terminal 中运行。）
- **"Finder文件夹中的终端"**：输入 `term` 或按下操作，即可在Finder当前打开的目录中立即启动你首选的终端。

### 4. 📂 多IDE最近项目发现
Lightspot自动监控以下最近工作区：
- **VS Code**、**Cursor**、**Zed**、**JetBrains IDE** (IntelliJ IDEA、PyCharm（含社区版）、WebStorm、GoLand、CLion、RustRover、Rider、PhpStorm、DataGrip、RubyMine、DataSpell)、**Android Studio** 和 **Sublime Text**。
- **键盘修饰键**：
  - `↵` (Return)：在关联的IDE中打开工作区。
  - `⌘↵` (Command + Return)：在项目根目录启动首选终端。
  - `⌥↵` (Option + Return)：在Finder中显示项目文件夹。

### 5. 🔌 进程终止器与端口终止器 (`kill`)
快速终止残留的开发服务器、卡住的后台任务或恶意进程：
- **按端口终止：** `kill :3000`, `kill :8080`, `kill :5173` (通过 `lsof` 解析正在*监听*该端口的进程；仅连接到该端口的客户端不会被列出)。
- **按进程名或PID终止：** `kill node`, `kill python`, `kill 14205`。系统进程（`launchd`、`kernel_task`、`WindowServer`、`loginwindow`）和 Lightspot 自身永远不会被列出。
- **终止级别：**
  - `↵` (Return)：优雅终止 (`SIGTERM`)。
  - `⌥↵` (Option + Return)：强制终止 (`SIGKILL`)。

### 6. 🛠️ 内置离线开发者工具 (DevTools)
在毫秒内执行常见的开发者操作，无需打开Web实用工具或安装CLI包：
- **`uuid`**：生成具有密码学安全性的随机UUID v4。
- **`b64 <text>`** / **`b64d <base64>`**（或 **`b64 decode <base64>`**）：Base64编码与解码。
- **`urlencode <url>`** / **`urldecode <url>`**：URL百分号编码。
- **`hash <text>`** / **`hash sha256|sha1|md5 <text>`**：即时加密校验和——一次显示全部三种，或只显示指定的算法。
- **`jwt <token>`**：解码并漂亮地打印JWT头部和负载。
- **`json <raw>`**：格式化、缩进和验证压缩JSON。
- **`epoch`** / **`now`**：当前Unix时间戳；**`epoch <时间戳>`** 转换为人类可读的日期，**`epoch 2024-01-15 10:30`** 则反向转换为时间戳（按本地时间，或带时区的ISO 8601）。
- **`#3498db`**：实时颜色预览色板，支持一键复制Hex、RGB和HSL。

### 7. 🔐 Sudo及特权操作的无头Touch ID
利用指纹生物识别技术执行特权维护操作（如 `Flush DNS Cache`、`Purge Inactive Memory`）：
- **无终端弹出窗口**：通过后台伪终端(PTY)运行，调用macOS的 `pam_tid.so` 实现即时Touch ID身份验证。
- **在终端中切换Sudo的Touch ID**：一个可搜索的快速操作（输入 `touch id` 或 `sudo`），在管理员授权提示后编辑 `/etc/pam.d/sudo_local`，让你在常规终端中的 `sudo` 命令也能使用Touch ID。其副标题会显示当前是否已启用sudo的Touch ID。

### 8. 📜 zsh历史记录与固定命令 (`⌘P` / `⌘⇧P`)
- 搜索本地的 `~/.zsh_history` (或自定义的 `$HISTFILE`)，提供亚毫秒级的即时排名。
- 在任何历史命令上按 **`⌘P`** 将其固定到启动器的顶部。
- 按 **`⌘⇧P`** 管理、重新排序或删除固定命令。

### 9. 📦 设置备份与跨机同步
- 在菜单栏中使用 **Export Settings…** / **Import Settings…**，将配置导出为干净的JSON文件或从中导入。内容包括自定义命令、固定的shell命令、搜索历史与排名、最近使用的应用，以及偏好设置（全局热键、登录时启动、菜单栏图标可见性、浏览器历史范围）。文本代码段、首选终端和默认网页搜索引擎不包含在内。
- 自动路径净化会将 `/Users/username` 替换为 `~`，这样配置就可以在工作Mac和个人Mac之间无缝共享。

### 10. 🔄 内置自动更新
- 在后台检查GitHub Releases（启动后不久，以及打开菜单栏菜单时），并从菜单栏提示新版本。检查成功后会间隔一天再检查；检查失败（离线、被限流）时会在下次启动或打开菜单时重试。**`Check for Updates...`** 可随时手动运行，**`Automatically Check for Updates`** 则可完全关闭自动检查。
- 原地安装：Lightspot会下载该版本中适用于这台 Mac 的构建（Apple 芯片上为 `Lightspot-arm64.zip`，Intel 上为 `Lightspot-x86_64.zip`，依据 Mac 本身的处理器判断，因此在 Rosetta 下运行的副本也会换成原生构建；没有这两个文件的版本则下载通用应用 `Lightspot.zip`）、进行校验、替换自身的应用包，启动新版本，并在新版本启动完成后才退出，因此Lightspot不会有消失的时刻。**`Skip This Version`** 只会忽略这一个版本，而不会关闭检查。Lightspot 1.2.0 至 1.3.9 的更新程序下载的是通用的 `Lightspot.zip`，因此它们会以通用应用的形式装上 1.4.0，之后的更新才是适用于您这台 Mac 的构建。
- 每次下载都有门槛：仅限HTTPS、仅限GitHub主机（重定向后会再次校验），解压后的应用包必须带有Lightspot的包标识符、含有这台 Mac 处理器代码的可运行可执行文件（从其 Mach-O 头读取），以及与公布版本完全一致的版本号，且绝不接受比已安装版本更旧的构建。
- 发布版本采用临时（ad-hoc）签名（本项目不附带Developer ID），因此没有可供验证的代码签名——以上检查加上通往GitHub的HTTPS就是全部的信任模型，与 `install.sh` 已经要求的完全相同。

### 11. 🧹 Clean Dev Mac (`cdm`)
[CleanDevMac](https://github.com/cleandevmac/cdm)（`cdm`）能找出占用磁盘的开发缓存和构建产物；Lightspot 在它自己的窗口中运行它；窗口可以移动，访达、密码提示或终端中的 cdm 切到前台时仍保持打开。输入 `cdm`、`clean dev mac` 或缓存名称（`derived data`、`npm cache`）并按下 **`↵`**：
- **先测量，不盲目勾选**：cdm 规则涵盖的每个类别（Xcode DerivedData、Go、npm/pnpm/Yarn、Gradle、Cargo、pip/uv、CocoaPods、JetBrains、浏览器和 Electron 应用缓存、未使用的 Android 镜像、clang 的模块缓存、被强制退出的 Chrome 留下的副本等）都会像 `du` 一样测量，按大小从大到小排列，并按 cdm 的安全默认值勾选。窗口会显示清理前后的磁盘状态。与 cdm 一样，在适用时还会显示两条提示：当重启可释放的空间（交换空间、macOS 开机时清空的临时文件夹、应用仍打开着的已删除文件）超过可用空间时，给出这一估算；当 Claude Code 的会话历史超过 1 GB 且有超过其保留期限的对话记录时，提示可让 Claude Code 同时删除 Claude Desktop 与 Cowork 会话的设置 `desktopSessionCleanupPeriodDays`。Lightspot 从不替您修改这项设置。
- **已安装的 SDK 组件和旧会话，默认不勾选**：cdm 的可选行也会出现：PlatformIO 的工具链；Android NDK、CMake 与 SDK 源码；除最新版之外的所有 Android build-tools 与平台版本；60 天内没人启动过的 AVD 的系统镜像（该行会列出 AVD 名称，镜像重新安装之前该 AVD 无法启动）；以及 30 天未动过的 Claude Code 会话，它们只会移到废纸篓。每一行都写明如何恢复。
- **代码库也一起**：测量完缓存后，Clean Dev Mac 会像 cdm 一样询问是否也扫描您的代码库中的构建和依赖垃圾；按 **`⇥`** 即可。每个代码库一行，列出其中的 `node_modules`、`dist`、`build`、`target`、`__pycache__` 以及其他被 git 忽略的文件，默认不勾选。只有代码库自己的 git 确认忽略的内容才会列出（被跟踪的 `build/` 会保留），`.env*` 文件以及包含其他代码库的文件夹永远不会列出。可再生的文件夹会被删除；其他被忽略的文件会移到废纸篓。
- **按键**：`↑↓` 选择（选中的行会显示其路径和大小），`Space` 勾选，`⇥` 扫描代码库，`↵` 显示逐项清理计划，再按一次 `↵` 开始清理，`⌥↵` 在访达中显示所选缓存，`⌘↵` 在终端中运行 cdm，`Esc` 退出计划，没有计划时则像 `⌘W` 一样关闭窗口。关闭窗口后扫描或清理仍会继续。
- **与 cdm 相同的规则**：Lightspot 读取 cdm 自己的规则文件：如果有 `~/.cleandevmac/rules` 就用它，否则使用 GitHub 上 cdm 的最新规则，再否则使用应用内置的副本。因此 cdm 能清理的缓存，Lightspot 也能清理。
- **与 cdm 相同的安全性**：执行任何操作之前，每个路径都要通过 cdm 的安全检查：必须位于您的主文件夹内，或位于 cdm 规则指定了缓存的、您自己在 `/private/var/folders` 下的临时文件夹内（两种情况都会先解析符号链接），并且绝不触碰 `~/Documents`、`~/Desktop`、`~/Downloads`、`~/Pictures`、`~/Movies`、`~/Music`、`~/.ssh`、`~/.gnupg` 和 iCloud 云盘。清理之前，计划会列出仍在运行、会重新写入其缓存的应用（请先退出它们）。每次清理都会记录到 `~/.cleandevmac/clean.log`，与 cdm 使用同一份日志。
- **其余一键直达**：Docker / Podman、Rust 工具链及其离线文档（用 `rustup` 移除）、已卸载应用的残留数据以及沙盒应用的缓存需要容器引擎、rustup 或对应用的扫描，因此 `⌘↵` 会在您首选的终端中直接从最新发布版本运行完整的 cdm。

### 12. 📦 一键安装：setup-zsh、MacStats 与开发工具
输入 `install`（或工具名称）并按下 **`↵`**：Lightspot 会在您首选的终端中运行该工具自己的安装程序，每一步都清晰可见。
- **Install setup-zsh**（[setup-zsh](https://github.com/openhoangnc/setup-zsh)）：可匹配历史记录任意位置的 zsh 自动建议、语法高亮，以及显示 git 状态的提示符。运行 `setup.sh` 后，打开一个加载了它的新 zsh。安装后，同一行可用于更新。
- **Install MacStats**（[mac-stats](https://github.com/openhoangnc/mac-stats)）：在菜单栏显示 CPU、内存、网速和 CPU 温度。运行其 `install.sh`，将其安装到 `/Applications` 并启动。
- **Install Dev Tools**：setup-zsh 的 `install-dev-tool` 菜单：Homebrew、Node.js、Go、Python 与 uv、Rust、JDK、Bun、Git、VS Code、Chrome、OrbStack、Android Studio 等，还能更新您的全局软件包。输入 `install node`、`install go`、`install rust` 等即可；如果没有 setup-zsh，该行会先安装它。
- 每一行都会显示工具是否已安装；**`⌥↵`** 打开其 GitHub 页面。

### 13. 🎛️ macOS 调整
那些您通常会从 dotfiles 的 README 中复制的 `defaults write` 单行命令，现在是快捷操作。每个开关都会读取当前设置并将其反转，因此同一行即可恢复：
- **程序坞**：**Clear Dock Icons**（先把程序坞的图标保存到 `~/Library/Application Support/Lightspot/dock-backup.plist`，再移除所有固定的应用并重启程序坞）、**Restore Dock Icons**（把图标放回原来的位置，保留之后添加的图标，并且只在重启后的程序坞显示出这些图标后才删除备份；两者都会等刚启动的程序坞稳定下来，若重启丢失了更改会再试一次）、**Toggle Dock Auto-Hide**、**Toggle Instant Dock Auto-Hide**（无延迟）、**Toggle Dock Recent Apps**、**Restart Dock**。
- **访达**：**Toggle Hidden Files in Finder**、**Toggle File Extensions in Finder**、**Toggle Finder Path Bar**、**Toggle Desktop Icons**（屏幕共享前很实用）、**Toggle .DS_Store on Network & USB Drives**、**Restart Finder**。
- **输入与截图**：**Toggle Press-and-Hold Accents**（按住按键即可重复输入）、**Toggle Smart Quotes & Dashes**、**Toggle Screenshot Shadows**。

均无需管理员密码。Restore Dock Icons 可撤销 Clear Dock Icons，开关类操作用同一行即可恢复。如需再调整 41 项设置（每项都显示状态并可撤销），请使用 Mac Tweaks 的 Settings（第 14 节）。

### 14. 🧰 Mac Tweaks (`free up space`)
Mac Tweaks 会释放 macOS 一直占着的空间，为这台 Mac 上的所有账户关闭 Apple Intelligence，以可撤销的方式更改 41 项 macOS 设置，并关闭或删除其他应用安装的 launchd 代理和守护进程。输入 `mac tweaks`、`free up space`、`debloat` 或想清除的内容（`remove garageband`、`macos installers`、`time machine snapshots`、`app caches`）并按下 **`↵`**，或在菜单栏中选择 **Clean Dev Mac...** 正下方的 **Mac Tweaks...**；输入 `turn off apple intelligence` 会直接打开 Apple Intelligence 部分，输入 `stop music from opening`、`turn off apple music`、`turn off mac analytics`、`turn off personalized ads` 或 `show the library folder` 会直接打开 Settings 部分，输入 `turn off background items`、`turn off launch agents`、`disable launch agents`、`turn off google updater`、`leftover launch agents` 或 `launch daemons` 会直接打开 Background Items 部分。它在自己的窗口中打开，每个部分一个标签页；每个部分在更改任何内容之前都会显示逐项计划，完成后显示结果。切换到系统设置批准描述文件或回应 Touch ID 提示时，窗口仍保持打开；可以把它移到任何位置（会记住位置），用关闭按钮、`⌘W` 或 `Esc` 关闭。（第 13 节中的 `defaults` 开关是快捷操作，不属于 Mac Tweaks。）
- **Free Up Space** 用与 Clean Dev Mac 相同的方式测量每一行；没有可释放内容的行会隐藏，0 字节的内容从不列出，前三行默认勾选：
  - **macOS installers**：`/Applications` 中旧的 `Install macOS*.app`，仅限带有 Apple 软件包标识符（`com.apple.InstallAssistant…`）的。
  - **iPhone and iPad updates**：访达下载的更新，位于 `~/Library/iTunes/iPhone Software Updates` 和 `iPad Software Updates`。
  - **Unavailable simulators**：运行时已不再安装的模拟器，通过 Xcode 的 `simctl` 处理；从不运行 `/usr/bin/xcrun`，因此只装了 Command Line Tools 的 Mac 没有这一行，也不会弹出它们的安装程序。
  - **Time Machine local snapshots**：本地快照，显示数量（macOS 不提供其大小）。
  - **Aerial videos**：这台 Mac 上所有账户共用的航拍视频（`/Library/Application Support/com.apple.idleassetsd/Customer`）；每个账户自己的副本是 Clean Dev Mac 中的一行。
  - **GarageBand and its sound library**：GarageBand 及其声音资源库；只要装有 Logic Pro 或 MainStage，资源库就会保留。
  - **iMovie**、**Keynote**、**Numbers** 和 **Pages**，仅限 Apple 自己的：不是 Apple 的 `Pages.app` 会保留。
  - **App caches**：`~/Library/Caches` 中的缓存，但不包括 macOS 自己的（`com.apple.*` 以及 macOS 写入的其他名称）、Lightspot 的，以及 Clean Dev Mac 规则涵盖的所有缓存，因此 Mac Tweaks 和 Clean Dev Mac 绝不会重复计算同一个文件夹。Mac Tweaks 从 Clean Dev Mac 的内存、`~/.cleandevmac/rules` 或应用内置的副本读取这些规则，从不下载。
  - 三个链接行：**Apple Intelligence models**（扫描过该部分之后、且模型仍在磁盘上时显示其大小）打开 Apple Intelligence 部分，**Developer caches and project junk** 打开 Clean Dev Mac，**More in System Settings** 打开系统设置中的储存空间。
- **Free Up Space 的文件去向**：移到废纸篓，在倒空废纸篓之前都能取回。模拟器（`simctl delete unavailable`）和快照（`tmutil deletelocalsnapshots`）会立即删除，对应的行也会注明；备份磁盘上的备份不受影响。结果会显示释放了多少空间、移到废纸篓的内容、删除的内容，以及留下的内容及原因，例如没有 App Management 权限时 macOS 不让 Lightspot 移动的应用（`⌥↵` 在访达中显示它）。
- **Apple Intelligence**（Apple 芯片，macOS 15.1 或更高版本）：这个 macOS 上的每项功能一行（Siri、ChatGPT 及其他 AI 扩展、Writing Tools、Genmoji、Image Playground、邮件・通知・信息・Safari 浏览器・备忘录的摘要、行内文本预测、Spatial Photos、Photos Clean Up、Xcode 预测性代码补全），显示其状态（On、Off、Locked off、Managed、Unknown）以及所需的模型。每项功能一开始都已勾选，表示要关闭；取消勾选即可保留。执行时会安装一个配置描述文件 **Lightspot Mac Tweaks**，由您在系统设置 › 通用 › 设备管理中批准（Lightspot 会打开它并最多等待 10 分钟；按 `Esc` 停止等待）：它为这台 Mac 上的所有账户关闭已勾选的功能，并把这些功能的模型下载指向一个关闭的本地端口。只有在描述文件生效后，Lightspot 才会请求 Apple 的资源服务删除保留的功能都不需要的模型，在 macOS 仍在使用时重试，并检查清单直到模型消失。**Finish removing the models** 会在重启后完成剩下的删除；**Turn Apple Intelligence back on** 会移除描述文件（如果其中还包含 Settings 的设置，则换成不含 Apple Intelligence 的描述文件）。由其他描述文件设定的功能保持原样，安装了 RemoveMacAI 的描述文件时，这个部分为只读。Lightspot 自身从不调用私有的资源框架：每次读取和删除都在一个短暂运行的子进程 `Lightspot --asset-service` 中进行，因此该框架占用的 9–11 MB 绝不会留在 Lightspot 的内存中。
- **Settings**：分为六组（Privacy、Annoyances、Apple apps、Finder、Dock and windows、Typing）的 41 项设置，每项显示它在这台 Mac 上的状态：On、Off、Partly、Managed（由其他描述文件设定，Lightspot 不会改动）或 Not on this macOS。一开始都不勾选；预设 **Recommended** 和 **Maximum privacy** 会勾选其中尚未开启的项。本地设置通过 cfprefsd 写入并读回确认，需要时 Finder、程序坞或 SystemUIServer 各重启一次。Mac Analytics、个性化广告、改进 Siri 与听写、改进搜索、Spotlight 互联网结果、Look Up 与 Safari 浏览器的搜索建议、Game Center、iPhone 镜像、Apple Music 和 Book Store 会放进同一个描述文件，其中 Apple Intelligence 的部分保持不变；计划会注明该描述文件适用于这台 Mac 上的所有账户。Apple Music 分三个层级：Apple Music 服务、让任何东西都无法打开“音乐”的启动项，以及播放、暂停和跳过键（`com.apple.rcd`）。选中的行和计划会把每项更改显示为命令（`defaults write …`、`launchctl …`、`chflags …`、`profile: …`）。
- **Background Items**：`~/Library/LaunchAgents`、`/Library/LaunchAgents` 和 `/Library/LaunchDaemons` 中的每个 `.plist` 各占一行，但不包括 macOS 自己的（`com.apple.*`）、没有 `Label` 的 plist（Google 的 Keystone 留下的空存根）以及以点开头的文件。每行显示该项目所属的应用（其程序所在的 `.app`、它运行的内容，或其 `AssociatedBundleIdentifiers` 指明的应用，因此 Docker 的辅助程序显示为“Docker”）、它的标签和它运行的内容（绝不显示其他参数，因为参数中可能含有令牌），以及它的状态：On、Off、Not loaded（可能已在系统设置的登录项中被关闭）或 Unknown，通过 `launchctl print-disabled` 和 `launchctl print` 读取。更新程序（标签或程序名中含有 `update`）带有 **Updater** 标记；既不是更新程序也不是残留项的行会提醒：关闭它可能导致所属应用无法正常工作。`Space` 勾选该行的更改：关闭（`launchctl disable`，然后 `bootout`）或重新开启（`enable`，然后 `bootstrap`）。`⌫` 改为把该行标记为删除，再按一次取消标记（该行显示 **Delete**）：Lightspot 先停止该项目，关闭它的标签，使其应用再写回的副本不会载入，然后把它的 plist 移到废纸篓；计划会显示等效的命令（`launchctl bootout`、`launchctl disable`、`mv … ~/.Trash/`）。删除仍已安装的应用的辅助程序可能导致该应用无法正常工作，应用也可能在下次运行时把它放回；该行和计划都会提醒。macOS 确认其程序已不存在的 **Leftover** 也以同样方式删除，并且只有它一开始就是勾选的。位于 macOS 保护的文件夹中或其他磁盘上的程序，以及以内联代码（`-c`、`-e`）运行的解释器，绝不会被判定为已不存在；plist 是符号链接、或与另一个 plist 共用标签的项目绝不会被移动，因此无法删除。您自己的代理以您的身份更改；每个守护进程的更改，以及只有管理员才能进行的移动，共用一次管理员授权；守护进程的更改适用于这台 Mac 上的所有账户，而关闭或开启 `/Library/LaunchAgents` 中的项目只对您的账户生效；删除守护进程或 `/Library/LaunchAgents` 中的项目适用于所有用户，可能会要求输入密码。只有 launchd 确认的结果才算数：结果会说明每个被删除的 plist 去了哪里，以及哪些仍在运行（守护进程直到重启，代理直到注销）或未能载入。作为符号链接的 plist 会逐个文件夹地追踪，绝不进入 macOS 保护的文件夹、其他磁盘或 `~/Library/CloudStorage`。最后一行会打开系统设置中的登录项。
- **撤销**：Lightspot 第一次更改某项设置之前，会把读到的值保存到 `~/Library/Application Support/Lightspot/tweaks-journal.json`，保存成功后才进行更改。勾选状态为 On 的行即可撤销它：按计划所示恢复为保存的值，若 Lightspot 没有保存任何值则恢复为 macOS 的默认值。**Undo everything Lightspot changed** 会恢复所有记录的更改，并在一次管理员授权后移除描述文件。它还会重新开启 Lightspot 关闭的后台项目（关闭之前已记入日志），并且只重新启动之前在运行的项目，其中的守护进程在同一次授权中恢复。plist 已不存在的条目不运行任何命令，直接从日志中删除，launchd 的开关保持关闭。它还会恢复 Lightspot 删除的后台项目：每个 plist 从废纸篓回到原来的位置，只按之前的状态开启和启动；root 的项目在同一次授权中恢复，并且只恢复 root 拥有的文件。它绝不会替换现在位于该位置的文件（如果应用已写回一个，Lightspot 只会把它重新开启），已不在废纸篓中的会加以说明并从日志中删除。只完成了一部分的设置属于您自己，只会被补全，绝不会被撤销。Free Up Space 移到废纸篓的文件和 Clear Dock Icons 的备份不在撤销范围内。
- **只在需要管理员时才要求密码**：删除快照、移动属于其他用户或因文件夹权限您自己无法移动的项目（该行会显示 **May ask for password**）、关闭或开启守护进程、删除和恢复守护进程或 `/Library/LaunchAgents` 中的项目，以及移除 Lightspot 的描述文件。一次执行中需要管理员权限的部分都放进一个脚本，只运行一次，通过 sudo 的 Touch ID 或密码对话框授权。安装描述文件则由您自己在系统设置中点击完成。
- **按键**：`↑↓` 选择（选中的行会显示其项目、模型或命令），`Space` 勾选（在预设上勾选其所有行，在 Background Items 中勾选该行的更改），`⌫` 把后台项目标记为删除，`⇥` / `⇧⇥` 切换部分，`↵` 显示逐项计划，再按一次 `↵` 执行，`⌥↵` 在访达中显示 Free Up Space 某一行的第一个项目或某个后台项目的 plist，`Esc` 退出计划或停止等待系统设置，两者都没有时则像 `⌘W` 一样关闭窗口。
- **结果**：每次执行都以结果收尾，完成了所要求的操作时显示绿色勾号。即使关闭窗口，执行仍会继续，重新打开 Mac Tweaks 会先显示进度，再显示结果。每次执行都会记录到 `~/Library/Application Support/Lightspot/mac-tweaks.log`。某个部分的扫描结果因另一个部分的执行而过时后，会重新扫描：Apple Intelligence 和 Settings 共用描述文件，Settings 和 Background Items 共用撤销日志。
- **绝不触碰**：Free Up Space 绝不触碰 `/System` 下的任何内容，`~/Desktop`、`~/Documents`、`~/Downloads`、`~/Pictures`、`~/Movies`、`~/Music`、iCloud 云盘、`~/Library/Containers`、`~/Library/Group Containers`、邮件、信息和 iPhone 备份（`MobileSync`），也绝不改动应用包内部：每个路径都必须直接位于该行固定的文件夹中（按原样以及解析符号链接后都要满足），自身不能是符号链接，并在移动前再检查一次。Apple Intelligence 和 Settings 不会改动其他配置描述文件设定的任何内容。Background Items 从不列出 macOS 自己的项目，也不改动它那三个文件夹以外的任何内容；它直接运行 `launchctl`，从不经过 shell，以 root 身份时只对扫描找到的标签和 plist 操作。Mac Tweaks 在您打开它之前什么都不读取，也不发出任何网络请求。
- **致谢**：Free Up Space、Apple Intelligence、Settings 和 Background Items 移植了 omlahore 的 [RemoveMacAI](https://github.com/omlahore/RemoveMacAI)（MIT 许可证）中的逻辑。其中 Apple Intelligence 的部分基于 4evy 的 [pared](https://github.com/4evy/pared)（MIT 许可证），Lightspot 的资源服务桥接、模型目录和下载拦截也遵循了它的做法。详见 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。

---

## ✨ 额外的内置功能

- **精确的macOS Spotlight UI**：带有动画展开和预览窗格（`NSVisualEffectView`）的浮动半透明超椭圆胶囊。
- **Mach / IOKit硬件HUD**：即时、无子进程的硬件诊断 (`sys`, `cpu`, `ram`, `memory`, `disk`, `battery`, `uptime`, `specs`, `resources`)：
  - 标准化多核CPU负载 %
  - 活动、固定、压缩和总物理RAM
  - 引导SSD可用和总存储空间
  - 电池百分比和充电状态
- **智能计算与灵活转换**：支持单位、货币和数字基数的完整递归下降数学解析器：
  - 数学：`(25 * 4) + sqrt(144)`, `2^16`, `log(1000)`
  - 单位：`100km in mi`, `72F in C`, `16GB in MB`
  - 货币：`$100 in EUR`, `50 GBP in USD`
  - 数字基数：`0xFF in dec`, `255 in hex`, `0b1010 in dec`
- **默认浏览器书签、历史记录与标签页**：仅为当前处于活动状态的默认浏览器（**Chrome**、**Safari**、**Firefox**、**Arc**、**Brave**、**Edge**）提供零冗余集成。书签和近期历史记录直接从浏览器自身的文件中读取（历史记录涵盖最近3天或7天，默认7天，也可通过菜单栏的 **Browser History** 关闭）；打开的标签页则通过Safari和基于Chromium的浏览器查询。
- **内存中的临时剪贴板**：仅限RAM的易失性环形缓冲区（最多50项），可通过 `clip <query>` 访问。从不写入磁盘，并严格过滤密码管理器（`1Password`、`Bitwarden`）。
- **macOS系统设置深层链接**：46 个直接深层链接，用于打开特定的macOS设置窗格 (`x-apple.systempreferences:...`)，可用系统设置自身搜索所用的关键词查找 (`night shift`, `lockdown mode`, `sticky keys`)，支持你的系统语言。在 macOS 27.2 上，系统设置退出后 LaunchServices 可能一分钟以上都没有察觉；这时 Lightspot 会在正在运行的系统设置中打开该窗格，没有正在运行的才新启动一个，而不是弹出它“已不再打开”的提示；程序坞中不会堆积多个副本。
- **多引擎网页搜索**：内置前缀快捷键：`g` (Google), `gh` (GitHub), `so` (StackOverflow), `npm`, `crates`, `wiki`, `mdn`, `yt`, `ddg`，另有 `brew <formula>`，它会打开 formulae.brew.sh 上对应formula的页面，而不是执行搜索。

---

## 🛑 完整的macOS Spotlight管理

Lightspot在菜单栏中内置了自动化功能，以禁用或重新启用Apple内置的Spotlight：

1. **Spotlight快捷键 (`⌘Space`)**：在无需root的情况下，禁用或恢复Apple默认的Spotlight热键——包括 `⌘Space`（「显示Spotlight搜索」）和 `⌥⌘Space`（「显示Finder搜索窗口」）。更改通过偏好设置守护进程写入，并通过回读进行验证，立即生效（无需注销）；而且一旦macOS释放 `⌘Space`，Lightspot便会立即将其收归自用。
2. **后台进程 (`com.apple.Spotlight`)**：通过 `launchctl` 禁用或启用Spotlight GUI后台代理。启用时还会加载并启动该代理，因此无需注销即可恢复Spotlight。
3. **文件索引 (`mdutil`)**：完全关闭所有挂载卷上的文件系统元数据索引 (`mds` / `mds_stores`)。
4. **一键主操作**：
   - **`Disable Everything (Shortcut + Process + Indexing)...`**：彻底关闭Apple Spotlight，以收回CPU、RAM、磁盘空间和 `⌘Space`。
   - **`Restore Default Spotlight...`**：随时将所有设置恢复为出厂macOS默认值。

---

## 🚀 构建与安装 (无需Xcode)

### 📦 方式A：单行命令安装 (推荐)
直接下载并安装最新预构建版本。每个版本都包含安装程序和更新程序会按您的 Mac 选择的 `Lightspot-arm64.zip`（Apple 芯片，约 1.6 MB）和 `Lightspot-x86_64.zip`（Intel，约 1.75 MB），通用应用 `Lightspot.zip`（约 2.9 MB），以及用于解读崩溃报告的符号文件 `Lightspot.app.dSYM.zip`：
```bash
curl -fsSL https://raw.githubusercontent.com/openhoangnc/mac-lightspot/main/install.sh | bash
```

### 🛠️ 方式B：从源码构建 (本地代码库)
```bash
# 1. 构建发布版本
./build.sh
# 或者: make build

# 2. 直接运行
./run.sh
# 或者: make run

# 3. 安装至 /Applications (或加 --user 安装至 ~/Applications)
./install.sh
# 或者: make install

# 4. 卸载
./uninstall.sh
# 或者: make uninstall
```

`./build.sh` 会以完整的链接时优化（LTO）编译每个架构，并去掉本地符号名（保留在 `build/Lightspot.app.dSYM` 中）：1.4.0 的通用二进制文件为 5.1 MB，比 1.3.9 的 8.8 MB 小 42%；仅 Apple 芯片版本为 2.2 MB（Intel 版本为 2.9 MB）。

### 4. 测试与验证
Lightspot没有XCTest目标。`scripts/` 下有三个独立脚本，会随源码一起即时编译，并需在仓库根目录下运行：逻辑与引擎测试运行器（84个测试块）、实时系统验证器（15个部分，在开发者的 Mac（macOS 27.2）上共206项检查；例如没有zsh历史记录、未安装VS Code或无法访问GitHub时，部分检查会被跳过），以及一项检查：它在屏幕外创建真实的 Mac Tweaks 和 Clean Dev Mac 窗口，使用只读扫描，让 Mac Tweaks 的每个部分经历重新扫描和部分切换，并让两个窗口经历各自的按键：
```bash
# 核心逻辑与引擎测试 (84个测试块)
swiftc -o /tmp/test_engine scripts/test_engine.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift Sources/Lightspot/System/AutoStartManager.swift Sources/Lightspot/System/SpotlightManager.swift Sources/Lightspot/System/FirstRunManager.swift Sources/Lightspot/System/UpdateManager.swift Sources/Lightspot/System/SingleInstanceGuard.swift Sources/Lightspot/System/LegacyNetworkStores.swift Sources/Lightspot/System/HotkeyManager.swift Sources/Lightspot/System/SystemShortcutConflicts.swift && /tmp/test_engine

# 实时系统检查 (15个部分，macOS 27.2 上共206项检查)
swiftc -o /tmp/deep_verify scripts/deep_verify.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift && /tmp/deep_verify

# 在屏幕外检查 Mac Tweaks 和 Clean Dev Mac 窗口 (约一分钟)
swiftc -parse-as-library -o /tmp/overlay_check scripts/overlay_check.swift $(find Sources/Lightspot -name '*.swift' ! -name AppMain.swift) && /tmp/overlay_check
```

---

## ⌨️ 快捷键与导航

| 按键 | 动作 |
|---|---|
| **`⌘Space`** / **`⌘⇧Space`** / **`⌥Space`** / **`⌃Space`** | 在任何位置呼出或关闭Lightspot（可在菜单栏中配置） |
| **`↓` / `↑`** | 在搜索结果中导航 |
| **`Return` (`↵`)** | 打开所选应用、在IDE中打开项目、运行命令或复制计算结果 |
| **`⌘Return` (`⌘↵`)** | 在首选终端中打开所选项目 |
| **`⌥Return` (`⌥↵`)** | 在Finder中显示项目 / 强制终止所选进程 (`SIGKILL`) / 打开安装项的 GitHub 页面 / 在Finder中显示 Mac Tweaks 某一行的第一个项目 |
| **`⌘P`** | 固定或取消固定所选终端历史记录命令 |
| **`⌘⇧P`** | 打开固定命令管理器浮层 |
| **`⌘⇧C`** | 打开自定义命令管理器浮层 |
| **`Space`** | 在 Clean Dev Mac 中勾选或取消勾选类别，或在 Mac Tweaks 中勾选或取消勾选行 |
| **`Delete` (`⌫`)** | 在 Mac Tweaks 中把后台项目标记为删除或取消标记 |
| **`Tab` (`⇥`)** | 在 Clean Dev Mac 中同时扫描代码库 / 在 Mac Tweaks 中切换到下一个部分（`⇧⇥` 上一个） |
| **`⌘Y` / `⌘⇧H`** | 打开搜索历史记录管理器浮层 |
| **`Escape`** | 关闭浮层、清除搜索字段或关闭Lightspot；在 Mac Tweaks 和 Clean Dev Mac 窗口中返回，再按则关闭窗口 |
| **`⌘W`** | 关闭 Mac Tweaks 或 Clean Dev Mac 窗口 |
| **点击外部** | 自动关闭悬浮面板 |

呼出所用的快捷键可在菜单栏的 **Shortcut** 中从四者里选择。macOS 将 `⌃Space` 指定为「选择上一个输入源」，因此选用它时，该按键也会切换输入源；**Shortcut** 子菜单会指出哪个系统快捷键已占用所选的组合。

---

## 🔒 隐私与安全保证

- **零文件索引**：Lightspot绝不会对您的个人文件、文档、下载或代码库进行索引。Clean Dev Mac 只测量 cdm 规则所指定的缓存文件夹以及两条提示所需的少数位置（见下文），且仅在您打开它时进行，除大小外不保留任何内容；它从不读取其他应用的沙盒容器。为了 Android 和 Claude Code 这两类行，它还会读取 AVD 文件夹和 `~/.claude/projects` 中文件的日期，以及 `~/.claude/sessions` 里标明运行中会话的小文件；从不读取对话记录的内容。对于被强制退出的 Chrome 留下的副本，它会列出您自己临时文件夹中的这些副本，并读取您正在运行的应用的启动时间。为了 cdm 的两条提示，它会读取已用的交换空间大小，测量 macOS 开机时清空的临时文件夹和 `~/.claude/projects` 的大小，向 `lsof` 查询应用仍打开着的已删除文件（只保留总量和占用最多的三个应用的名称），并读取 `~/.claude/settings.json` 中的两个键（`cleanupPeriodDays`、`desktopSessionCleanupPeriodDays`），从不写入该文件。当您要求它扫描代码库（`⇥`）时，它会在您的主文件夹中查找 git 代码库，最多六层，不进入 `~/Library`、`~/Documents`、`~/Desktop`、`~/Downloads`、`~/Pictures`、`~/Movies` 和 `~/Music`，并询问每个代码库的 git 忽略了哪些文件。Mac Tweaks 只读取固定的几处位置，且只读取您打开的那个部分所需的内容。Free Up Space：`/Applications` 中的名称，以及其中 Install macOS 应用和 GarageBand、iMovie、Keynote、Numbers、Pages 的 `Info.plist`；`~/Library/iTunes/iPhone Software Updates` 和 `iPad Software Updates`、`/Library/Application Support/com.apple.idleassetsd/Customer` 以及 `~/Library/Caches` 中的条目，包括每个列出项目的大小和所有者；GarageBand 的三个资源库文件夹，以及是否装有 Logic Pro 或 MainStage；Xcode 的 `simctl` 列出的不可用模拟器和 `tmutil` 列出的本地快照日期；有航拍视频可列出时读取壁纸索引（`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`）；以及 Clean Dev Mac 的规则。执行时，它逐个查询 `~/.Trash` 中的名称，从不列出废纸篓的内容。Apple Intelligence：资源服务中模型集及其大小的清单，由短暂运行的辅助进程读取，该进程不读取任何文件夹（只在删除过程中读取 `/System/Library/AssetsV2` 里某个模型集文件夹的条目数，从不列出内容），以及通过 cfprefsd 读取各功能的设置和两个描述文件的标记。Settings：通过 cfprefsd 读取其 41 项设置的偏好设置和限制、程序坞的图标以及描述文件的标记，还有 launchctl 的已停用服务列表、Music.app 及其可执行文件的 inode 号、资源库文件夹的隐藏属性，以及它的撤销日志。Background Items：`~/Library/LaunchAgents`、`/Library/LaunchAgents` 和 `/Library/LaunchDaemons` 中的名称，以及其中的每个 `.plist`（只在它是不超过 1 MiB 的普通文件时读取，只保留标签、程序、参数、关联应用的标识符和 `Disabled`，参数从不显示也不记录）；您的账户和系统的 `launchctl print-disabled`，以及每个项目的 `launchctl print`（只保留退出状态，因为其输出会列出该任务的环境变量）；plist 指明的每个程序，或解释器运行的脚本，逐个文件夹地查询，绝不进入 macOS 保护的文件夹、其他磁盘或 `~/Library/CloudStorage`；每个 plist 的所有者；LaunchServices 中 plist 指明的应用；以及撤销日志中的后台项目条目。撤销日志中有后台项目时，Settings 也会为 Undo everything 的计划读取一次这三个文件夹。扫描超过五分钟后，关闭 Mac Tweaks 会丢弃找到的内容，只保留 Free Up Space 的总量和 Apple Intelligence 扫描读到的模型信息。
- **纯RAM的临时剪贴板**：剪贴板历史记录仅保留在易失性内存中，并主动忽略隐藏/密码管理器类型（`org.nspasteboard.ConcealedType`、`1Password`、`Bitwarden`）。它从不写入磁盘，也不会进入搜索历史；搜索历史同样不会保存您从计算器、开发者工具或代码段结果中复制的文本。
- **默认浏览器隔离**：书签、已打开的标签页和近期浏览历史仅在本机从您配置的默认浏览器中读取，避免跨浏览器抓取。
- **由用户触发的命令**：您的命令、脚本和快捷操作只有在明确的用户操作（`Return` 或 `⌘↵`）下才会运行。
- **管理员命令只运行一次**：特权命令通过带 Touch ID 的 `sudo` 或 macOS 密码对话框运行，自 1.4.0 起绝不会运行两次：命令会先输出一个随机标记，一旦这个标记表明 sudo 已启动该命令，其结果即为最终结果，因此在 Touch ID 下运行失败的命令不会再在密码对话框后重新运行。标记之后其标准输入为 `/dev/null`，因此它运行的任何内容都不会在隐藏的终端上等待输入。Lightspot 自己构建的脚本（Mac Tweaks 的管理员批处理，每个参数都用单引号括起）走另一个不改动脚本内容的入口。系统日志只记录特权命令是否运行及其退出状态，绝不记录可能包含文件路径的命令文本。
- **零遥测，仅与两个由您掌控的服务通信**：没有分析统计、没有追踪、无需账号。Lightspot 自身只与两个服务通信，且两者都由您决定。第一个是用于更新的 GitHub：向公共发布 API（`api.github.com/repos/openhoangnc/mac-lightspot/releases/latest`）发出未经身份验证的 `GET` 请求，`User-Agent` 为 `Lightspot/<版本> (+https://github.com/openhoangnc/mac-lightspot)`；它在启动后不久以及打开菜单栏菜单时发出，但检查成功后每天最多一次（检查失败会在下次启动或打开菜单时重试）。在菜单栏中关闭 **`Automatically Check for Updates`**，它便不会自行发出。安装您接受的更新时，会从 GitHub 下载其 zip 文件（`User-Agent: Lightspot/<版本>`）。两者都使用临时（ephemeral）会话，因此不会在磁盘上保存任何响应或 Cookie。旧版本使用的是 macOS 的共享会话（更新检查直到 1.2.0，IP 查询在 1.2.0 之前），会把响应留在 `~/Library/Caches/com.lightspot.app`，把 Cookie 留在 `~/Library/HTTPStorages`；Lightspot 会在启动时删除这些残留，卸载程序也会将其删除。第二个是 ipify：`GET https://api.ipify.org`（第三方服务），用于获取您的公网IP，并且只在您主动查询时发出：输入明确指向它的查询（`ip`, `my ip`, `public ip`, `ipv4`），或在 **IP Address** 行上按下 `Return`。与任何网站一样，ipify 会看到您的IP地址和一个标准的 macOS User-Agent。查询结果仅在内存中缓存 15 分钟，从不写入磁盘。打开 **Clean Dev Mac** 时，还会向 GitHub 请求 cdm 的规则文件（`GET https://raw.githubusercontent.com/cleandevmac/cdm/main/rules/index.json` 及其中列出的文件，使用标准的 macOS User-Agent，通过临时会话发出），每小时最多一次；规则只保存在内存中，没有网络时使用应用内置的副本。将您自己的规则放在 `~/.cleandevmac/rules` 中即可完全不发出此请求。Mac Tweaks 不发出任何请求：它从内存、`~/.cleandevmac/rules` 或应用内置的副本读取 Clean Dev Mac 的规则，从不下载。在终端中运行 cdm（`⌘↵`）会从 cdm 的 GitHub 发布版本下载其脚本，与 cdm 自己的说明一致。安装类的行也是如此：每一行都在您的终端中运行对应工具的安装程序，从 GitHub 下载的是该脚本，而不是 Lightspot。网页搜索、URL 和书签由您的浏览器打开，且仅在您按下 `Return` 时才会打开。
- **写入磁盘的内容**：Lightspot 自身的偏好设置（`UserDefaults`，位于 `~/Library/Preferences/com.lightspot.app.plist`）、一个锁文件、安装更新期间的临时文件、清理时写入 cdm 日志的记录，以及在 Mac Tweaks 中执行操作时写入的小文件：
  - 设置：`lightspot_hotkey_option`, `lightspot_terminal_app`, `lightspot_search_engine`, `lightspot_browser_history_days`, `lightspot_hide_menubar_icon`, `lightspot_auto_start_enabled`, `lightspot_first_run_completed`, `lightspot_spotlight_state`（最近一次检测到的 Spotlight 状态，用于菜单显示）、`lightspot_auto_update_enabled`, `lightspot_last_update_check`, `lightspot_skipped_version`（自动更新检查）。
  - 您创建的内容：`lightspot_pinned_commands`, `lightspot_custom_commands`, `lightspot_snippets`。
  - 使用记录：`lightspot_recent_app_bundle_ids`（最近启动的应用）和 `lightspot_search_history`：您输入的查询和打开的结果（标题、应用与项目路径、URL、Shell 命令），以及用于排序的选择次数。可在搜索历史管理器（`⌘Y`）中查看或清除。剪贴板、计算器和开发者工具的选择从不记录；代码段和硬件报告的选择只保留查询词和次数，绝不保存复制的文本。
  - `~/.cleandevmac/clean.log`：仅在您使用 Clean Dev Mac 清理时写入。每次清理删除或移到废纸篓的内容，会追加到 cdm 自己使用的日志中（与 cdm 一样以 1 MiB 为上限）。您在清理器中确认的内容会被永久删除，标记为 Trash 的类别除外，它们会被移到废纸篓。
  - `~/Library/Application Support/Lightspot/mac-tweaks.log`：仅在您于 Mac Tweaks 中执行操作时写入。记录每次执行的开始和结束时间、更改、移到废纸篓或删除的内容、留下的内容及原因，以及释放的空间。超过 1 MiB 时只保留最新的 256 KiB（与 cdm 的日志一样）。您在 Free Up Space 中确认的文件会移到废纸篓；不可用的模拟器和 Time Machine 快照会被永久删除。
  - `~/Library/Application Support/Lightspot/tweaks-journal.json`：Mac Tweaks 的撤销日志，记录每项设置在 Lightspot 更改之前的值，以及 Lightspot 关闭或删除的每个后台项目之前是否已关闭、是否已载入，被删除项目的 plist 原来的位置和在废纸篓中的去向，在更改之前保存，撤销后删除。Lightspot 无法读取的日志绝不会被覆盖，而是另存为 `tweaks-journal-unreadable-<日期>-<id>.json`。Settings 也会写入其他应用的偏好设置（访达、程序坞、全局域等），但只写入您执行的那些，且每项都先记入日志。
  - `~/Library/Application Support/Lightspot/dock-backup.plist`：Clear Dock Icons 在清空程序坞之前写入，图标恢复后由 Restore Dock Icons 删除。
  - `~/Library/Application Support/Lightspot/LightspotMacTweaks.mobileconfig`：仅在一次执行等待您批准 Lightspot 的描述文件期间存在，安装后即删除。描述文件 **Lightspot Mac Tweaks** 本身由您在系统设置中安装，适用于这台 Mac 上的所有账户；在那里移除它即可撤销它所做的一切更改。
  - 卸载程序会删除以上所有文件，但保留撤销日志和程序坞备份，以便重新安装的 Lightspot 仍能撤销，并会说明保留了什么以及如何撤销。Lightspot 关闭的面向所有用户的后台项目在所有账户中保持关闭。
  - `~/Library/Application Support/Lightspot/com.lightspot.app.lock`：防止启动第二个副本。其中记录正在运行的进程的 PID，以及其可执行文件的路径、inode 和修改时间，以便新的启动能区分是同一构建还是更新的构建。
  - 安装您接受的更新期间：下载的文件、解压后的应用包和一个小型辅助脚本位于 macOS 临时目录（`NSTemporaryDirectory()`，文件夹 `lightspot-update-…` 与 `lightspot-updater-…`）中，旧版本会以 `Lightspot.app.lightspot-old` 保留在应用旁边，直到新版本就位。辅助脚本完成后会将它们全部删除。
  - **Export Settings** 只会将 JSON 备份（包含搜索历史）写入您选择的文件。
