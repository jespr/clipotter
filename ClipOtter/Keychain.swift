import Foundation
import Security

/// Minimal generic-password Keychain wrapper for storing the Claude API key.
enum Keychain {
    private static let service = "com.jespr.ClipOtter"
    /// Pre-rename service ID. Read once and migrated forward (see `get`).
    private static let legacyService = "com.jespr.Transcript"

    static func set(_ value: String, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)

        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        if let value = read(account, from: service) { return value }
        // Migrate a value stored under the pre-rename service ID, then forget the old copy.
        if let legacy = read(account, from: legacyService) {
            set(legacy, for: account)
            return legacy
        }
        return nil
    }

    private static func read(_ account: String, from service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
