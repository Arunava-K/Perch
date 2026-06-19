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

    init(
        id: UUID = UUID(),
        kind: ClipKind,
        timestamp: Date = Date(),
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil,
        isPinned: Bool = false,
        isSensitive: Bool = false,
        ocrText: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.timestamp = timestamp
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
        self.isPinned = isPinned
        self.isSensitive = isSensitive
        self.ocrText = ocrText
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
