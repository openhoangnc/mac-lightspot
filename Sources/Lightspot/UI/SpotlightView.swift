import SwiftUI
import AppKit

struct SpotlightView: View {
    @ObservedObject var viewModel: SearchViewModel
    @State private var showSettingsMenu: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            // 1. Top Floating Pill Search Bar
            searchCapsuleBar

            // 2. Floating Bottom Panel (Applications or Search Results)
            if viewModel.isPanelExpanded {
                bottomContentPanel
            }

            Spacer(minLength: 0)
        }
        .frame(width: SpotlightPanel.panelWidth, height: SpotlightPanel.defaultHeight, alignment: .top)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }

    // MARK: - Top Search Capsule Bar

    private var searchCapsuleBar: some View {
        HStack(spacing: 12) {
            // Leading Icon
            ZStack {
                if viewModel.viewMode == .applications {
                    AppStoreGlyphView(size: 19)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            .frame(width: 22, height: 22)
            .padding(.leading, 4)

            // Search Text Field
            HStack(spacing: 6) {
                SearchFieldView(
                    text: $viewModel.query,
                    placeholder: viewModel.viewMode == .applications ? "Applications" : "Search"
                ) { newText in
                    viewModel.performSearch(newText)
                }
                .frame(height: 32)

                // Inline "― Open" badge when searching and top hit exists
                if viewModel.viewMode == .searchResults, (viewModel.selectedApp ?? viewModel.displayedApps.first) != nil {
                    HStack(spacing: 3) {
                        Text("―")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.35))
                        Text("Open")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                    )
                }
            }

            Spacer(minLength: 0)

            // Trailing Controls
            HStack(spacing: 8) {
                // Top Hit App Icon preview
                if viewModel.viewMode == .searchResults, let topApp = viewModel.selectedApp ?? viewModel.displayedApps.first {
                    LazyAppIconView(path: topApp.path, size: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 5.5, style: .continuous))
                        .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
                }

                // Clear button
                if !viewModel.query.isEmpty {
                    Button(action: { viewModel.clearSearch() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }

                // More Options (...) Button
                Menu {
                    // Category Navigation
                    Button("Next Category (Tab)") {
                        viewModel.nextCategory()
                    }
                    Button("Previous Category (⇧Tab)") {
                        viewModel.previousCategory()
                    }

                    Divider()

                    // Shortcut Submenu
                    Menu("Shortcut (\(viewModel.currentHotkeyOption.shortLabel))") {
                        ForEach(HotkeyOption.allCases) { option in
                            Button(action: { viewModel.setHotkeyOption(option) }) {
                                HStack {
                                    Text(option.displayName)
                                    if option == viewModel.currentHotkeyOption {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }

                    // System Spotlight Submenu
                    Menu("System Spotlight") {
                        Button(viewModel.isSpotlightShortcutEnabled ? "Disable Spotlight Shortcut (⌘Space)" : "Enable Spotlight Shortcut (⌘Space)") {
                            viewModel.toggleSpotlightShortcut()
                        }
                        Button(viewModel.isSpotlightServiceDisabled ? "Enable Spotlight Process (launchctl)" : "Disable Spotlight Process (launchctl)") {
                            viewModel.toggleSpotlightService()
                        }
                        Button(viewModel.isSpotlightIndexingEnabled ? "Disable File Indexing (mdutil)..." : "Enable File Indexing (mdutil)...") {
                            viewModel.toggleSpotlightIndexing()
                        }
                        Divider()
                        Button("Disable Everything...") {
                            viewModel.disableAllSpotlight()
                        }
                        Button("Restore Default Spotlight...") {
                            viewModel.enableAllSpotlight()
                        }
                        Divider()
                        Button("Open Keyboard Shortcuts Settings...") {
                            viewModel.openKeyboardSettings()
                        }
                    }

                    Divider()

                    // Launch at Login Toggle
                    Button(action: { viewModel.toggleAutoStart() }) {
                        HStack {
                            Text("Launch at Login")
                            if viewModel.isAutoStartEnabled {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    // Hide / Show Menu Bar Icon Toggle
                    Button(action: { viewModel.toggleMenuBarIcon() }) {
                        HStack {
                            Text(viewModel.isMenuBarIconHidden ? "Show Menu Bar Icon" : "Hide Menu Bar Icon")
                            if !viewModel.isMenuBarIconHidden {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Divider()

                    Button("Clear Search (Esc)") {
                        viewModel.clearSearch()
                    }

                    Button("About Lightspot") {
                        viewModel.showAbout()
                    }

                    Button("Close Lightspot") {
                        viewModel.onHide?()
                    }

                    Divider()

                    Button("Quit Lightspot (⌘Q)") {
                        viewModel.quitApp()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 24, height: 24)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 54)
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.65)
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color.clear,
                        Color.black.opacity(0.2)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.42),
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.22)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.85
                    )
            )
            .shadow(color: .black.opacity(0.50), radius: 24, x: 0, y: 12)
        )
    }

    // MARK: - Floating Bottom Panel

    private var bottomContentPanel: some View {
        VStack(spacing: 0) {
            // Category Pills Tab Bar
            CategoryChipsView(
                selectedCategory: $viewModel.selectedCategory,
                onSelect: { cat in
                    viewModel.selectCategory(cat)
                }
            )
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider()
                .background(Color.white.opacity(0.12))
                .padding(.horizontal, 16)

            if viewModel.viewMode == .applications {
                // 7-Column Applications Grid (Recent Apps on 1st row + Categorized Sections below)
                AppGridView(
                    recentApps: viewModel.selectedCategory == .all ? viewModel.recentApps : nil,
                    categorySections: viewModel.selectedCategory == .all ? viewModel.categorySections : nil,
                    apps: viewModel.displayedApps,
                    selectedIndex: viewModel.gridSelectedIndex,
                    onSelect: { app in
                        viewModel.launchApp(app)
                    }
                )
            } else {
                // Search Mode (Instant Calculator + Matching Items)
                VStack(spacing: 6) {
                    if let calc = viewModel.calculatorResult {
                        CalculatorCardView(
                            expression: viewModel.query,
                            result: calc,
                            onCopy: {
                                viewModel.activateSelected()
                            }
                        )
                    }

                    if !viewModel.groupedResults.isEmpty {
                        SearchResultsView(
                            groupedResults: viewModel.groupedResults,
                            selectedIndex: viewModel.searchSelectedIndex,
                            onSelect: { result in
                                if let idx = viewModel.flatSearchResults.firstIndex(of: result) {
                                    viewModel.searchSelectedIndex = idx
                                    viewModel.activateSelected()
                                }
                            }
                        )
                    } else if !viewModel.displayedApps.isEmpty {
                        AppGridView(
                            apps: viewModel.displayedApps,
                            selectedIndex: viewModel.gridSelectedIndex,
                            onSelect: { app in
                                viewModel.launchApp(app)
                            }
                        )
                    } else if viewModel.calculatorResult == nil {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 32, weight: .light))
                                .foregroundColor(.white.opacity(0.3))
                            Text("No results found for \"\(viewModel.query)\"")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.4))
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .frame(height: 450)
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.62)
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.06),
                        Color.clear,
                        Color.black.opacity(0.25)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.35),
                                Color.white.opacity(0.06),
                                Color.white.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.85
                    )
            )
            .shadow(color: .black.opacity(0.50), radius: 32, x: 0, y: 16)
        )
    }
}
