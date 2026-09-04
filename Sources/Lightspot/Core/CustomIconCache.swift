import AppKit
import Foundation

/// Fast in-memory cache and image processor for custom base64-encoded command icons.
public final class CustomIconCache: @unchecked Sendable {
    public static let shared = CustomIconCache()

    private let cache = NSCache<NSString, NSImage>()
    private let lock = NSLock()

    private init() {
        cache.countLimit = 256
    }

    /// Retrieve an NSImage decoded from a Base64 string, using memory cache to prevent decoding on every render pass.
    public func image(for base64String: String) -> NSImage? {
        guard !base64String.isEmpty else { return nil }
        let key = base64String as NSString

        lock.lock()
        if let cached = cache.object(forKey: key) {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let data = Data(base64Encoded: base64String, options: [.ignoreUnknownCharacters]),
              let image = NSImage(data: data) else {
            return nil
        }

        lock.lock()
        cache.setObject(image, forKey: key)
        lock.unlock()
        return image
    }

    /// Processes any file URL (image, icns, or .app bundle), resizes to max dimension, and returns base64 PNG data string.
    public static func encodeImageFileToBase64(at fileURL: URL, maxDimension: CGFloat = 128) -> String? {
        let path = fileURL.path
        var sourceImage: NSImage?

        // 1. If it's a regular image file that NSImage can load directly
        if let direct = NSImage(contentsOf: fileURL), direct.isValid {
            sourceImage = direct
        } else {
            // 2. Otherwise use workspace icon (supports .app bundles, unknown file types, etc.)
            sourceImage = NSWorkspace.shared.icon(forFile: path)
        }

        guard let img = sourceImage, img.isValid else { return nil }

        // Determine target size preserving aspect ratio
        let origSize = img.size
        guard origSize.width > 0 && origSize.height > 0 else { return nil }

        let ratio = min(maxDimension / origSize.width, maxDimension / origSize.height, 1.0)
        let targetSize = NSSize(
            width: max(1, round(origSize.width * ratio)),
            height: max(1, round(origSize.height * ratio))
        )

        // Render to bitmap rep
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        rep.size = targetSize

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high

        img.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: origSize),
            operation: .sourceOver,
            fraction: 1.0
        )

        NSGraphicsContext.restoreGraphicsState()

        guard let pngData = rep.representation(using: .png, properties: [:]) else { return nil }
        return pngData.base64EncodedString()
    }

    /// Clear cache on memory pressure
    public func clear() {
        lock.lock()
        cache.removeAllObjects()
        lock.unlock()
    }
}
