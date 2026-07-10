import Foundation
import SwiftData

@MainActor
enum OutboxService {
    static func enqueue(checkIn: CravingCheckIn, context: ModelContext) throws {
        let request = CheckInRequest(intensity: checkIn.intensity, trigger: checkIn.trigger, copingAction: checkIn.copingAction, note: checkIn.note, resisted: checkIn.resisted, occurredAt: checkIn.occurredAt)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.keyEncodingStrategy = .convertToSnakeCase
        context.insert(PendingOperation(id: checkIn.id, kind: "check-in", payload: try encoder.encode(request)))
        try context.save()
    }

    static func flush(context: ModelContext, client: APIClient = .shared) async {
        guard KeychainStore.readToken() != nil else { return }
        let descriptor = FetchDescriptor<PendingOperation>(sortBy: [SortDescriptor(\.createdAt)])
        guard let operations = try? context.fetch(descriptor) else { return }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; decoder.keyDecodingStrategy = .convertFromSnakeCase
        for operation in operations where operation.kind == "check-in" {
            do {
                let request = try decoder.decode(CheckInRequest.self, from: operation.payload)
                _ = try await client.post(checkIn: request, idempotencyKey: operation.id.uuidString)
                let id = operation.id
                if let checkIn = try context.fetch(FetchDescriptor<CravingCheckIn>(predicate: #Predicate { $0.id == id })).first { checkIn.synced = true }
                context.delete(operation)
                try context.save()
            } catch {
                operation.attempts += 1
                try? context.save()
                break
            }
        }
    }
}

