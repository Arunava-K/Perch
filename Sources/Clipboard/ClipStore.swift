import AppKit
import Defaults

/// In-memory clip history, backed by JSON persistence. Single source of truth
/// for the UI (added in later phases).
@MainActor
final class ClipStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    /// Called when a clip is freshly captured (used to drive the notch peek).
    var onCapture: ((ClipItem) -> Void)?

    private let persistence = ClipPersistence()

    init() {
        items = persistence.load()
    }

    /// Insert a freshly captured clip, deduplicating by identity (a repeat copy
    /// moves the existing entry to the top and keeps its pin state).
    func add(_ item: ClipItem) {
        var list = items
        if let idx = list.firstIndex(where: { $0.identityKey == item.identityKey }) {
            var existing = list.remove(at: idx)
            existing.timestamp = item.timestamp
            existing.sourceAppName = item.sourceAppName ?? existing.sourceAppName
            existing.sourceAppBundleID = item.sourceAppBundleID ?? existing.sourceAppBundleID
            existing.isSensitive = item.isSensitive
            list.insert(existing, at: 0)
        } else {
            list.insert(item, at: 0)
        }
        enforceLimits(&list)
        items = list
        persistence.save(items)
        triggerOCRIfNeeded()
        if let top = items.first { onCapture?(top) }
    }

    func setOCRText(_ text: String, for id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }), items[idx].ocrText == nil else { return }
        items[idx].ocrText = text
        persistence.save(items)
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
        persistence.save(items)
    }

    func remove(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let removed = items.remove(at: idx)
        deleteBlobIfOrphaned(removed, in: items)
        persistence.save(items)
    }

    func clear() {
        let old = items
        items = items.filter { $0.isPinned }
        for item in old where !item.isPinned {
            deleteBlobIfOrphaned(item, in: items)
        }
        persistence.save(items)
    }

    // MARK: Eviction

    /// Enforce the configured count and age caps. Pinned items are never evicted.
    private func enforceLimits(_ list: inout [ClipItem]) {
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
        for item in removed {
            deleteBlobIfOrphaned(item, in: list)
        }
    }

    private func deleteBlobIfOrphaned(_ item: ClipItem, in list: [ClipItem]) {
        guard case .image(let file, _, _, _) = item.kind else { return }
        let stillReferenced = list.contains { other in
            if case .image(let otherFile, _, _, _) = other.kind { return otherFile == file }
            return false
        }
        if !stillReferenced {
            BlobStore.shared.delete(file: file)
        }
    }
}
