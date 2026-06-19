import Foundation

/// The classified content of a clipboard entry. Large payloads (images) are
/// stored as sidecar blob files, not inline, so the JSON history stays small.
enum ClipKind: Codable, Equatable {
    case text(string: String)
    case link(url: URL)
    case color(hex: String)
    case image(blobFile: String, contentHash: String, pixelWidth: Int, pixelHeight: Int)
    case file(bookmark: Data, path: String, displayName: String)

    /// Stable key used to deduplicate repeated copies of the same content.
    var identityKey: String {
        switch self {
        case .text(let s): return "text:\(s)"
        case .link(let u): return "link:\(u.absoluteString)"
        case .color(let h): return "color:\(h.lowercased())"
        case .image(_, let hash, _, _): return "image:\(hash)"
        case .file(_, let path, _): return "file:\(path)"
        }
    }

    /// Short, human-readable label for debugging / future UI.
    var previewText: String {
        switch self {
        case .text(let s): return s
        case .link(let u): return u.absoluteString
        case .color(let h): return h
        case .image(_, _, let w, let h): return "Image \(w)×\(h)"
        case .file(_, _, let name): return name
        }
    }

    var typeName: String {
        switch self {
        case .text: return "text"
        case .link: return "link"
        case .color: return "color"
        case .image: return "image"
        case .file: return "file"
        }
    }
}
