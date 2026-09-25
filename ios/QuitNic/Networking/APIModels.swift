import Foundation

struct RegistrationResponse: Codable, Sendable { let deviceId: String; let accessToken: String; let tokenType: String }
struct QuitPlanRequest: Codable, Sendable { let nicotineType: String; let dailyConsumption: Double; let unitCost: Double; let quitDate: Date; let motivation: String; let reminderHour: Int?; let currencyCode: String }
struct CheckInRequest: Codable, Sendable { let intensity: Int; let trigger: String; let copingAction: String; let note: String?; let resisted: Bool; let usedNicotine: Bool?; let occurredAt: Date }

// The wire shape of a local record, stated once. `OutboxService` and `SyncCoordinator`
// each carried a private, byte-identical `request(for: plan)` — two places to update
// whenever the plan gains a field, and one of them silently going stale is a sync bug
// nothing would catch.
extension QuitPlanRequest {
    init(_ plan: QuitPlan) {
        self.init(
            nicotineType: plan.nicotineType,
            dailyConsumption: plan.dailyConsumption,
            unitCost: plan.unitCost,
            quitDate: plan.quitDate,
            motivation: plan.motivation,
            reminderHour: plan.reminderHour,
            currencyCode: plan.currencyCode
        )
    }
}

extension CheckInRequest {
    init(_ checkIn: CravingCheckIn) {
        self.init(
            intensity: checkIn.intensity,
            trigger: checkIn.trigger,
            copingAction: checkIn.copingAction,
            note: checkIn.note,
            resisted: checkIn.resisted,
            usedNicotine: checkIn.usedNicotine,
            occurredAt: checkIn.occurredAt
        )
    }
}
struct CheckInResponse: Codable, Identifiable, Sendable { let id: String; let intensity: Int; let trigger: String; let copingAction: String; let note: String?; let resisted: Bool; let usedNicotine: Bool?; let occurredAt: Date }
struct ConversationTurn: Codable, Sendable { let role: String; let content: String }
struct CoachingRequest: Codable, Sendable { let message: String; let recentContext: [ConversationTurn]; var style: String = "chat" }
struct CoachingResponse: Codable, Sendable { let message: String; let isSafetyResponse: Bool }
struct TranscriptionResponse: Codable, Sendable { let text: String }
struct DeleteResponse: Codable, Sendable { let deleted: Bool }
struct ErrorEnvelope: Codable, Sendable { struct Detail: Codable, Sendable { let code: String; let message: String }; let error: Detail }
