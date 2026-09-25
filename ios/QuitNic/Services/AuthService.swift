import Foundation

/// The single owner of "am I authenticated".
///
/// Before this existed, 401 was handled three incompatible ways: Coach re-registered,
/// the outbox retried forever, and the progress screen silently gave up. Registration
/// itself was duplicated in onboarding and in the coaching view model. Anything that
/// needs a token now goes through here.
actor AuthService {
    static let shared = AuthService()

    private let client: APIClient
    /// Concurrent callers that all need a token share one registration rather than
    /// racing to create several anonymous accounts for the same device.
    private var registration: Task<String, Error>?

    init(client: APIClient = .shared) {
        self.client = client
    }

    /// A token, registering once if this device has never connected.
    func token() async throws -> String {
        if let existing = KeychainStore.readToken() { return existing }
        return try await register()
    }

    /// The token this device already has, or `nil`. Never registers — for callers that
    /// must stay local-only (a plan edit made offline, say).
    ///
    /// The single answer to "is this device connected". An unused `hasToken` property
    /// sat beside this, and the coaching view model read the keychain directly, so the
    /// same question had three spellings.
    nonisolated func existingToken() -> String? { KeychainStore.readToken() }

    /// Discard a token the server rejected and get a fresh one. This is the step the
    /// outbox was missing: without it a dead token meant an unbounded retry loop.
    func recoverFromUnauthorized() async throws -> String {
        KeychainStore.deleteToken()
        registration = nil
        return try await register()
    }

    func signOut() {
        KeychainStore.deleteToken()
        registration = nil
    }

    private func register() async throws -> String {
        if let registration { return try await registration.value }
        let task = Task<String, Error> { [client] in
            let response = try await client.register()
            try KeychainStore.saveToken(response.accessToken)
            return response.accessToken
        }
        registration = task
        defer { registration = nil }
        return try await task.value
    }
}
