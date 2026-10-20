import Foundation
import Security
import DictidyKit

/// Provider keys use separate accounts; the existing Anthropic account is retained unchanged.
enum KeychainService {
    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            "Couldn't update the API key in Keychain: " + (SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)")
        }
    }

    private static func query(_ provider: RewriteProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.opensource.dictidy",
         kSecAttrAccount as String: provider == .anthropic ? "anthropic-api-key" : "openai-api-key"]
    }

    static func save(_ key: String, provider: RewriteProvider) throws {
        let base = query(provider)
        let value = [kSecValueData as String: Data(key.utf8)]
        var status = SecItemUpdate(base as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            var attrs = base
            attrs[kSecValueData as String] = Data(key.utf8)
            attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(attrs as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    static func load(provider: RewriteProvider) -> String? {
        var request = query(provider)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Check presence without decrypting the key or asking for authorization at launch.
    static func exists(provider: RewriteProvider) -> Bool {
        SecItemCopyMatching(query(provider) as CFDictionary, nil) == errSecSuccess
    }

    static func delete(provider: RewriteProvider) throws {
        let status = SecItemDelete(query(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
