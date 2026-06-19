import AppKit

/// A curated staging tray: items the user explicitly drags onto the notch.
/// Unlike the clipboard history, the shelf never auto-evicts — items stay until
/// removed. Reuses `ClipItem` so the same cards, drag-out, and previews apply.
@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    private let repo = ClipRepository.shared

    init() {
        items = repo.load(.shelf)
    }

    /// Add a dropped item to the front, de-duplicating by identity.
    func add(_ item: ClipItem) {
        if let idx = items.firstIndex(where: { $0.identityKey == item.identityKey }) {
            // Re-drop: move it to the front instead of duplicating.
            let existing = items.remove(at: idx)
            items.insert(existing, at: 0)
            repo.upsertFront(existing, container: .shelf)
        } else {
            items.insert(item, at: 0)
            repo.upsertFront(item, container: .shelf)
        }
    }

    func remove(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let removed = items.remove(at: idx)
        repo.deletePermanently(id)
        deleteBlobIfOrphaned(removed)
    }

    func clear() {
        let removed = items
        items = []
        for item in removed {
            repo.deletePermanently(item.id)
            deleteBlobIfOrphaned(item)
        }
    }

    /// Delete an image clip's sidecar blob if no row (any container) still
    /// references it. Call only after the row has left the DB.
    private func deleteBlobIfOrphaned(_ item: ClipItem) {
        guard case .image(let file, _, _, _) = item.kind else { return }
        if !repo.isBlobReferenced(file) {
            BlobStore.shared.delete(file: file)
        }
    }
}
