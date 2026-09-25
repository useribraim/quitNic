import Foundation
import SwiftData

struct Milestone: Identifiable, Equatable {
    let hours: Int
    let title: String
    /// Short line for the in-progress card on Today.
    let detail: String
    /// Longer copy for the full-screen celebration moment, independent of `detail`.
    let celebration: String
    /// Forward-looking copy: what the stretch *leading up to* this checkpoint tends to
    /// feel like. Deliberately hedged ("usually", "often") — these are general patterns,
    /// not predictions about a specific person.
    let whatToExpect: String
    var id: Int { hours }

    func replacing(celebration: String? = nil, whatToExpect: String? = nil) -> Milestone {
        Milestone(
            hours: hours,
            title: title,
            detail: detail,
            celebration: celebration ?? self.celebration,
            whatToExpect: whatToExpect ?? self.whatToExpect
        )
    }
}

struct LocalProgress {
    /// Time since the most recent nicotine use — this is what resets after a slip.
    let seconds: Int
    /// Conservative totals for the current nicotine-free streak. Without asking how much
    /// was used during a slip, claiming uninterrupted lifetime savings would be false.
    let moneySaved: Double
    let avoidedUnits: Double
    let streakDays: Int
    let nextMilestone: Milestone?
}

enum ProgressCalculator {
    // Checkpoints follow the general shape of nicotine-withdrawal research: nicotine's own
    // direct effect clears within about a day, cravings often peak in the 48-72 hour range,
    // and physical symptoms mostly settle over two to four weeks while habit- and cue-based
    // cravings persist longer.
    //
    // Deliberately dense early and stopping at two months. The first week is where somebody
    // actually needs to see the next marker within reach — a roadmap whose second stop is
    // days away is useless on day one. Past two months the streak is no longer the thing
    // being worked at, so further checkpoints would just be an ever-receding horizon.
    static let milestones = [
        Milestone(
            hours: 2, title: "2 Hours",
            detail: "The first gap",
            celebration: "Two hours nicotine-free. You have already practised interrupting your usual pattern.",
            whatToExpect: "An urge may show up around a time or situation when you usually used nicotine. Its timing and intensity are individual."
        ),
        Milestone(
            hours: 8, title: "8 Hours",
            detail: "Through the first wave",
            celebration: "You have cleared a full stretch of your usual routine without nicotine — several trigger moments already behind you.",
            whatToExpect: "Cravings can arrive in waves rather than on a fixed schedule. Try the coping response that helped with the previous one."
        ),
        Milestone(
            hours: 48, title: "2 Days",
            detail: "Into the steepest part",
            celebration: "Two days in. You are staying with the change even while your body and routines adjust.",
            whatToExpect: "Irritability, poor sleep and low concentration can be noticeable around now. Withdrawal is different for everyone and usually eases with time."
        ),
        Milestone(
            hours: 72, title: "3 Days",
            detail: "Through the early peak",
            celebration: "Three days nicotine-free. You have made it through many of the earliest cues without returning to the old routine.",
            whatToExpect: "Withdrawal is often strongest during the first week, especially the first three days, but timing and intensity vary from person to person."
        ),
        Milestone(
            hours: 120, title: "5 Days",
            detail: "Settling into the first week",
            celebration: "Five days of choosing a different response. That is real practice, not just elapsed time.",
            whatToExpect: "Cravings may begin to feel shorter or less frequent, though it is also normal for them to remain uneven for a while."
        ),
        Milestone(
            hours: 168, title: "1 Week",
            detail: "Seven days of new routines",
            celebration: "A full week nicotine-free. You now have a week of evidence about which situations are hardest and what helps you through them.",
            whatToExpect: "Withdrawal symptoms are often strongest in the first week. They commonly ease over the following weeks, but everyone’s timing differs."
        ),
        Milestone(
            hours: 336, title: "2 Weeks",
            detail: "Two weeks of momentum",
            celebration: "Two weeks nicotine-free. The repeated choice not to use is becoming a routine of its own.",
            whatToExpect: "Mood, sleep and concentration may be settling. Cue-based cravings can still appear even when the background pull is quieter."
        ),
        Milestone(
            hours: 672, title: "4 Weeks",
            detail: "One month of momentum",
            celebration: "One month nicotine-free. Many withdrawal symptoms ease over the first few weeks, while habits and reminders can take longer to loosen.",
            whatToExpect: "Cravings may now be more connected to a place, mood or routine. Keep using the patterns you have recorded instead of expecting every cue to disappear."
        ),
        Milestone(
            hours: 1_440, title: "2 Months",
            detail: "Two months clear",
            celebration: "Two months nicotine-free. You have repeatedly practised responding to routines and cues without using.",
            whatToExpect: "Cravings may be occasional from here, but an unexpected cue can still feel strong. That does not erase the routine you have built."
        )
    ]

