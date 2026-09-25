import Foundation
import XCTest
@testable import QuitNic

final class JourneyTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testEveryMilestoneHasForwardLookingCopy() {
        for type in NicotineType.allCases {
            for milestone in ProgressCalculator.milestones(for: type) {
                XCTAssertFalse(milestone.whatToExpect.isEmpty, "\(type) \(milestone.title) is missing whatToExpect")
                XCTAssertFalse(milestone.celebration.isEmpty, "\(type) \(milestone.title) is missing celebration")
            }
        }
    }

    func testSmokingRecoveryClaimsAppearOnlyForCigarettePlans() {
        let cigaretteCopy = ProgressCalculator.milestones(for: .cigarettes)
            .map { "\($0.celebration) \($0.whatToExpect)" }
            .joined(separator: " ")
            .lowercased()
        XCTAssertTrue(cigaretteCopy.contains("carbon monoxide"))
        XCTAssertTrue(cigaretteCopy.contains("smoke-free"))

        for type in [NicotineType.vape, .pouches, .other] {
            let copy = ProgressCalculator.milestones(for: type)
                .map { "\($0.celebration) \($0.whatToExpect)" }
                .joined(separator: " ")
                .lowercased()
            XCTAssertFalse(copy.contains("carbon monoxide"), "smoking claim leaked into \(type)")
            XCTAssertFalse(copy.contains("smoke-free"), "smoking claim leaked into \(type)")
            XCTAssertFalse(copy.contains("bronchial"), "smoking claim leaked into \(type)")
        }
    }

    func testProductSpecificCopyNamesVapingAndPouches() {
        let vapeDay = ProgressCalculator.milestones(for: .vape).first { $0.hours == 48 }
        let pouchDay = ProgressCalculator.milestones(for: .pouches).first { $0.hours == 48 }
        XCTAssertTrue(vapeDay?.celebration.contains("vape-free") == true)
        XCTAssertTrue(pouchDay?.celebration.contains("pouch-free") == true)
    }

    func testEveryNicotineTypeKeepsTheSameCheckpointSchedule() {
        let expected = ProgressCalculator.milestones.map(\.hours)
        for type in NicotineType.allCases {
            XCTAssertEqual(ProgressCalculator.milestones(for: type).map(\.hours), expected)
        }
    }

    func testJourneyMarksPassedCheckpointsReachedAndTheRestAhead() {
        // Just under 48 hours in: 2h and 8h are behind, 48h is the next one.
        let now = start.addingTimeInterval(47 * 3_600)
        let stops = ProgressCalculator.journey(streakStart: start, now: now)

        XCTAssertEqual(stops.count, ProgressCalculator.milestones.count)
        XCTAssertEqual(stops.filter(\.isReached).map(\.milestone.hours), [2, 8])
        XCTAssertEqual(stops.first(where: \.isNext)?.milestone.hours, 48)
    }

    func testCheckpointsAreDenseEarlyAndStopAtTwoMonths() {
        let hours = ProgressCalculator.milestones.map(\.hours)
        XCTAssertEqual(hours, hours.sorted(), "checkpoints must be in ascending order")
        XCTAssertEqual(Set(hours).count, hours.count, "checkpoints must be unique")
        // The first day is where somebody needs the next marker within reach.
        XCTAssertGreaterThanOrEqual(hours.filter { $0 <= 72 }.count, 4)
        XCTAssertEqual(hours.last, 1_440, "the roadmap should end at two months")
    }

    func testExactlyOneCheckpointIsEverMarkedNext() {
        // Every value here is short of the final checkpoint; "all passed" is covered below.
        for hoursIn in [0, 1, 5, 6, 23, 24, 71, 72, 200, 700, 1_400] {
            let now = start.addingTimeInterval(TimeInterval(hoursIn) * 3_600)
            let nextCount = ProgressCalculator.journey(streakStart: start, now: now).filter(\.isNext).count
            XCTAssertEqual(nextCount, 1, "expected one next checkpoint at \(hoursIn)h in")
        }
    }

    func testNoCheckpointIsNextOnceAllArePassed() {
        let now = start.addingTimeInterval(50_000 * 3_600)
        let stops = ProgressCalculator.journey(streakStart: start, now: now)
        XCTAssertTrue(stops.allSatisfy(\.isReached))
        XCTAssertNil(stops.first(where: \.isNext))
    }

    func testNextCheckpointCountdownCountsDownToTheRealTarget() {
        let now = start.addingTimeInterval(47 * 3_600)
        let stops = ProgressCalculator.journey(streakStart: start, now: now)
        guard case .next(let remaining)? = stops.first(where: \.isNext)?.state else {
            return XCTFail("expected a next checkpoint")
        }
        // 48h target, 47h elapsed -> 1h remaining.
        XCTAssertEqual(remaining, 3_600, accuracy: 1)
    }

    func testAFreshStartHasNothingReachedAndAimsAtTheFirstCheckpoint() {
        let stops = ProgressCalculator.journey(streakStart: start, now: start)
        XCTAssertTrue(stops.filter(\.isReached).isEmpty)
        XCTAssertEqual(stops.first(where: \.isNext)?.milestone.hours, 2)
    }

    func testProgressToNextStopIsFractionalBetweenCheckpoints() {
        // Halfway between the 8h and 48h checkpoints is 28h.
        let now = start.addingTimeInterval(28 * 3_600)
        XCTAssertEqual(ProgressCalculator.progressToNextStop(streakStart: start, now: now), 0.5, accuracy: 0.01)
    }

    func testProgressToNextStopIsCompleteWhenEveryCheckpointIsPassed() {
        let now = start.addingTimeInterval(50_000 * 3_600)
        XCTAssertEqual(ProgressCalculator.progressToNextStop(streakStart: start, now: now), 1, accuracy: 0.001)
    }

    func testProgressNeverGoesNegativeForAFutureQuitDate() {
        let now = start.addingTimeInterval(-3_600)
        let value = ProgressCalculator.progressToNextStop(streakStart: start, now: now)
        XCTAssertGreaterThanOrEqual(value, 0)
        XCTAssertLessThanOrEqual(value, 1)
    }

    // MARK: - Wording

    func testCountdownSwitchesUnitsAsTheHorizonGrows() {
        XCTAssertEqual(JourneyFormatter.countdown(30 * 60), "in 30m")
        XCTAssertEqual(JourneyFormatter.countdown(9 * 3_600), "in 9h")
        XCTAssertEqual(JourneyFormatter.countdown(5 * 86_400), "in 5d")
        XCTAssertEqual(JourneyFormatter.countdown(120 * 86_400), "in 4mo")
        XCTAssertEqual(JourneyFormatter.countdown(3 * 365 * 86_400), "in 3y")
    }

    func testCountdownNeverShowsZero() {
        XCTAssertEqual(JourneyFormatter.countdown(10), "in 1m")
    }

    func testSpokenCountdownUsesWholeWordsAndAgrees() {
        XCTAssertEqual(JourneyFormatter.spokenCountdown(3_600), "1 hour")
        XCTAssertEqual(JourneyFormatter.spokenCountdown(9 * 3_600), "9 hours")
        XCTAssertEqual(JourneyFormatter.spokenCountdown(86_400 * 5), "5 days")
    }

    func testElapsedHeadlineReadsNaturallyAtEachScale() {
        XCTAssertEqual(JourneyFormatter.elapsedHeadline(45 * 60), "45 minutes in")
        XCTAssertEqual(JourneyFormatter.elapsedHeadline(3_600 + 120), "1 hour, 2 minutes in")
        XCTAssertEqual(JourneyFormatter.elapsedHeadline(47 * 3_600), "1 day, 23 hours in")
        XCTAssertEqual(JourneyFormatter.elapsedHeadline(48 * 3_600), "2 days in")
    }

    func testReachedTextDescribesHowLongAgo() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        XCTAssertEqual(JourneyFormatter.reachedText(now.addingTimeInterval(-600), now: now), "just now")
        XCTAssertEqual(JourneyFormatter.reachedText(now.addingTimeInterval(-5 * 3_600), now: now), "5h ago")
        XCTAssertEqual(JourneyFormatter.reachedText(now.addingTimeInterval(-4 * 86_400), now: now), "4d ago")
    }
}
