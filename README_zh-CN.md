# Lightspot 🔍

[English](README.md) | [简体中文](README_zh-CN.md) | [Español](README_es.md) | [日本語](README_ja.md) | [Français](README_fr.md)

> **纯粹的Swift构建，macOS Spotlight的轻量级、完美像素替代品 — 专为需要极速响应且免受文件索引臃肿困扰的开发者和高级用户设计。**

Lightspot忠实再现了macOS Spotlight现代的悬浮胶囊设计和半透明玻璃美学（`NSVisualEffectView`）。在底层，它提供亚毫秒级的响应能力（搜索时间 < 1.0毫秒），**完全没有后台文件索引**，消耗**0.0%的空闲CPU**和不到**25MB的RAM**。

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

Lightspot不主动抓取整个硬盘，而是严格关注高级用户实际搜索的内容：应用程序、IDE项目、浏览器选项卡、开发者实用工具和自定义命令。

### 比较矩阵

| 指标 | Apple Spotlight | Raycast / Alfred | Lightspot 🔍 |
|:---|:---|:---|:---|
| **文件索引** | 无法控制的后台抓取 | 可选 / 可配置 | **从不** (通过架构保证) |
| **空闲CPU使用率** | 操作期间峰值超过100% | 1% – 5% (后台) | **0.0%** (完全休眠) |
| **磁盘存储** | 10 GB – 200 GB+ 隐藏缓存 | 100 MB – 1 GB | **0 KB** (零磁盘占用) |
| **RAM占用** | 500 MB – 2 GB+ | 200 MB – 500 MB | **约15 – 25 MB** (纯Swift) |
| **应用启动** | 经常损坏；需要重建 | 可靠 | **100%可靠** (直接扫描) |
| **搜索延迟** | 防抖处理 (50 – 200 ms) | 10 – 30 ms | **< 1.0 ms** (瞬时同步) |
| **离线隐私** | 发送Siri遥测至Apple | 需要同步账号 | **100%本地、离线且无遥测** |

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
  - 绑定自定义的1-3个字母前缀（例如 `dlog <container>` 追踪docker日志，`c <url>` 请求curl headers，`png <host>` 进行ping操作）。
- **自定义关键字与图标**：
  - 添加模糊关键字以实现即时发现，并使用SF Symbols或base64应用图标自定义图标。

### 2. 💬 动态文本代码段 (`⌘P` / `snippets`)
定义带有自动动态变量扩展的可重用文本代码段：
- `{{date}}`：当前日期 (`YYYY-MM-DD`)
- `{{time}}`：当前时间 (`HH:mm:ss`)
- `{{iso}}`：ISO 8601 UTC 时间戳 (`2026-09-05T14:30:00Z`)
- `{{uuid}}`：随机UUID v4
- `{{clipboard}}`：当前剪贴板的内容

输入任何代码段关键字（例如 `iso`、`uuid`、`date`）并按 **`↵`** 即可将计算后的字符串直接复制到剪贴板。

### 3. 💻 从7种现代终端模拟器中选择
Lightspot与你最喜欢的终端模拟器集成。随时通过菜单栏切换：
- **Ghostty**、**Warp**、**Alacritty**、**iTerm2**、**Kitty**、**WezTerm** 和 **Apple Terminal**。
- **"Finder文件夹中的终端"**：输入 `term` 或按下操作，即可在Finder当前打开的目录中立即启动你首选的终端。

### 4. 📂 多IDE最近项目发现
Lightspot自动监控以下最近工作区：
- **VS Code**、**Cursor**、**Zed**、**JetBrains套件** (IntelliJ IDEA, WebStorm, PyCharm, CLion, GoLand, Rider等) 和 **Sublime Text**。
- **键盘修饰键**：
  - `↵` (Return)：在关联的IDE中打开工作区。
  - `⌘↵` (Command + Return)：在项目根目录启动首选终端。
  - `⌥↵` (Option + Return)：在Finder中显示项目文件夹。

