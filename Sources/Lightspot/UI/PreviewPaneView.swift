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
            if let icon = previewIcon(for: result) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            } else {
                Image(systemName: previewSystemIcon(for: result))
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

    private func previewIcon(for result: SearchResult) -> NSImage? {
        switch result.category {
        case .topHit, .applications:
            // Try to get the large icon
            let bundleID = result.id.replacingOccurrences(of: "app-", with: "")
                                    .replacingOccurrences(of: "top-app-", with: "")
            if let largeIcon = AppScanner.shared.largeIcon(for: bundleID) {
                return largeIcon
            }
            return result.icon
        default:
            return nil
        }
    }

    private func previewSystemIcon(for result: SearchResult) -> String {
        switch result.category {
        case .systemSettings: return "gear"
        case .quickActions: return "bolt.circle.fill"
        case .calculator: return "equal.circle.fill"
        case .webSearch: return "globe"
        default: return "magnifyingglass"
        }
    }

    private func actionHint(for result: SearchResult) -> String {
        switch result.category {
        case .topHit, .applications: return "Press ↵ to open"
        case .systemSettings: return "Press ↵ to open settings"
        case .quickActions: return "Press ↵ to execute"
        case .calculator: return "Press ↵ to copy result"
        case .webSearch: return "Press ↵ to search in browser"
        }
    }
}
