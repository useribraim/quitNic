import Foundation
import Security

enum KeychainStoreError: LocalizedError {
    case unavailable(OSStatus)

    var errorDescription: String? {
        "QuitNic could not securely save your private session. Please restart the app and try again."
    }
}

/// Where the anonymous access token lives.
///
/// Behind a protocol so the sync tests can run at all: the simulator test bundle is
/// unsigned, so every real keychain write there fails with `errSecMissingEntitlement`
/// (-34018). That silently killed the whole outbox suite — precisely the code most worth
/// testing.
protocol TokenStoring: AnyObject, Sendable {
    func read() -> String?
    func save(_ token: String) throws
    func delete()
}

final class KeychainTokenStore: TokenStoring {
    private let service: String
    private let account = "anonymous-access-token"
    /// The first build shipped a placeholder service identifier. Read-through migration
    /// keeps anyone who already registered under it signed in.
    private static let legacyService = "com.example.QuitNic"

    init(service: String = Bundle.main.bundleIdentifier ?? "com.ibraimabduramanov.QuitNic") {
        self.service = service
    }

    func read() -> String? {
        if let token = readToken(service: service) { return token }
        // Migrate once, then stop paying for the second lookup.
        guard let legacy = readToken(service: Self.legacyService) else { return nil }
        try? save(legacy)
        SecItemDelete(baseQuery(service: Self.legacyService) as CFDictionary)
        return legacy
    }

    func save(_ token: String) throws {
        let lookup = baseQuery(service: service)
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

    func delete() {
        SecItemDelete(baseQuery(service: service) as CFDictionary)
        SecItemDelete(baseQuery(service: Self.legacyService) as CFDictionary)
    }

    private func baseQuery(service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func readToken(service: String) -> String? {
        var query = baseQuery(service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// The app-wide token facade. Callers keep using `KeychainStore.readToken()`; tests swap
/// `backing` for an in-memory store.
enum KeychainStore {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _backing: TokenStoring = KeychainTokenStore()

    static var backing: TokenStoring {
        get { lock.withLock { _backing } }
        set { lock.withLock { _backing = newValue } }
    }

    static func readToken() -> String? { backing.read() }
    static func saveToken(_ token: String) throws { try backing.save(token) }
    static func deleteToken() { backing.delete() }

    /// Keychain items outlive app deletion on iOS. Without this, a reinstall silently
    /// adopts the token of a server-side account it has no local data for — and
    /// onboarding's `readToken() == nil` guard then skips re-registration, so the person
    /// stays bound to an account they cannot see. A UserDefaults marker dies with the app
    /// container, so its absence is exactly "this install is new".
    static func resetIfFreshInstall(defaults: UserDefaults = .standard) {
        let marker = "quitNicKeychainSeeded"
        guard !defaults.bool(forKey: marker) else { return }
        deleteToken()
        defaults.set(true, forKey: marker)
    }
}
