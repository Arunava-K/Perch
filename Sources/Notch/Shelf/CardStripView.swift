import SwiftUI
import AppKit

/// A horizontal strip of clip cards, reused by the Clipboard and Pinned tabs.
/// Supports a select mode for multi-select + multi-item drag-out.
struct CardStripView: View {
    let items: [ClipItem]
    var emptyTitle: String = "No clips yet"
    var emptySymbol: String = "tray"
    var onPick: (ClipItem) -> Void
    var onTogglePin: ((ClipItem) -> Void)? = nil
    var onDelete: (ClipItem) -> Void = { _ in }
    var onShare: ((ClipItem) -> Void)? = nil
    var showsPin: Bool = true
    /// When true, taps toggle selection instead of pasting; drag carries all selected.
    var selectionMode: Bool = false
    @Binding var selectedIDs: Set<UUID>
    /// Long-press a card to enter multi-select with this id selected.
    var onEnterSelection: ((UUID) -> Void)? = nil

    init(
        items: [ClipItem],
        emptyTitle: String = "No clips yet",
        emptySymbol: String = "tray",
        onPick: @escaping (ClipItem) -> Void,
        onTogglePin: ((ClipItem) -> Void)? = nil,
        onDelete: @escaping (ClipItem) -> Void = { _ in },
        onShare: ((ClipItem) -> Void)? = nil,
        showsPin: Bool = true,
        selectionMode: Bool = false,
        selectedIDs: Binding<Set<UUID>> = .constant([]),
        onEnterSelection: ((UUID) -> Void)? = nil
    ) {
        self.items = items
        self.emptyTitle = emptyTitle
        self.emptySymbol = emptySymbol
        self.onPick = onPick
        self.onTogglePin = onTogglePin
        self.onDelete = onDelete
        self.onShare = onShare
        self.showsPin = showsPin
        self.selectionMode = selectionMode
        self._selectedIDs = selectedIDs
        self.onEnterSelection = onEnterSelection
    }

    private var selectedItems: [ClipItem] {
        // Preserve strip order for stable multi-drag stacking.
        items.filter { selectedIDs.contains($0.id) }
    }

    var body: some View {
        if items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: emptySymbol)
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.white.opacity(0.3))
                Text(emptyTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ClipCardView(
                            item: item,
                            isSelected: selectedIDs.contains(item.id),
                            selectionMode: selectionMode,
                            onPick: {
                                if selectionMode {
                                    toggle(item.id)
                                } else {
                                    onPick(item)
                                }
                            },
                            onLongPress: {
                                onEnterSelection?(item.id)
                            },
                            onTogglePin: showsPin ? { onTogglePin?(item) } : nil,
                            onDelete: {
                                deleteAnimated(item)
                            },
                            onShare: onShare.map { handler in { handler(item) } },
                            dragItems: {
                                if selectionMode, selectedIDs.count > 1, selectedIDs.contains(item.id) {
                                    return selectedItems
                                }
                                return [item]
                            }
                        )
                        .transition(.cardDelete)
                        .staggeredAppear(index)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 2)
                .animation(ClipStripAnimation.delete, value: items.map(\.id))
            }
            .frame(height: 124)
            .scrollClipDisabled()
        }
    }

    private func toggle(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
        Haptics.tap()
    }

    private func deleteAnimated(_ item: ClipItem) {
        withAnimation(ClipStripAnimation.delete) {
            selectedIDs.remove(item.id)
            onDelete(item)
        }
        Haptics.tap()
    }
}