### 5. 🔌 进程终止器与端口终止器 (`kill`)
快速终止残留的开发服务器、卡住的后台任务或恶意进程：
- **按端口终止：** `kill :3000`, `kill :8080`, `kill :5173` (通过 `lsof` 自动解析监听的PID)。
- **按进程名或PID终止：** `kill node`, `kill python`, `kill 14205`。
- **终止级别：**
  - `↵` (Return)：优雅终止 (`SIGTERM`)。
  - `⌥↵` (Option + Return)：强制终止 (`SIGKILL`)。

### 6. 🛠️ 内置离线开发者工具 (DevTools)
在毫秒内执行常见的开发者操作，无需打开Web实用工具或安装CLI包：
- **`uuid`**：生成具有密码学安全性的随机UUID v4。
- **`b64 <text>`** / **`b64d <hash>`**：Base64编码与解码。
- **`urlencode <url>`** / **`urldecode <url>`**：URL百分号编码。
- **`hash sha256 <text>`** / **`sha1`** / **`md5`**：即时加密校验和。
- **`jwt <token>`**：解码并漂亮地打印JWT头部和负载。
- **`json <raw>`**：格式化、缩进和验证压缩JSON。
- **`epoch`** / **`now`**：Unix时间戳与人类日期之间的相互转换。
- **`#3498db`**：实时颜色预览色板，支持一键复制Hex、RGB和HSL。

### 7. 🔐 Sudo及特权操作的无头Touch ID
利用指纹生物识别技术执行特权维护操作（如 `Flush DNS Cache`、`Purge Inactive Memory`）：
- **无终端弹出窗口**：通过后台伪终端(PTY)运行，调用macOS的 `pam_tid.so` 实现即时Touch ID身份验证。
- **在终端中切换Sudo的Touch ID**：一键菜单操作，配置 `/etc/pam.d/sudo_local`，让你在常规终端中的 `sudo` 命令也能使用Touch ID。

### 8. 📜 zsh历史记录与固定命令 (`⌘P` / `⌘⇧P`)
- 搜索本地的 `~/.zsh_history` (或自定义的 `$HISTFILE`)，提供亚毫秒级的即时排名。
- 在任何历史命令上按 **`⌘P`** 将其固定到启动器的顶部。
- 按 **`⌘⇧P`** 管理、重新排序或删除固定命令。

### 9. 📦 设置备份与跨机同步
- 将整个配置（自定义命令、固定项、代码段、热键）导出到干净的JSON文件中。
- 自动路径净化会将 `/Users/username` 替换为 `~`，这样配置就可以在工作Mac和个人Mac之间无缝共享。

---

## ✨ 额外的内置功能

- **精确的macOS Spotlight UI**：带有动画展开和预览窗格（`NSVisualEffectView`）的浮动半透明超椭圆胶囊。
- **Mach / IOKit硬件HUD**：即时、无子进程的硬件诊断 (`sys`, `cpu`, `ram`, `battery`, `uptime`)：
  - 标准化多核CPU负载 %
  - 活动、固定、压缩和总物理RAM
  - 引导SSD可用和总存储空间
  - 电池百分比和充电状态
- **智能计算与灵活转换**：支持单位、货币和数字基数的完整递归下降数学解析器：
  - 数学：`(25 * 4) + sqrt(144)`, `2^16`, `log(1000)`
  - 单位：`100km in mi`, `72F in C`, `16GB in MB`
  - 货币：`$100 in EUR`, `50 GBP in USD`
  - 数字基数：`0xFF in dec`, `255 in hex`, `0b1010 in dec`
- **默认浏览器书签与标签页**：仅为当前处于活动状态的默认浏览器（**Chrome**、**Safari**、**Firefox**、**Arc**、**Brave**、**Edge**）提供零冗余的书签和打开的标签页集成。
- **内存中的临时剪贴板**：仅限RAM的易失性环形缓冲区（最多50项），可通过 `clip <query>` 访问。从不写入磁盘，并严格过滤密码管理器（`1Password`、`Bitwarden`）。
- **macOS系统设置深层链接**：35+ 个直接深层链接，用于打开特定的macOS设置窗格 (`x-apple.systempreferences:...`)。
- **多引擎网页搜索**：内置前缀快捷键：`gh` (GitHub), `so` (StackOverflow), `npm`, `crates`, `wiki`, `mdn`, `brew`, `yt`, `ddg`。

