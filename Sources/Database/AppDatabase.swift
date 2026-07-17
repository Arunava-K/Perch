import Foundation
import GRDB

/// Owns the on-disk SQLite database and its schema migrations.
///
/// Replaces the old JSON history files. The schema is intentionally
/// future-proofed for upcoming Phase 0/2 work: trash columns, a per-clip
/// lock flag, an `embedding` BLOB for on-device semantic search, and an
/// FTS5 virtual table for full-text search.
final class AppDatabase {
    static let shared: AppDatabase? = {
        do {
            return try AppDatabase()
        } catch {
            NSLog("Mybar: database unavailable; clipboard persistence is disabled: \(error)")
            return nil
        }
    }()

    let dbQueue: DatabaseQueue

    init() throws {
        let url = AppPaths.root.appendingPathComponent("mybar.sqlite")
        var config = Configuration()
        config.foreignKeysEnabled = true
        dbQueue = try DatabaseQueue(path: url.path, configuration: config)
        try migrator.migrate(dbQueue)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_clips") { db in
            try db.create(table: "clip") { t in
                t.column("id", .text).primaryKey()
                // "history" or "shelf" — both reuse the same row shape.
                t.column("container", .text).notNull().indexed()
                // JSON-encoded ClipKind payload.
                t.column("kind", .blob).notNull()
                t.column("timestamp", .double).notNull()
                t.column("sourceAppName", .text)
                t.column("sourceAppBundleID", .text)
                t.column("isPinned", .boolean).notNull().defaults(to: false)
                t.column("isSensitive", .boolean).notNull().defaults(to: false)
                t.column("ocrText", .text)
                // Phase 0: encrypted vault.
                t.column("isLocked", .boolean).notNull().defaults(to: false)
                // Phase 0: undo / trash. Explicit deletes are recoverable.
                t.column("isTrashed", .boolean).notNull().defaults(to: false).indexed()
                t.column("trashedAt", .double)
                // Phase 2: on-device semantic search vector.
                t.column("embedding", .blob)
                // Sidecar blob filename for image clips — lets us check orphaned
                // blobs across every container with a simple query.
                t.column("blobFile", .text)
                // Denormalized text for FTS.
                t.column("searchText", .text).notNull().defaults(to: "")
                // Monotonic ordering within a container (front = highest).
                t.column("position", .double).notNull().defaults(to: 0)
            }

            // Full-text search index kept in sync with clip.searchText via triggers.
            try db.create(virtualTable: "clip_fts", using: FTS5()) { t in
                t.synchronize(withTable: "clip")
                t.column("searchText")
            }
        }

        migrator.registerMigration("v2_vault") { db in
            // Encrypted payload for locked clips (AES-GCM combined box).
            try db.alter(table: "clip") { t in
                t.add(column: "sealed", .blob)
            }
        }

        migrator.registerMigration("v3_richtext") { db in
            // Optional RTF representation of a text clip, for formatted paste.
            try db.alter(table: "clip") { t in
                t.add(column: "richRTF", .blob)
            }
        }

        return migrator
    }
}
