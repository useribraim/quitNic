import Foundation
import SwiftData
import XCTest
@testable import QuitNic

final class ProgressCalculatorTests: XCTestCase {
    func testTwoDayProgress() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let plan = QuitPlan(nicotineType: "cigarettes", dailyConsumption: 10, unitCost: 0.75, quitDate: now.addingTimeInterval(-172_800), motivation: "Health", reminderHour: nil)
        let result = ProgressCalculator.calculate(plan: plan, now: now)
        XCTAssertEqual(result.seconds, 172_800)
        XCTAssertEqual(result.moneySaved, 15, accuracy: 0.001)
        XCTAssertEqual(result.avoidedUnits, 20, accuracy: 0.001)
        XCTAssertEqual(result.streakDays, 2)
        // 48 elapsed hours sits between the 24h and 72h checkpoints.
        XCTAssertEqual(result.nextMilestone?.title, "3 Days")
    }

    func testFutureQuitDateDoesNotProduceNegativeProgress() {
        let plan = QuitPlan(nicotineType: "vape", dailyConsumption: 1, unitCost: 5, quitDate: .now.addingTimeInterval(3600), motivation: "Freedom", reminderHour: nil)
        XCTAssertEqual(ProgressCalculator.calculate(plan: plan).seconds, 0)
    }

    func testLatestNicotineUseRestartsTheTimer() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let plan = QuitPlan(nicotineType: "cigarettes", dailyConsumption: 10, unitCost: 0.75, quitDate: now.addingTimeInterval(-172_800), motivation: "Health", reminderHour: nil)
        let result = ProgressCalculator.calculate(plan: plan, lastNicotineUse: now.addingTimeInterval(-3_600), now: now)
        XCTAssertEqual(result.seconds, 3_600)
        XCTAssertEqual(result.streakDays, 0)
    }

    func testSlipResetsSavingsToTheCurrentHonestStreak() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let plan = QuitPlan(nicotineType: "cigarettes", dailyConsumption: 10, unitCost: 0.75, quitDate: now.addingTimeInterval(-172_800), motivation: "Health", reminderHour: nil)
        let result = ProgressCalculator.calculate(plan: plan, lastNicotineUse: now.addingTimeInterval(-3_600), now: now)
        XCTAssertEqual(result.moneySaved, 0.3125, accuracy: 0.001)
        XCTAssertEqual(result.avoidedUnits, 10.0 / 24.0, accuracy: 0.001)
    }

    func testMilestonesContinueBeyondOneWeek() {
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        let plan = QuitPlan(nicotineType: "cigarettes", dailyConsumption: 10, unitCost: 0.75, quitDate: now.addingTimeInterval(-3_600 * 400), motivation: "Health", reminderHour: nil)
        XCTAssertEqual(ProgressCalculator.calculate(plan: plan, now: now).nextMilestone?.title, "4 Weeks")
    }

    func testNoMilestoneRemainsAfterTheFinalOne() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let plan = QuitPlan(nicotineType: "cigarettes", dailyConsumption: 10, unitCost: 0.75, quitDate: now.addingTimeInterval(-3_600 * 50_000), motivation: "Health", reminderHour: nil)
        XCTAssertNil(ProgressCalculator.calculate(plan: plan, now: now).nextMilestone)
    }

    func testMovingQuitDateEarlierIsABackdate() {
        let original = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(ProgressCalculator.isBackdate(original: original, edited: original.addingTimeInterval(-3_600)))
    }

    func testMovingQuitDateLaterIsNotABackdate() {
        let original = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(ProgressCalculator.isBackdate(original: original, edited: original.addingTimeInterval(3_600)))
    }

    func testLeavingQuitDateUnchangedIsNotABackdate() {
        let original = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(ProgressCalculator.isBackdate(original: original, edited: original))
    }

    func testSubMinuteRoundingIsNotTreatedAsABackdate() {
        let original = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(ProgressCalculator.isBackdate(original: original, edited: original.addingTimeInterval(-30)))
    }

    func testPouchPlanMoneySavedUsesTheEnteredPerPouchCost() {
        // Regression guard for pouch support: the formula must not silently special-case
        // nicotine type — a pouch plan's savings should be exactly daily units × cost, the
        // same as any other type, once the per-pouch cost has been entered correctly.
        let now = Date(timeIntervalSince1970: 1_000_000)
        let plan = QuitPlan(nicotineType: "pouches", dailyConsumption: 12, unitCost: 0.4, quitDate: now.addingTimeInterval(-86_400), motivation: "Health", reminderHour: nil)
        let result = ProgressCalculator.calculate(plan: plan, now: now)
        XCTAssertEqual(result.moneySaved, 4.8, accuracy: 0.001)
        XCTAssertEqual(result.avoidedUnits, 12, accuracy: 0.001)
    }
}
