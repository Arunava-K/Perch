import Foundation
import NaturalLanguage

/// Turns clip text into on-device semantic vectors using Apple's sentence
/// embedding model (no network, no model download). Vectors are L2-normalized,
/// so cosine similarity reduces to a dot product.
final class EmbeddingService {
    static let shared = EmbeddingService()

    private let model = NLEmbedding.sentenceEmbedding(for: .english)

    /// Whether semantic embeddings are available on this system/language.
    var isAvailable: Bool { model != nil }

    /// Embed a string into a normalized vector, or nil if it can't be embedded
    /// (no model, empty text, or out-of-vocabulary).
    func embed(_ text: String) -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let model, !trimmed.isEmpty,
              let raw = model.vector(for: trimmed) else { return nil }
        return EmbeddingService.normalize(raw.map { Float($0) })
    }

    /// Cosine similarity of two normalized vectors (dot product). Returns 0 for
    /// mismatched dimensions.
    static func similarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var dot: Float = 0
        for i in a.indices { dot += a[i] * b[i] }
        return dot
    }

    private static func normalize(_ v: [Float]) -> [Float] {
        let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return v }
        return v.map { $0 / norm }
    }

    // MARK: BLOB (de)serialization

    /// Pack a vector into raw little-endian Float32 bytes for the DB column.
    static func data(from vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Unpack a vector previously stored via `data(from:)`.
    static func vector(from data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float>.size
        guard count > 0 else { return [] }
        return data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self).prefix(count))
        }
    }
}
