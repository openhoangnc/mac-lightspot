import SwiftUI
import AppKit

struct SpotlightView: View {
    @ObservedObject var viewModel: SearchViewModel
    @State private var showSettingsMenu: Bool = false

    var body: some View {
        mainContent
            .overlay {
                if viewModel.isCustomCommandManagerPresented {
                    customCommandManagerLayer
                } else if viewModel.isPinManagerPresented {
                    pinManagerLayer
                } else if viewModel.isHistoryManagerPresented {
                    historyManagerLayer
                }
            }
    }

    private var mainContent: some View {
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

    // MARK: - Custom Commands Manager Layer

    private var customCommandManagerLayer: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 76)

            CustomCommandsView(
                commands: viewModel.customCommands,
                selectedIndex: viewModel.customCommandSelectedIndex,
                onSelect: { index in viewModel.customCommandSelectedIndex = index },
                onRun: { index in viewModel.runCustomCommand(at: index) },
                onDelete: { index in viewModel.deleteCustomCommand(at: index) },
                onMove: { index, offset in viewModel.moveCustomCommand(at: index, offset: offset) },
                onSave: { command in viewModel.saveCustomCommand(command) },
                onClose: { viewModel.hideCustomCommandManager() }
            )
            .frame(height: 450)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Pinned Commands Manager Layer

    /// Covers exactly the bottom results panel (10pt top padding + 54pt capsule +
    /// 12pt stack spacing = 76pt down, 450pt tall) so the manager reads as a sheet
    /// over the results while the search field above it keeps focus and keyboard
    /// routing. Keep these numbers in step with `bottomContentPanel`.
    private var pinManagerLayer: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 76)

            PinnedCommandsView(
                commands: viewModel.pinnedCommands,
                selectedIndex: viewModel.pinSelectedIndex,
                onSelect: { index in viewModel.pinSelectedIndex = index },
                onRun: { index in viewModel.runPinnedCommand(at: index) },
                onUnpin: { index in viewModel.unpinCommand(at: index) },
                onMove: { index, offset in viewModel.movePinnedCommand(at: index, offset: offset) },
                onClose: { viewModel.hidePinManager() }
            )
            .frame(height: 450)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Search History Manager Layer

    private var historyManagerLayer: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 76)

            SearchHistoryView(
                entries: viewModel.historyEntries,
                selectedIndex: viewModel.historySelectedIndex,
                onSelect: { index in viewModel.historySelectedIndex = index },
                onRun: { index in viewModel.runHistoryEntry(at: index) },
                onDelete: { index in viewModel.deleteHistoryEntry(at: index) },
                onClearAll: { viewModel.clearAllHistory() },
                onClose: { viewModel.hideHistoryManager() }
            )
            .frame(height: 450)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
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
                if viewModel.viewMode == .searchResults, viewModel.hasTopHitOrApp {
                    HStack(spacing: 3) {
                        Text("―")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.35))
                        Text(viewModel.topHitBadgeText)
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
                if viewModel.viewMode == .searchResults, let topAppPath = viewModel.topHitAppPath {
                    LazyAppIconView(path: topAppPath, size: 24)
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
                EllipsisMenuButton {
                    viewModel.menuBarController?.buildMenu()
                }
                .frame(width: 24, height: 24)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 54)
        .background(
            ZStack {
                Capsule()
                    .fill(Color.black.opacity(0.65))
                    .shadow(color: .black.opacity(0.50), radius: 24, x: 0, y: 12)

                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow, cornerRadius: 27)
                    .clipShape(Capsule())

                Color.black.opacity(0.65)
                    .clipShape(Capsule())

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color.clear,
                        Color.black.opacity(0.2)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(Capsule())
            }
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
                            },
                            onTogglePin: { result in
                                if case .runInTerminal(let command) = result.action {
                                    viewModel.togglePin(for: command)
                                }
                            },
                            onOpenTerminal: { result in
                                viewModel.openProjectInTerminal(result)
                            },
                            onOpenFinder: { result in
                                viewModel.openProjectInFinder(result)
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
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.black.opacity(0.62))
                    .shadow(color: .black.opacity(0.50), radius: 32, x: 0, y: 16)

                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow, cornerRadius: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                Color.black.opacity(0.62)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.06),
                        Color.clear,
                        Color.black.opacity(0.25)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
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
        )
    }
}
