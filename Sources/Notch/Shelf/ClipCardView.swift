import SwiftUI

/// A single clip rendered as a tappable card. Click pastes into the active app
/// (or copies if Accessibility isn't granted); drag carries it to other apps.
struct ClipCardView: View {
    let item: ClipItem
    var onPick: () -> Void = {}
    var onTogglePin: () -> Void = {}
    var onDelete: () -> Void = {}

    @State private var confirm = false
    @State private var confirmLabel = "Copied"
    @State private var hovering = false

    private let cardSize = CGSize(width: 132, height: 118)
    private let radius: CGFloat = 13
    private let footerHeight: CGFloat = 26

    var body: some View {
        Button(action: activate) {
            VStack(spacing: 0) {
                preview
                    .frame(width: cardSize.width,
                           height: hasFooter ? cardSize.height - footerHeight : cardSize.height)
                    .clipped()
                if hasFooter { footer }
            }
            .frame(width: cardSize.width, height: cardSize.height)
            .background(Color.white.opacity(hovering ? 0.11 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(alignment: .topLeading) { pinBadge }
            .overlay(alignment: .topTrailing) { formatTag }
            .overlay { confirmOverlay }
            .scaleEffect(hovering ? 1.03 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: hovering)
        }
        .buttonStyle(PressableStyle(pressedScale: 0.96))
        .onHover { hovering = $0 }
        .onDrag { makeItemProvider() }
        .help(tooltip)
        .contextMenu {
            Button(item.isPinned ? "Unpin" : "Pin",
                   systemImage: item.isPinned ? "pin.slash" : "pin", action: onTogglePin)
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    // MARK: Preview (type-specific top region)

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .text(let string):
            Text(string)
                .font(.system(size: 12.5))
                .lineSpacing(2)
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)

        case .link(let url):
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: "link")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)
                Text(url.host ?? url.absoluteString)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)

        case .color(let hex):
            ZStack(alignment: .bottomLeading) {
                (Color(hexString: hex) ?? .gray)
                Text(hex.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.4), in: Capsule())
                    .padding(9)
            }

        case .image(let blobFile, _, _, _):
            if let image = NSImage(contentsOf: BlobStore.shared.url(for: blobFile)) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                placeholder("photo")
            }

        case .file(_, let path, _):
            FileThumbnail(path: path, size: CGSize(width: 80, height: 80))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .locked(let type):
            VStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 18))
                Text("Locked \(type)").font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Visual clips (files & images) fill the card with a corner tag; the rest
    /// keep their source-app footer.
    private var hasFooter: Bool {
        switch item.kind {
        case .file, .image: return false
        default: return true
        }
    }

    /// Filename surfaced on hover (files only) since the name block is gone.
    private var tooltip: String {
        if case .file(_, _, let name) = item.kind { return name }
        return ""
    }

    /// Corner badge: extension for files, pixel size for images.
    @ViewBuilder
    private var formatTag: some View {
        if let label = tagLabel {
            Text(label)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2.5)
                .background(.black.opacity(0.5), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
                .padding(6)
        }
    }

    private var tagLabel: String? {
        switch item.kind {
        case .file(_, let path, _):
            let ext = (path as NSString).pathExtension.uppercased()
            return ext.isEmpty ? "FILE" : ext
        case .image:
            // Captured image data is stored as PNG.
            return "PNG"
        default:
            return nil
        }
    }

    private func placeholder(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 22))
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: typeSymbol)
                .font(.system(size: 8.5, weight: .semibold))
            Text(item.sourceAppName ?? item.kind.typeName.capitalized)
                .font(.system(size: 9.5, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white.opacity(0.4))
        .padding(.horizontal, 12)
        .frame(width: cardSize.width, height: footerHeight)
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.06)).frame(height: 0.5)
        }
    }

    private var typeSymbol: String {
        switch item.kind {
        case .text: return "textformat"
        case .link: return "link"
        case .color: return "paintpalette.fill"
        case .image: return "photo"
        case .file: return "doc"
        case .locked: return "lock.fill"
        }
    }

    @ViewBuilder
    private var pinBadge: some View {
        if item.isPinned {
            Image(systemName: "pin.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.yellow)
                .padding(5)
                .background(.ultraThinMaterial, in: Circle())
                .padding(6)
        }
    }

    @ViewBuilder
    private var confirmOverlay: some View {
        if confirm {
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.black.opacity(0.6))
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 20))
                    Text(confirmLabel).font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.white)
            }
            .transition(.opacity)
        }
    }

    // MARK: Actions

    private func activate() {
        let outcome = PasteService.paste(item)
        Haptics.tap()
        confirmLabel = outcome == .pasted ? "Pasted" : "Copied"
        withAnimation(.easeOut(duration: 0.15)) { confirm = true }
        Task {
            try? await Task.sleep(for: .milliseconds(550))
            onPick()
            withAnimation(.easeIn(duration: 0.2)) { confirm = false }
        }
    }

    private func makeItemProvider() -> NSItemProvider {
        switch item.kind {
        case .text(let string):
            return NSItemProvider(object: string as NSString)
        case .color(let hex):
            return NSItemProvider(object: hex as NSString)
        case .link(let url):
            return NSItemProvider(object: url as NSURL)
        case .image(let blobFile, _, _, _):
            let url = BlobStore.shared.url(for: blobFile)
            return NSItemProvider(contentsOf: url) ?? NSItemProvider()
        case .file(let bookmark, let path, _):
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope],
                                  relativeTo: nil, bookmarkDataIsStale: &stale) {
                _ = url.startAccessingSecurityScopedResource()
                return NSItemProvider(contentsOf: url) ?? NSItemProvider(object: path as NSString)
            }
            return NSItemProvider(object: path as NSString)
        case .locked:
            // Sealed content can't leave the app without being revealed.
            return NSItemProvider()
        }
    }
}
