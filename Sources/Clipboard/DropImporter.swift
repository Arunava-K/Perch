import AppKit
import UniformTypeIdentifiers

/// Imports items dropped onto the notch (drag-in) and hands each off to `add`.
enum DropImporter {
    @MainActor
    static func importProviders(_ providers: [NSItemProvider], add: @escaping @MainActor (ClipItem) -> Void) {
        for provider in providers {
            Task {
                if let item = await makeItem(from: provider) {
                    add(item)
                }
            }
        }
    }

    /// Convenience for the clipboard store.
    @MainActor
    static func importProviders(_ providers: [NSItemProvider], into store: ClipStore) {
        importProviders(providers, add: { store.add($0) })
    }

    private static func makeItem(from provider: NSItemProvider) async -> ClipItem? {
        // File on disk → security-scoped bookmark.
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = await loadURL(provider, type: UTType.fileURL.identifier), url.isFileURL {
            let bookmark = (try? url.bookmarkData(options: [.withSecurityScope]))
                ?? (try? url.bookmarkData())
            if let bookmark {
                return ClipItem(kind: .file(bookmark: bookmark, path: url.path,
                                            displayName: url.lastPathComponent))
            }
        }

        // Image bitmap.
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
           let data = await loadData(provider, type: UTType.image.identifier),
           let image = NSImage(data: data), let png = image.pngData() {
            let saved = BlobStore.shared.savePNG(png)
            let size = image.pixelSize
            return ClipItem(kind: .image(blobFile: saved.file, contentHash: saved.hash,
                                         pixelWidth: Int(size.width), pixelHeight: Int(size.height)))
        }

        // Web URL.
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = await loadURL(provider, type: UTType.url.identifier), !url.isFileURL {
            return ClipItem(kind: .link(url: url))
        }

        // Plain text.
        if let text = await loadText(provider) {
            return ClipItem(kind: .text(string: text))
        }
        return nil
    }

    // MARK: Async provider loaders

    private static func loadURL(_ provider: NSItemProvider, type: String) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data,
                          let string = String(data: data, encoding: .utf8),
                          let url = URL(string: string) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func loadData(_ provider: NSItemProvider, type: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private static func loadText(_ provider: NSItemProvider) async -> String? {
        for type in [UTType.utf8PlainText.identifier, UTType.plainText.identifier, UTType.text.identifier]
        where provider.hasItemConformingToTypeIdentifier(type) {
            if let data = await loadData(provider, type: type),
               let string = String(data: data, encoding: .utf8), !string.isEmpty {
                return string
            }
        }
        return nil
    }
}
