import SwiftUI

/// Compact content shown during a copy sneak-peek: a small thumbnail/icon and
/// the captured clip's preview, under a "Copied" label.
struct ClipPeekView: View {
    let item: ClipItem

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text("Copied")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .textCase(.uppercase)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch item.kind {
        case .image(let file, _, _, _):
            if let image = NSImage(contentsOf: BlobStore.shared.url(for: file)) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                badge("photo", .gray)
            }
        case .color(let hex):
            (Color(hexString: hex) ?? .gray)
        case .link:
            badge("link", .blue)
        case .file:
            badge("doc.fill", .orange)
        case .text:
            badge("textformat", Color.white.opacity(0.15))
        }
    }

    private func badge(_ symbol: String, _ tint: Color) -> some View {
        ZStack {
            tint.opacity(0.9)
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var label: String {
        switch item.kind {
        case .text(let s): return s.replacingOccurrences(of: "\n", with: " ")
        case .link(let u): return u.host ?? u.absoluteString
        case .color(let hex): return hex.uppercased()
        case .image(_, _, let w, let h): return "Image · \(w)×\(h)"
        case .file(_, _, let name): return name
        }
    }
}
