import AppKit
import Defaults

/// In-memory clip history, backed by the SQLite repository. Single source of
/// truth for the UI. The published `items` array holds the active (non-trashed)
/// history, front-first.
@MainActor
final class ClipStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    /// Soft-deleted clips, most-recently-trashed first. Recoverable until
    /// permanently purged.
    @Published private(set) var trashedItems: [ClipItem] = []

    /// Called when a clip is freshly captured (used to drive the notch peek).
    var onCapture: ((ClipItem) -> Void)?

    private let repo = ClipRepository.shared

    /// Batches of ids the user deleted, newest last — drives ⌘Z undo.
    private var undoStack: [[UUID]] = []
    var canUndo: Bool { !undoStack.isEmpty }

    /// In-memory semantic vectors keyed by clip id, for fast similarity search.
    private var embeddingCache: [UUID: [Float]] = [:]

    /// Serial queue for embedding work — NLEmbedding isn't safe to call from many
    /// threads at once, so we compute vectors one at a time, off the main thread.
    private let embeddingQueue = DispatchQueue(label: "com.steinerco.mybar.embedding", qos: .utility)

    init() {
        items = repo.load(.history)
        trashedItems = repo.loadTrashed()
        purgeExpiredTrash()
        loadEmbeddings()
    }

    /// Insert a freshly captured clip, deduplicating by identity (a repeat copy
    /// moves the existing entry to the top and keeps its pin state).
    func add(_ item: ClipItem) {
        var list = items
        let front: ClipItem
        if let idx = list.firstIndex(where: { $0.identityKey == item.identityKey }) {
            var existing = list.remove(at: idx)
            existing.timestamp = item.timestamp
            existing.sourceAppName = item.sourceAppName ?? existing.sourceAppName
            existing.sourceAppBundleID = item.sourceAppBundleID ?? existing.sourceAppBundleID
            existing.isSensitive = item.isSensitive
            list.insert(existing, at: 0)
            front = existing
        } else {
            list.insert(item, at: 0)
            front = item
        }
        let removed = enforceLimits(&list)
        items = list

        repo.upsertFront(front, container: .history)
        for evicted in removed {
            repo.deletePermanently(evicted.id)
            embeddingCache[evicted.id] = nil
            deleteBlobIfOrphaned(evicted)
        }

        triggerEmbedding(for: front.id)
        triggerOCRIfNeeded()
        if let top = items.first { onCapture?(top) }
    }

    func setOCRText(_ text: String, for id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }), items[idx].ocrText == nil else { return }
        items[idx].ocrText = text
        repo.setOCR(text, id: id)
        // Re-embed now that OCR text contributes to the clip's searchable text.
        triggerEmbedding(for: id)
    }

    /// Kick off OCR for the newest image clip if it hasn't been processed yet.
    private func triggerOCRIfNeeded() {
        guard let top = items.first,
              case .image(let file, _, _, _) = top.kind,
              top.ocrText == nil else { return }
        let id = top.id
        let url = BlobStore.shared.url(for: file)
        Task { [weak self] in
            guard let text = await OCRService.recognizeText(in: url) else { return }
            await MainActor.run { self?.setOCRText(text, for: id) }
        }
    }

    func setPinned(_ pinned: Bool, for id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].isPinned = pinned
        repo.setPinned(pinned, id: id)
    }

    /// Move a clip to the trash (recoverable via undo or "Put Back").
    func remove(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let removed = items.remove(at: idx)
        repo.trash(id)
        trashedItems.insert(removed, at: 0)
        undoStack.append([id])
    }

    /// Move all unpinned clips to the trash.
    func clear() {
        let removed = items.filter { !$0.isPinned }
        guard !removed.isEmpty else { return }
        items = items.filter { $0.isPinned }
        repo.trashUnpinned(in: .history)
        trashedItems = repo.loadTrashed()
        undoStack.append(removed.map(\.id))
    }

    // MARK: Trash

    /// Put a single trashed clip back into the active history.
    func restore(_ id: UUID) {
        repo.restore(id)
        trashedItems.removeAll { $0.id == id }
        items = repo.load(.history)
        dropFromUndo(id)
    }

    /// Undo the most recent delete (single clip or a "clear" batch).
    @discardableResult
    func restoreLast() -> Bool {
        guard let batch = undoStack.popLast() else { return false }
        for id in batch { repo.restore(id) }
        items = repo.load(.history)
        trashedItems = repo.loadTrashed()
        return true
    }

    /// Permanently delete a single trashed clip.
    func deleteTrashedPermanently(_ id: UUID) {
        guard let idx = trashedItems.firstIndex(where: { $0.id == id }) else { return }
        let item = trashedItems.remove(at: idx)
        repo.deletePermanently(id)
        embeddingCache[id] = nil
        dropFromUndo(id)
        deleteBlobIfOrphaned(item)
    }

    /// Permanently delete everything in the trash.
    func emptyTrash() {
        let removed = trashedItems
        trashedItems = []
        repo.emptyTrash()
        undoStack.removeAll()
        for item in removed {
            embeddingCache[item.id] = nil
            deleteBlobIfOrphaned(item)
        }
    }

    private func purgeExpiredTrash() {
        repo.purgeTrash(olderThan: Defaults[.trashRetentionDays])
        trashedItems = repo.loadTrashed()
        cleanupOrphanedBlobs()
    }

    /// Drop any image blob no longer referenced by a row in any container.
    private func cleanupOrphanedBlobs() {
        for file in BlobStore.shared.allFiles() where !repo.isBlobReferenced(file) {
            BlobStore.shared.delete(file: file)
        }
    }

    private func dropFromUndo(_ id: UUID) {
        undoStack = undoStack.compactMap { batch in
            let remaining = batch.filter { $0 != id }
            return remaining.isEmpty ? nil : remaining
        }
    }

    // MARK: Semantic embeddings

    /// Load persisted vectors into the cache, then backfill any active clips
    /// that don't have one yet (e.g. captured before this feature shipped).
    private func loadEmbeddings() {
        for (id, vector) in repo.allEmbeddings() { embeddingCache[id] = vector }
        let missing = items.filter { embeddingCache[$0.id] == nil && !$0.isLocked }
        for item in missing { triggerEmbedding(for: item.id) }
    }

    /// Compute and store a clip's vector off the main thread (idempotent-ish:
    /// recomputes if called again, e.g. after OCR adds text).
    private func triggerEmbedding(for id: UUID) {
        guard let item = items.first(where: { $0.id == id }), !item.isLocked else { return }
        let text = item.searchText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        embeddingQueue.async { [weak self] in
            guard let vector = EmbeddingService.shared.embed(text) else { return }
            Task { @MainActor in self?.storeEmbedding(vector, for: id) }
        }
    }

    private func storeEmbedding(_ vector: [Float], for id: UUID) {
        // Clip may have been locked while the embedding was computing.
        guard let item = items.first(where: { $0.id == id }), !item.isLocked else { return }
        guard repo.setEmbedding(EmbeddingService.data(from: vector), id: id) else { return }
        embeddingCache[id] = vector
    }

    private func dropEmbedding(for id: UUID) {
        embeddingCache[id] = nil
        _ = repo.setEmbedding(nil, id: id)
    }

    func embedding(for id: UUID) -> [Float]? { embeddingCache[id] }

    /// Whether on-device semantic search is usable on this machine.
    var semanticSearchAvailable: Bool { EmbeddingService.shared.isAvailable }

    /// FTS-backed keyword search over the full history, run off the main thread
    /// so typing stays smooth no matter how big the history. Empty query returns
    /// the most recent clips. Shared by Quick Search (and, later, the Library).
    func search(_ query: String, limit: Int = 60) async -> [ClipItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Array(items.prefix(limit)) }
        return await Task.detached(priority: .userInitiated) {
            ClipRepository.shared.search(trimmed, limit: limit)
        }.value
    }

    /// Hybrid ranking: semantic similarity (cosine of normalized vectors) blended
    /// with a keyword-substring boost. Empty query returns the full history.
    /// Falls back to keyword-only when embeddings aren't available.
    func semanticResults(for query: String) -> [ClipItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }

        let queryVector = EmbeddingService.shared.embed(trimmed)
        let lowerQuery = trimmed.lowercased()
        var scored: [(item: ClipItem, score: Float)] = []

        for item in items {
            let keywordHit = item.searchText.lowercased().contains(lowerQuery)
            var score: Float = keywordHit ? 0.6 : 0
            if let queryVector, let vector = embeddingCache[item.id] {
                score += max(0, EmbeddingService.similarity(queryVector, vector))
            }
            // Keep keyword hits and semantically close clips; drop the long tail.
            if keywordHit || score > 0.18 {
                scored.append((item, score))
            }
        }

        return scored.sorted { $0.score > $1.score }.map(\.item)
    }

    // MARK: Vault

    /// Ids revealed (decrypted) for the current session only.
    private var revealedIDs: Set<UUID> = []

    func isRevealed(_ id: UUID) -> Bool { revealedIDs.contains(id) }

    /// Can this clip be locked? Images are excluded for now (their blob lives
    /// unencrypted on disk); already-locked clips obviously can't re-lock.
    func canLock(_ item: ClipItem) -> Bool {
        if item.isLocked { return false }
        switch item.kind {
        case .image, .locked: return false
        default: return true
        }
    }

    /// Encrypt a clip at rest (prompts Touch ID to access the vault key).
    func lock(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }), canLock(items[idx]) else { return }
        let realKind = items[idx].kind
        do {
            let json = try JSONEncoder().encode(realKind)
            let sealed = try ClipCrypto.seal(json, reason: "Lock this clip in Mybar")
            let lockedKind = ClipKind.locked(type: realKind.typeName)
            guard repo.applyLock(id: id, lockedKind: lockedKind, sealed: sealed) else { return }
            items[idx].kind = lockedKind
            items[idx].isLocked = true
            revealedIDs.remove(id)
            // Locked content must not be semantically searchable.
            dropEmbedding(for: id)
        } catch {
            NSLog("Mybar: lock failed — \(error)")
        }
    }

    /// Decrypt a locked clip for this session (prompts Touch ID). Persistence
    /// stays sealed; the clip re-locks on next launch.
    @discardableResult
    func reveal(_ id: UUID) -> Bool {
        guard let idx = items.firstIndex(where: { $0.id == id }), items[idx].isLocked,
              let sealed = repo.sealedPayload(id: id) else { return false }
        do {
            let data = try ClipCrypto.open(sealed, reason: "Unlock this clip")
            items[idx].kind = try JSONDecoder().decode(ClipKind.self, from: data)
            revealedIDs.insert(id)
            return true
        } catch {
            NSLog("Mybar: reveal failed — \(error)")
            return false
        }
    }

    /// Permanently remove protection, decrypting first if needed.
    func removeLock(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }), items[idx].isLocked else { return }
        if !revealedIDs.contains(id), !reveal(id) { return }
        let realKind = items[idx].kind  // now decrypted in memory
        let searchText = items[idx].searchText
        guard repo.removeLock(id: id, kind: realKind, searchText: searchText) else { return }
        items[idx].isLocked = false
        revealedIDs.remove(id)
        triggerEmbedding(for: id)
    }

    // MARK: Eviction

    /// Enforce the configured count and age caps, returning the evicted items.
    /// Pinned items are never evicted. Automatic eviction is permanent (only
    /// explicit user deletes are recoverable via the trash).
    private func enforceLimits(_ list: inout [ClipItem]) -> [ClipItem] {
        let limit = max(1, Defaults[.historyLimit])
        let maxAgeDays = Defaults[.historyMaxAgeDays]
        let cutoff = Calendar.current.date(byAdding: .day, value: -maxAgeDays, to: Date())

        var kept: [ClipItem] = []
        var removed: [ClipItem] = []
        var unpinnedKept = 0

        for item in list {  // newest-first
            if item.isPinned {
                kept.append(item)
                continue
            }
            if let cutoff, item.timestamp < cutoff {
                removed.append(item)
                continue
            }
            if unpinnedKept < limit {
                kept.append(item)
                unpinnedKept += 1
            } else {
                removed.append(item)
            }
        }

        list = kept
        return removed
    }

    /// Delete an image clip's sidecar blob if no row (any container, incl. the
    /// trash) still references it. Call only after the row has left the DB.
    private func deleteBlobIfOrphaned(_ item: ClipItem) {
        guard case .image(let file, _, _, _) = item.kind else { return }
        if !repo.isBlobReferenced(file) {
            BlobStore.shared.delete(file: file)
        }
    }
}
