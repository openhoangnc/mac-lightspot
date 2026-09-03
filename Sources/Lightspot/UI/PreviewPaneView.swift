import SwiftUI
import AppKit

struct PreviewPaneView: View {
    let result: SearchResult?

    var body: some View {
        Group {
            if let result = result {
                previewContent(for: result)
            } else {
                emptyPreview
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func previewContent(for result: SearchResult) -> some View {
        VStack(spacing: 16) {
            Spacer()

            // Large icon
            switch result.iconType {
            case .app(let path):
                LazyAppIconView(path: path, size: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            case .systemSymbol(let name):
                Image(systemName: name)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .foregroundColor(.accentColor)
            }

            // Title
            Text(result.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            // Category label
            Text(result.category.displayName)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            // Subtitle / detail
            if !result.subtitle.isEmpty {
                Text(result.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            // Action hint
            Text(actionHint(for: result))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary.opacity(0.8))
                .padding(.top, 4)

            Spacer()
        }
        .padding()
    }

    private var emptyPreview: some View {
        VStack {
            Spacer()
            Image(systemName: "magnifyingglass")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .foregroundColor(.secondary.opacity(0.3))
            Text("Type to search")
                .font(.system(size: 13))
                .foregroundColor(.secondary.opacity(0.5))
            Spacer()
        }
    }

    private func actionHint(for result: SearchResult) -> String {
        switch result.action {
        case .launchApp: return "Press ↵ to open"
        case .openSettings: return "Press ↵ to open settings"
        case .runQuickAction: return "Press ↵ to execute"
        case .runInTerminal: return "Press ↵ to run in Terminal"
        case .copyToClipboard: return "Press ↵ to copy result"
        case .openWebSearch: return "Press ↵ to search in browser"
        case .openURL: return "Press ↵ to open in browser"
        case .openFolder: return "Press ↵ to open in VS Code · ⌥↵ for Terminal"
        }
    }
}
