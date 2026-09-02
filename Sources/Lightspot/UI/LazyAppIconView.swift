import SwiftUI
import AppKit

struct LazyAppIconView: View {
    let path: String
    let size: CGFloat

    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon = icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.clear
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
        // Run on main thread, since NSCache is fast and NSWorkspace caching is also fast
        let img = AppIconCache.shared.icon(forPath: path, size: Int(size))
        self.icon = img
    }
}
