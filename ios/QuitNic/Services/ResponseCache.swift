import Foundation
import SwiftData

@MainActor
enum ResponseCache {
    static func put<T: Encodable>(_ value: T, key: String, lifetime: TimeInterval, context: ModelContext) throws {
        let data = try JSONEncoder().encode(value)
        let descriptor = FetchDescriptor<CachedPayload>(predicate: #Predicate { $0.key == key })
        if let cached = try context.fetch(descriptor).first { cached.payload = data; cached.expiresAt = .now.addingTimeInterval(lifetime) }
        else { context.insert(CachedPayload(key: key, payload: data, expiresAt: .now.addingTimeInterval(lifetime))) }
        try context.save()
    }
    static func get<T: Decodable>(_ type: T.Type, key: String, context: ModelContext, now: Date = .now) -> T? {
        let descriptor = FetchDescriptor<CachedPayload>(predicate: #Predicate { $0.key == key })
        guard let cached = try? context.fetch(descriptor).first, cached.expiresAt > now else { return nil }
        return try? JSONDecoder().decode(type, from: cached.payload)
    }
}

