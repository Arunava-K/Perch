import AppKit

/// Writes a stored clip back to the general pasteboard.
enum ClipboardWriter {
    /// Writes a clip to the pasteboard. When `asPlainText` is false and the clip
    /// carries RTF, both representations are written so the destination can keep
    /// formatting; when true, only the plain string is written.
    static func copy(_ item: ClipItem, asPlainText: Bool = false) {
        let pb = NSPasteboard.general
        pb.clearContents()

        switch item.kind {
        case .text(let string):
            if !asPlainText, let rtf = item.richRTF {
                pb.setData(rtf, forType: .rtf)
            }
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

        case .locked:
            // Sealed content can't be written without first being revealed.
            break
        }
    }
}
