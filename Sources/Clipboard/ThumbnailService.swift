import AppKit
import QuickLookThumbnailing

/// Generates and caches QuickLook thumbnails for file clips.
actor ThumbnailService {
    static let shared = ThumbnailService()

    private var cache: [String: NSImage] = [:]

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
