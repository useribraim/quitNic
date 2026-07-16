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
    var usedNicotine: Bool?
    var occurredAt: Date
    var synced: Bool

    init(id: UUID = UUID(), intensity: Int, trigger: String, copingAction: String, note: String?, resisted: Bool, usedNicotine: Bool? = nil, occurredAt: Date = .now, synced: Bool = false) {
        self.id = id; self.intensity = intensity; self.trigger = trigger; self.copingAction = copingAction
        self.note = note; self.resisted = resisted; self.occurredAt = occurredAt; self.synced = synced
        self.usedNicotine = usedNicotine
    }
}

@Model
final class ActiveCoachingPlan {
    @Attribute(.unique) var id: UUID
    var summary: String
    var createdAt: Date
    var delayEndsAt: Date?
    var completedAt: Date?

    init(id: UUID = UUID(), summary: String, createdAt: Date = .now, delayEndsAt: Date? = nil, completedAt: Date? = nil) {
        self.id = id
        self.summary = summary
        self.createdAt = createdAt
        self.delayEndsAt = delayEndsAt
        self.completedAt = completedAt
    }
}

@Model
final class RescueSession {
    @Attribute(.unique) var id: UUID
    var startingIntensity: Int
    var endingIntensity: Int?
    var trigger: String
    var intervention: String
    var startedAt: Date
    var completedAt: Date?
    var resisted: Bool?
    var durationSeconds: Int
    var synced: Bool

    init(
        id: UUID = UUID(),
        startingIntensity: Int,
        endingIntensity: Int? = nil,
        trigger: String,
        intervention: String,
        startedAt: Date = .now,
        completedAt: Date? = nil,
        resisted: Bool? = nil,
        durationSeconds: Int = 0,
        synced: Bool = false
    ) {
        self.id = id
        self.startingIntensity = startingIntensity
        self.endingIntensity = endingIntensity
        self.trigger = trigger
        self.intervention = intervention
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.resisted = resisted
        self.durationSeconds = durationSeconds
        self.synced = synced
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
