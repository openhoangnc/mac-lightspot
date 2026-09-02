import SwiftUI
import AppKit

struct SpotlightView: View {
    @ObservedObject var viewModel: SearchViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar

            // Results + Preview (only when there are results)
            if viewModel.hasResults {
                Divider()
                    .padding(.horizontal, 8)

                HStack(spacing: 0) {
                    // Left: Results list
                    ResultsListView(
                        groupedResults: viewModel.groupedResults,
                        selectedIndex: viewModel.selectedIndex,
                        onSelect: { index in
                            viewModel.selectedIndex = index
                            viewModel.activateSelected()
                        }
                    )
                    .frame(width: 320)

                    // Divider
                    Divider()

                    // Right: Preview pane
                    PreviewPaneView(result: viewModel.selectedResult)
                        .frame(maxWidth: .infinity)
                }
                .frame(height: 380)
            }
        }
        .frame(width: 680)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .light))
                .foregroundColor(.secondary)

            SearchFieldView(text: $viewModel.query) { newText in
                viewModel.performSearch(newText)
            }
            .frame(height: 30)

            if !viewModel.query.isEmpty {
                Button(action: { viewModel.clearSearch() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
