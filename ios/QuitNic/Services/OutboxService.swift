import Foundation
import SwiftData

@MainActor
enum OutboxService {
    private static var isFlushing = false

    /// After this many transient failures an operation is abandoned. Without a ceiling a
    /// permanently-failing operation retried forever and blocked everything behind it.
    static let maximumAttempts = 8
    /// Foreground recovery should be bounded even after a long offline stretch.
    static let maximumOperationsPerFlush = 25
    private static let baseRetryDelay: TimeInterval = 30
    static let maximumRetryDelay: TimeInterval = 6 * 3_600

    /// Snapshot model values on the main actor, encode on a utility executor, then return
    /// to SwiftData only for the mutation and save.
    ///
    /// A synchronous `enqueue(checkIn:)` twin used to sit beside this, encoding on the
    /// main actor. Nothing shipping called it — only tests did, which meant the suite was
    /// exercising a second implementation of a path production never took.
    static func enqueue(checkIn: CravingCheckIn, context: ModelContext) async throws {
        let payload = try await OutboxPayloadCoder.encode(CheckInRequest(checkIn))
        try upsert(id: checkIn.id, payload: payload, context: context)
        try context.save()
    }

    private static func upsert(id checkInID: UUID, payload: Data, context: ModelContext) throws {
        if let existing = try context.fetch(FetchDescriptor<PendingOperation>(predicate: #Predicate { $0.id == checkInID })).first {
            existing.kind = "check-in"
            existing.payload = payload
            existing.attempts = 0
            existing.nextAttemptAt = .distantPast
        } else {
            context.insert(PendingOperation(id: checkInID, kind: "check-in", payload: payload))
        }
    }

    static func enqueueDeletion(checkInID: UUID, context: ModelContext) throws {
        removePendingCheckIn(id: checkInID, context: context)
        context.insert(PendingOperation(id: checkInID, kind: "delete-check-in", payload: Data()))
        try context.save()
    }

    /// Remove a queued check-in that has not yet been sent, so an undone slip does not
    /// still reach the server. If it already synced there is nothing pending to cancel;
    /// the local records are deleted by the caller either way.
    static func cancelPendingCheckIn(id: UUID, context: ModelContext) {
        removePendingCheckIn(id: id, context: context)
        try? context.save()
    }

    private static func removePendingCheckIn(id: UUID, context: ModelContext) {
        let pending = (try? context.fetch(FetchDescriptor<PendingOperation>(
            predicate: #Predicate { $0.id == id && $0.kind == "check-in" }
        ))) ?? []
        pending.forEach(context.delete)
    }

    /// A plan has one server-side state, so a queued edit replaces any earlier one rather
    /// than stacking up behind it.
    static func enqueue(plan: QuitPlan, context: ModelContext) async throws {
        let payload = try await OutboxPayloadCoder.encode(QuitPlanRequest(plan))
        let existing = try context.fetch(FetchDescriptor<PendingOperation>(
            predicate: #Predicate { $0.kind == "quit-plan" }
        ))
        existing.forEach(context.delete)
        context.insert(PendingOperation(kind: "quit-plan", payload: payload))
        try context.save()
    }

    /// Queue every check-in the server has not acknowledged.
    ///
    /// Recovery used to live in the coaching view model, which re-POSTed the person's
    /// entire history serially on the main actor — and only ran if they happened to open
    /// Coach and hit an error. Routing it through the outbox makes it bounded, resumable
    /// and idempotent (each operation carries the check-in's own id as its key).
    @discardableResult
    static func enqueueUnsyncedCheckIns(context: ModelContext) async -> Int {
        var unsyncedDescriptor = FetchDescriptor<CravingCheckIn>(
            predicate: #Predicate { $0.synced == false },
            sortBy: [SortDescriptor(\.occurredAt)]
        )
        // A long offline history must not be materialized on the foreground path.
        // Recover one delivery budget at a time; the next foreground picks up the rest.
        unsyncedDescriptor.fetchLimit = maximumOperationsPerFlush
        let unsynced = (try? context.fetch(unsyncedDescriptor)) ?? []
        guard !unsynced.isEmpty else { return 0 }
        var candidates: [(UUID, CheckInRequest)] = []
        candidates.reserveCapacity(unsynced.count)
        for checkIn in unsynced {
            let id = checkIn.id
            var existingDescriptor = FetchDescriptor<PendingOperation>(
                predicate: #Predicate { $0.id == id && $0.kind == "check-in" }
            )
            existingDescriptor.fetchLimit = 1
            guard (try? context.fetch(existingDescriptor).isEmpty) == true else { continue }
            candidates.append((id, CheckInRequest(checkIn)))
        }
        let encoded = await OutboxPayloadCoder.encodeCheckIns(candidates)
        for item in encoded {
            context.insert(PendingOperation(id: item.id, kind: "check-in", payload: item.payload))
        }
        let added = encoded.count
        if added > 0 { try? context.save() }
        return added
    }

    static func flush(
        context: ModelContext,
        client: APIClient = .shared,
        auth: AuthService = .shared,
        now: Date = .now
    ) async {
        // Deterministic airplane mode for the persisted end-to-end UI test. Queued
        // operations remain untouched, exactly as they would during a real outage.
        guard !ProcessInfo.processInfo.arguments.contains("-ui-testing-offline") else { return }
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        var descriptor = FetchDescriptor<PendingOperation>(sortBy: [SortDescriptor(\.createdAt)])
        descriptor.fetchLimit = maximumOperationsPerFlush
        guard let fetched = try? context.fetch(descriptor) else { return }
        let operations = fetched.filter { $0.nextAttemptAt <= now }
        guard !operations.isEmpty else { return }

        // Register only when there is actual work. An empty outbox should not touch the
        // keychain or network on every foreground.
        guard (try? await auth.token()) != nil else { return }
        var didRecoverSession = false
        var hasChanges = false

        operationLoop: for operation in operations {
            var outcome = await attempt(operation, context: context, client: client)

            // A rejected token is worth exactly one re-registration per flush. Retrying
            // the same request afterwards is safe: both endpoints are idempotent.
            if case .failed(.unauthorized) = outcome, !didRecoverSession {
                didRecoverSession = true
                if (try? await auth.recoverFromUnauthorized()) != nil {
                    outcome = await attempt(operation, context: context, client: client)
                }
            }

            switch outcome {
            case .delivered, .undeliverable:
                context.delete(operation)
                hasChanges = true
            case .failed(let error) where error.isTransient:
                defer_(operation, context: context, now: now)
                hasChanges = true
                // Offline fails identically for everything behind it; stop rather than
                // burning the whole queue's attempt budget on one outage.
                if case .transport = error { break operationLoop }
            case .failed:
                // Not retryable and not recovered. Keep the local record, drop the job.
                context.delete(operation)
                hasChanges = true
            }
        }
        if hasChanges { try? context.save() }
    }

    private enum Outcome {
        case delivered
        /// The payload itself can never be sent — corrupt, or an unknown kind.
        case undeliverable
        case failed(APIError)
    }

    private static func attempt(_ operation: PendingOperation, context: ModelContext, client: APIClient) async -> Outcome {
        do {
            switch operation.kind {
            case "quit-plan":
                guard let request = try? await OutboxPayloadCoder.decode(QuitPlanRequest.self, from: operation.payload) else { return .undeliverable }
                try await client.save(plan: request)
                return .delivered
            case "check-in":
                guard let request = try? await OutboxPayloadCoder.decode(CheckInRequest.self, from: operation.payload) else { return .undeliverable }
                _ = try await client.post(checkIn: request, idempotencyKey: operation.id.uuidString)
                let id = operation.id
                if let checkIn = try? context.fetch(FetchDescriptor<CravingCheckIn>(predicate: #Predicate { $0.id == id })).first {
                    checkIn.synced = true
                }
                return .delivered
            case "delete-check-in":
                try await client.deleteCheckIn(id: operation.id)
                return .delivered
            default:
                return .undeliverable
            }
        } catch let error as APIError {
            return .failed(error)
        } catch {
            return .failed(.transport(error.localizedDescription))
        }
    }

    /// Record the failure and push the next try out exponentially, or give up once the
    /// budget is spent. Named with a trailing underscore because `defer` is a keyword.
    private static func defer_(_ operation: PendingOperation, context: ModelContext, now: Date) {
        operation.attempts += 1
        if operation.attempts >= maximumAttempts {
            context.delete(operation)
        } else {
            let backoff = min(maximumRetryDelay, baseRetryDelay * pow(2, Double(operation.attempts - 1)))
            operation.nextAttemptAt = now.addingTimeInterval(backoff)
        }
    }

}

/// Off-main JSON for queued payloads. The encoder and decoder are built once: three
/// separate copies of the same four-line factory used to be constructed inside every
/// detached task, one per operation.
enum OutboxPayloadCoder {
    struct EncodedCheckIn: Sendable {
        let id: UUID
        let payload: Data
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    static func encodeCheckIns(_ values: [(UUID, CheckInRequest)]) async -> [EncodedCheckIn] {
        await Task.detached(priority: .utility) {
            values.compactMap { id, value in
                guard let payload = try? encoder.encode(value) else { return nil }
                return EncodedCheckIn(id: id, payload: payload)
            }
        }.value
    }

    static func encode<T: Encodable & Sendable>(_ value: T) async throws -> Data {
        try await Task.detached(priority: .utility) { try encoder.encode(value) }.value
    }

    static func decode<T: Decodable & Sendable>(_ type: T.Type, from data: Data) async throws -> T {
        try await Task.detached(priority: .utility) { try decoder.decode(type, from: data) }.value
    }
}
