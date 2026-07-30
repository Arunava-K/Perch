import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ShelfTab: View {
    @ObservedObject var shelf: ShelfStore
    var dismiss: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            if !shelf.items.isEmpty {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button {
                        ShelfActions.shareAll(shelf.items)
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(ShelfChromeButtonStyle())

                    Button {
                        ShelfActions.zipAndShare(shelf.items)
                    } label: {
                        Label("Zip", systemImage: "doc.zipper")
                    }
                    .buttonStyle(ShelfChromeButtonStyle())
                }
                .padding(.horizontal, 28)
                .padding(.top, 2)
            }

            CardStripView(
                items: shelf.items,
                emptyTitle: "Drag files here to stage them",
                emptySymbol: "tray.and.arrow.down",
                onPick: { _ in dismiss() },
                onTogglePin: nil,
                onDelete: { shelf.remove($0.id) },
                onShare: { ShelfActions.shareOne($0) },
                showsPin: false
            )
        }
    }
}

private struct ShelfChromeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.55 : 0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(.white.opacity(configuration.isPressed ? 0.08 : 0.06))
            )
    }
}

/// Share / AirDrop / zip helpers for staged shelf items.
enum ShelfActions {
    static func shareOne(_ item: ClipItem) {
        guard let objects = shareObjects(for: [item]), !objects.isEmpty else { return }
        presentPicker(objects)
    }

    static func shareAll(_ items: [ClipItem]) {
        guard let objects = shareObjects(for: items), !objects.isEmpty else { return }
        presentPicker(objects)
    }

    static func zipAndShare(_ items: [ClipItem]) {
        guard let url = makeZip(items) else { return }
        presentPicker([url])
    }

    private static func presentPicker(_ items: [Any]) {
        guard let view = NSApp.keyWindow?.contentView
                ?? NSApp.windows.first(where: { $0.isVisible })?.contentView
        else { return }
        let picker = NSSharingServicePicker(items: items)
        let rect = NSRect(x: view.bounds.midX - 1, y: view.bounds.midY - 1, width: 2, height: 2)
        picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
    }

    private static func shareObjects(for items: [ClipItem]) -> [Any]? {
        var out: [Any] = []
        for item in items {
            switch item.kind {
            case .text(let s):
                out.append(s)
            case .link(let url):
                out.append(url)
            case .color(let hex):
                out.append(hex)
            case .image(let file, _, _, _):
                if let data = BlobStore.shared.pngData(for: file),
                   let img = NSImage(data: data) {
                    out.append(img)
                } else {
                    out.append(BlobStore.shared.url(for: file))
                }
            case .file(let bookmark, let path, _):
                var stale = false
                if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope],
                                      relativeTo: nil, bookmarkDataIsStale: &stale) {
                    _ = url.startAccessingSecurityScopedResource()
                    out.append(url)
                } else {
                    out.append(URL(fileURLWithPath: path))
                }
            case .locked:
                break
            }
        }
        return out.isEmpty ? nil : out
    }

    private static func makeZip(_ items: [ClipItem]) -> URL? {
        let fm = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let folder = fm.temporaryDirectory.appendingPathComponent("Perch-Shelf-\(stamp)", isDirectory: true)
        try? fm.removeItem(at: folder)
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        var index = 0
        for item in items {
            index += 1
            switch item.kind {
            case .text(let s):
                let url = folder.appendingPathComponent("text-\(index).txt")
                try? s.data(using: .utf8)?.write(to: url)
            case .link(let link):
                let url = folder.appendingPathComponent("link-\(index).txt")
                try? link.absoluteString.data(using: .utf8)?.write(to: url)
            case .color(let hex):
                let url = folder.appendingPathComponent("color-\(index).txt")
                try? hex.data(using: .utf8)?.write(to: url)
            case .image(let file, _, _, _):
                let dest = folder.appendingPathComponent("image-\(index).png")
                if let data = BlobStore.shared.pngData(for: file) {
                    try? data.write(to: dest)
                } else {
                    try? fm.copyItem(at: BlobStore.shared.url(for: file), to: dest)
                }
            case .file(let bookmark, let path, let name):
                var stale = false
                let src: URL
                if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope],
                                      relativeTo: nil, bookmarkDataIsStale: &stale) {
                    _ = url.startAccessingSecurityScopedResource()
                    src = url
                } else {
                    src = URL(fileURLWithPath: path)
                }
                let dest = folder.appendingPathComponent(name.isEmpty ? src.lastPathComponent : name)
                try? fm.copyItem(at: src, to: dest)
            case .locked:
                break
            }
        }

        let zipURL = fm.temporaryDirectory.appendingPathComponent("Perch-Shelf-\(stamp).zip")
        try? fm.removeItem(at: zipURL)
        let coord = NSFileCoordinator()
        var error: NSError?
        var ok = false
        coord.coordinate(readingItemAt: folder, options: [.forUploading], error: &error) { tempZip in
            do {
                try fm.copyItem(at: tempZip, to: zipURL)
                ok = true
            } catch {
                ok = false
            }
        }
        try? fm.removeItem(at: folder)
        return ok ? zipURL : nil
    }
}

@MainActor
final class ShelfModule: NotchModule {
    let id = "shelf"
    let title = "Shelf"
    let icon = "tray.full.fill"
    var acceptsDrops: Bool { true }

    private let shelf: ShelfStore
    init(shelf: ShelfStore) { self.shelf = shelf }

    func handleDrop(_ providers: [NSItemProvider]) {
        DropImporter.importProviders(providers, add: { [shelf] item in shelf.add(item) })
    }

    func makeContent(_ context: ModuleContext) -> AnyView {
        AnyView(ShelfTab(shelf: shelf, dismiss: context.dismiss))
    }
}
