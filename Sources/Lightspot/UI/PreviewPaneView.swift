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

            // Specialized color swatch or large icon
            if result.id.hasPrefix("dev-color-") {
                let hex = String(result.id.dropFirst("dev-color-".count))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: hex) ?? Color.accentColor)
                    .frame(width: 80, height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            } else {
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
                if result.id.hasPrefix("dev-json-") || result.id.hasPrefix("dev-jwt-"), case .copyToClipboard(let text) = result.action {
                    ScrollView {
                        Text(text)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(maxHeight: 180)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.35))
                    )
                    .padding(.horizontal, 16)
                } else {
                    Text(result.subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(4)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
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
        case .openFolder, .openProject: return "Press ↵ to open · ⌥↵ for Terminal · ⌘↵ for Finder"
        case .killProcess: return "Press ↵ to terminate · ⌥↵ to force kill"
        }
    }
}

// MARK: - Color Hex Extension

private extension Color {
    init?(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        guard Scanner(string: clean).scanHexInt64(&int) else { return nil }
        let a, r, g, b: UInt64
        switch clean.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
