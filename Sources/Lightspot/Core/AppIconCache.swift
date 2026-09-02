import AppKit

/// A thread-safe, bounded cache for application icons.
/// Limits memory by evicting older icons when capacity is reached or on system memory warnings.
public final class AppIconCache: @unchecked Sendable {
    public static let shared = AppIconCache()

    private let cache = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(label: "com.lightspot.iconcache.sync")

    private init() {
        // Limit to approx 64 icons to keep memory bounded (~8-10MB max)
        cache.countLimit = 64
        cache.evictsObjectsWithDiscardedContent = true
    }

    /// Fetches an icon, returning cached version if available, otherwise loading it from disk.
    public func icon(forPath path: String, size: Int = 128) -> NSImage {
        let key = "\(path)_\(size)" as NSString
        
        // 1. Check cache (fast path)
        var cachedIcon: NSImage?
        queue.sync {
            cachedIcon = cache.object(forKey: key)
        }
        
        if let icon = cachedIcon {
            return icon
        }

        // 2. Load from disk (slow path)
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: size, height: size)
        
        // 3. Store in cache
        queue.sync {
            cache.setObject(icon, forKey: key)
        }
        
        return icon
    }

    /// Clears all cached icons. Call this when panel is hidden or under memory pressure.
    public func clear() {
        queue.sync {
            cache.removeAllObjects()
        }
    }
}
