import SwiftUI

/// A horizontal strip of clip cards, reused by the Clipboard and Pinned tabs.
struct CardStripView: View {
    let items: [ClipItem]
    var emptyTitle: String = "No clips yet"
    var emptySymbol: String = "tray"
    var onPick: (ClipItem) -> Void
    var onTogglePin: (ClipItem) -> Void = { _ in }
    var onDelete: (ClipItem) -> Void = { _ in }

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
                            onPick: { onPick(item) },
                            onTogglePin: { onTogglePin(item) },
                            onDelete: { onDelete(item) }
                        )
                        .staggeredAppear(index)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 2)
            }
            .frame(height: 124)
            .scrollClipDisabled()
        }
    }
}
