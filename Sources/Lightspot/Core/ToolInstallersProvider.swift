import AppKit

// MARK: - Tool Installers Provider
//
// One-keystroke installs for the author's own tools: setup-zsh (zsh setup, which also
// carries the `install-dev-tool` menu) and MacStats (menu bar monitor). Each row runs the
// tool's own documented installer in the preferred terminal, where its output and any
// prompt stay in front of the user; nothing is installed behind their back.

struct ToolInstaller: Sendable, Equatable {
    enum ID: String, Sendable, CaseIterable {
        case setupZsh = "setup-zsh"
        case macStats = "mac-stats"
        case devTools = "dev-tools"
    }

    let id: ID
    let title: String
    let keywords: [String]
    let sfSymbol: String
    /// What the tool is, for the row when it is not installed yet.
    let summary: String
    let repository: URL

    /// The row's action: a sentinel, like `internal:copy-ip`, so search history keeps the
    /// row rather than a command that depends on what was installed at the time.
    var script: String { "internal:install:\(id.rawValue)" }
    var resultID: String { "action-install-\(id.rawValue)" }
}

/// What is installed, as last read off the disk.
struct ToolInstallState: Sendable, Equatable {
    var setupZsh = false
    var macStats = false
}

final class ToolInstallersProvider: @unchecked Sendable {
    static let shared = ToolInstallersProvider()

    static let setupZshScript = "https://raw.githubusercontent.com/openhoangnc/setup-zsh/main/setup.sh"
    static let macStatsScript = "https://raw.githubusercontent.com/openhoangnc/mac-stats/main/install.sh"

    static let installers: [ToolInstaller] = [
        ToolInstaller(
            id: .setupZsh,
            title: "Install setup-zsh",
            keywords: ["setup-zsh", "setup zsh", "zsh", "zshrc", "zsh setup", "oh my zsh", "ohmyzsh",
                       "autosuggestions", "syntax highlighting", "shell setup", "git prompt", "install"],
            sfSymbol: "apple.terminal.fill",
            summary: "Zsh autosuggestions that match anywhere, syntax highlighting, a git prompt",
            repository: URL(string: "https://github.com/openhoangnc/setup-zsh")!
        ),
        ToolInstaller(
            id: .macStats,
            title: "Install MacStats",
            // Names only: "temperature" or "cpu" would make a reinstall the Top Hit for a
            // question MacStats answers once installed.
            keywords: ["macstats", "mac stats", "mac-stats", "menu bar stats", "menu bar monitor", "install"],
            sfSymbol: "chart.xyaxis.line",
            summary: "CPU, RAM, network speed and CPU temperature in the menu bar",
            repository: URL(string: "https://github.com/openhoangnc/mac-stats")!
        ),
        ToolInstaller(
            id: .devTools,
            title: "Install Dev Tools",
            keywords: ["install-dev-tool", "install dev tool", "install dev tools", "dev tools installer",
                       "install homebrew", "install brew", "install node", "install nodejs", "install go",
                       "install golang", "install python", "install uv", "install rust", "install bun",
                       "install jdk", "install java", "install git", "install vscode", "install vs code",
                       "install chrome", "install orbstack", "install android studio", "install claude",
                       "install chatgpt", "install gcloud", "install dbx", "install mongodb compass",
                       "install antigravity", "update dev tools", "update global packages", "install"],
            sfSymbol: "shippingbox.fill",
            summary: "setup-zsh's menu: Homebrew, Node.js, Go, Python & uv, Rust, JDK, Bun, VS Code, Chrome…",
            repository: URL(string: "https://github.com/openhoangnc/setup-zsh#4-dev-tools-installer-install-dev-tool")!
        ),
    ]

    static func installer(_ id: ToolInstaller.ID) -> ToolInstaller {
        installers.first { $0.id == id }!
    }

    static func installer(forScript script: String) -> ToolInstaller? {
        installers.first { $0.script == script }
    }

    // MARK: Install state

    /// setup-zsh puts everything under this folder; its `bin/` is on `PATH` once installed.
    static func setupZshDirectory(home: String) -> String { home + "/.zsh/setup-zsh" }
    static func devToolPath(home: String) -> String { setupZshDirectory(home: home) + "/bin/install-dev-tool" }
    static let macStatsBundleID = "com.openhoangnc.macstats"
    static let macStatsPath = "/Applications/MacStats.app"

