import Foundation
import SwiftUI
import AppKit

enum SpotlightViewMode: Equatable {
    case applications
    case searchResults
}

@MainActor
final class SearchViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var query: String = ""
    @Published var selectedCategory: AppCategory = .all
    @Published var gridSelectedIndex: Int = 0
    @Published var searchSelectedIndex: Int = 0
    @Published var groupedResults: [ResultCategory: [SearchResult]] = [:]
    @Published var calculatorResult: String? = nil
    @Published var isPanelExpanded: Bool = true

    // Pinned command state. `pinnedCommands` mirrors PinnedCommandsStore so the
    // manager sheet can render without touching the lock on every body pass.
    @Published var isPinManagerPresented: Bool = false
    @Published var pinnedCommands: [String] = []
    @Published var pinSelectedIndex: Int = 0

    // Search history state
    @Published var isHistoryManagerPresented: Bool = false
    @Published var historyEntries: [SearchHistoryEntry] = []
    @Published var historySelectedIndex: Int = 0

    // Custom commands state
    @Published var isCustomCommandManagerPresented: Bool = false
    @Published var customCommands: [CustomCommand] = []
    @Published var customCommandSelectedIndex: Int = 0

    // MARK: - Dependencies
    weak var hotkeyManager: HotkeyManager?
    weak var menuBarController: MenuBarController?

    // MARK: - Callbacks
    var onHide: (() -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?

    // MARK: - Constants
    static let gridColumns = 7
    static let compactHeight: CGFloat = 68
    static let expandedHeight: CGFloat = 530

    // MARK: - Cached State
    private var _cachedRecentApps: [AppInfo] = []
    private var _cachedCategorySections: [(category: AppCategory, apps: [AppInfo])] = []
    private var _cachedAllApps: [AppInfo] = []

    // MARK: - Computed Properties

    var recentApps: [AppInfo] {
        if _cachedRecentApps.isEmpty {
            _cachedRecentApps = RecentAppsManager.shared.getRecentApps(limit: 7)
        }
        return _cachedRecentApps
    }

    var categorySections: [(category: AppCategory, apps: [AppInfo])] {
        if _cachedCategorySections.isEmpty {
            refreshSectionsCache()
        }
        return _cachedCategorySections
    }

    var viewMode: SpotlightViewMode {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .applications : .searchResults
    }

    var displayedApps: [AppInfo] {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if selectedCategory == .all {
                if _cachedAllApps.isEmpty {
                    refreshSectionsCache()
                }
                return _cachedAllApps
            } else {
                return AppScanner.shared.apps(for: selectedCategory)
            }
        } else {
            return AppScanner.shared.searchApps(SearchQuery(query))
        }
    }

    var flatSearchResults: [SearchResult] {
        SearchEngine.flatResults(from: groupedResults)
    }

    var hasSearchResults: Bool {
        !groupedResults.isEmpty || calculatorResult != nil
    }

    var selectedSearchResult: SearchResult? {
        let flat = flatSearchResults
        guard searchSelectedIndex >= 0 && searchSelectedIndex < flat.count else { return nil }
        return flat[searchSelectedIndex]
    }

    /// The shell command behind the current selection, when it is a history result.
    var selectedCommand: String? {
        guard let result = selectedSearchResult,
              case .runInTerminal(let command) = result.action else { return nil }
        return command
    }

    var selectedApp: AppInfo? {
        let apps = displayedApps
        guard gridSelectedIndex >= 0 && gridSelectedIndex < apps.count else { return nil }
        return apps[gridSelectedIndex]
    }

    /// Top hit app path (O(1), zero redundant search execution)
    var topHitAppPath: String? {
        if let sel = selectedSearchResult {
            if case .launchApp(let path) = sel.action {
                return path
            }
            if case .openFolder = sel.action {
                let appPath = VSCodeProjectsProvider.vsCodeAppPath
                if !appPath.isEmpty { return appPath }
            }
        }
        if let top = groupedResults[.topHit]?.first {
            if case .launchApp(let path) = top.action {
                return path
            }
            if case .openFolder = top.action {
                let appPath = VSCodeProjectsProvider.vsCodeAppPath
                if !appPath.isEmpty { return appPath }
            }
        }
        if let firstApp = groupedResults[.applications]?.first, case .launchApp(let path) = firstApp.action {
            return path
        }
        return nil
    }

    var hasTopHitOrApp: Bool {
        selectedSearchResult != nil || groupedResults[.topHit]?.first != nil || topHitAppPath != nil
    }

    var topHitBadgeText: String {
        guard let item = selectedSearchResult ?? groupedResults[.topHit]?.first else {
            return "Open"
        }
        switch item.action {
        case .launchApp, .openSettings, .openURL: return "Open"
        case .openFolder, .openProject: return "Open ↵ · Terminal ⌘↵ · Finder ⌥↵"
        case .killProcess(_, _, let force): return force ? "Force Kill" : "Terminate"
        case .runInTerminal, .runQuickAction: return "Run"
        case .copyToClipboard: return "Copy"
        case .openWebSearch: return "Search"
        }
    }

    // MARK: - Initialization

    init() {
        refreshSectionsCache()
        updateHeight()
    }

    func refreshSectionsCache() {
        _cachedRecentApps = RecentAppsManager.shared.getRecentApps(limit: 7)
        let allCategories: [AppCategory] = [
            .productivity, .utilities, .entertainment, .social, .creativity, .developerTools, .infoReading, .other
        ]
        let sections: [(category: AppCategory, apps: [AppInfo])] = allCategories.compactMap { cat in
            let catApps = AppScanner.shared.apps(for: cat)
            return catApps.isEmpty ? nil : (category: cat, apps: catApps)
        }
        _cachedCategorySections = sections

        var all: [AppInfo] = _cachedRecentApps
        for section in sections {
            all.append(contentsOf: section.apps)
        }
        _cachedAllApps = all
    }

    // MARK: - Actions

    func selectCategory(_ category: AppCategory) {
        selectedCategory = category
        gridSelectedIndex = 0
    }

    func performSearch(_ text: String) {
        // Every assignment to an @Published property sends objectWillChange, and each
        // send costs a SwiftUI body pass. The text field's binding has usually already
        // written `query`, so assign only what actually changed.
        if self.query != text { self.query = text }
        let q = SearchQuery(text)

        if q.isEmpty {
            if !self.groupedResults.isEmpty { self.groupedResults = [:] }
            if self.calculatorResult != nil { self.calculatorResult = nil }
            if self.gridSelectedIndex != 0 { self.gridSelectedIndex = 0 }
            if self.searchSelectedIndex != 0 { self.searchSelectedIndex = 0 }
            return
        }

        // Check for instant calculator result
        let calc = CalculatorEngine.evaluate(q.trimmed)

        // Perform search across all providers
        let results = SearchEngine.shared.searchImmediate(q)

        if self.calculatorResult != calc { self.calculatorResult = calc }
        if self.groupedResults != results { self.groupedResults = results }
        if self.searchSelectedIndex != 0 { self.searchSelectedIndex = 0 }
        if self.gridSelectedIndex != 0 { self.gridSelectedIndex = 0 }
    }

    func updateHeight() {
        let targetHeight: CGFloat = isPanelExpanded ? Self.expandedHeight : Self.compactHeight
        onHeightChange?(targetHeight)
    }

    func toggleExpanded() {
        isPanelExpanded.toggle()
        updateHeight()
    }

    // MARK: - 2D Keyboard Navigation

    func moveLeft() {
        if isCustomCommandManagerPresented {
            moveUp()
        } else if isHistoryManagerPresented {
            moveUp()
        } else if isPinManagerPresented {
            moveUp()
        } else if viewMode == .applications {
            if gridSelectedIndex > 0 {
                gridSelectedIndex -= 1
            }
        } else {
            moveUp()
        }
    }

    func moveRight() {
        if isCustomCommandManagerPresented {
            moveDown()
        } else if isHistoryManagerPresented {
            moveDown()
        } else if isPinManagerPresented {
            moveDown()
        } else if viewMode == .applications {
            let apps = displayedApps
            if gridSelectedIndex < apps.count - 1 {
                gridSelectedIndex += 1
            }
        } else {
            moveDown()
        }
    }

    func moveUp() {
        if isCustomCommandManagerPresented {
            guard !customCommands.isEmpty else { return }
            customCommandSelectedIndex = customCommandSelectedIndex > 0 ? customCommandSelectedIndex - 1 : customCommands.count - 1
        } else if isHistoryManagerPresented {
            guard !historyEntries.isEmpty else { return }
            historySelectedIndex = historySelectedIndex > 0 ? historySelectedIndex - 1 : historyEntries.count - 1
        } else if isPinManagerPresented {
            guard !pinnedCommands.isEmpty else { return }
            pinSelectedIndex = pinSelectedIndex > 0 ? pinSelectedIndex - 1 : pinnedCommands.count - 1
        } else if viewMode == .applications {
            let nextIndex = gridSelectedIndex - Self.gridColumns
            if nextIndex >= 0 {
                gridSelectedIndex = nextIndex
            }
        } else {
            let flat = flatSearchResults
            guard !flat.isEmpty else { return }
            if searchSelectedIndex > 0 {
                searchSelectedIndex -= 1
            } else {
                searchSelectedIndex = flat.count - 1
            }
        }
    }

    func moveDown() {
        if isCustomCommandManagerPresented {
            guard !customCommands.isEmpty else { return }
            customCommandSelectedIndex = customCommandSelectedIndex < customCommands.count - 1 ? customCommandSelectedIndex + 1 : 0
        } else if isHistoryManagerPresented {
            guard !historyEntries.isEmpty else { return }
            historySelectedIndex = historySelectedIndex < historyEntries.count - 1 ? historySelectedIndex + 1 : 0
        } else if isPinManagerPresented {
            guard !pinnedCommands.isEmpty else { return }
            pinSelectedIndex = pinSelectedIndex < pinnedCommands.count - 1 ? pinSelectedIndex + 1 : 0
        } else if viewMode == .applications {
            let apps = displayedApps
            let nextIndex = gridSelectedIndex + Self.gridColumns
            if nextIndex < apps.count {
                gridSelectedIndex = nextIndex
            } else if gridSelectedIndex < apps.count - 1 {
                gridSelectedIndex = apps.count - 1
            }
        } else {
            let flat = flatSearchResults
            guard !flat.isEmpty else { return }
            if searchSelectedIndex < flat.count - 1 {
                searchSelectedIndex += 1
            } else {
                searchSelectedIndex = 0
            }
        }
    }

    func nextCategory() {
        if isCustomCommandManagerPresented || isPinManagerPresented || isHistoryManagerPresented { return }
        let all = AppCategory.allCases
        guard let idx = all.firstIndex(of: selectedCategory) else { return }
        let nextIdx = (idx + 1) % all.count
        selectedCategory = all[nextIdx]
        gridSelectedIndex = 0
    }

    func previousCategory() {
        if isCustomCommandManagerPresented || isPinManagerPresented || isHistoryManagerPresented { return }
        let all = AppCategory.allCases
        guard let idx = all.firstIndex(of: selectedCategory) else { return }
        let prevIdx = (idx - 1 + all.count) % all.count
        selectedCategory = all[prevIdx]
        gridSelectedIndex = 0
    }

    func activateSelected() {
        if isCustomCommandManagerPresented {
            runCustomCommand(at: customCommandSelectedIndex)
            return
        }

        if isHistoryManagerPresented {
            runHistoryEntry(at: historySelectedIndex)
            return
        }

        if isPinManagerPresented {
            runPinnedCommand(at: pinSelectedIndex)
            return
        }

        if viewMode == .applications {
            guard let app = selectedApp else { return }
            launchApp(app)
        } else {
            // Search result mode
            if let calc = calculatorResult, searchSelectedIndex == 0 && (selectedSearchResult?.category == .calculator || flatSearchResults.isEmpty) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(calc, forType: .string)
                onHide?()
                return
            }

            guard let result = selectedSearchResult else {
                if let firstApp = displayedApps.first {
                    launchApp(firstApp)
                }
                return
            }

            // Record selection in SearchHistoryManager
            SearchHistoryManager.shared.recordSelection(result: result, query: query)

            // If it's an application, also keep RecentAppsManager in sync
            if result.id.hasPrefix("top-app-") {
                let bundleId = String(result.id.dropFirst("top-app-".count))
                RecentAppsManager.shared.recordLaunch(bundleIdentifier: bundleId)
            } else if result.id.hasPrefix("app-") {
                let bundleId = String(result.id.dropFirst("app-".count))
                RecentAppsManager.shared.recordLaunch(bundleIdentifier: bundleId)
            }
            
            onHide?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                switch result.action {
                case .launchApp(let path):
                    AppScanner.launchApp(at: path)
                case .openSettings(let deepLink):
                    if let url = URL(string: deepLink) {
                        NSWorkspace.shared.open(url)
                    }
                case .runQuickAction(let script, let usesOsascript):
                    QuickActionsProvider.execute(script: script, usesOsascript: usesOsascript)
                case .copyToClipboard(let text):
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                case .openWebSearch(let url):
                    NSWorkspace.shared.open(url)
                case .runInTerminal(let command):
                    TerminalLauncher.run(command)
                case .openURL(let url):
                    NSWorkspace.shared.open(url)
                case .openFolder(let path):
                    Self.openFolderInVSCode(at: path)
                case .openProject(let path, let appBundleID):
                    Self.openProject(at: path, bundleIdentifier: appBundleID)
                case .killProcess(let pid, _, let force):
                    ProcessKillerProvider.terminateProcess(pid: pid, force: force)
                }
            }
        }
    }

    /// Primary project opener: launches project in respective or default IDE
    static func openProject(at path: String, bundleIdentifier: String?) {
        let folderURL = URL(fileURLWithPath: path)
        if let bundleID = bundleIdentifier,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open([folderURL], withApplicationAt: appURL, configuration: config)
        } else if let vsCodeURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open([folderURL], withApplicationAt: vsCodeURL, configuration: config)
        } else {
            NSWorkspace.shared.open(folderURL)
        }
    }

    /// Primary folder opener: launches folder in Visual Studio Code
    static func openFolderInVSCode(at path: String) {
        let folderURL = URL(fileURLWithPath: path)
        if let vsCodeURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open([folderURL], withApplicationAt: vsCodeURL, configuration: config)
        } else if FileManager.default.fileExists(atPath: "/Applications/Visual Studio Code.app") {
            let vsCodeURL = URL(fileURLWithPath: "/Applications/Visual Studio Code.app")
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open([folderURL], withApplicationAt: vsCodeURL, configuration: config)
        } else {
            NSWorkspace.shared.open(folderURL)
        }
    }

    /// Secondary action: triggered by Option+Return (⌥↵) - Opens Finder for projects
    func activateSecondary() {
        guard let result = selectedSearchResult else { return }

        // Record selection in SearchHistoryManager
        SearchHistoryManager.shared.recordSelection(result: result, query: query)

        onHide?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            switch result.action {
            case .openFolder(let path), .openProject(let path, _):
                Self.openFolderInFinder(at: path)
            case .killProcess(let pid, _, _):
                ProcessKillerProvider.terminateProcess(pid: pid, force: true)
            case .launchApp(let path):
                NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
            default:
                break
            }
        }
    }

    /// Dedicated action for clicking the Terminal button on a project row
    func openProjectInTerminal(_ result: SearchResult) {
        let targetPath: String?
        switch result.action {
        case .openFolder(let path), .openProject(let path, _):
            targetPath = path
        default:
            targetPath = nil
        }
        guard let path = targetPath else { return }
        SearchHistoryManager.shared.recordSelection(result: result, query: query)
        onHide?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            TerminalLauncher.openFolder(at: path)
        }
    }

    /// Tertiary action: triggered by Command+Return (⌘↵) - Opens Terminal for projects
    func activateFinder() {
        guard let result = selectedSearchResult else { return }

        // Record selection in SearchHistoryManager
        SearchHistoryManager.shared.recordSelection(result: result, query: query)

        onHide?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            switch result.action {
            case .openFolder(let path), .openProject(let path, _):
                TerminalLauncher.openFolder(at: path)
            case .runInTerminal(let command):
                TerminalLauncher.run(command)
            case .launchApp(let path):
                NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
            default:
                break
            }
        }
    }

    /// Dedicated action for clicking the Finder button on a project row
    func openProjectInFinder(_ result: SearchResult) {
        let targetPath: String?
        switch result.action {
        case .openFolder(let path), .openProject(let path, _):
            targetPath = path
        default:
            targetPath = nil
        }
        guard let path = targetPath else { return }
        SearchHistoryManager.shared.recordSelection(result: result, query: query)
        onHide?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Self.openFolderInFinder(at: path)
        }
    }

    /// Opens folder directly in Finder
    static func openFolderInFinder(at path: String) {
        let folderURL = URL(fileURLWithPath: path)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        if let finderURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") {
            NSWorkspace.shared.open([folderURL], withApplicationAt: finderURL, configuration: config)
        } else {
            NSWorkspace.shared.open(folderURL)
        }
    }

    func launchApp(_ app: AppInfo) {
        RecentAppsManager.shared.recordLaunch(bundleIdentifier: app.bundleIdentifier)
        SearchHistoryManager.shared.recordSelection(
            itemId: "app-\(app.bundleIdentifier)",
            title: app.name,
            subtitle: "Application",
            category: .applications,
            iconType: .app(path: app.path),
            action: .launchApp(path: app.path),
            query: query
        )
        onHide?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            AppScanner.launchApp(at: app.path)
        }
    }

    func handleCancel() {
        if isCustomCommandManagerPresented {
            hideCustomCommandManager()
        } else if isHistoryManagerPresented {
            hideHistoryManager()
        } else if isPinManagerPresented {
            hidePinManager()
        } else if !query.isEmpty {
            clearSearch()
        } else {
            onHide?()
        }
    }

    func clearSearch() {
        query = ""
        groupedResults = [:]
        calculatorResult = nil
        gridSelectedIndex = 0
        searchSelectedIndex = 0
    }

    func reset() {
        clearSearch()
        isPanelExpanded = true
        isPinManagerPresented = false
        isHistoryManagerPresented = false
        isCustomCommandManagerPresented = false
        pinnedCommands = PinnedCommandsStore.shared.commands()
        historyEntries = SearchHistoryManager.shared.entries()
        customCommands = CustomCommandsStore.shared.entries()
        pinSelectedIndex = 0
        historySelectedIndex = 0
        customCommandSelectedIndex = 0
    }

    /// Clear all transient arrays to free memory when hidden
    func reclaimMemory() {
        groupedResults.removeAll(keepingCapacity: false)
        query = ""
        calculatorResult = nil
        isPinManagerPresented = false
        isHistoryManagerPresented = false
        isCustomCommandManagerPresented = false
        pinnedCommands.removeAll(keepingCapacity: false)
        historyEntries.removeAll(keepingCapacity: false)
        customCommands.removeAll(keepingCapacity: false)
        pinSelectedIndex = 0
        historySelectedIndex = 0
        customCommandSelectedIndex = 0
    }

    // MARK: - Search History

    func showHistoryManager() {
        if isPinManagerPresented { isPinManagerPresented = false }
        historyEntries = SearchHistoryManager.shared.entries()
        historySelectedIndex = 0
        if !isPanelExpanded {
            isPanelExpanded = true
            updateHeight()
        }
        isHistoryManagerPresented = true
    }

    func hideHistoryManager() {
        isHistoryManagerPresented = false
    }

    func toggleHistoryManager() {
        if isHistoryManagerPresented {
            hideHistoryManager()
        } else {
            showHistoryManager()
        }
    }

    func deleteHistoryEntry(at index: Int) {
        guard index >= 0, index < historyEntries.count else { return }
        let entry = historyEntries[index]
        SearchHistoryManager.shared.deleteEntry(id: entry.id)
        historyEntries = SearchHistoryManager.shared.entries()
        historySelectedIndex = min(index, max(historyEntries.count - 1, 0))
    }

    func clearAllHistory() {
        SearchHistoryManager.shared.clearHistory()
        historyEntries = []
        historySelectedIndex = 0
    }

    func runHistoryEntry(at index: Int) {
        guard index >= 0, index < historyEntries.count else { return }
        let entry = historyEntries[index]
        isHistoryManagerPresented = false

        // Re-record this selection
        SearchHistoryManager.shared.recordSelection(
            itemId: entry.itemId,
            title: entry.title,
            subtitle: entry.subtitle,
            category: entry.category,
            iconType: entry.iconType,
            action: entry.action,
            query: entry.query
        )

        onHide?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            switch entry.action {
            case .launchApp(let path):
                if entry.itemId.hasPrefix("app-") {
                    let bundleId = String(entry.itemId.dropFirst("app-".count))
                    RecentAppsManager.shared.recordLaunch(bundleIdentifier: bundleId)
                }
                AppScanner.launchApp(at: path)
            case .openSettings(let deepLink):
                if let url = URL(string: deepLink) {
                    NSWorkspace.shared.open(url)
                }
            case .runQuickAction(let script, let usesOsascript):
                QuickActionsProvider.execute(script: script, usesOsascript: usesOsascript)
            case .copyToClipboard(let text):
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            case .openWebSearch(let url):
                NSWorkspace.shared.open(url)
            case .runInTerminal(let command):
                TerminalLauncher.run(command)
            case .openURL(let url):
                NSWorkspace.shared.open(url)
            case .openFolder(let path):
                Self.openFolderInVSCode(at: path)
            case .openProject(let path, let appBundleID):
                Self.openProject(at: path, bundleIdentifier: appBundleID)
            case .killProcess(let pid, _, let force):
                ProcessKillerProvider.terminateProcess(pid: pid, force: force)
            }
        }
    }

    // MARK: - Custom Commands

    func showCustomCommandManager() {
        if isPinManagerPresented { isPinManagerPresented = false }
        if isHistoryManagerPresented { isHistoryManagerPresented = false }
        customCommands = CustomCommandsStore.shared.entries()
        customCommandSelectedIndex = 0
        if !isPanelExpanded {
            isPanelExpanded = true
            updateHeight()
        }
        isCustomCommandManagerPresented = true
    }

    func hideCustomCommandManager() {
        isCustomCommandManagerPresented = false
    }

    func toggleCustomCommandManager() {
        if isCustomCommandManagerPresented {
            hideCustomCommandManager()
        } else {
            showCustomCommandManager()
        }
    }

    func runCustomCommand(at index: Int) {
        guard index >= 0, index < customCommands.count else { return }
        let command = customCommands[index]
        isCustomCommandManagerPresented = false
        onHide?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            switch command.type {
            case .url:
                if let url = command.normalizedURL {
                    NSWorkspace.shared.open(url)
                }
            case .terminal:
                TerminalLauncher.run(command.target)
            case .appleScript:
                QuickActionsProvider.execute(script: command.target, usesOsascript: true)
            case .shell:
                QuickActionsProvider.execute(script: command.target, usesOsascript: false)
            }
        }
    }

    func deleteCustomCommand(at index: Int) {
        guard index >= 0, index < customCommands.count else { return }
        let command = customCommands[index]
        CustomCommandsStore.shared.delete(id: command.id)
        customCommands = CustomCommandsStore.shared.entries()
        customCommandSelectedIndex = min(index, max(customCommands.count - 1, 0))
    }

    func moveCustomCommand(at index: Int, offset: Int) {
        guard index >= 0, index < customCommands.count else { return }
        CustomCommandsStore.shared.move(from: index, offset: offset)
        customCommands = CustomCommandsStore.shared.entries()
        customCommandSelectedIndex = min(max(index + offset, 0), max(customCommands.count - 1, 0))
    }

    func saveCustomCommand(_ command: CustomCommand) {
        if customCommands.contains(where: { $0.id == command.id }) {
            CustomCommandsStore.shared.update(command)
        } else {
            CustomCommandsStore.shared.add(command)
        }
        customCommands = CustomCommandsStore.shared.entries()
        if let idx = customCommands.firstIndex(where: { $0.id == command.id }) {
            customCommandSelectedIndex = idx
        }
    }

    // MARK: - Pinned Commands

    func showPinManager() {
        if isHistoryManagerPresented { isHistoryManagerPresented = false }
        pinnedCommands = PinnedCommandsStore.shared.commands()
        pinSelectedIndex = 0
        if !isPanelExpanded {
            isPanelExpanded = true
            updateHeight()
        }
        isPinManagerPresented = true
    }

    func hidePinManager() {
        isPinManagerPresented = false
    }

    func togglePinManager() {
        if isPinManagerPresented {
            hidePinManager()
        } else {
            showPinManager()
        }
    }

    /// ⌘P: pins or unpins the selected history result, or unpins the selected row
    /// while the manager is open.
    func togglePinForSelection() {
        if isPinManagerPresented {
            unpinCommand(at: pinSelectedIndex)
            return
        }
        guard let command = selectedCommand else { return }
        PinnedCommandsStore.shared.toggle(command)
        reloadResultsKeepingSelection()
    }

    func togglePin(for command: String) {
        PinnedCommandsStore.shared.toggle(command)
        reloadResultsKeepingSelection()
    }

    func unpinCommand(at index: Int) {
        guard index >= 0, index < pinnedCommands.count else { return }
        PinnedCommandsStore.shared.unpin(pinnedCommands[index])
        pinnedCommands = PinnedCommandsStore.shared.commands()
        pinSelectedIndex = min(index, max(pinnedCommands.count - 1, 0))
        reloadResultsKeepingSelection()
    }

    func movePinnedCommand(at index: Int, offset: Int) {
        guard index >= 0, index < pinnedCommands.count else { return }
        PinnedCommandsStore.shared.move(from: index, offset: offset)
        pinnedCommands = PinnedCommandsStore.shared.commands()
        pinSelectedIndex = min(max(index + offset, 0), max(pinnedCommands.count - 1, 0))
        reloadResultsKeepingSelection()
    }

    func runPinnedCommand(at index: Int) {
        guard index >= 0, index < pinnedCommands.count else { return }
        runCommandInTerminal(pinnedCommands[index])
    }

    /// Opens Terminal and runs the command, dismissing the panel first so the new
    /// Terminal window is not covered by it.
    func runCommandInTerminal(_ command: String) {
        isPinManagerPresented = false
        onHide?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            TerminalLauncher.run(command)
        }
    }

    /// Pinning changes a result's score, so the row moves. Re-run the search and
    /// follow the command that was selected rather than the index it used to sit at.
    private func reloadResultsKeepingSelection() {
        pinnedCommands = PinnedCommandsStore.shared.commands()

        let q = SearchQuery(query)
        guard !q.isEmpty else { return }

        let previousCommand = selectedCommand
        let results = SearchEngine.shared.searchImmediate(q)
        groupedResults = results

        let flat = SearchEngine.flatResults(from: results)
        if flat.isEmpty {
            searchSelectedIndex = 0
            return
        }
        if let command = previousCommand,
           let index = flat.firstIndex(where: {
               if case .runInTerminal(let candidate) = $0.action { return candidate == command }
               return false
           }) {
            searchSelectedIndex = index
        } else {
            searchSelectedIndex = min(searchSelectedIndex, flat.count - 1)
        }
    }

    // MARK: - Menu Actions

    var currentHotkeyOption: HotkeyOption { hotkeyManager?.currentOption ?? .commandSpace }
    func setHotkeyOption(_ option: HotkeyOption) {
        hotkeyManager?.currentOption = option
        menuBarController?.rebuildMenu()
        objectWillChange.send()
    }

    // MARK: - Search Engine
    var currentSearchEngine: SearchEngineOption {
        WebSearchProvider.shared.defaultEngine
    }

    func setSearchEngine(_ option: SearchEngineOption) {
        WebSearchProvider.shared.defaultEngine = option
        menuBarController?.rebuildMenu()
        objectWillChange.send()
    }

    // MARK: - Browser History
    var currentBrowserHistoryDays: BrowserHistoryDays {
        BrowserIntegrationProvider.shared.historyLimitDays
    }

    func setBrowserHistoryDays(_ option: BrowserHistoryDays) {
        BrowserIntegrationProvider.shared.historyLimitDays = option
        menuBarController?.rebuildMenu()
        objectWillChange.send()
    }

    // MARK: - Terminal App
    var currentTerminalApp: TerminalAppOption {
        TerminalLauncher.currentTerminal
    }

    var installedTerminalOptions: [TerminalAppOption] {
        TerminalAppOption.installedOptions
    }

    func setTerminalApp(_ option: TerminalAppOption) {
        TerminalLauncher.currentTerminal = option
        menuBarController?.rebuildMenu()
        objectWillChange.send()
    }

    // MARK: - Clipboard History
    func clearClipboardHistory() {
        ClipboardHistoryManager.shared.clearHistory()
    }
    
    var isMenuBarIconHidden: Bool { menuBarController?.isMenuBarIconHidden ?? false }
    func toggleMenuBarIcon() {
        menuBarController?.toggleHideMenuBarIconAction()
        objectWillChange.send()
    }
    
    var isAutoStartEnabled: Bool { AutoStartManager.isEnabled }
    func toggleAutoStart() {
        _ = AutoStartManager.toggle()
        menuBarController?.rebuildMenu()
        objectWillChange.send()
    }

    var isSpotlightShortcutEnabled: Bool { SpotlightManager.isShortcutEnabled() }
    func toggleSpotlightShortcut() {
        let current = SpotlightManager.isShortcutEnabled()
        SpotlightManager.setShortcut(enabled: !current)
        menuBarController?.rebuildMenu()
        objectWillChange.send()
    }

    var isSpotlightServiceDisabled: Bool { SpotlightManager.isServiceDisabled() }
    func toggleSpotlightService() {
        let current = SpotlightManager.isServiceDisabled()
        SpotlightManager.setService(enabled: current)
        menuBarController?.rebuildMenu()
        objectWillChange.send()
    }

    var isSpotlightIndexingEnabled: Bool { SpotlightManager.isIndexingEnabled() }
    func toggleSpotlightIndexing() {
        let current = SpotlightManager.isIndexingEnabled()
        SpotlightManager.setIndexing(enabled: !current) { [weak self] _ in
            self?.menuBarController?.rebuildMenu()
            self?.objectWillChange.send()
        }
    }

    var spotlightStatusSummary: String {
        let isShortcutOn = isSpotlightShortcutEnabled
        let isServiceDisabled = isSpotlightServiceDisabled
        let isIndexingOn = isSpotlightIndexingEnabled
        return "Status: Shortcut " + (isShortcutOn ? "ON" : "OFF") +
               ", Process " + (isServiceDisabled ? "OFF" : "ON") +
               ", Indexing " + (isIndexingOn ? "ON" : "OFF")
    }

    func disableAllSpotlight() {
        SpotlightManager.disableAll(includeIndexing: true) { [weak self] _ in
            self?.menuBarController?.rebuildMenu()
            self?.objectWillChange.send()
        }
    }

    func enableAllSpotlight() {
        SpotlightManager.enableAll(includeIndexing: true) { [weak self] _ in
            self?.menuBarController?.rebuildMenu()
            self?.objectWillChange.send()
        }
    }

    func openKeyboardSettings() {
        onHide?()
        SpotlightManager.openKeyboardSettings()
    }

    func showAbout() {
        onHide?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.menuBarController?.showAbout()
        }
    }

    func exportSettings() {
        onHide?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            SettingsBackupController.shared.exportSettings()
        }
    }

    func importSettings() {
        onHide?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            SettingsBackupController.shared.importSettings()
        }
    }

    func reloadAfterSettingsImport() {
        pinnedCommands = PinnedCommandsStore.shared.commands()
        pinSelectedIndex = 0
        customCommands = CustomCommandsStore.shared.entries()
        customCommandSelectedIndex = 0
        historyEntries = SearchHistoryManager.shared.entries()
        historySelectedIndex = 0
        _cachedRecentApps = []
        _cachedCategorySections = []
        _cachedAllApps = []
        objectWillChange.send()
    }

    func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
