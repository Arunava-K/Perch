import AppKit
import Quartz

/// Presents image/file clips in a QuickLook panel.
final class QuickLookPreview: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLookPreview()

    private var urls: [URL] = []

    /// QuickLook-able URLs for the given clips (images & files only).
    static func quickLookURLs(for items: [ClipItem]) -> [URL] {
        items.compactMap { item in
            switch item.kind {
            case .image(let file, _, _, _):
                return BlobStore.shared.url(for: file)
            case .file(let bookmark, let path, _):
                var stale = false
                if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope],
                                      relativeTo: nil, bookmarkDataIsStale: &stale) {
                    _ = url.startAccessingSecurityScopedResource()
                    return url
                }
                return URL(fileURLWithPath: path)
            default:
                return nil
            }
        }
    }

    func show(_ items: [ClipItem]) {
        let urls = Self.quickLookURLs(for: items)
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        self.urls = urls
        panel.dataSource = self
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urls[index] as NSURL
    }
}