    /// Blocking: reads the disk (and LaunchServices for MacStats, which may live elsewhere).
    static func readInstallState(home: String) -> ToolInstallState {
        let fm = FileManager.default
        return ToolInstallState(
            setupZsh: fm.isExecutableFile(atPath: devToolPath(home: home)),
            macStats: fm.fileExists(atPath: macStatsPath)
                || NSWorkspace.shared.urlForApplication(withBundleIdentifier: macStatsBundleID) != nil
        )
    }

    private let home: String
    private let lock = NSLock()
    private var state = ToolInstallState()
    private var lastRead = Date.distantPast
    private var reading = false
    private let queue = DispatchQueue(label: "com.lightspot.toolinstallers", qos: .utility)
    private static let staleAfter: TimeInterval = 10

    init(home: String = NSHomeDirectory()) {
        self.home = home
    }

    /// Non-blocking: the last state read, refreshed in the background when stale. The rows
    /// are on the keystroke path, so they never touch the disk themselves (invariant 0).
    var installState: ToolInstallState {
        lock.lock()
        let snapshot = state
        let due = Date().timeIntervalSince(lastRead) > Self.staleAfter && !reading
        if due {
            // Claim the slot now so a burst of keystrokes queues one read, not one each.
            reading = true
            lastRead = Date()
        }
        lock.unlock()
        if due {
            queue.async { [self] in
                let fresh = Self.readInstallState(home: home)
                lock.lock()
                state = fresh
                lastRead = Date()
                reading = false
                lock.unlock()
            }
        }
        return snapshot
    }

    /// Primes the state when the panel opens, so the first keystroke already has it.
    func warmUp() {
        _ = installState
    }

    // MARK: Commands

    /// What runs in the terminal for `installer`, given what is installed right now.
    static func command(for installer: ToolInstaller, state: ToolInstallState) -> String {
        // A fresh login zsh picks up what setup.sh wrote, as `source ~/.zshrc` would, without
        // loading its plugins twice into the shell that ran it.
        let setup = "curl -fsSL \(setupZshScript) | bash"
        switch installer.id {
        case .setupZsh:
            return "\(setup) && exec zsh -l"
        case .macStats:
            return "curl -fsSL \(macStatsScript) | bash"
        case .devTools:
            // The menu reads keys from the terminal, so it runs as a file, never piped, and it
            // writes its PATH entries into setup-zsh's env.zsh, so setup-zsh comes first.
            let menu = "~/.zsh/setup-zsh/bin/install-dev-tool"
            return state.setupZsh ? menu : "\(setup) && exec zsh -lic '\(menu); exec zsh -l'"
        }
    }

    /// Blocking: reads the install state fresh, then starts the installer in the terminal.
    func run(_ installer: ToolInstaller) {
        let fresh = Self.readInstallState(home: home)
        lock.lock()
        state = fresh
        lastRead = Date()
        lock.unlock()
        TerminalLauncher.run(Self.command(for: installer, state: fresh))
    }

    // MARK: Search

    static func subtitle(for installer: ToolInstaller, state: ToolInstallState) -> String {
        switch installer.id {
        case .setupZsh:
            return state.setupZsh
                ? "Installed · ↵ Update (re-runs setup; your own ~/.zshrc lines stay) · ⌥↵ GitHub"
                : "\(installer.summary) · ↵ Install in Terminal · ⌥↵ GitHub"
        case .macStats:
            return state.macStats
                ? "Installed · ↵ Reinstall the latest release in Terminal · ⌥↵ GitHub"
                : "\(installer.summary) · ↵ Install in Terminal · ⌥↵ GitHub"
        case .devTools:
            return state.setupZsh
                ? "\(installer.summary) · ↵ Open in Terminal"
                : "Comes with setup-zsh · ↵ Install setup-zsh, then open the installer"
        }
    }

    func search(_ query: SearchQuery) -> [SearchResult] {
        guard !query.isEmpty else { return [] }
        var results: [SearchResult] = []
        var state: ToolInstallState?
        for installer in Self.installers {
            var best = FuzzyMatcher.score(query: query, targetLower: installer.title.lowercased(), targetTokens: [], targetInitials: nil)
            for keyword in installer.keywords {
                if let score = FuzzyMatcher.score(query: query, targetLower: keyword, targetTokens: [], targetInitials: nil) {
                    best = max(best ?? 0, score * 0.95)
                }
            }
            guard let score = best else { continue }
            if state == nil { state = installState }
            results.append(SearchResult(
                id: installer.resultID,
                title: installer.title,
                subtitle: Self.subtitle(for: installer, state: state ?? ToolInstallState()),
                iconType: .systemSymbol(name: installer.sfSymbol),
                category: .quickActions,
                score: score,
                action: .runQuickAction(script: installer.script, usesOsascript: false)
            ))
        }
        return results
    }
}
