import SwiftUI
import AppKit

struct AppGridView: View {
    var recentApps: [AppInfo]? = nil
    var categorySections: [(category: AppCategory, apps: [AppInfo])]? = nil
    let apps: [AppInfo]
    let selectedIndex: Int
    let onSelect: (AppInfo) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 7)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                if apps.isEmpty {
                    VStack(spacing: 12) {
                        Spacer(minLength: 40)
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 36, weight: .light))
                            .foregroundColor(.white.opacity(0.3))
                        Text("No applications found")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.4))
                        Spacer(minLength: 40)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else if let sections = categorySections, let recents = recentApps, !sections.isEmpty {
                    // Grouped All-Apps View (Recent Apps on Top + Categorized Sections Below)
                    VStack(alignment: .leading, spacing: 18) {
                        // 1. Recent Apps (First Row)
                        if !recents.isEmpty {
                            LazyVGrid(columns: columns, spacing: 18) {
                                ForEach(Array(recents.enumerated()), id: \.element.id) { index, app in
                                    AppGridItemView(
                                        app: app,
                                        isSelected: index == selectedIndex,
                                        onTap: { onSelect(app) }
                                    )
                                    .id(index)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                        }

                        // 2. Categorized Sections
                        ForEach(Array(sections.enumerated()), id: \.element.category.id) { sectionIdx, section in
                            let sectionStartIndex = calculateStartIndex(sectionIdx: sectionIdx, recentsCount: recents.count, sections: sections)

                            VStack(alignment: .leading, spacing: 10) {
                                // Category Section Header
                                Text(section.category.shortName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.65))
                                    .padding(.horizontal, 24)
                                    .padding(.top, 4)

                                LazyVGrid(columns: columns, spacing: 18) {
                                    ForEach(Array(section.apps.enumerated()), id: \.element.id) { itemIdx, app in
                                        let globalIndex = sectionStartIndex + itemIdx
                                        AppGridItemView(
                                            app: app,
                                            isSelected: globalIndex == selectedIndex,
                                            onTap: { onSelect(app) }
                                        )
                                        .id(globalIndex)
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                } else {
                    // Flat Grid (Search Results or Single Filtered Category)
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                            AppGridItemView(
                                app: app,
                                isSelected: index == selectedIndex,
                                onTap: { onSelect(app) }
                            )
                            .id(index)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .onChange(of: selectedIndex) { newIdx in
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(newIdx, anchor: .center)
                }
            }
        }
    }

    private func calculateStartIndex(sectionIdx: Int, recentsCount: Int, sections: [(category: AppCategory, apps: [AppInfo])]) -> Int {
        var count = recentsCount
        for i in 0..<sectionIdx {
            count += sections[i].apps.count
        }
        return count
    }
}

struct AppGridItemView: View {
    let app: AppInfo
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                // Squircle App Icon
                ZStack {
                    Image(nsImage: app.icon128)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 11.5, style: .continuous))
                        .shadow(color: .black.opacity(0.35), radius: 5, x: 0, y: 3)
                        .scaleEffect(isHovered || isSelected ? 1.06 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered || isSelected)

                    if isSelected {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.8), Color.cyan.opacity(0.6)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                            .frame(width: 60, height: 60)
                            .shadow(color: Color.cyan.opacity(0.4), radius: 6, x: 0, y: 0)
                    }
                }
                .frame(width: 60, height: 60)

                // App Label
                Text(app.name)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 78)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.12) : (isHovered ? Color.white.opacity(0.06) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
