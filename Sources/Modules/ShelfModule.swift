import SwiftUI

struct ShelfTab: View {
    @ObservedObject var shelf: ShelfStore
    var dismiss: () -> Void

    var body: some View {
        CardStripView(
            items: shelf.items,
            emptyTitle: "Drag files here to stage them",
            emptySymbol: "tray.and.arrow.down",
            onPick: { _ in dismiss() },
            onTogglePin: { _ in },
            onDelete: { shelf.remove($0.id) }
        )
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
