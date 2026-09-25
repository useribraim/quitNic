import XCTest
@testable import QuitNic

final class NicotineTypeTests: XCTestCase {
    func testStoredValueRoundTripsForEveryCase() {
        for type in NicotineType.allCases {
            XCTAssertEqual(NicotineType(storedValue: type.storedValue), type)
        }
    }

    func testUnrecognizedStoredValueDefaultsToCigarettes() {
        XCTAssertEqual(NicotineType(storedValue: "chewing-tobacco"), .cigarettes)
        XCTAssertEqual(NicotineType(storedValue: ""), .cigarettes)
    }

    /// One table instead of three near-identical tests, each walking the same four cases
    /// to restate the same switch. The nouns are load-bearing: they are interpolated into
    /// "12 pouches per day" and "Cost per pouch", so plural and singular must agree.
    func testEveryTypeNamesItselfAndItsUnit() {
        let expected: [(NicotineType, display: String, plural: String, singular: String)] = [
            (.pouches, "Nicotine Pouches", "pouches", "pouch"),
            (.cigarettes, "Cigarettes", "cigarettes", "cigarette"),
            (.vape, "Vape", "vape sessions", "vape session"),
            (.other, "Other", "units", "unit")
        ]
        XCTAssertEqual(expected.count, NicotineType.allCases.count, "a new type needs its nouns here")
        for row in expected {
            XCTAssertEqual(row.0.displayName, row.display, "\(row.0) display name")
            XCTAssertEqual(row.0.unitNounPlural, row.plural, "\(row.0) plural noun")
            XCTAssertEqual(row.0.unitNounSingular, row.singular, "\(row.0) singular noun")
        }
    }

    func testOnlyPouchesSupportPerContainerPricing() {
        XCTAssertTrue(NicotineType.pouches.supportsPerContainerPricing)
        XCTAssertFalse(NicotineType.cigarettes.supportsPerContainerPricing)
        XCTAssertFalse(NicotineType.vape.supportsPerContainerPricing)
        XCTAssertFalse(NicotineType.other.supportsPerContainerPricing)
    }

    func testQuitPlanNicotineTypeValueReflectsStoredString() {
        let plan = QuitPlan(nicotineType: "pouches", dailyConsumption: 12, unitCost: 0.4, quitDate: .now, motivation: "Health", reminderHour: nil)
        XCTAssertEqual(plan.nicotineTypeValue, .pouches)
    }

    func testQuitPlanNicotineTypeValueSetterUpdatesStoredString() {
        let plan = QuitPlan(nicotineType: "cigarettes", dailyConsumption: 10, unitCost: 0.75, quitDate: .now, motivation: "Health", reminderHour: nil)
        plan.nicotineTypeValue = .vape
        XCTAssertEqual(plan.nicotineType, "vape")
    }

    func testOtherPlanTypeIsPreservedNotCoercedToCigarettes() {
        // Historically a plan with "other" (e.g. created through a future client or the
        // API directly) was silently relabeled as cigarettes by every display path.
        let plan = QuitPlan(nicotineType: "other", dailyConsumption: 4, unitCost: 2, quitDate: .now, motivation: "Health", reminderHour: nil)
        XCTAssertEqual(plan.nicotineTypeValue, .other)
        XCTAssertEqual(plan.nicotineTypeValue.displayName, "Other")
    }
}
