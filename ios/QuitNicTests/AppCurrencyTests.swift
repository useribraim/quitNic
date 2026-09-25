import XCTest
@testable import QuitNic

final class AppCurrencyTests: XCTestCase {
    func testOptionsAlwaysIncludeTheDeviceCurrency() {
        XCTAssertTrue(AppCurrency.options.contains(QuitPlan.deviceCurrencyCode))
    }

    func testOptionsIncludeCommonCurrencies() {
        for code in ["USD", "EUR", "GBP", "JPY"] {
            XCTAssertTrue(AppCurrency.options.contains(code), "Expected \(code) in the currency list")
        }
    }

    func testFormatUsesTheRequestedCurrencySymbol() {
        XCTAssertTrue(AppCurrency.format(12.5, code: "EUR").contains("€"))
        XCTAssertTrue(AppCurrency.format(12.5, code: "USD").contains("$"))
    }

    func testSymbolNameHasAFallbackForUnmappedCurrencies() {
        XCTAssertEqual(AppCurrency.symbolName(for: "XYZ"), "banknote.fill")
    }

    func testSymbolNameMapsKnownCurrencies() {
        XCTAssertEqual(AppCurrency.symbolName(for: "EUR"), "eurosign.circle.fill")
        XCTAssertEqual(AppCurrency.symbolName(for: "USD"), "dollarsign.circle.fill")
        XCTAssertEqual(AppCurrency.symbolName(for: "JPY"), "yensign.circle.fill")
    }

    func testPlaceholderExampleUsesFractionDigitsForEuro() {
        // EUR has two minor units, so a sub-unit example ("0.75") is realistic.
        XCTAssertTrue(AppCurrency.placeholderExample(code: "EUR").contains("75"))
    }

    func testPlaceholderExampleAvoidsFractionsForZeroDecimalCurrencies() {
        // JPY has no minor unit; "¥0.75" is not a price anyone would enter or see.
        let placeholder = AppCurrency.placeholderExample(code: "JPY")
        XCTAssertFalse(placeholder.contains("."))
    }

    func testLabelIncludesTheCurrencyCode() {
        XCTAssertTrue(AppCurrency.label(for: "EUR").hasPrefix("EUR"))
    }
}
