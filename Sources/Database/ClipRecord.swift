import Foundation
import GRDB

/// GRDB row backing a `ClipItem`. Carries storage-only fields (container,
/// trash, lock, ordering, embedding) that the UI-facing `ClipItem` doesn't
/// need to know about.
struct ClipRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "clip"

    var id: String
    var container: String
    var kind: Data
    var timestamp: Double
    var sourceAppName: String?
    var sourceAppBundleID: String?
    var isPinned: Bool
    var isSensitive: Bool
    var ocrText: String?
    var isLocked: Bool
    var isTrashed: Bool
    var trashedAt: Double?
    var embedding: Data?
    var blobFile: String?
    var searchText: String
    var position: Double
    /// AES-GCM ciphertext of the original kind JSON, when `isLocked`.
    var sealed: Data?
    /// RTF representation of a text clip, for formatted paste.
    var richRTF: Data?
}

extension ClipRecord {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    /// Build a record from a domain item for a given container/position.
    init(item: ClipItem, container: ClipContainer, position: Double) {
        self.id = item.id.uuidString
        self.container = container.rawValue
        self.kind = (try? ClipRecord.encoder.encode(item.kind)) ?? Data()
        self.timestamp = item.timestamp.timeIntervalSince1970
        self.sourceAppName = item.sourceAppName
        self.sourceAppBundleID = item.sourceAppBundleID
        self.isPinned = item.isPinned
        self.isSensitive = item.isSensitive
        self.ocrText = item.ocrText
        self.isLocked = false
        self.isTrashed = false
        self.trashedAt = nil
        self.embedding = nil
        self.blobFile = ClipRecord.blobFile(for: item.kind)
        self.searchText = item.searchText
        self.position = position
        self.sealed = nil
        self.richRTF = item.richRTF
    }

    /// Reconstruct the domain item; returns nil if the payload can't decode.
    func toItem() -> ClipItem? {
        guard let kindValue = try? ClipRecord.decoder.decode(ClipKind.self, from: kind) else { return nil }
        return ClipItem(
            id: UUID(uuidString: id) ?? UUID(),
            kind: kindValue,
            timestamp: Date(timeIntervalSince1970: timestamp),
            sourceAppName: sourceAppName,
            sourceAppBundleID: sourceAppBundleID,
            isPinned: isPinned,
            isSensitive: isSensitive,
            ocrText: ocrText,
            isLocked: isLocked,
            richRTF: richRTF
        )
    }

    static func blobFile(for kind: ClipKind) -> String? {
        if case .image(let file, _, _, _) = kind { return file }
        return nil
    }
}

/// Logical buckets sharing the `clip` table.
enum ClipContainer: String {
    case history
    case shelf
}
