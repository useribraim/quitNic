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
        XCTAssertEqual(result.nextMilestone, "First week")
    }

    func testFutureQuitDateDoesNotProduceNegativeProgress() {
        let plan = QuitPlan(nicotineType: "vape", dailyConsumption: 1, unitCost: 5, quitDate: .now.addingTimeInterval(3600), motivation: "Freedom", reminderHour: nil)
        XCTAssertEqual(ProgressCalculator.calculate(plan: plan).seconds, 0)
    }
}

