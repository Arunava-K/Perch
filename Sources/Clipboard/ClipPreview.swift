import SwiftUI

/// Renders the type-specific visual for a clip. Shared by the notch shelf cards
/// and the Library window cells so they stay consistent.
struct ClipPreview: View {
    let item: ClipItem
    var compact: Bool = true

    var body: some View {
        switch item.kind {
        case .text(let string):
            Text(string)
                .font(.system(size: compact ? 11 : 12))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(compact ? 5 : 10)
                .padding(8)

        case .link(let url):
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "link")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.8))
                Text(url.host ?? url.absoluteString)
                    .font(.system(size: compact ? 10 : 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
            }
            .padding(8)

        case .color(let hex):
            ZStack(alignment: .bottomLeading) {
                (Color(hexString: hex) ?? .gray)
                Text(hex)
                    .font(.system(size: compact ? 9 : 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 4))
                    .padding(6)
            }

        case .image(let blobFile, _, _, _):
            if let image = NSImage(contentsOf: BlobStore.shared.url(for: blobFile)) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                fallbackIcon("photo")
            }

        case .file(_, let path, _):
            FileThumbnail(path: path, size: CGSize(width: 64, height: 64))
        }
    }

    private func fallbackIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 22))
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Async-loading QuickLook thumbnail for a file path, with an icon fallback.
struct FileThumbnail: View {
    let path: String
    let size: CGSize

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .padding(10)
        .task {
            let url = URL(fileURLWithPath: path)
            image = await ThumbnailService.shared.thumbnail(forFileAt: url, size: size)
        }
    }
}
