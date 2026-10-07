import Foundation
import CryptoKit
import Synchronization

/// Handles encryption and decryption of the event queue
enum QueueEncryption {

    /// Cached key so the Keychain is hit at most once per process lifetime,
    /// not on every queue save/load (getOrCreateKey runs on every enqueue/flush).
    private static let cachedKey = Mutex<SymmetricKey?>(nil)

    /// Generate a key for queue encryption (stored in Keychain)
    static func generateKey() -> SymmetricKey {
        return SymmetricKey(size: .bits256)
    }

    /// Get or create the encryption key
    static func getOrCreateKey() -> SymmetricKey? {
        cachedKey.withLock { cache -> SymmetricKey? in
            if let existing = cache {
                return existing
            }

            // Try to retrieve existing key from Keychain
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.luxardolabs.LuxAnalytics",
                kSecAttrAccount as String: "EncryptionKey",
                kSecReturnData as String: true
            ]

            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)

            if status == errSecSuccess, let keyData = result as? Data {
                let key = SymmetricKey(data: keyData)
                cache = key
                return key
            }

            // Generate new key
            let newKey = generateKey()
            let keyData = newKey.withUnsafeBytes { Data($0) }

            // Store in Keychain
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.luxardolabs.LuxAnalytics",
                kSecAttrAccount as String: "EncryptionKey",
                kSecValueData as String: keyData,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus == errSecSuccess {
                cache = newKey
                return newKey
            }

            // If we can't store the key, encryption is not available
            return nil
        }
    }
    
    /// Encrypt data
    static func encrypt(_ data: Data) -> Data? {
        guard let key = getOrCreateKey() else { return nil }
        
        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            return sealedBox.combined
        } catch {
            SecureLogger.log("Encryption failed: \(error)", category: .error, level: .error)
            return nil
        }
    }
    
    /// Decrypt data
    static func decrypt(_ data: Data) -> Data? {
        guard let key = getOrCreateKey() else { return nil }
        
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            SecureLogger.log("Decryption failed: \(error)", category: .error, level: .error)
            return nil
        }
    }
    
    /// Delete the encryption key (for testing or reset)
    static func deleteKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.luxardolabs.LuxAnalytics",
            kSecAttrAccount as String: "EncryptionKey"
        ]

        SecItemDelete(query as CFDictionary)
        // Clear the in-memory cache so a subsequent getOrCreateKey() regenerates
        // rather than returning the just-deleted key.
        cachedKey.withLock { $0 = nil }
    }
}