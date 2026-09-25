import XCTest
@testable import QuitNic

final class PouchCostCalculatorTests: XCTestCase {
    func testTypicalCanSplitsEvenlyAcrossPouches() {
        let cost = PouchCostCalculator.perPouchCost(costPerCan: 6.0, pouchesPerCan: 15)
        XCTAssertEqual(cost, 0.4, accuracy: 0.0001)
    }

    func testSinglePouchPerCanEqualsTheCanPrice() {
        let cost = PouchCostCalculator.perPouchCost(costPerCan: 5.0, pouchesPerCan: 1)
        XCTAssertEqual(cost, 5.0, accuracy: 0.0001)
    }

    func testZeroPouchesPerCanDoesNotDivideByZero() {
        XCTAssertEqual(PouchCostCalculator.perPouchCost(costPerCan: 6.0, pouchesPerCan: 0), 0)
    }

    func testNegativePouchesPerCanIsTreatedAsInvalid() {
        XCTAssertEqual(PouchCostCalculator.perPouchCost(costPerCan: 6.0, pouchesPerCan: -3), 0)
    }

    func testFreeCanProducesZeroPerPouchCost() {
        XCTAssertEqual(PouchCostCalculator.perPouchCost(costPerCan: 0, pouchesPerCan: 20), 0)
    }

    func testFractionalCanPriceDividesCorrectly() {
        let cost = PouchCostCalculator.perPouchCost(costPerCan: 8.49, pouchesPerCan: 20)
        XCTAssertEqual(cost, 0.4245, accuracy: 0.0001)
    }

    func testQuitPlanMetricsRejectZeroAndNegativeCosts() {
        XCTAssertNotNil(QuitPlanInputValidator.metricsError(dailyConsumption: 10, unitCost: 0))
        XCTAssertNotNil(QuitPlanInputValidator.metricsError(dailyConsumption: 10, unitCost: -1))
    }

    func testQuitPlanMetricsRejectImpossibleAmountsAndNonFiniteValues() {
        XCTAssertNotNil(QuitPlanInputValidator.metricsError(dailyConsumption: 0, unitCost: 1))
        XCTAssertNotNil(QuitPlanInputValidator.metricsError(dailyConsumption: 101, unitCost: 1))
        XCTAssertNotNil(QuitPlanInputValidator.metricsError(dailyConsumption: .infinity, unitCost: 1))
        XCTAssertNotNil(QuitPlanInputValidator.metricsError(dailyConsumption: 10, unitCost: .nan))
    }

    func testQuitPlanMetricsAcceptOrdinaryValues() {
        XCTAssertNil(QuitPlanInputValidator.metricsError(dailyConsumption: 10, unitCost: 0.75))
    }
}
