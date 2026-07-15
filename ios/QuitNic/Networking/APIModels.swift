import Foundation

struct RegistrationResponse: Codable { let deviceId: String; let accessToken: String; let tokenType: String }
struct QuitPlanRequest: Codable { let nicotineType: String; let dailyConsumption: Double; let unitCost: Double; let quitDate: Date; let motivation: String; let reminderHour: Int? }
struct CheckInRequest: Codable { let intensity: Int; let trigger: String; let copingAction: String; let note: String?; let resisted: Bool; let occurredAt: Date }
struct CheckInResponse: Codable, Identifiable { let id: String; let intensity: Int; let trigger: String; let copingAction: String; let note: String?; let resisted: Bool; let occurredAt: Date }
struct ConversationTurn: Codable { let role: String; let content: String }
struct CoachingRequest: Codable { let message: String; let recentContext: [ConversationTurn] }
struct CoachingResponse: Codable { let message: String; let isSafetyResponse: Bool }
struct TranscriptionResponse: Codable { let text: String }
struct MilestoneDTO: Codable { let title: String; let targetHours: Int; let achieved: Bool }
struct ProgressResponse: Codable { let nicotineFreeSeconds: Int; let moneySaved: Double; let avoidedUnits: Double; let currentStreakDays: Int; let nextMilestone: MilestoneDTO? }
struct ErrorEnvelope: Codable { struct Detail: Codable { let code: String; let message: String }; let error: Detail }
