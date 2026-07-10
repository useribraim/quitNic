import Foundation
import SwiftData

@Model
final class QuitPlan {
    var nicotineType: String
    var dailyConsumption: Double
    var unitCost: Double
    var quitDate: Date
    var motivation: String
    var reminderHour: Int?
    var updatedAt: Date

    init(nicotineType: String, dailyConsumption: Double, unitCost: Double, quitDate: Date, motivation: String, reminderHour: Int?) {
        self.nicotineType = nicotineType; self.dailyConsumption = dailyConsumption
        self.unitCost = unitCost; self.quitDate = quitDate; self.motivation = motivation
        self.reminderHour = reminderHour; self.updatedAt = .now
    }
}

@Model
final class CravingCheckIn {
    @Attribute(.unique) var id: UUID
    var intensity: Int
    var trigger: String
    var copingAction: String
    var note: String?
    var resisted: Bool
    var occurredAt: Date
    var synced: Bool

    init(id: UUID = UUID(), intensity: Int, trigger: String, copingAction: String, note: String?, resisted: Bool, occurredAt: Date = .now, synced: Bool = false) {
        self.id = id; self.intensity = intensity; self.trigger = trigger; self.copingAction = copingAction
        self.note = note; self.resisted = resisted; self.occurredAt = occurredAt; self.synced = synced
    }
}

@Model
final class ChatMessage {
    @Attribute(.unique) var id: UUID
    var role: String
    var content: String
    var createdAt: Date
    var isSafetyResponse: Bool
    init(role: String, content: String, isSafetyResponse: Bool = false) {
        self.id = UUID(); self.role = role; self.content = content; self.createdAt = .now; self.isSafetyResponse = isSafetyResponse
    }
}

@Model
final class PendingOperation {
    @Attribute(.unique) var id: UUID
    var kind: String
    var payload: Data
    var createdAt: Date
    var attempts: Int
    init(id: UUID = UUID(), kind: String, payload: Data) {
        self.id = id; self.kind = kind; self.payload = payload; self.createdAt = .now; self.attempts = 0
    }
}

@Model
final class CachedPayload {
    @Attribute(.unique) var key: String
    var payload: Data
    var expiresAt: Date
    init(key: String, payload: Data, expiresAt: Date) { self.key = key; self.payload = payload; self.expiresAt = expiresAt }
}