---

## 🛑 完整的macOS Spotlight管理

Lightspot在菜单栏中内置了自动化功能，以禁用或重新启用Apple内置的Spotlight：

1. **Spotlight快捷键 (`⌘Space`)**：在无需root的情况下，禁用或恢复macOS符号热键中Apple默认的 `⌘Space` 快捷键。
2. **后台进程 (`com.apple.Spotlight`)**：通过 `launchctl` 禁用或启用Spotlight GUI后台代理。
3. **文件索引 (`mdutil`)**：完全关闭所有挂载卷上的文件系统元数据索引 (`mds` / `mds_stores`)。
4. **一键主操作**：
   - **`Disable Everything (Shortcut + Process + Indexing)...`**：彻底关闭Apple Spotlight，以收回CPU、RAM、磁盘空间和 `⌘Space`。
   - **`Restore Default Spotlight...`**：随时将所有设置恢复为出厂macOS默认值。

---

## 🚀 构建与安装 (无需Xcode)

Lightspot使用标准Swift工具和简单的Shell脚本构建。无需安装Xcode IDE。

### 1. 构建
```bash
./build.sh
# 或者: make build
```
编译发布二进制文件 (`-Osize -wmo`)，剥离调试符号，打包 `Info.plist` 和高分辨率图标，并为 `build/Lightspot.app` 签名。

### 2. 运行
```bash
./run.sh
# 或者: make run
```

### 3. 安装到 `/Applications`
```bash
./install.sh
# 或者: make install
# (传递 --user 以安装到 ~/Applications)
```

### 4. 测试与验证
Lightspot包含112个自动化测试套件和实时系统运行检查：
```bash
# 核心逻辑与引擎测试 (24个测试套件)
swiftc -o /tmp/test_engine scripts/test_engine.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift && /tmp/test_engine

# 实时系统检查 (88个验证检查)
swiftc -o /tmp/deep_verify scripts/deep_verify.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift && /tmp/deep_verify
```

---

## ⌨️ 快捷键与导航

| 按键 | 动作 |
|---|---|
| **`⌘Space`** / **`⌘⇧Space`** | 在任何位置呼出或关闭Lightspot（可在菜单栏中配置） |
| **`↓` / `↑`** | 在搜索结果中导航 |
| **`Return` (`↵`)** | 打开所选应用、在IDE中打开项目、运行命令或复制计算结果 |
| **`⌘Return` (`⌘↵`)** | 在首选终端中打开所选项目 |
| **`⌥Return` (`⌥↵`)** | 在Finder中显示项目 / 强制终止所选进程 (`SIGKILL`) |
| **`⌘P`** | 固定或取消固定所选终端历史记录命令 |
| **`⌘⇧P`** | 打开固定命令管理器浮层 |
| **`⌘⇧C`** | 打开自定义命令管理器浮层 |
| **`⌘Y` / `⌘⇧H`** | 打开搜索历史记录管理器浮层 |
| **`Escape`** | 关闭浮层、清除搜索字段或关闭Lightspot |
| **点击外部** | 自动关闭悬浮面板 |

---

## 📁 项目结构

