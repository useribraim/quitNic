import Foundation
import SwiftData
import XCTest
@testable import QuitNic

@MainActor
final class OutboxServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var previousToken: String?

    override func setUp() async throws {
        let schema = Schema([QuitPlan.self, CravingCheckIn.self, ChatMessage.self, PendingOperation.self, CachedPayload.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = ModelContext(container)
        previousToken = KeychainStore.readToken()
        try KeychainStore.saveToken("test-token")
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        if let previousToken { try KeychainStore.saveToken(previousToken) } else { KeychainStore.deleteToken() }
        container = nil
        context = nil
    }

    func testEnqueueStoresOperationKeyedByCheckInIdentifier() throws {
        let checkIn = makeCheckIn()
        let operations = try context.fetch(FetchDescriptor<PendingOperation>())
        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations.first?.id, checkIn.id)
        XCTAssertEqual(operations.first?.kind, "check-in")
    }

    func testFlushDeliversCheckInOnceWithItsIdempotencyKey() async throws {
        let checkIn = makeCheckIn()
        let recorder = RequestRecorder()
        MockURLProtocol.handler = { request in
            recorder.record(request)
            return (Self.response(for: request, status: 201), Self.checkInResponseBody(id: checkIn.id))
        }
        await OutboxService.flush(context: context, client: makeClient())
        XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertEqual(recorder.requests.first?.value(forHTTPHeaderField: "Idempotency-Key"), checkIn.id.uuidString)
        XCTAssertTrue(try fetchCheckIn(checkIn.id).synced)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PendingOperation>()).count, 0)
    }

    func testOfflineFlushRetainsOperationAndLocalCheckIn() async throws {
        let checkIn = makeCheckIn()
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await OutboxService.flush(context: context, client: makeClient())
        let operations = try context.fetch(FetchDescriptor<PendingOperation>())
        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations.first?.attempts, 1)
        XCTAssertFalse(try fetchCheckIn(checkIn.id).synced)
    }

    func testRetriedFlushAfterRecoveryDeliversExactlyOnce() async throws {
        let checkIn = makeCheckIn()
        MockURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        await OutboxService.flush(context: context, client: makeClient())
        let recorder = RequestRecorder()
        MockURLProtocol.handler = { request in
            recorder.record(request)
            return (Self.response(for: request, status: 201), Self.checkInResponseBody(id: checkIn.id))
        }
        await OutboxService.flush(context: context, client: makeClient())
        await OutboxService.flush(context: context, client: makeClient())
        XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertEqual(recorder.requests.first?.value(forHTTPHeaderField: "Idempotency-Key"), checkIn.id.uuidString)
        XCTAssertTrue(try fetchCheckIn(checkIn.id).synced)
    }

    func testConcurrentFlushesDoNotDuplicateDelivery() async throws {
        let checkIn = makeCheckIn()
        let recorder = RequestRecorder()
        MockURLProtocol.handler = { request in
            recorder.record(request)
            Thread.sleep(forTimeInterval: 0.05)
            return (Self.response(for: request, status: 201), Self.checkInResponseBody(id: checkIn.id))
        }
        let client = makeClient()
        let first = Task { @MainActor in
            await OutboxService.flush(context: context, client: client)
        }
        let second = Task { @MainActor in
            await OutboxService.flush(context: context, client: client)
        }
        _ = await (first.value, second.value)
        XCTAssertEqual(recorder.requests.count, 1)
    }

    func testPermanentRejectionDropsOperationButKeepsLocalCheckIn() async throws {
        let checkIn = makeCheckIn()
        MockURLProtocol.handler = { request in (Self.response(for: request, status: 422), Data()) }
        await OutboxService.flush(context: context, client: makeClient())
        XCTAssertEqual(try context.fetch(FetchDescriptor<PendingOperation>()).count, 0)
        XCTAssertFalse(try fetchCheckIn(checkIn.id).synced)
    }

    func testServerOutageRetainsOperationForLaterRetry() async throws {
        _ = makeCheckIn()
        MockURLProtocol.handler = { request in (Self.response(for: request, status: 503), Data()) }
        await OutboxService.flush(context: context, client: makeClient())
        let operations = try context.fetch(FetchDescriptor<PendingOperation>())
        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations.first?.attempts, 1)
    }

    func testPoisonedPayloadIsDiscardedWithoutBlockingLaterOperations() async throws {
        context.insert(PendingOperation(id: UUID(), kind: "check-in", payload: Data("not-json".utf8)))
        try context.save()
        let checkIn = makeCheckIn()
        let recorder = RequestRecorder()
        MockURLProtocol.handler = { request in
            recorder.record(request)
            return (Self.response(for: request, status: 201), Self.checkInResponseBody(id: checkIn.id))
        }
        await OutboxService.flush(context: context, client: makeClient())
        XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertEqual(recorder.requests.first?.value(forHTTPHeaderField: "Idempotency-Key"), checkIn.id.uuidString)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PendingOperation>()).count, 0)
    }

    // MARK: - Helpers

    @discardableResult
    private func makeCheckIn() -> CravingCheckIn {
        let checkIn = CravingCheckIn(intensity: 6, trigger: "stress", copingAction: "walked", note: nil, resisted: true)
        context.insert(checkIn)
        try! OutboxService.enqueue(checkIn: checkIn, context: context)
        return checkIn
    }

    private func fetchCheckIn(_ id: UUID) throws -> CravingCheckIn {
        try XCTUnwrap(context.fetch(FetchDescriptor<CravingCheckIn>(predicate: #Predicate { $0.id == id })).first)
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
