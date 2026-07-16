import Foundation
import SwiftData

@MainActor
enum OutboxService {
    private static var isFlushing = false

    static func enqueue(checkIn: CravingCheckIn, context: ModelContext) throws {
        let request = CheckInRequest(intensity: checkIn.intensity, trigger: checkIn.trigger, copingAction: checkIn.copingAction, note: checkIn.note, resisted: checkIn.resisted, usedNicotine: checkIn.usedNicotine, occurredAt: checkIn.occurredAt)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.keyEncodingStrategy = .convertToSnakeCase
        context.insert(PendingOperation(id: checkIn.id, kind: "check-in", payload: try encoder.encode(request)))
        try context.save()
    }

    static func enqueue(plan: QuitPlan, context: ModelContext) throws {
        let request = QuitPlanRequest(
            nicotineType: plan.nicotineType,
            dailyConsumption: plan.dailyConsumption,
            unitCost: plan.unitCost,
            quitDate: plan.quitDate,
            motivation: plan.motivation,
            reminderHour: plan.reminderHour
        )
        let existing = try context.fetch(FetchDescriptor<PendingOperation>()).filter { $0.kind == "quit-plan" }
        existing.forEach(context.delete)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.keyEncodingStrategy = .convertToSnakeCase
        context.insert(PendingOperation(kind: "quit-plan", payload: try encoder.encode(request)))
        try context.save()
    }

    static func flush(context: ModelContext, client: APIClient = .shared) async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }
        guard KeychainStore.readToken() != nil else { return }
        let descriptor = FetchDescriptor<PendingOperation>(sortBy: [SortDescriptor(\.createdAt)])
        guard let operations = try? context.fetch(descriptor) else { return }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; decoder.keyDecodingStrategy = .convertFromSnakeCase
        for operation in operations {
            if operation.kind == "quit-plan" {
                guard let request = try? decoder.decode(QuitPlanRequest.self, from: operation.payload) else {
                    context.delete(operation)
                    try? context.save()
                    continue
                }
                do {
                    try await client.save(plan: request)
                    context.delete(operation)
                    try context.save()
                    continue
                } catch let error as APIError where isRetryable(error) {
                    operation.attempts += 1
                    try? context.save()
                    break
                } catch {
                    // Keep the local plan; the next manual edit can create a fresh sync operation.
                    context.delete(operation)
                    try? context.save()
                    continue
                }
            }

            guard operation.kind == "check-in" else { continue }
            guard let request = try? decoder.decode(CheckInRequest.self, from: operation.payload) else {
                // The payload can never be sent; keep the local check-in but stop retrying.
                context.delete(operation)
                try? context.save()
                continue
            }
            do {
                _ = try await client.post(checkIn: request, idempotencyKey: operation.id.uuidString)
                let id = operation.id
                if let checkIn = try context.fetch(FetchDescriptor<CravingCheckIn>(predicate: #Predicate { $0.id == id })).first { checkIn.synced = true }
                context.delete(operation)
                try context.save()
            } catch let error as APIError where isRetryable(error) {
                operation.attempts += 1
                try? context.save()
                break
            } catch {
                // The server permanently rejected this operation; keep the local check-in.
                context.delete(operation)
                try? context.save()
            }
        }
    }

    private static func isRetryable(_ error: APIError) -> Bool {
        switch error {
        case .transport, .rateLimited, .unauthorized, .invalidResponse, .decoding: true
        case .server(let status): status >= 500
        }
    }
}
