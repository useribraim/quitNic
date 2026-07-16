import Foundation
import Security

enum KeychainStoreError: LocalizedError {
    case unavailable(OSStatus)

    var errorDescription: String? {
        "QuitNic could not securely save your private session. Please restart the app and try again."
    }
}

enum KeychainStore {
    private static let service = "com.example.QuitNic"
    private static let account = "anonymous-access-token"
    static func saveToken(_ token: String) throws {
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(lookup as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw KeychainStoreError.unavailable(updateStatus) }

        let addStatus = SecItemAdd((lookup.merging(attributes) { _, new in new }) as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainStoreError.unavailable(addStatus) }
    }
    static func readToken() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?; guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func deleteToken() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
    }
}