    /// Returns copy that matches the product being quit. The timeline is shared because
    /// nicotine withdrawal and habit cues can occur across products; smoking-recovery
    /// claims are added only for cigarette plans, never inferred for vapes or pouches.
    ///
    /// Every screen calls this on each body evaluation, so the four possible answers are
    /// built once and handed back rather than re-derived. Rebuilding all ten structs per
    /// call cost 0.539 µs; returning the stored array costs 0.075 µs.
    static func milestones(for nicotineType: NicotineType) -> [Milestone] {
        switch nicotineType {
        case .cigarettes: cigaretteMilestones
        case .vape: vapeMilestones
        case .pouches: pouchMilestones
        case .other: milestones
        }
    }

    private static let cigaretteMilestones = derivedMilestones(for: .cigarettes)
    private static let vapeMilestones = derivedMilestones(for: .vape)
    private static let pouchMilestones = derivedMilestones(for: .pouches)

    private static func derivedMilestones(for nicotineType: NicotineType) -> [Milestone] {
        milestones.map { milestone in
            switch (nicotineType, milestone.hours) {
            case (.cigarettes, 8):
                milestone.replacing(
                    celebration: "Eight hours smoke-free. Carbon monoxide in the blood may already be falling and oxygen levels recovering.",
                    whatToExpect: milestone.whatToExpect
                )
            case (.cigarettes, 48):
                milestone.replacing(
                    celebration: "After two smoke-free days, carbon monoxide is expected to have cleared from the body, and taste and smell may start improving."
                )
            case (.cigarettes, 72):
                milestone.replacing(
                    celebration: "Three days smoke-free. Some people notice easier breathing as the bronchial tubes begin to relax.",
                    whatToExpect: milestone.whatToExpect
                )
            case (.cigarettes, 336):
                milestone.replacing(
                    whatToExpect: "Over roughly 2 to 12 smoke-free weeks, circulation can improve. Cravings and day-to-day experience still vary."
                )
            case (.cigarettes, 1_440):
                milestone.replacing(
                    whatToExpect: "Across the first months after quitting smoking, coughing and shortness of breath often decrease. Improvement is gradual and individual."
                )
            case (.vape, 2):
                milestone.replacing(celebration: "Two hours without vaping. You have interrupted the reach-and-inhale routine at least once already.")
            case (.vape, 48):
                milestone.replacing(celebration: "Two full days vape-free. Your brain and daily cues are learning a different pattern.")
            case (.vape, 1_440):
                milestone.replacing(celebration: "Two months vape-free. The change is no longer new; it is a routine you have lived in.")
            case (.pouches, 2):
                milestone.replacing(celebration: "Two hours without a nicotine pouch. You have interrupted the reach-and-place routine at least once already.")
            case (.pouches, 48):
                milestone.replacing(celebration: "Two full days pouch-free. Your brain and daily cues are learning a different pattern.")
            case (.pouches, 1_440):
                milestone.replacing(celebration: "Two months pouch-free. The change is no longer new; it is a routine you have lived in.")
            default:
                milestone
            }
        }
    }

