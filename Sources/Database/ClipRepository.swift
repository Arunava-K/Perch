import Foundation
import GRDB

/// All clip persistence goes through here. Methods are resilient (errors are
/// logged, not thrown) to match the previous JSON store's behavior, so callers
/// stay simple.
final class ClipRepository {
    static let shared = ClipRepository()

    private let dbQueue = AppDatabase.shared.dbQueue

    private init() {
        migrateFromJSONIfNeeded()
    }

    // MARK: Loading

    /// Active (non-trashed) items in a container, front-first.
    func load(_ container: ClipContainer) -> [ClipItem] {
        records(sql: """
            SELECT * FROM clip
            WHERE container = ? AND isTrashed = 0
            ORDER BY position DESC
            """, arguments: [container.rawValue])
    }

    /// Trashed items, most-recently-trashed first.
    func loadTrashed() -> [ClipItem] {
        records(sql: """
            SELECT * FROM clip
            WHERE isTrashed = 1
            ORDER BY trashedAt DESC
            """, arguments: [])
    }

    private func records(sql: String, arguments: StatementArguments) -> [ClipItem] {
        (try? dbQueue.read { db in
            try ClipRecord.fetchAll(db, sql: sql, arguments: arguments)
        })?.compactMap { $0.toItem() } ?? []
    }

    // MARK: Full-text search

    /// Keyword search over active history via the FTS5 index, best matches first.
    /// Thread-safe (GRDB serializes), so callers can run it off the main thread.
    func search(_ query: String, limit: Int = 60) -> [ClipItem] {
        guard let match = Self.ftsQuery(from: query) else { return [] }
        return records(sql: """
            SELECT clip.* FROM clip
            JOIN clip_fts ON clip_fts.rowid = clip.rowid
            WHERE clip_fts MATCH ? AND clip.container = 'history' AND clip.isTrashed = 0
            ORDER BY clip_fts.rank, clip.position DESC
            LIMIT ?
            """, arguments: [match, limit])
    }

    /// Turn raw user text into a safe FTS5 prefix query: alphanumeric tokens,
    /// each prefix-matched and AND-ed (e.g. "git clo" → "git* clo*"). Dropping
    /// punctuation avoids FTS syntax errors from arbitrary input.
    private static func ftsQuery(from text: String) -> String? {
        let tokens = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\($0)*" }.joined(separator: " ")
    }

    // MARK: Writing

    /// Insert a new item (or move an existing one to the front), updating its
    /// mutable fields. Used for both fresh captures and re-copies.
    func upsertFront(_ item: ClipItem, container: ClipContainer) {
        try? dbQueue.write { db in
            let next = try nextPosition(db, container: container)
            var record = ClipRecord(item: item, container: container, position: next)
            // Preserve existing lock/pin/embedding state on a re-copy.
            if let existing = try ClipRecord.fetchOne(db, key: item.id.uuidString) {
                record.isPinned = item.isPinned || existing.isPinned
                record.isLocked = existing.isLocked
                record.embedding = existing.embedding
                record.ocrText = item.ocrText ?? existing.ocrText
            }
            try record.save(db)
        }
    }

    func setPinned(_ pinned: Bool, id: UUID) {
        update(id: id) { $0.isPinned = pinned }
    }

    func setOCR(_ text: String, id: UUID) {
        update(id: id) { record in
            record.ocrText = text
            if let item = record.toItem() {
                var withOCR = item
                withOCR.ocrText = text
                record.searchText = withOCR.searchText
            }
        }
    }

    private func update(id: UUID, _ mutate: @escaping (inout ClipRecord) -> Void) {
        try? dbQueue.write { db in
            guard var record = try ClipRecord.fetchOne(db, key: id.uuidString) else { return }
            mutate(&record)
            try record.update(db)
        }
    }

    // MARK: Deleting

    /// Permanent removal (used for automatic eviction).
    func deletePermanently(_ id: UUID) {
        _ = try? dbQueue.write { db in
            try ClipRecord.deleteOne(db, key: id.uuidString)
        }
    }

    /// Permanently remove every unpinned, non-trashed item in a container.
    func deleteUnpinned(in container: ClipContainer) {
        _ = try? dbQueue.write { db in
            try ClipRecord
                .filter(sql: "container = ? AND isPinned = 0 AND isTrashed = 0", arguments: [container.rawValue])
                .deleteAll(db)
        }
    }

    /// Soft-delete into the trash (recoverable).
    func trash(_ id: UUID, at date: Date = Date()) {
        update(id: id) { record in
            record.isTrashed = true
            record.trashedAt = date.timeIntervalSince1970
        }
    }

    /// Move unpinned, non-trashed items in a container into the trash.
    func trashUnpinned(in container: ClipContainer, at date: Date = Date()) {
        _ = try? dbQueue.write { db in
            try db.execute(sql: """
                UPDATE clip SET isTrashed = 1, trashedAt = ?
                WHERE container = ? AND isPinned = 0 AND isTrashed = 0
                """, arguments: [date.timeIntervalSince1970, container.rawValue])
        }
    }

