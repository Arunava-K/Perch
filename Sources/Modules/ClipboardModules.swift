import SwiftUI

/// Shared tab view for clip strips; observes the store so it updates live.
struct ClipStripTab: View {
    @ObservedObject var store: ClipStore
    var pinnedOnly: Bool
    var emptyTitle: String
    var emptySymbol: String
    var dismiss: () -> Void

    var body: some View {
        CardStripView(
            items: pinnedOnly ? store.items.filter { $0.isPinned } : store.items,
            emptyTitle: emptyTitle,
            emptySymbol: emptySymbol,
            onPick: { _ in dismiss() },
            onTogglePin: { store.setPinned(!$0.isPinned, for: $0.id) },
            onDelete: { store.remove($0.id) }
        )
    }
}

@MainActor
final class ClipboardModule: NotchModule {
    let id = "clipboard"
    let title = "Clipboard"
    let icon = "doc.on.clipboard.fill"

    private let store: ClipStore
    init(store: ClipStore) { self.store = store }

    func makeContent(_ context: ModuleContext) -> AnyView {
        AnyView(ClipStripTab(store: store, pinnedOnly: false,
                             emptyTitle: "No clips yet — copy something",
                             emptySymbol: "tray", dismiss: context.dismiss))
    }
}

@MainActor
final class PinnedModule: NotchModule {
    let id = "pinned"
    let title = "Pinned"
    let icon = "pin.fill"

    private let store: ClipStore
    init(store: ClipStore) { self.store = store }

    func makeContent(_ context: ModuleContext) -> AnyView {
        AnyView(ClipStripTab(store: store, pinnedOnly: true,
                             emptyTitle: "Pin clips to keep them here",
                             emptySymbol: "pin", dismiss: context.dismiss))
    }
}
