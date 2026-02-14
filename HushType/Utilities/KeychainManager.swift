import Foundation
import Security

// MARK: - Keychain Error

/// Errors that can occur during Keychain operations.
enum KeychainError: Error {
    case itemNotFound
    case duplicateItem
    case unexpectedStatus(OSStatus)
    case invalidData
}

// MARK: - Keychain Key Registry

/// Registry of all Keychain item keys used by HushType.
enum KeychainKey {
    /// API key for a remote Ollama instance.
    static let ollamaAPIKey = "com.hushtype.ollamaAPIKey"

    /// License key for future premium features.
    static let licenseKey = "com.hushtype.licenseKey"

    /// Encryption key for exported data files.
    static let exportEncryptionKey = "com.hushtype.exportEncryptionKey"
}

// MARK: - Keychain Manager

/// Manages secure storage of sensitive data in the macOS Keychain.
///
/// All items use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` which means:
/// - Items are only accessible while the Mac is unlocked
/// - Items are not included in unencrypted backups
/// - Items are not transferred to a new device via Migration Assistant
/// - On Apple Silicon, items are protected by the Secure Enclave
struct KeychainManager {
    private static let service = "com.hushtype.app"

    /// Save a string value to the Keychain.
    ///
    /// If an item with the same key already exists, it is overwritten.
    static func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        // Delete existing item first to avoid duplicate errors
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Retrieve a string value from the Keychain.
    ///
    /// - Throws: `KeychainError.itemNotFound` if no item exists for the key.
    static func load(key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }

        return string
    }

    /// Delete a value from the Keychain.
    ///
    /// Does not throw if the item does not exist.
    static func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
