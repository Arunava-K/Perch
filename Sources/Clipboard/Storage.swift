import AppKit
import CryptoKit

/// Resolves Mybar's Application Support directory, creating it on first use.
enum AppPaths {
    static let root: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Mybar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}

/// Stores large binary payloads (images) as content-addressed sidecar files so
/// identical content is de-duplicated on disk automatically.
final class BlobStore {
    static let shared = BlobStore()

    let directory: URL

    init() {
        directory = AppPaths.root.appendingPathComponent("blobs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Returns the sidecar filename and the content hash (used for dedup keys).
    func savePNG(_ data: Data) -> (file: String, hash: String) {
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let file = "\(hash).png"
        let url = directory.appendingPathComponent(file)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url, options: .atomic)
        }
        return (file, hash)
    }

    func url(for file: String) -> URL { directory.appendingPathComponent(file) }

    func delete(file: String) {
        try? FileManager.default.removeItem(at: url(for: file))
    }
}

/// Reads/writes the clip history as JSON, decoding item-by-item so a single
/// corrupt entry can't wipe the whole history.
final class ClipPersistence {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(filename: String = "clips.json") {
        fileURL = AppPaths.root.appendingPathComponent(filename)
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> [ClipItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        if let items = try? decoder.decode([ClipItem].self, from: data) { return items }

        // Fallback: salvage whatever decodes, skip corrupt entries.
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        var valid: [ClipItem] = []
        for element in array {
            if let itemData = try? JSONSerialization.data(withJSONObject: element),
               let item = try? decoder.decode(ClipItem.self, from: itemData) {
                valid.append(item)
            }
        }
        return valid
    }

    func save(_ items: [ClipItem]) {
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
