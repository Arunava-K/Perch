import AppKit
import ImageIO
import QuickLookThumbnailing

/// Generates and caches QuickLook thumbnails for file clips.
actor ThumbnailService {
    static let shared = ThumbnailService()

    private var cache: [String: NSImage] = [:]
    private var imageCache: [String: NSImage] = [:]

    /// A downsampled thumbnail for a stored image blob, decoded at the target
    /// size via ImageIO (never the full-resolution image) and cached by
    /// path + size. Decoding a 132px card from a 34-megapixel PNG on the main
    /// thread — on every body re-eval — was the notch's scroll lag.
    func imageThumbnail(at url: URL, maxPixel: CGFloat) -> NSImage? {
        let key = "\(url.path)#\(Int(maxPixel))"
        if let cached = imageCache[key] { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        imageCache[key] = image
        return image
    }

    func thumbnail(forFileAt url: URL, size: CGSize) async -> NSImage? {
        let key = "\(url.path)#\(Int(size.width))x\(Int(size.height))"
        if let cached = cache[key] { return cached }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: 2.0,
            representationTypes: .all
        )

        let image: NSImage? = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
                continuation.resume(returning: rep?.nsImage)
            }
        }

        if let image { cache[key] = image }
        return image
    }
}
