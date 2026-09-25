import Foundation
import SwiftUI

enum AppCurrency {
    private static let placeholderCache = NSCache<NSString, NSString>()

    /// A short list covering the common cases, plus whatever the device is set to so
    /// nobody is stuck with a currency that is not theirs.
    static let options: [String] = {
        let common = ["USD", "EUR", "GBP", "CAD", "AUD", "NZD", "CHF", "SEK", "NOK", "DKK", "PLN", "CZK", "HUF", "RON", "TRY", "UAH", "INR", "JPY", "BRL", "MXN", "ZAR", "SGD"]
        var seen = Set<String>()
        return ([QuitPlan.deviceCurrencyCode] + common).filter { seen.insert($0).inserted }.sorted()
    }()

    static func label(for code: String) -> String {
        let name = Locale.current.localizedString(forCurrencyCode: code) ?? code
        return "\(code) — \(name)"
    }

    static func format(_ amount: Double, code: String) -> String {
        amount.formatted(.currency(code: code))
    }

    /// Savings for an always-on dashboard figure. Once the amount is past pocket change
    /// the cents tick over every minute, which turns a motivating number into ambient
    /// churn; below that threshold the cents are the only thing moving, so they stay.
    static func formatSavings(_ amount: Double, code: String) -> String {
        amount >= 20
            ? amount.formatted(.currency(code: code).precision(.fractionLength(0)))
            : amount.formatted(.currency(code: code))
    }

    /// A locale-correct example value for a cost text field's placeholder. A fixed
    /// "0.75" placeholder is fine for EUR/USD but actively misleading for a currency
    /// like JPY that has no minor unit — nobody prices anything at "¥0.75".
    static func placeholderExample(code: String) -> String {
        if let cached = placeholderCache.object(forKey: code as NSString) {
            return cached as String
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        let exampleValue = formatter.maximumFractionDigits == 0 ? 75.0 : 0.75
        let result = formatter.string(from: NSNumber(value: exampleValue)) ?? "0.75"
        placeholderCache.setObject(result as NSString, forKey: code as NSString)
        return result
    }

    /// SF Symbol for the currency, falling back to a generic one for codes without a glyph.
    static func symbolName(for code: String) -> String {
        switch code {
        case "USD", "CAD", "AUD", "NZD", "SGD", "MXN", "BRL": "dollarsign.circle.fill"
        case "EUR": "eurosign.circle.fill"
        case "GBP": "sterlingsign.circle.fill"
        case "JPY": "yensign.circle.fill"
        case "INR": "indianrupeesign.circle.fill"
        case "TRY": "turkishlirasign.circle.fill"
        case "PLN": "polishzlotysign.circle.fill"
        case "UAH": "hryvniasign.circle.fill"
        case "CHF": "francsign.circle.fill"
        case "SEK", "NOK", "DKK": "danishkronesign.circle.fill"
        default: "banknote.fill"
        }
    }
}

struct CurrencyPicker: View {
    @Binding var selection: String

    var body: some View {
        Picker("Currency", selection: $selection) {
            ForEach(AppCurrency.options, id: \.self) { code in
                Text(code)
                    .tag(code)
                    .accessibilityLabel(AppCurrency.label(for: code))
            }
        }
        .tint(.primary)
    }
}
