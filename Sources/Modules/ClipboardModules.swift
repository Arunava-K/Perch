import SwiftUI

/// The Clipboard tab: an All / Pinned filter above the live card strip.
struct ClipStripTab: View {
    @ObservedObject var store: ClipStore
    var dismiss: () -> Void

    @State private var pinnedOnly = false
    @Namespace private var seg

    /// The notch is for quick access only — show recent clips plus any pins, and
    /// leave the full history to Quick Search (⌃⌘V) and the Library window. This
    /// keeps the card strip cheap to build/scroll no matter how big the history.
    private static let recentLimit = 20

    private var items: [ClipItem] {
        if pinnedOnly { return store.items.filter { $0.isPinned } }
        let recent = store.items.prefix(Self.recentLimit)
        let olderPinned = store.items.dropFirst(Self.recentLimit).filter { $0.isPinned }
        return Array(recent) + Array(olderPinned)
    }

    var body: some View {
        VStack(spacing: 8) {
            filterBar
                .padding(.horizontal, 28)

            CardStripView(
                items: items,
                emptyTitle: pinnedOnly ? "Pin clips to keep them here" : "No clips yet — copy something",
                emptySymbol: pinnedOnly ? "pin" : "tray",
                onPick: { _ in dismiss() },
                onTogglePin: { store.setPinned(!$0.isPinned, for: $0.id) },
                onDelete: { store.remove($0.id) }
            )
        }
    }

    private var filterBar: some View {
        HStack(spacing: 2) {
            segment("All", selected: !pinnedOnly) { pinnedOnly = false }
            segment("Pinned", selected: pinnedOnly) { pinnedOnly = true }
            Spacer(minLength: 0)
        }
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { action() }
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? .white : .white.opacity(0.45))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background {
                    if selected {
                        Capsule().fill(.white.opacity(0.14))
                            .matchedGeometryEffect(id: "segpill", in: seg)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

@MainActor
final class ClipboardModule: NotchModule {
    let id = "clipboard"
    let title = "Clipboard"
    let icon = "doc.on.clipboard.fill"

    /// A touch taller than the default so the filter row sits above the strip.
    var preferredExpandedHeight: CGFloat { 210 }

    private let store: ClipStore
    init(store: ClipStore) { self.store = store }

    func makeContent(_ context: ModuleContext) -> AnyView {
        AnyView(ClipStripTab(store: store, dismiss: context.dismiss))
    }
}
