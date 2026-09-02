import SwiftUI
import AppKit

struct ResultsListView: View {
    let groupedResults: [ResultCategory: [SearchResult]]
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    private var orderedCategories: [ResultCategory] {
        SearchEngine.orderedCategories(from: groupedResults)
    }

    private var flatResults: [SearchResult] {
        SearchEngine.flatResults(from: groupedResults)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(orderedCategories, id: \.self) { category in
                        if let results = groupedResults[category] {
                            // Section Header
                            Text(category.displayName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                                .padding(.horizontal, 12)
                                .padding(.top, category == orderedCategories.first ? 4 : 10)
                                .padding(.bottom, 2)

                            // Results
                            ForEach(Array(results.enumerated()), id: \.element.id) { _, result in
                                let globalIndex = globalIndex(for: result)
                                ResultRowView(
                                    result: result,
                                    isSelected: globalIndex == selectedIndex
                                )
                                .id(result.id)
                                .onTapGesture {
                                    if let idx = globalIndex {
                                        onSelect(idx)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .onChange(of: selectedIndex) { newIndex in
                let flat = flatResults
                if newIndex >= 0 && newIndex < flat.count {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        proxy.scrollTo(flat[newIndex].id, anchor: nil)
                    }
                }
            }
        }
    }

    private func globalIndex(for result: SearchResult) -> Int? {
        flatResults.firstIndex(where: { $0.id == result.id })
    }
}
