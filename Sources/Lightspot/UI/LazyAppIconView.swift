import SwiftUI
import AppKit

struct LazyAppIconView: View {
    let path: String
    let size: CGFloat

    @State private var icon: NSImage?

    init(path: String, size: CGFloat) {
        self.path = path
        self.size = size
        // Instant synchronous fast path if already present in memory cache
        if let cached = AppIconCache.shared.cachedIcon(forPath: path, size: Int(size)) {
            _icon = State(initialValue: cached)
        } else {
            _icon = State(initialValue: nil)
        }
    }

    var body: some View {
        Group {
            if let icon = icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            loadIcon()
        }
        .onChange(of: path) { _ in
            loadIcon()
        }
    }

    private func loadIcon() {
        if let cached = AppIconCache.shared.cachedIcon(forPath: path, size: Int(size)) {
            self.icon = cached
            return
        }

        AppIconCache.shared.loadIconAsync(forPath: path, size: Int(size)) { loaded in
            self.icon = loaded
        }
    }
}
