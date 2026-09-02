import AppKit

/// A thread-safe, high-performance cache for application icons.
/// Supports instantaneous in-memory lookup and non-blocking background disk loading.
public final class AppIconCache: @unchecked Sendable {
    public static let shared = AppIconCache()

    private let cache = NSCache<NSString, NSImage>()
    private let loadQueue = DispatchQueue(label: "com.lightspot.iconcache.load", qos: .userInitiated, attributes: .concurrent)

    private init() {
        // Allow caching up to 512 icons in memory (~20MB max)
        cache.countLimit = 512
        cache.evictsObjectsWithDiscardedContent = false
    }

    /// Returns a cached icon if available immediately in memory (O(1), zero disk I/O).
    public func cachedIcon(forPath path: String, size: Int = 128) -> NSImage? {
        let key = "\(path)_\(size)" as NSString
        return cache.object(forKey: key)
    }

    /// Fetches an icon synchronously: checks in-memory cache first, otherwise loads from disk.
    public func icon(forPath path: String, size: Int = 128) -> NSImage {
        let key = "\(path)_\(size)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: size, height: size)
        cache.setObject(icon, forKey: key)
        return icon
    }

    /// Asynchronously loads an icon without blocking the main/UI thread.
    /// If already cached in memory, returns immediately.
    public func loadIconAsync(forPath path: String, size: Int = 128, completion: @escaping @Sendable @MainActor (NSImage) -> Void) {
        let key = "\(path)_\(size)" as NSString
        if let cached = cache.object(forKey: key) {
            Task { @MainActor in
                completion(cached)
            }
            return
        }

        loadQueue.async { [weak self] in
            guard let self = self else { return }
            let icon = NSWorkspace.shared.icon(forFile: path)
            icon.size = NSSize(width: size, height: size)
            let cacheKey = "\(path)_\(size)" as NSString
            self.cache.setObject(icon, forKey: cacheKey)
            Task { @MainActor in
                completion(icon)
            }
        }
    }

    /// Prewarms icons in the background for a list of app paths.
    public func prewarmIcons(for paths: [String], size: Int = 128) {
        loadQueue.async { [weak self] in
            guard let self = self else { return }
            for path in paths {
                let key = "\(path)_\(size)" as NSString
                if self.cache.object(forKey: key) == nil {
                    let icon = NSWorkspace.shared.icon(forFile: path)
                    icon.size = NSSize(width: size, height: size)
                    self.cache.setObject(icon, forKey: key)
                }
            }
        }
    }

    /// Clears all cached icons under memory pressure.
    public func clear() {
        cache.removeAllObjects()
    }
}