    func restore(_ id: UUID) {
        try? dbQueue.write { db in
            guard var record = try ClipRecord.fetchOne(db, key: id.uuidString) else { return }
            record.isTrashed = false
            record.trashedAt = nil
            record.position = try nextPosition(db, container: ClipContainer(rawValue: record.container) ?? .history)
            try record.update(db)
        }
    }

    /// Permanently delete everything currently in the trash.
    func emptyTrash() {
        _ = try? dbQueue.write { db in
            try ClipRecord.filter(sql: "isTrashed = 1").deleteAll(db)
        }
    }

    /// Permanently delete trashed items older than the given age.
    func purgeTrash(olderThan days: Int) {
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400).timeIntervalSince1970
        _ = try? dbQueue.write { db in
            try ClipRecord
                .filter(sql: "isTrashed = 1 AND trashedAt IS NOT NULL AND trashedAt < ?", arguments: [cutoff])
                .deleteAll(db)
        }
    }

    // MARK: Vault (encrypted clips)

    /// Seal a clip: store the locked placeholder kind + ciphertext, and clear
    /// its searchText so encrypted content never lands in the FTS index.
    func applyLock(id: UUID, lockedKind: ClipKind, sealed: Data) {
        let kindData = (try? JSONEncoder().encode(lockedKind)) ?? Data()
        try? dbQueue.write { db in
            guard var record = try ClipRecord.fetchOne(db, key: id.uuidString) else { return }
            record.kind = kindData
            record.sealed = sealed
            record.isLocked = true
            record.blobFile = ClipRecord.blobFile(for: lockedKind)
            record.searchText = ""
            try record.update(db)
        }
    }

    /// Remove protection: restore the plaintext kind + searchText, drop ciphertext.
    func removeLock(id: UUID, kind: ClipKind, searchText: String) {
        let kindData = (try? JSONEncoder().encode(kind)) ?? Data()
        try? dbQueue.write { db in
            guard var record = try ClipRecord.fetchOne(db, key: id.uuidString) else { return }
            record.kind = kindData
            record.sealed = nil
            record.isLocked = false
            record.blobFile = ClipRecord.blobFile(for: kind)
            record.searchText = searchText
            try record.update(db)
        }
    }

    func sealedPayload(id: UUID) -> Data? {
        try? dbQueue.read { db in
            try ClipRecord.fetchOne(db, key: id.uuidString)?.sealed
        } ?? nil
    }

    // MARK: Embeddings (semantic search)

    func setEmbedding(_ data: Data?, id: UUID) {
        _ = try? dbQueue.write { db in
            try db.execute(sql: "UPDATE clip SET embedding = ? WHERE id = ?",
                           arguments: [data, id.uuidString])
        }
    }

    /// (id, vector) pairs for active history clips that have an embedding.
    func allEmbeddings() -> [(id: UUID, vector: [Float])] {
        let rows = (try? dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, embedding FROM clip
                WHERE container = 'history' AND isTrashed = 0 AND embedding IS NOT NULL
                """)
        }) ?? []
        return rows.compactMap { row in
            guard let idString: String = row["id"], let uuid = UUID(uuidString: idString),
                  let data: Data = row["embedding"] else { return nil }
            return (uuid, EmbeddingService.vector(from: data))
        }
    }

    // MARK: Blob references

    /// Is this image blob still referenced by any row (any container, incl. trash)?
    func isBlobReferenced(_ file: String) -> Bool {
        let count = (try? dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clip WHERE blobFile = ?", arguments: [file])
        }) ?? 0
        return count > 0
    }

    // MARK: Helpers

    private func nextPosition(_ db: Database, container: ClipContainer) throws -> Double {
        let maxPos = try Double.fetchOne(
            db,
            sql: "SELECT COALESCE(MAX(position), 0) FROM clip WHERE container = ?",
            arguments: [container.rawValue]
        ) ?? 0
        return maxPos + 1
    }

    // MARK: One-time JSON import

    private func migrateFromJSONIfNeeded() {
        let marker = AppPaths.root.appendingPathComponent(".migratedToSQLite")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }

        importJSON(filename: "clips.json", container: .history)
        importJSON(filename: "shelf.json", container: .shelf)

        FileManager.default.createFile(atPath: marker.path, contents: nil)
    }

    private func importJSON(filename: String, container: ClipContainer) {
        let items = ClipPersistence(filename: filename).load()
        guard !items.isEmpty else { return }
        // Preserve original order: index 0 (newest) gets the highest position.
        try? dbQueue.write { db in
            let count = items.count
            for (index, item) in items.enumerated() {
                let position = Double(count - index)
                try ClipRecord(item: item, container: container, position: position).insert(db)
            }
        }
    }
}
