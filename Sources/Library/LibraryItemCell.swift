import SwiftUI

/// A clip rendered as a Library grid cell with selection, pin badge, and a
/// context menu of manage actions.
struct LibraryItemCell: View {
    let item: ClipItem
    let isSelected: Bool
    var isTrashMode: Bool = false
    var canLock: Bool = false
    var isRevealed: Bool = false
    var hasRichText: Bool = false
    let onSelect: () -> Void
    /// Primary action: copy in normal mode, "Put Back" in trash mode.
    let onCopy: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    let onQuickLook: () -> Void
    var onLock: () -> Void = {}
    var onReveal: () -> Void = {}
    var onRemoveLock: () -> Void = {}
    var onCopyPlain: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ClipPreview(item: item, compact: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            footer
        }
        .frame(height: 150)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.black.opacity(0.12),
                              lineWidth: isSelected ? 2.5 : 1)
        )
        .overlay(alignment: .topTrailing) {
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.yellow)
                    .padding(6)
            }
        }
        .overlay(alignment: .topLeading) {
            if item.isLocked {
                Image(systemName: isRevealed ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(isRevealed ? .green : .secondary)
                    .padding(6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onCopy)
        .onTapGesture(perform: onSelect)
        .contextMenu {
            if isTrashMode {
                Button("Put Back", action: onCopy)
                if canQuickLook { Button("Quick Look", action: onQuickLook) }
                Divider()
                Button("Delete Permanently", role: .destructive, action: onDelete)
            } else if item.isLocked {
                if isRevealed {
                    Button("Copy", action: onCopy)
                    if canQuickLook { Button("Quick Look", action: onQuickLook) }
                } else {
                    Button("Reveal…", action: onReveal)
                }
                Button("Remove Lock…", action: onRemoveLock)
                Divider()
                Button("Delete", role: .destructive, action: onDelete)
            } else {
                Button("Copy", action: onCopy)
                if hasRichText { Button("Copy as Plain Text", action: onCopyPlain) }
                Button(item.isPinned ? "Unpin" : "Pin", action: onTogglePin)
                if canLock { Button("Lock", action: onLock) }
                if canQuickLook { Button("Quick Look", action: onQuickLook) }
                Divider()
                Button("Delete", role: .destructive, action: onDelete)
            }
        }
    }

    private var canQuickLook: Bool {
        switch item.kind {
        case .image, .file: return true
        default: return false
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Image(systemName: typeSymbol).font(.system(size: 9, weight: .semibold))
            Text(item.sourceAppName ?? item.kind.typeName.capitalized)
                .font(.system(size: 10)).lineLimit(1)
            Spacer()
            Text(item.timestamp, format: .relative(presentation: .numeric))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.04))
    }

    private var typeSymbol: String {
        switch item.kind {
        case .text: return "textformat"
        case .link: return "link"
        case .color: return "paintpalette"
        case .image: return "photo"
        case .file: return "doc"
        case .locked: return "lock.fill"
        }
    }
}
