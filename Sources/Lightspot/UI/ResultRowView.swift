import SwiftUI
import AppKit

struct ResultRowView: View {
    let result: SearchResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            if let icon = result.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: "questionmark.circle")
                    .resizable()
                    .frame(width: 28, height: 28)
                    .foregroundColor(.secondary)
            }

            // Title + Subtitle
            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)

                if !result.subtitle.isEmpty {
                    Text(result.subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
    }
}
