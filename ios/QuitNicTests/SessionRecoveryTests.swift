import Foundation
import SwiftData
import XCTest
@testable import QuitNic

@MainActor
final class SessionRecoveryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var previousBacking: TokenStoring!

    override func setUp() async throws {
        container = try ModelContainer(
            for: Schema([QuitPlan.self, CravingCheckIn.self, PendingOperation.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)
        previousBacking = KeychainStore.backing
        KeychainStore.backing = InMemoryTokenStore()
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        KeychainStore.backing = previousBacking
        container = nil
        context = nil
    }

    // MARK: - Fresh installs

    /// Keychain items outlive app deletion. A reinstall used to silently adopt the old
    /// token, and onboarding's `readToken() == nil` guard then skipped re-registration —
    /// binding the person to an account whose data they no longer had.
    func testReinstallDiscardsTheTokenLeftBehindByThePreviousInstall() throws {
        try KeychainStore.saveToken("token-from-previous-install")
        let freshContainer = UserDefaults(suiteName: "fresh-install-\(UUID().uuidString)")!

        KeychainStore.resetIfFreshInstall(defaults: freshContainer)

        XCTAssertNil(KeychainStore.readToken())
    }

    func testAnOrdinaryLaunchKeepsTheExistingSession() throws {
        let defaults = UserDefaults(suiteName: "existing-install-\(UUID().uuidString)")!
        KeychainStore.resetIfFreshInstall(defaults: defaults)
        try KeychainStore.saveToken("live-token")

        KeychainStore.resetIfFreshInstall(defaults: defaults)

        XCTAssertEqual(KeychainStore.readToken(), "live-token")
    }

    // MARK: - Registration

    func testConcurrentCallersShareOneRegistration() async throws {
        let registrations = Counter()
        MockURLProtocol.handler = { request in
            _ = registrations.next()
            return (Self.response(for: request, status: 201),
                    Data(#"{"device_id":"d1","access_token":"shared","token_type":"bearer"}"#.utf8))
        }
        let auth = AuthService(client: makeClient())

        async let first = try? auth.token()
        async let second = try? auth.token()
        async let third = try? auth.token()
        let tokens = await [first, second, third]

        XCTAssertEqual(tokens.compactMap { $0 }, ["shared", "shared", "shared"])
        // Three screens needing a token must not create three anonymous accounts.
        XCTAssertEqual(registrations.next(), 1)
    }

    func testRecoveryReplacesTheRejectedToken() async throws {
        try KeychainStore.saveToken("stale")
        MockURLProtocol.handler = { request in
            (Self.response(for: request, status: 201),
             Data(#"{"device_id":"d1","access_token":"replacement","token_type":"bearer"}"#.utf8))
        }
        let auth = AuthService(client: makeClient())

        let token = try await auth.recoverFromUnauthorized()

        XCTAssertEqual(token, "replacement")
        XCTAssertEqual(KeychainStore.readToken(), "replacement")
    }

    // MARK: - Plan sync

    func testAPlanEditedWithoutASessionIsQueuedRatherThanLost() async throws {
        let plan = makePlan()

        let reachedServer = await SyncCoordinator.savePlan(
            plan, context: context, client: makeClient(), auth: AuthService(client: makeClient())
        )

        XCTAssertFalse(reachedServer)
        let queued = try context.fetch(FetchDescriptor<PendingOperation>())
        XCTAssertEqual(queued.map(\.kind), ["quit-plan"])
    }

    func testAPlanSaveThatHitsARejectedTokenRecoversAndSucceeds() async throws {
        try KeychainStore.saveToken("stale")
        let plan = makePlan()
        let planPuts = Counter()
        MockURLProtocol.handler = { request in
            if request.url!.path.contains("register") {
                return (Self.response(for: request, status: 201),
                        Data(#"{"device_id":"d1","access_token":"replacement","token_type":"bearer"}"#.utf8))
            }
            let status = planPuts.next() == 0 ? 401 : 200
            return (Self.response(for: request, status: status),
                    Data(#"{"nicotine_type":"vape","daily_consumption":5,"unit_cost":1.5,"quit_date":"2026-07-11T10:00:00Z","motivation":"Sleep","reminder_hour":null,"currency_code":"GBP"}"#.utf8))
        }
        let client = makeClient()

        let reachedServer = await SyncCoordinator.savePlan(
            plan, context: context, client: client, auth: AuthService(client: client)
        )

        XCTAssertTrue(reachedServer)
        XCTAssertEqual(KeychainStore.readToken(), "replacement")
        XCTAssertEqual(try context.fetch(FetchDescriptor<PendingOperation>()).count, 0)
    }

    func testOnboardingLeavesQueuedWorkWhenRegistrationFails() async throws {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let plan = makePlan()
        let client = makeClient()

        await SyncCoordinator.registerAndSyncNewPlan(
            plan, context: context, client: client, auth: AuthService(client: client)
        )

        // The old code swallowed this into a `try?` and the plan never reached the server.
        XCTAssertEqual(try context.fetch(FetchDescriptor<PendingOperation>()).map(\.kind), ["quit-plan"])
    }

    // MARK: - Helpers

    private func makePlan() -> QuitPlan {
        let plan = QuitPlan(nicotineType: "vape", dailyConsumption: 5, unitCost: 1.5, quitDate: .now, motivation: "Sleep", reminderHour: nil, currencyCode: "GBP")
        context.insert(plan)
        try? context.save()
        return plan
    }

    private func makeClient() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return APIClient(baseURL: URL(string: "https://example.test")!, session: URLSession(configuration: configuration))
    }

    private static func response(for request: URLRequest, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }
}

/// Lets a mock handler answer differently on successive calls.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.withLock { defer { value += 1 }; return value } }
}
