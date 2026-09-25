import Foundation
@testable import QuitNic

/// The simulator test bundle is unsigned, so every real keychain write fails with
/// `errSecMissingEntitlement` (-34018). That made `setUp` throw and took the entire
/// outbox suite down with it — thirteen tests reported as failures that nobody could
/// read a result from. Swapping the backing store keeps the sync tests honest.
final class InMemoryTokenStore: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    init(token: String? = nil) {
        self.token = token
    }

    func read() -> String? { lock.withLock { token } }
    func save(_ token: String) throws { lock.withLock { self.token = token } }
    func delete() { lock.withLock { token = nil } }
}
