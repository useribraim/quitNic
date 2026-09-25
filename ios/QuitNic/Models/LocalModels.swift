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
    /// Costs are entered and displayed in the person's own currency. A default keeps
    /// SwiftData's lightweight migration working for plans created before this existed.
    var currencyCode: String = QuitPlan.deviceCurrencyCode

    init(nicotineType: String, dailyConsumption: Double, unitCost: Double, quitDate: Date, motivation: String, reminderHour: Int?, currencyCode: String = QuitPlan.deviceCurrencyCode) {
        self.nicotineType = nicotineType; self.dailyConsumption = dailyConsumption
        self.unitCost = unitCost; self.quitDate = quitDate; self.motivation = motivation
        self.reminderHour = reminderHour; self.updatedAt = .now
        self.currencyCode = currencyCode
    }

    static var deviceCurrencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    var nicotineTypeValue: NicotineType {
        get { NicotineType(storedValue: nicotineType) }
        set { nicotineType = newValue.storedValue }
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
    /// Earliest time this may be tried again. `attempts` used to be incremented and then
    /// never read, so a failing operation was retried on every single foreground with no
    /// backoff and no ceiling. Defaulted for SwiftData's lightweight migration.
    var nextAttemptAt: Date = Date.distantPast

    init(id: UUID = UUID(), kind: String, payload: Data) {
        self.id = id; self.kind = kind; self.payload = payload; self.createdAt = .now; self.attempts = 0
        self.nextAttemptAt = .distantPast
    }
}

@Model
final class MilestoneAcknowledgement {
    /// Which `Milestone.hours` this covers. Recording it stops the celebration screen
    /// from reappearing on every launch once someone has seen it. A slip clears all of
    /// these so the new streak can earn its own celebrations.
    @Attribute(.unique) var hours: Int
    var acknowledgedAt: Date
    init(hours: Int, acknowledgedAt: Date = .now) {
        self.hours = hours
        self.acknowledgedAt = acknowledgedAt
    }

    /// Silently mark every checkpoint already behind `streakStart` as seen.
    ///
    /// Call this whenever the streak *origin moves* — an edited quit date, or a slip —
    /// rather than when time actually passes. Crossing a checkpoint because a date was
    /// changed is not an achievement, and celebrating it tells the person something
    /// untrue about their own progress. Only elapsed time should earn a celebration.
    @MainActor
    static func backfill(streakStart: Date, context: ModelContext, now: Date = .now) {
        let elapsedHours = now.timeIntervalSince(streakStart) / 3_600
        let existing = Set((try? context.fetch(FetchDescriptor<MilestoneAcknowledgement>()))?.map(\.hours) ?? [])
        for milestone in ProgressCalculator.milestones
        where Double(milestone.hours) <= elapsedHours && !existing.contains(milestone.hours) {
            context.insert(MilestoneAcknowledgement(hours: milestone.hours))
        }
        try? context.save()
    }

    /// Discard every acknowledgement and re-derive them from a moved streak origin. Used
    /// after an edit that can shift the streak in either direction, where keeping the old
    /// set would either replay a celebration or suppress one that is now unearned.
    @MainActor
    static func reset(streakStart: Date, context: ModelContext, now: Date = .now) {
        if let existing = try? context.fetch(FetchDescriptor<MilestoneAcknowledgement>()) {
            existing.forEach(context.delete)
            try? context.save()
        }
        backfill(streakStart: streakStart, context: context, now: now)
    }
}