    /// One row of the journey roadmap: a checkpoint plus where it sits relative to now.
    struct JourneyStop: Identifiable, Equatable {
        enum State: Equatable {
            case reached(at: Date)
            /// The checkpoint being worked toward right now.
            case next(in: TimeInterval)
            case upcoming(in: TimeInterval)
        }

        let milestone: Milestone
        let state: State
        var id: Int { milestone.hours }

        var isReached: Bool { if case .reached = state { return true }; return false }
        var isNext: Bool { if case .next = state { return true }; return false }
    }

    /// The full roadmap for a streak: every checkpoint, marked reached / next / upcoming,
    /// with the real dates and countdowns so the view stays presentational.
    static func journey(streakStart: Date, nicotineType: NicotineType = .other, now: Date = .now) -> [JourneyStop] {
        let elapsed = max(0, now.timeIntervalSince(streakStart))
        var seenNext = false
        return milestones(for: nicotineType).map { milestone in
            let target = TimeInterval(milestone.hours) * 3_600
            if elapsed >= target {
                return JourneyStop(milestone: milestone, state: .reached(at: streakStart.addingTimeInterval(target)))
            }
            let remaining = target - elapsed
            defer { seenNext = true }
            return JourneyStop(milestone: milestone, state: seenNext ? .upcoming(in: remaining) : .next(in: remaining))
        }
    }

    /// How far between the last reached checkpoint and the next one somebody is, 0...1.
    /// Drives the connecting rail so the "you are here" marker sits proportionally.
    static func progressToNextStop(streakStart: Date, now: Date = .now) -> Double {
        let elapsedHours = max(0, now.timeIntervalSince(streakStart)) / 3_600
        guard let next = milestones.first(where: { Double($0.hours) > elapsedHours }) else { return 1 }
        let previous = milestones.last { Double($0.hours) <= elapsedHours }?.hours ?? 0
        let span = max(1, next.hours - previous)
        return min(1, max(0, (elapsedHours - Double(previous)) / Double(span)))
    }

    /// Where the current streak counts from: the quit date, unless a recorded slip is
    /// later and has moved it.
    static func streakStart(quitDate: Date, lastSlip: Date?) -> Date {
        max(quitDate, lastSlip ?? quitDate)
    }

    /// The same, reading the most recent slip from the store. One row, never a scan of
    /// the whole history — five screens used to write this query out by hand.
    @MainActor
    static func streakStart(quitDate: Date, context: ModelContext) -> Date {
        var descriptor = FetchDescriptor<CravingCheckIn>(
            predicate: #Predicate { $0.usedNicotine == true },
            sortBy: [SortDescriptor(\.occurredAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return streakStart(quitDate: quitDate, lastSlip: (try? context.fetch(descriptor))?.first?.occurredAt)
    }

    /// Whether moving a quit date from `original` to `edited` is a backdate — making the
    /// streak and savings look bigger without it having actually happened. A one-minute
    /// tolerance absorbs picker rounding so an unchanged date never reads as backdated.
    static func isBackdate(original: Date, edited: Date) -> Bool {
        edited < original.addingTimeInterval(-60)
    }

    static func calculate(plan: QuitPlan, lastNicotineUse: Date? = nil, now: Date = .now) -> LocalProgress {
        let streakStart = streakStart(quitDate: plan.quitDate, lastSlip: lastNicotineUse)
        let seconds = max(0, Int(now.timeIntervalSince(streakStart)))
        let streakDaysExact = Double(seconds) / 86_400
        let elapsedHours = Double(seconds) / 3_600
        return LocalProgress(
            seconds: seconds,
            moneySaved: streakDaysExact * plan.dailyConsumption * plan.unitCost,
            avoidedUnits: streakDaysExact * plan.dailyConsumption,
            streakDays: Int((Double(seconds) / 86_400).rounded(.down)),
            nextMilestone: milestones(for: plan.nicotineTypeValue).first { elapsedHours < Double($0.hours) }
        )
    }
}
