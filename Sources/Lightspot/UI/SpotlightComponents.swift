import SwiftUI
import AppKit

// MARK: - App Store Glyph Vector Icon

struct AppStoreGlyphView: View {
    var size: CGFloat = 18

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let strokeWidth: CGFloat = w * 0.125

            // Bar 1: Left diagonal (bottom-left to apex)
            var p1 = Path()
            p1.move(to: CGPoint(x: w * 0.20, y: h * 0.85))
            p1.addLine(to: CGPoint(x: w * 0.50, y: h * 0.15))
            context.stroke(
                p1,
                with: .color(.white.opacity(0.85)),
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
            )

            // Bar 2: Right diagonal (bottom-right to apex)
            var p2 = Path()
            p2.move(to: CGPoint(x: w * 0.80, y: h * 0.85))
            p2.addLine(to: CGPoint(x: w * 0.50, y: h * 0.15))
            context.stroke(
                p2,
                with: .color(.white.opacity(0.85)),
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
            )

            // Bar 3: Horizontal crossbar
            var p3 = Path()
            p3.move(to: CGPoint(x: w * 0.16, y: h * 0.62))
            p3.addLine(to: CGPoint(x: w * 0.84, y: h * 0.62))
            context.stroke(
                p3,
                with: .color(.white.opacity(0.85)),
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
            )
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Glowing Cursor View (Apple Intelligence / Siri Aura)

struct GlowCursorView: View {
    @State private var isPulsing: Bool = false

    var body: some View {
        ZStack {
            // Ambient Aura Halo
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.2, green: 0.8, blue: 1.0).opacity(0.8),
                            Color(red: 0.4, green: 0.6, blue: 1.0).opacity(0.6)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 26)
                .blur(radius: isPulsing ? 4 : 2.5)
                .opacity(isPulsing ? 0.9 : 0.6)

            // Bright Center Core
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white,
                            Color(red: 0.85, green: 0.95, blue: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 2.5, height: 24)
                .shadow(color: Color(red: 0.3, green: 0.85, blue: 1.0).opacity(0.9), radius: 6, x: 0, y: 0)
        }
        .frame(width: 10, height: 26)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

// MARK: - Category Filter Chips Bar

struct CategoryChipsView: View {
    @Binding var selectedCategory: AppCategory
    let onSelect: (AppCategory) -> Void

    private let categories: [AppCategory] = [
        .productivity, .utilities, .entertainment, .social, .creativity, .developerTools, .infoReading, .other
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(categories) { category in
                    let isSelected = category == selectedCategory
                    CategoryChipButton(
                        title: category.shortName,
                        isSelected: isSelected,
                        onTap: {
                            if selectedCategory == category {
                                onSelect(.all)
                            } else {
                                onSelect(category)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

struct CategoryChipButton: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .white : .white.opacity(0.62))
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(
                            isSelected
                                ? Color.white.opacity(0.20)
                                : (isHovered ? Color.white.opacity(0.08) : Color.clear)
                        )
                )
                .overlay(
                    isSelected
                        ? Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                        : nil
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Calculator Result Card

struct CalculatorCardView: View {
    let expression: String
    let result: String
    let onCopy: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onCopy) {
            HStack(spacing: 16) {
                // Calculator Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.85), Color.orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: Color.orange.opacity(0.3), radius: 8, y: 3)

                    Image(systemName: "equal")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                }

                // Calculation details
                VStack(alignment: .leading, spacing: 2) {
                    Text(result)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)

                    Text(expression)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.white.opacity(0.65))
                }

                Spacer()

                // Action hint badge
                HStack(spacing: 4) {
                    Image(systemName: "return")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Copy")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.75))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.12 : 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}

// MARK: - Search Results Section List

struct SearchResultsView: View {
    let groupedResults: [ResultCategory: [SearchResult]]
    let selectedIndex: Int
    let onSelect: (SearchResult) -> Void

    private var flatResults: [SearchResult] {
        SearchEngine.flatResults(from: groupedResults)
    }

    var body: some View {
        let flat = flatResults
        let selectedID = (selectedIndex >= 0 && selectedIndex < flat.count) ? flat[selectedIndex].id : nil

        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(SearchEngine.orderedCategories(from: groupedResults), id: \.self) { category in
                        if let items = groupedResults[category] {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(category.displayName)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.5))
                                    .textCase(.uppercase)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 4)

                                ForEach(items, id: \.id) { item in
                                    let isSelected = item.id == selectedID
                                    SearchResultRow(
                                        result: item,
                                        isSelected: isSelected,
                                        onTap: { onSelect(item) }
                                    )
                                    .id(item.id)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
            }
            .onChange(of: selectedIndex) { newIndex in
                let currentFlat = flatResults
                if newIndex >= 0 && newIndex < currentFlat.count {
                    proxy.scrollTo(currentFlat[newIndex].id, anchor: nil)
                }
            }
        }
    }
}

struct SearchResultRow: View {
    let result: SearchResult
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Result Icon
                switch result.iconType {
                case .app(let path):
                    LazyAppIconView(path: path, size: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                case .systemSymbol(let name):
                    Image(systemName: name)
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle().fill(Color.white.opacity(0.1))
                        )
                }

                // Texts
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.title)
                        .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if !result.subtitle.isEmpty {
                        Text(result.subtitle)
                            .font(.system(size: 11.5))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Selection hint
                if isSelected {
                    Image(systemName: "return")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.18)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.white.opacity(0.18)
                            : (isHovered ? Color.white.opacity(0.08) : Color.clear)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
