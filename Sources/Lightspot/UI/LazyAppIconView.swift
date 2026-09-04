import SwiftUI
import AppKit

struct LazyAppIconView: View {
    let path: String
    let size: CGFloat

    @State private var icon: NSImage?

    init(path: String, size: CGFloat) {
        self.path = path
        self.size = size
        // Instant synchronous fast path from cache or workspace icon
        if let cached = AppIconCache.shared.cachedIcon(forPath: path, size: Int(size)) {
            _icon = State(initialValue: cached)
        } else {
            let loaded = AppIconCache.shared.icon(forPath: path, size: Int(size))
            _icon = State(initialValue: loaded)
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
        .id("\(path)_\(Int(size))")
        .onChange(of: path) { newPath in
            self.icon = AppIconCache.shared.icon(forPath: newPath, size: Int(size))
        }
    }
}
