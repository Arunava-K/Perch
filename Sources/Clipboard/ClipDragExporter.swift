import AppKit
import UniformTypeIdentifiers

/// Materializes clips as file URLs for single- and multi-item drag/drop into
/// other apps (Finder, chat UIs, AI agents, …).
enum ClipDragExporter {
    private static var stagingRoot: URL?

    static func fileURLs(for items: [ClipItem]) -> [URL] {
        items.compactMap { stageFile(for: $0) }
    }

    static func copyToPasteboard(_ items: [ClipItem]) {
        let urls = fileURLs(for: items)
        let pb = NSPasteboard.general
        pb.clearContents()
        guard !urls.isEmpty else { return }
        pb.writeObjects(urls as [NSURL])
        // Help single-image destinations when only one clip is copied.
        if items.count == 1, case .image(let file, _, _, _) = items[0].kind,
           let data = BlobStore.shared.pngData(for: file) {
            pb.setData(data, forType: .png)
        }
    }

    /// Multi-file drag session using real file URLs (what drop targets expect).
    @MainActor
    static func beginDragging(items: [ClipItem], event: NSEvent) {
        let urls = fileURLs(for: items)
        guard !urls.isEmpty else { return }

        // Prefer the event's window (the notch panel); fall back to any visible view.
        let view = event.window?.contentView
            ?? NSApp.windows.reversed().first(where: { $0.isVisible })?.contentView
        guard let view else { return }

        var draggingItems: [NSDraggingItem] = []
        let origin = view.convert(event.locationInWindow, from: nil)

        for (index, url) in urls.enumerated() {
            // PasteboardItem with file URL types is more reliable than bare NSURL
            // for some Electron / AI chat drop targets.
            let pbItem = NSPasteboardItem()
            pbItem.setString(url.absoluteString, forType: .fileURL)
            pbItem.setString(url.path, forType: NSPasteboard.PasteboardType("public.file-url"))

            let drag = NSDraggingItem(pasteboardWriter: pbItem)
            let size = CGSize(width: 64, height: 64)
            let stack = CGFloat(index) * 12
            let frame = CGRect(
                x: origin.x - size.width / 2 + stack,
                y: origin.y - size.height / 2 - stack,
                width: size.width,
                height: size.height
            )
            drag.setDraggingFrame(frame, contents: dragPreviewImage(for: url, size: size))
            draggingItems.append(drag)
        }

        let session = view.beginDraggingSession(with: draggingItems, event: event, source: DragSource.shared)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    // MARK: Staging

    private static func stageFile(for item: ClipItem) -> URL? {
        let root = stagingDirectory()
        switch item.kind {
        case .image(let file, _, _, _):
            guard let data = BlobStore.shared.pngData(for: file) else { return nil }
            let dest = root.appendingPathComponent(shortName(prefix: "Screenshot", id: item.id, ext: "png"))
            do {
                try data.write(to: dest, options: .atomic)
                return dest
            } catch {
                return nil
            }

        case .file(let bookmark, let path, let displayName):
            var stale = false
            let src: URL
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope],
                                  relativeTo: nil, bookmarkDataIsStale: &stale) {
                _ = url.startAccessingSecurityScopedResource()
                src = url
            } else {
                src = URL(fileURLWithPath: path)
            }
            let name = displayName.isEmpty ? src.lastPathComponent : displayName
            let dest = root.appendingPathComponent(uniqueName(name, in: root))
            if src.standardizedFileURL == dest.standardizedFileURL { return src }
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.copyItem(at: src, to: dest)
                return dest
            } catch {
                return src
            }

        case .text(let string):
            let dest = root.appendingPathComponent(shortName(prefix: "Text", id: item.id, ext: "txt"))
            try? string.data(using: .utf8)?.write(to: dest, options: .atomic)
            return dest

        case .link(let url):
            let dest = root.appendingPathComponent(shortName(prefix: "Link", id: item.id, ext: "txt"))
            try? url.absoluteString.data(using: .utf8)?.write(to: dest, options: .atomic)
            return dest

        case .color(let hex):
            let dest = root.appendingPathComponent(shortName(prefix: "Color", id: item.id, ext: "txt"))
            try? hex.data(using: .utf8)?.write(to: dest, options: .atomic)
            return dest

        case .locked:
            return nil
        }
    }

    private static func stagingDirectory() -> URL {
        // Fresh folder per drag batch so names stay unique and old files don't pile up forever.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerchDrag-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        stagingRoot = dir
        return dir
    }

    private static func shortName(prefix: String, id: UUID, ext: String) -> String {
        let tail = String(id.uuidString.prefix(6))
        return "\(prefix)-\(tail).\(ext)"
    }

    private static func uniqueName(_ name: String, in dir: URL) -> String {
        let fm = FileManager.default
        var candidate = name
        var i = 2
        while fm.fileExists(atPath: dir.appendingPathComponent(candidate).path) {
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            candidate = ext.isEmpty ? "\(base)-\(i)" : "\(base)-\(i).\(ext)"
            i += 1
        }
        return candidate
    }

    private static func dragPreviewImage(for url: URL, size: CGSize) -> NSImage {
        if let img = NSImage(contentsOf: url) {
            let scaled = NSImage(size: size)
            scaled.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            let ratio = min(size.width / img.size.width, size.height / img.size.height)
            let drawSize = CGSize(width: img.size.width * ratio, height: img.size.height * ratio)
            let origin = CGPoint(x: (size.width - drawSize.width) / 2, y: (size.height - drawSize.height) / 2)
            img.draw(in: CGRect(origin: origin, size: drawSize),
                     from: .zero, operation: .copy, fraction: 1)
            scaled.unlockFocus()
            return scaled
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = size
        return icon
    }
}

private final class DragSource: NSObject, NSDraggingSource {
    static let shared = DragSource()

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
