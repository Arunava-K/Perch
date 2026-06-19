import Foundation

/// A single clipboard history entry.
struct ClipItem: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: ClipKind
    var timestamp: Date
    var sourceAppName: String?
    var sourceAppBundleID: String?
    var isPinned: Bool
    var isSensitive: Bool
    /// Text recognized from image clips (OCR), for search.
    var ocrText: String?
    /// Whether this clip is encrypted at rest (vault). Persisted via the DB
    /// column, not this struct's Codable form, so it's excluded from CodingKeys.
    var isLocked: Bool = false
    /// RTF representation of a text clip when the source provided one, enabling
    /// formatted paste (and "paste as plain" to strip it). DB-backed.
    var richRTF: Data? = nil

    /// Excludes DB-only fields (`isLocked`, `richRTF`) which have defaults, which
    /// also keeps legacy `clips.json` (without them) decodable during migration.
    private enum CodingKeys: String, CodingKey {
        case id, kind, timestamp, sourceAppName, sourceAppBundleID, isPinned, isSensitive, ocrText
    }

    init(
        id: UUID = UUID(),
        kind: ClipKind,
        timestamp: Date = Date(),
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil,
        isPinned: Bool = false,
        isSensitive: Bool = false,
        ocrText: String? = nil,
        isLocked: Bool = false,
        richRTF: Data? = nil
    ) {
        self.id = id
        self.kind = kind
        self.timestamp = timestamp
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
        self.isPinned = isPinned
        self.isSensitive = isSensitive
        self.ocrText = ocrText
        self.isLocked = isLocked
        self.richRTF = richRTF
    }

    var identityKey: String { kind.identityKey }

    /// Text used for searching (clip content + any OCR text).
    var searchText: String {
        var parts = [kind.previewText]
        if let ocrText { parts.append(ocrText) }
        if let app = sourceAppName { parts.append(app) }
        return parts.joined(separator: " ")
    }
}