```
mac-lightspot/
├── Package.swift                 # SPM 清单 (Swift 6, macOS 13+)
├── Makefile                      # make build / run / install / uninstall / clean
├── build.sh                      # 发布构建 & .app打包脚本
├── run.sh                        # 构建 & 启动助手
├── install.sh                    # 安装到 /Applications 或 ~/Applications
├── uninstall.sh                  # 干净的移除脚本
├── README.md                     # 文档 & 设计原理
├── CLAUDE.md                     # 架构、不变量 & 开发者指南
├── Resources/
│   ├── Info.plist                # LSUIElement=1, 权限, 应用程序包元数据
│   └── AppIcon.icns              # 多尺寸macOS应用程序图标
├── scripts/
│   ├── generate_icon.sh          # 编程式图标生成器 (Core Graphics + iconutil)
│   ├── test_engine.swift         # 自动化测试运行器 (24个测试套件)
│   └── deep_verify.swift         # 实时系统验证 (88个检查)
└── Sources/
    └── Lightspot/
        ├── AppMain.swift         # @main 入口点 & NSApplicationDelegate
        ├── Core/
        │   ├── Models.swift      # SearchResult, ResultCategory, SearchAction, FuzzyMatcher
        │   ├── AppScanner.swift  # 快速异步应用扫描器 & 内存图标缓存
        │   ├── BrowserIntegrationProvider.swift # 默认浏览器书签 & 标签页
        │   ├── CalculatorEngine.swift # 数学解析器 & 转换调度器
        │   ├── ClipboardHistoryManager.swift    # 内存中的临时剪贴板环形缓冲区
        │   ├── ConversionEngine.swift   # 单位、货币、基数 & 温度引擎
        │   ├── CustomCommandsStore.swift # 自定义用户命令模型 & 持久化
        │   ├── DevToolsProvider.swift   # UUID, Base64, Hash, JWT, JSON, 色板
        │   ├── NetworkInfoProvider.swift # 本地IPv4 & 公共互联网IP地址
        │   ├── ProcessKillerProvider.swift # 按名称、PID和端口终止进程
        │   ├── QuickActionsProvider.swift # 焦点系统操作 & Finder中的终端
        │   ├── RecentProjectsProvider.swift # 多IDE项目扫描器 (VS Code, Cursor, Zed, JetBrains, Sublime)
        │   ├── SearchEngine.swift       # 同步搜索聚合器 & 排名
        │   ├── SearchHistoryManager.swift # 搜索查询 & 选择历史记录
        │   ├── SettingsBackup.swift     # 设置导出 & 导入备份
        │   ├── SettingsProvider.swift   # 35+ 个macOS系统设置深层链接
        │   ├── ShellHistoryProvider.swift # zsh历史记录解析器 & 固定命令
        │   ├── SnippetsStore.swift      # 具有变量插值的文本扩展代码段
        │   ├── SystemInfoProvider.swift # 零子进程Mach/IOKit硬件HUD
        │   └── WebSearchProvider.swift  # 多引擎搜索 & 前缀快捷键
        ├── System/
        │   ├── HotkeyManager.swift      # Carbon全局热键
        │   ├── MenuBarController.swift  # 菜单栏状态栏项 & 偏好设置
        │   ├── SettingsBackupController.swift # 设置导入/导出控制器
        │   ├── SpotlightManager.swift   # macOS Spotlight 禁用/恢复自动化
        │   └── TerminalLauncher.swift   # 7个终端模拟器启动器 & Finder检测
        └── UI/
            ├── CustomCommandsView.swift # 自定义命令管理器浮层
            ├── HistoryManagerView.swift # 搜索历史记录管理器浮层
            ├── PinnedCommandsView.swift # 固定命令管理器浮层
            ├── PreviewPaneView.swift    # 丰富详情卡片 & 实时预览
            ├── SearchFieldView.swift    # NSTextField桥接 & 自定义字段编辑器
            ├── SearchViewModel.swift    # 响应式视图模型 & 按键事件路由器
            ├── SpotlightComponents.swift# 搜索结果行、按钮 & 类别标头
            ├── SpotlightPanel.swift     # 具有活力的悬浮无边框NSPanel
            └── SpotlightView.swift      # 根SwiftUI视图
```

---

## 🔒 隐私与安全保证

- **零文件索引**：Lightspot绝不会对您的个人文件、文档、下载或代码库进行索引。
- **纯RAM的临时剪贴板**：剪贴板历史记录仅保留在易失性内存中（从不写入磁盘），并主动忽略隐藏/密码管理器类型（`org.nspasteboard.ConcealedType`、`1Password`、`Bitwarden`）。
- **默认浏览器隔离**：书签和标签页仅从您配置的默认浏览器中读取，避免跨浏览器抓取。
- **沙盒化子进程**：只有在明确的用户操作（`Return` 或 `⌘↵`）下才会运行命令和脚本。
- **零遥测 & 100%离线**：没有网络请求、没有远程分析、没有任何追踪。
