import Foundation

struct LocalProgress {
    let seconds: Int; let moneySaved: Double; let avoidedUnits: Double; let streakDays: Int; let nextMilestone: String?
}

enum ProgressCalculator {
    static func calculate(plan: QuitPlan, lastNicotineUse: Date? = nil, now: Date = .now) -> LocalProgress {
        let startDate = max(plan.quitDate, lastNicotineUse ?? plan.quitDate)
        let seconds = max(0, Int(now.timeIntervalSince(startDate)))
        let days = Double(seconds) / 86_400
        let milestones = [(24, "First day"), (168, "First week"), (720, "First month"), (2160, "Three months")]
        let next = milestones.first { seconds < $0.0 * 3600 }?.1
        return LocalProgress(seconds: seconds, moneySaved: days * plan.dailyConsumption * plan.unitCost, avoidedUnits: days * plan.dailyConsumption, streakDays: Int(days.rounded(.down)), nextMilestone: next)
    }
}
