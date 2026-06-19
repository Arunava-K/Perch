import AppKit

/// Writes a stored clip back to the general pasteboard.
enum ClipboardWriter {
    static func copy(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()

        switch item.kind {
        case .text(let string):
            pb.setString(string, forType: .string)

        case .link(let url):
            pb.setString(url.absoluteString, forType: .string)
            pb.setString(url.absoluteString, forType: .URL)

        case .color(let hex):
            pb.setString(hex, forType: .string)

        case .image(let blobFile, _, _, _):
            let url = BlobStore.shared.url(for: blobFile)
            if let data = try? Data(contentsOf: url) {
                pb.setData(data, forType: .png)
            }

        case .file(let bookmark, let path, _):
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                pb.writeObjects([url as NSURL])
            } else {
                pb.writeObjects([NSURL(fileURLWithPath: path)])
            }
        }
    }
}
