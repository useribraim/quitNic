import Foundation
import SwiftData
import XCTest
@testable import QuitNic

@MainActor
final class OutboxServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var previousBacking: TokenStoring!

    override func setUp() async throws {
        let schema = Schema([QuitPlan.self, CravingCheckIn.self, ChatMessage.self, PendingOperation.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = ModelContext(container)
        previousBacking = KeychainStore.backing
        KeychainStore.backing = InMemoryTokenStore(token: "test-token")
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        KeychainStore.backing = previousBacking
        container = nil
        context = nil
    }

    func testEnqueueStoresOperationKeyedByCheckInIdentifier() async throws {
        let checkIn = await makeCheckIn()
        let operations = try context.fetch(FetchDescriptor<PendingOperation>())
        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations.first?.id, checkIn.id)
        XCTAssertEqual(operations.first?.kind, "check-in")
    }

    func testCorrectedCheckInReplacesPendingPayloadInsteadOfDuplicatingIt() async throws {
        let checkIn = await makeCheckIn()
        checkIn.intensity = 9
        checkIn.trigger = "corrected trigger"
        try await OutboxService.enqueue(checkIn: checkIn, context: context)

        let operations = try context.fetch(FetchDescriptor<PendingOperation>())
        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations.first?.id, checkIn.id)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let request = try decoder.decode(CheckInRequest.self, from: XCTUnwrap(operations.first).payload)
        XCTAssertEqual(request.intensity, 9)
        XCTAssertEqual(request.trigger, "corrected trigger")
    }

    func testDeletionReplacesPendingCreateAndUsesDeleteEndpoint() async throws {
        let checkIn = await makeCheckIn()
        try OutboxService.enqueueDeletion(checkInID: checkIn.id, context: context)
        let queued = try context.fetch(FetchDescriptor<PendingOperation>())
        XCTAssertEqual(queued.count, 1)
        XCTAssertEqual(queued.first?.kind, "delete-check-in")

        let recorder = RequestRecorder()
        MockURLProtocol.handler = { request in
            recorder.record(request)
            return (Self.response(for: request, status: 200), Data(#"{"deleted":true}"#.utf8))
        }
        await flush()

        XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertEqual(recorder.requests.first?.httpMethod, "DELETE")
        XCTAssertTrue(recorder.requests.first?.url?.path.hasSuffix("/check-ins/\(checkIn.id.uuidString)") == true)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PendingOperation>()).count, 0)
    }

    func testFlushDeliversCheckInOnceWithItsIdempotencyKey() async throws {
        let checkIn = await makeCheckIn()
        let recorder = RequestRecorder()
        MockURLProtocol.handler = { request in
            recorder.record(request)
            return (Self.response(for: request, status: 201), Self.checkInResponseBody(id: checkIn.id))
        }
        await flush()
        XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertEqual(recorder.requests.first?.value(forHTTPHeaderField: "Idempotency-Key"), checkIn.id.uuidString)
        XCTAssertTrue(try fetchCheckIn(checkIn.id).synced)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PendingOperation>()).count, 0)
    }

    func testOfflineFlushRetainsOperationAndLocalCheckIn() async throws {
        let checkIn = await makeCheckIn()
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await flush()
        let operations = try context.fetch(FetchDescriptor<PendingOperation>())
        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations.first?.attempts, 1)
        XCTAssertFalse(try fetchCheckIn(checkIn.id).synced)
    }

    func testRetriedFlushAfterRecoveryDeliversExactlyOnce() async throws {
        let checkIn = await makeCheckIn()
        MockURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        await flush()
        let recorder = RequestRecorder()
        MockURLProtocol.handler = { request in
            recorder.record(request)
            return (Self.response(for: request, status: 201), Self.checkInResponseBody(id: checkIn.id))
        }
        let afterBackoff = Date.now.addingTimeInterval(120)
        await flush(now: afterBackoff)
        await flush(now: afterBackoff)
        XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertEqual(recorder.requests.first?.value(forHTTPHeaderField: "Idempotency-Key"), checkIn.id.uuidString)
        XCTAssertTrue(try fetchCheckIn(checkIn.id).synced)
    }

    func testConcurrentFlushesDoNotDuplicateDelivery() async throws {
        let checkIn = await makeCheckIn()
        let recorder = RequestRecorder()
        MockURLProtocol.handler = { request in
            recorder.record(request)
            Thread.sleep(forTimeInterval: 0.05)
            return (Self.response(for: request, status: 201), Self.checkInResponseBody(id: checkIn.id))
        }
        let client = makeClient()
        let auth = AuthService(client: client)
        let first = Task { @MainActor in
            await OutboxService.flush(context: context, client: client, auth: auth)
        }
        let second = Task { @MainActor in
            await OutboxService.flush(context: context, client: client, auth: auth)
        }
        _ = await (first.value, second.value)
        XCTAssertEqual(recorder.requests.count, 1)
    }

    func testEmptyOutboxDoesNotRegisterOrTouchTheNetwork() async throws {
        KeychainStore.backing = InMemoryTokenStore()
        let recorder = RequestRecorder()
        MockURLProtocol.handler = { request in
            recorder.record(request)
            return (Self.response(for: request, status: 201), Data())
        }
        let client = makeClient()

        await OutboxService.flush(
            context: context,
            client: client,
            auth: AuthService(client: client)
        )

        XCTAssertTrue(recorder.requests.isEmpty)
        XCTAssertNil(KeychainStore.readToken())
    }

    func testFlushProcessesOnlyOneForegroundBudget() async throws {
        let total = OutboxService.maximumOperationsPerFlush + 2
        for _ in 0..<total { _ = await makeCheckIn() }
        let recorder = RequestRecorder()
        MockURLProtocol.handler = { request in
            recorder.record(request)
            let id = UUID(uuidString: request.value(forHTTPHeaderField: "Idempotency-Key")!)!
            return (Self.response(for: request, status: 201), Self.checkInResponseBody(id: id))
        }

        await flush()

        XCTAssertEqual(recorder.requests.count, OutboxService.maximumOperationsPerFlush)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<PendingOperation>()).count,
            total - OutboxService.maximumOperationsPerFlush
        )
    }

    func testPermanentRejectionDropsOperationButKeepsLocalCheckIn() async throws {
        let checkIn = await makeCheckIn()
        MockURLProtocol.handler = { request in (Self.response(for: request, status: 422), Data()) }
        await flush()
        XCTAssertEqual(try context.fetch(FetchDescriptor<PendingOperation>()).count, 0)
        XCTAssertFalse(try fetchCheckIn(checkIn.id).synced)
    }

    func testServerOutageRetainsOperationForLaterRetry() async throws {
        _ = await makeCheckIn()
        MockURLProtocol.handler = { request in (Self.response(for: request, status: 503), Data()) }
        await flush()
        let operations = try context.fetch(FetchDescriptor<PendingOperation>())
        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations.first?.attempts, 1)
    }

    func testPoisonedPayloadIsDiscardedWithoutBlockingLaterOperations() async throws {
        context.insert(PendingOperation(id: UUID(), kind: "check-in", payload: Data("not-json".utf8)))
        try context.save()
        let checkIn = await makeCheckIn()
        let recorder = RequestRecorder()
        MockURLProtocol.handler = { request in
            recorder.record(request)
            return (Self.response(for: request, status: 201), Self.checkInResponseBody(id: checkIn.id))
        }
        await flush()
        XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertEqual(recorder.requests.first?.value(forHTTPHeaderField: "Idempotency-Key"), checkIn.id.uuidString)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PendingOperation>()).count, 0)
    }

    func testPlanEditsCoalesceToOneOfflineOperation() async throws {
        let plan = QuitPlan(nicotineType: "vape", dailyConsumption: 5, unitCost: 1.5, quitDate: .now, motivation: "Sleep", reminderHour: nil)
        context.insert(plan)
        try await OutboxService.enqueue(plan: plan, context: context)
        plan.dailyConsumption = 7
        try await OutboxService.enqueue(plan: plan, context: context)

        let operations = try context.fetch(FetchDescriptor<PendingOperation>())
        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations.first?.kind, "quit-plan")
        let request = try decodePlanRequest(operations.first!)
        XCTAssertEqual(request.dailyConsumption, 7)
    }

    func testEnqueuedPlanIncludesCurrencyCodeForServerSync() async throws {
        let plan = QuitPlan(nicotineType: "pouches", dailyConsumption: 12, unitCost: 0.4, quitDate: .now, motivation: "Health", reminderHour: nil, currencyCode: "GBP")
        context.insert(plan)
        try await OutboxService.enqueue(plan: plan, context: context)
        let operation = try XCTUnwrap(context.fetch(FetchDescriptor<PendingOperation>()).first)
        let request = try decodePlanRequest(operation)
        XCTAssertEqual(request.currencyCode, "GBP")
    }

    func testCancelPendingCheckInRemovesOnlyTheMatchingOperation() async throws {
        let toCancel = await makeCheckIn()
        let toKeep = await makeCheckIn()
        OutboxService.cancelPendingCheckIn(id: toCancel.id, context: context)
        let remaining = try context.fetch(FetchDescriptor<PendingOperation>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, toKeep.id)
    }

    func testCancelPendingCheckInIsANoOpWhenNothingMatches() async throws {
        _ = await makeCheckIn()
        OutboxService.cancelPendingCheckIn(id: UUID(), context: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PendingOperation>()).count, 1)
    }

    func testCancelledCheckInIsNeverFlushedToTheServer() async throws {
        let checkIn = await makeCheckIn()
        OutboxService.cancelPendingCheckIn(id: checkIn.id, context: context)
        let recorder = RequestRecorder()
        MockURLProtocol.handler = { request in
            recorder.record(request)
            return (Self.response(for: request, status: 201), Self.checkInResponseBody(id: checkIn.id))
        }
        await flush()
        XCTAssertEqual(recorder.requests.count, 0)
    }

    // MARK: - Retry budget and backoff

    func testBackoffKeepsAFailedOperationOffTheWireUntilItsNextAttempt() async throws {
        _ = await makeCheckIn()
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await flush()

        let recorder = RequestRecorder()
        MockURLProtocol.handler = { request in
            recorder.record(request)
            return (Self.response(for: request, status: 201), Data("{}".utf8))
        }
        // Same instant as the failure: the operation is still inside its backoff window.
        await flush()
        XCTAssertEqual(recorder.requests.count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PendingOperation>()).first?.attempts, 1)
    }

    func testOperationIsAbandonedOnceItsAttemptBudgetIsSpent() async throws {
        let checkIn = await makeCheckIn()
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }

        // Each pass steps past the previous backoff. Before the budget existed this loop
        // would never terminate — the operation was retried forever on every foreground.
        var now = Date.now
        for _ in 0..<(OutboxService.maximumAttempts + 2) {
            await flush(now: now)
            now = now.addingTimeInterval(OutboxService.maximumRetryDelay + 1)
        }

        XCTAssertEqual(try context.fetch(FetchDescriptor<PendingOperation>()).count, 0)
        // The person's own record is never destroyed by a delivery failure.
        XCTAssertFalse(try fetchCheckIn(checkIn.id).synced)
    }

    // MARK: - Session recovery

    func testRejectedTokenIsReplacedAndTheOperationDelivered() async throws {
        let checkIn = await makeCheckIn()
        let recorder = RequestRecorder()
        let seenCheckIn = Counter()
        MockURLProtocol.handler = { request in
            recorder.record(request)
            if request.url!.path.contains("register") {
                return (Self.response(for: request, status: 201),
                        Data(#"{"device_id":"d1","access_token":"fresh-token","token_type":"bearer"}"#.utf8))
            }
            // The first delivery is rejected; the retry after re-registration succeeds.
            let status = seenCheckIn.next() == 0 ? 401 : 201
            return (Self.response(for: request, status: status), Self.checkInResponseBody(id: checkIn.id))
        }

        await flush()

        XCTAssertEqual(KeychainStore.readToken(), "fresh-token")
        XCTAssertTrue(try fetchCheckIn(checkIn.id).synced)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PendingOperation>()).count, 0)
        XCTAssertTrue(recorder.requests.contains { $0.url!.path.contains("register") })
    }

    func testUnrecoverableSessionDoesNotRetryWithinOneFlush() async throws {
        _ = await makeCheckIn()
        let recorder = RequestRecorder()
        MockURLProtocol.handler = { request in
            recorder.record(request)
            return (Self.response(for: request, status: 401), Data())
        }

        await flush()

        // One delivery, one registration attempt, one more delivery — and then it stops,
        // rather than spinning on a token the server will never accept.
        XCTAssertLessThanOrEqual(recorder.requests.count, 3)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PendingOperation>()).count, 0)
    }

    // MARK: - Picking up work that was never queued

    func testUnsyncedCheckInsAreQueuedWithoutDuplicatingExistingWork() async throws {
        let alreadyQueued = await makeCheckIn()
        // A check-in saved when the enqueue itself failed: local, unsynced, no operation.
        let orphan = CravingCheckIn(intensity: 8, trigger: "party", copingAction: "left", note: nil, resisted: true)
        context.insert(orphan)
        let delivered = CravingCheckIn(intensity: 3, trigger: "coffee", copingAction: "walked", note: nil, resisted: true, synced: true)
        context.insert(delivered)
        try context.save()

        let added = await OutboxService.enqueueUnsyncedCheckIns(context: context)
        XCTAssertEqual(added, 1)

        let ids = Set(try context.fetch(FetchDescriptor<PendingOperation>()).map(\.id))
        XCTAssertEqual(ids, [alreadyQueued.id, orphan.id])
    }

    func testUnsyncedRecoveryQueuesOnlyOneForegroundBudget() async throws {
        let total = OutboxService.maximumOperationsPerFlush + 3
        for index in 0..<total {
            context.insert(CravingCheckIn(
                intensity: 5,
                trigger: "offline-\(index)",
                copingAction: "walked",
                note: nil,
                resisted: true,
                occurredAt: Date(timeIntervalSince1970: TimeInterval(index))
            ))
        }
        try context.save()

        let added = await OutboxService.enqueueUnsyncedCheckIns(context: context)

        XCTAssertEqual(added, OutboxService.maximumOperationsPerFlush)
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<PendingOperation>()),
            OutboxService.maximumOperationsPerFlush
        )
    }

    func testARejectedOperationDoesNotBlockTheOneBehindIt() async throws {
        let rejected = await makeCheckIn()
        let deliverable = await makeCheckIn()
        let recorder = RequestRecorder()
        MockURLProtocol.handler = { request in
            recorder.record(request)
            let key = request.value(forHTTPHeaderField: "Idempotency-Key")
            let status = key == rejected.id.uuidString ? 422 : 201
            return (Self.response(for: request, status: status), Self.checkInResponseBody(id: deliverable.id))
        }

        await flush()

        XCTAssertEqual(recorder.requests.count, 2)
        XCTAssertTrue(try fetchCheckIn(deliverable.id).synced)
        XCTAssertFalse(try fetchCheckIn(rejected.id).synced)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PendingOperation>()).count, 0)
    }

    // MARK: - Decoding helper

    private func decodePlanRequest(_ operation: PendingOperation) throws -> QuitPlanRequest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(QuitPlanRequest.self, from: operation.payload)
    }

    // MARK: - Helpers

    @discardableResult
    private func makeCheckIn() async -> CravingCheckIn {
        let checkIn = CravingCheckIn(intensity: 6, trigger: "stress", copingAction: "walked", note: nil, resisted: true)
        context.insert(checkIn)
        try! await OutboxService.enqueue(checkIn: checkIn, context: context)
        return checkIn
    }

    private func fetchCheckIn(_ id: UUID) throws -> CravingCheckIn {
        try XCTUnwrap(context.fetch(FetchDescriptor<CravingCheckIn>(predicate: #Predicate { $0.id == id })).first)
    }

    private func flush(now: Date = .now) async {
        let client = makeClient()
        await OutboxService.flush(context: context, client: client, auth: AuthService(client: client), now: now)
    }

    private func makeClient() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return APIClient(baseURL: URL(string: "https://example.test")!, session: URLSession(configuration: configuration))
    }

    private static func response(for request: URLRequest, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    private static func checkInResponseBody(id: UUID) -> Data {
        Data("""
        {"id":"\(id.uuidString)","intensity":6,"trigger":"stress","coping_action":"walked","note":null,"resisted":true,"occurred_at":"2026-07-11T10:00:00Z"}
        """.utf8)
    }
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [URLRequest] = []
    var requests: [URLRequest] { lock.withLock { stored } }
    func record(_ request: URLRequest) { lock.withLock { stored.append(request) } }
}
