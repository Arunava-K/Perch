import AppKit

/// A curated staging tray: items the user explicitly drags onto the notch.
/// Unlike the clipboard history, the shelf never auto-evicts — items stay until
/// removed. Reuses `ClipItem` so the same cards, drag-out, and previews apply.
@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    private let persistence = ClipPersistence(filename: "shelf.json")

    init() {
        items = persistence.load()
    }

    /// Add a dropped item to the front, de-duplicating by identity.
    func add(_ item: ClipItem) {
        if let idx = items.firstIndex(where: { $0.identityKey == item.identityKey }) {
            // Re-drop: move it to the front instead of duplicating.
            let existing = items.remove(at: idx)
            items.insert(existing, at: 0)
        } else {
            items.insert(item, at: 0)
        }
        persistence.save(items)
    }

    func remove(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let removed = items.remove(at: idx)
        deleteBlobIfOrphaned(removed)
        persistence.save(items)
    }

    func clear() {
        let old = items
        items = []
        old.forEach(deleteBlobIfOrphaned)
        persistence.save(items)
    }

    private func deleteBlobIfOrphaned(_ item: ClipItem) {
        guard case .image(let file, _, _, _) = item.kind else { return }
        let stillReferenced = items.contains { other in
            if case .image(let otherFile, _, _, _) = other.kind { return otherFile == file }
            return false
        }
        if !stillReferenced { BlobStore.shared.delete(file: file) }
    }
}
