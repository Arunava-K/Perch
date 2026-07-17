import Foundation
import GRDB

/// All clip persistence goes through here. Methods log failures rather than
/// throwing, keeping clipboard capture available if the database is unavailable.
final class ClipRepository {
    static let shared = ClipRepository()

    private let dbQueue = AppDatabase.shared?.dbQueue

    private init() { migrateFromJSONIfNeeded() }

    private func read<T>(_ operation: (Database) throws -> T) -> T? {
        guard let dbQueue else {
            NSLog("Mybar: database read skipped because the database is unavailable")
            return nil
        }
        do { return try dbQueue.read(operation) }
        catch {
            NSLog("Mybar: database read failed: \(error)")
            return nil
        }
    }

    @discardableResult
    private func write(_ operation: (Database) throws -> Void) -> Bool {
        guard let dbQueue else {
            NSLog("Mybar: database write skipped because the database is unavailable")
            return false
        }
        do {
            try dbQueue.write(operation)
            return true
        } catch {
            NSLog("Mybar: database write failed: \(error)")
            return false
        }
    }

    // MARK: Loading

    func load(_ container: ClipContainer) -> [ClipItem] {
        records(sql: "SELECT * FROM clip WHERE container = ? AND isTrashed = 0 ORDER BY position DESC", arguments: [container.rawValue])
    }

    func loadTrashed() -> [ClipItem] {
        records(sql: "SELECT * FROM clip WHERE isTrashed = 1 ORDER BY trashedAt DESC", arguments: [])
    }

    private func records(sql: String, arguments: StatementArguments) -> [ClipItem] {
        read { try ClipRecord.fetchAll($0, sql: sql, arguments: arguments) }?.compactMap { $0.toItem() } ?? []
    }

    // MARK: Full-text search

    func search(_ query: String, limit: Int = 60) -> [ClipItem] {
        guard let match = Self.ftsQuery(from: query) else { return [] }
        return records(sql: "SELECT clip.* FROM clip JOIN clip_fts ON clip_fts.rowid = clip.rowid WHERE clip_fts MATCH ? AND clip.container = 'history' AND clip.isTrashed = 0 ORDER BY clip_fts.rank, clip.position DESC LIMIT ?", arguments: [match, limit])
    }

    private static func ftsQuery(from text: String) -> String? {
        let tokens = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\($0)*" }.joined(separator: " ")
    }

    // MARK: Writing

    func upsertFront(_ item: ClipItem, container: ClipContainer) {
        write { db in
            let next = try nextPosition(db, container: container)
            var record = ClipRecord(item: item, container: container, position: next)
            if let existing = try ClipRecord.fetchOne(db, key: item.id.uuidString) {
                record.isPinned = item.isPinned || existing.isPinned
                record.isLocked = existing.isLocked
                record.embedding = existing.embedding
                record.ocrText = item.ocrText ?? existing.ocrText
            }
            try record.save(db)
        }
    }

