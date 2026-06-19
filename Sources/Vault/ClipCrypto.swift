import Foundation
import CryptoKit

/// AES-GCM seal/open for locked clip payloads, using the biometric vault key.
enum ClipCrypto {
    static func seal(_ data: Data, reason: String) throws -> Data {
        let key = try VaultKey.key(reason: reason)
        let box = try AES.GCM.seal(data, using: key)
        guard let combined = box.combined else { throw VaultError.encoding }
        return combined
    }

    static func open(_ data: Data, reason: String) throws -> Data {
        let key = try VaultKey.key(reason: reason)
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key)
    }
}
