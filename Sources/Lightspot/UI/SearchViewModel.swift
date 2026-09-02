import Foundation
import SwiftUI
import AppKit

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var selectedIndex: Int = 0
    @Published var groupedResults: [ResultCategory: [SearchResult]] = [:]

    var onHide: (() -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?

    var flatResults: [SearchResult] {
        SearchEngine.flatResults(from: groupedResults)
    }

    var hasResults: Bool {
        !groupedResults.isEmpty
    }

    var selectedResult: SearchResult? {
        let flat = flatResults
        guard selectedIndex >= 0 && selectedIndex < flat.count else { return nil }
        return flat[selectedIndex]
    }

    func performSearch(_ text: String) {
        if text.isEmpty {
            groupedResults = [:]
            selectedIndex = 0
            onHeightChange?(60)
            return
        }

        SearchEngine.shared.search(text) { [weak self] results in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                self.groupedResults = results
                self.selectedIndex = 0
                let targetHeight: CGFloat = self.hasResults ? 460 : 60
                self.onHeightChange?(targetHeight)
            }
        }
    }

    func moveSelectionUp() {
        let flat = flatResults
        guard !flat.isEmpty else { return }
        if selectedIndex > 0 {
            selectedIndex -= 1
        } else {
            selectedIndex = flat.count - 1
        }
    }

    func moveSelectionDown() {
        let flat = flatResults
        guard !flat.isEmpty else { return }
        if selectedIndex < flat.count - 1 {
            selectedIndex += 1
        } else {
            selectedIndex = 0
        }
    }

    func activateSelected() {
        guard let result = selectedResult else { return }
        onHide?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            result.action()
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
        selectedIndex = 0
        onHeightChange?(60)
    }

    func reset() {
        query = ""
        groupedResults = [:]
        selectedIndex = 0
    }
}