    func setPinned(_ pinned: Bool, id: UUID) { update(id: id) { $0.isPinned = pinned } }

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
        write { db in
            guard var record = try ClipRecord.fetchOne(db, key: id.uuidString) else { return }
            mutate(&record)
            try record.update(db)
        }
    }

    // MARK: Deleting

    func deletePermanently(_ id: UUID) { write { try ClipRecord.deleteOne($0, key: id.uuidString) } }

    func deleteUnpinned(in container: ClipContainer) {
        write { try ClipRecord.filter(sql: "container = ? AND isPinned = 0 AND isTrashed = 0", arguments: [container.rawValue]).deleteAll($0) }
    }

    func trash(_ id: UUID, at date: Date = Date()) {
        update(id: id) { $0.isTrashed = true; $0.trashedAt = date.timeIntervalSince1970 }
    }

    func trashUnpinned(in container: ClipContainer, at date: Date = Date()) {
        write { try $0.execute(sql: "UPDATE clip SET isTrashed = 1, trashedAt = ? WHERE container = ? AND isPinned = 0 AND isTrashed = 0", arguments: [date.timeIntervalSince1970, container.rawValue]) }
    }

    func restore(_ id: UUID) {
        write { db in
            guard var record = try ClipRecord.fetchOne(db, key: id.uuidString) else { return }
            record.isTrashed = false
            record.trashedAt = nil
            record.position = try nextPosition(db, container: ClipContainer(rawValue: record.container) ?? .history)
            try record.update(db)
        }
    }

    func emptyTrash() { write { try ClipRecord.filter(sql: "isTrashed = 1").deleteAll($0) } }

    func purgeTrash(olderThan days: Int) {
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400).timeIntervalSince1970
        write { try ClipRecord.filter(sql: "isTrashed = 1 AND trashedAt IS NOT NULL AND trashedAt < ?", arguments: [cutoff]).deleteAll($0) }
    }

    // MARK: Vault

    func applyLock(id: UUID, lockedKind: ClipKind, sealed: Data) -> Bool {
        guard let kindData = try? JSONEncoder().encode(lockedKind) else {
            NSLog("Mybar: could not encode locked clip")
            return false
        }
        return write { db in
            guard var record = try ClipRecord.fetchOne(db, key: id.uuidString) else { return }
            record.kind = kindData
            record.sealed = sealed
            record.isLocked = true
            record.embedding = nil
            record.blobFile = ClipRecord.blobFile(for: lockedKind)
            record.searchText = ""
            try record.update(db)
        }
    }

    func removeLock(id: UUID, kind: ClipKind, searchText: String) -> Bool {
        guard let kindData = try? JSONEncoder().encode(kind) else {
            NSLog("Mybar: could not encode unlocked clip")
            return false
        }
        return write { db in
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
        read { try ClipRecord.fetchOne($0, key: id.uuidString)?.sealed } ?? nil
    }

    // MARK: Embeddings

    func setEmbedding(_ data: Data?, id: UUID) -> Bool {
        write { db in
            // The clip could have been locked while its embedding was computed.
            guard var record = try ClipRecord.fetchOne(db, key: id.uuidString), !record.isLocked else { return }
            record.embedding = data
            try record.update(db)
        }
    }

    func allEmbeddings() -> [(id: UUID, vector: [Float])] {
        let rows = read { try Row.fetchAll($0, sql: "SELECT id, embedding FROM clip WHERE container = 'history' AND isTrashed = 0 AND embedding IS NOT NULL") } ?? []
        return rows.compactMap { row in
            guard let idString: String = row["id"], let uuid = UUID(uuidString: idString), let data: Data = row["embedding"] else { return nil }
            return (uuid, EmbeddingService.vector(from: data))
        }
    }

    // MARK: Blob references

    func isBlobReferenced(_ file: String) -> Bool {
        guard let result = read({ db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clip WHERE blobFile = ?", arguments: [file])
        }) else {
            // Never delete a blob when its reference check cannot be trusted.
            return true
        }
        return (result ?? 0) > 0
    }

    private func nextPosition(_ db: Database, container: ClipContainer) throws -> Double {
        (try Double.fetchOne(db, sql: "SELECT COALESCE(MAX(position), 0) FROM clip WHERE container = ?", arguments: [container.rawValue]) ?? 0) + 1
    }

    // MARK: One-time JSON import

    private func migrateFromJSONIfNeeded() {
        let marker = AppPaths.root.appendingPathComponent(".migratedToSQLite")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        do {
            let history = try legacyItems(filename: "clips.json")
            let shelf = try legacyItems(filename: "shelf.json")
            if !history.isEmpty || !shelf.isEmpty {
                guard let dbQueue else { throw CocoaError(.fileNoSuchFile) }
                try dbQueue.write { db in
                    try insertLegacy(history, into: .history, db: db)
                    try insertLegacy(shelf, into: .shelf, db: db)
                }
            }
            guard FileManager.default.createFile(atPath: marker.path, contents: nil) else {
                NSLog("Mybar: could not write legacy migration marker")
                return
            }
        } catch {
            NSLog("Mybar: legacy JSON migration failed and will be retried: \(error)")
        }
    }

    private func legacyItems(filename: String) throws -> [ClipItem] {
        let url = AppPaths.root.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try ClipPersistence(filename: filename).loadForMigration()
    }

    private func insertLegacy(_ items: [ClipItem], into container: ClipContainer, db: Database) throws {
        let count = items.count
        for (index, item) in items.enumerated() {
            try ClipRecord(item: item, container: container, position: Double(count - index)).insert(db)
        }
    }
}
