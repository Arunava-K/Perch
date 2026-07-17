import AppKit
import Quartz

/// Presents image/file clips in a QuickLook panel.
final class QuickLookPreview: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookPreview()

    private var urls: [URL] = []
    private var securityScopedURLs: [URL] = []

    /// QuickLook-able URLs for the given clips (images & files only).
    private func quickLookURLs(for items: [ClipItem]) -> (urls: [URL], scopedURLs: [URL]) {
        var scopedURLs: [URL] = []
        let urls = items.compactMap { item in
            switch item.kind {
            case .image(let file, _, _, _):
                return BlobStore.shared.url(for: file)
            case .file(let bookmark, let path, _):
                var stale = false
                if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope],
                                      relativeTo: nil, bookmarkDataIsStale: &stale) {
                    if url.startAccessingSecurityScopedResource() {
                        scopedURLs.append(url)
                    }
                    return url
                }
                return URL(fileURLWithPath: path)
            default:
                return nil
            }
        }
        return (urls, scopedURLs)
    }

    func show(_ items: [ClipItem]) {
        let preview = quickLookURLs(for: items)
        guard !preview.urls.isEmpty, let panel = QLPreviewPanel.shared() else {
            preview.scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
            return
        }
        stopAccessingSecurityScopedURLs()
        securityScopedURLs = preview.scopedURLs
        self.urls = preview.urls
        panel.dataSource = self
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urls[index] as NSURL
    }

    func previewPanelWillClose(_ panel: QLPreviewPanel!) {
        stopAccessingSecurityScopedURLs()
    }

    private func stopAccessingSecurityScopedURLs() {
        securityScopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        securityScopedURLs.removeAll()
    }
}
