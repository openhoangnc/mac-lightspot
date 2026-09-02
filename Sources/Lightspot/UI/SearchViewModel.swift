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
        }
        if let top = groupedResults[.topHit]?.first, case .launchApp(let path) = top.action {
            return path
        }
        if let firstApp = groupedResults[.applications]?.first, case .launchApp(let path) = firstApp.action {
            return path
        }
        return nil
    }

    var hasTopHitOrApp: Bool {
        topHitAppPath != nil
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
        self.query = text
        let q = SearchQuery(text)

        if q.isEmpty {
            self.groupedResults = [:]
            self.calculatorResult = nil
            self.gridSelectedIndex = 0
            self.searchSelectedIndex = 0
            return
        }

        // Check for instant calculator result
        let calc = CalculatorEngine.evaluate(q.trimmed)

        // Perform search across all providers
        let results = SearchEngine.shared.searchImmediate(q)

        self.calculatorResult = calc
        self.groupedResults = results
        self.searchSelectedIndex = 0
        self.gridSelectedIndex = 0
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
        if viewMode == .applications {
            if gridSelectedIndex > 0 {
                gridSelectedIndex -= 1
            }
        } else {
            moveUp()
        }
    }

    func moveRight() {
        if viewMode == .applications {
            let apps = displayedApps
            if gridSelectedIndex < apps.count - 1 {
                gridSelectedIndex += 1
            }
        } else {
            moveDown()
        }
    }

    func moveUp() {
        if viewMode == .applications {
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
        if viewMode == .applications {
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
        let all = AppCategory.allCases
        guard let idx = all.firstIndex(of: selectedCategory) else { return }
        let nextIdx = (idx + 1) % all.count
        selectedCategory = all[nextIdx]
        gridSelectedIndex = 0
    }

    func previousCategory() {
        let all = AppCategory.allCases
        guard let idx = all.firstIndex(of: selectedCategory) else { return }
        let prevIdx = (idx - 1 + all.count) % all.count
        selectedCategory = all[prevIdx]
        gridSelectedIndex = 0
    }

    func activateSelected() {
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
                }
            }
        }
    }

    func launchApp(_ app: AppInfo) {
        RecentAppsManager.shared.recordLaunch(bundleIdentifier: app.bundleIdentifier)
        onHide?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            AppScanner.launchApp(at: app.path)
        }
    }

    func handleCancel() {
        if !query.isEmpty {
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
    }

    /// Clear all transient arrays to free memory when hidden
    func reclaimMemory() {
        groupedResults.removeAll(keepingCapacity: false)
        query = ""
        calculatorResult = nil
    }

    // MARK: - Menu Actions

    var currentHotkeyOption: HotkeyOption { hotkeyManager?.currentOption ?? .commandSpace }
    func setHotkeyOption(_ option: HotkeyOption) {
        hotkeyManager?.currentOption = option
        menuBarController?.rebuildMenu()
        objectWillChange.send()
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

    func disableAllSpotlight() {
        SpotlightManager.disableAll(includeIndexing: false)
        menuBarController?.rebuildMenu()
        objectWillChange.send()
    }

    func enableAllSpotlight() {
        SpotlightManager.enableAll(includeIndexing: false)
        menuBarController?.rebuildMenu()
        objectWillChange.send()
    }

    func openKeyboardSettings() {
        onHide?()
        SpotlightManager.openKeyboardSettings()
    }

    func showAbout() {
        onHide?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.orderFrontStandardAboutPanel(nil)
        }
    }

    func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
