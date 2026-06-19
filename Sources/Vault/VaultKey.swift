import Foundation
import Security
import LocalAuthentication
import CryptoKit

enum VaultError: Error {
    case keychain(OSStatus)
    case auth
    case encoding
}

/// Manages the single symmetric key used to encrypt locked clips. The key lives
/// in the Keychain behind a biometric/user-presence access control, so reading
/// it triggers Touch ID (or a password fallback). Created lazily on first lock.
enum VaultKey {
    private static let service = "com.steinerco.mybar.vault"
    private static let account = "clip-encryption-key"

    /// Returns the key, creating it on first use. May prompt for Touch ID.
    static func key(reason: String) throws -> SymmetricKey {
        if let existing = try load(reason: reason) { return existing }
        return try create()
    }

    private static func load(reason: String) throws -> SymmetricKey? {
        let context = LAContext()
        context.localizedReason = reason
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        switch status {
        case errSecSuccess:
            guard let data = out as? Data else { throw VaultError.encoding }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        case errSecUserCanceled, errSecAuthFailed:
            throw VaultError.auth
        default:
            throw VaultError.keychain(status)
        }
    }

    private static func create() throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            nil
        ) else { throw VaultError.auth }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: access,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultError.keychain(status) }
        return key
    }
}
