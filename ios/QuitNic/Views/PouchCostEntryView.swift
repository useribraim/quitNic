import SwiftUI

/// Pure conversion from a can price to a per-pouch price, pulled out of the view so it is
/// directly unit-testable without constructing SwiftUI state.
enum PouchCostCalculator {
    static func perPouchCost(costPerCan: Double, pouchesPerCan: Double) -> Double {
        guard pouchesPerCan > 0 else { return 0 }
        return costPerCan / pouchesPerCan
    }
}

/// Lets a pouch user report cost the way they actually know it — most people can name
/// what a can costs and roughly how many pouches are in it, but not the per-pouch price
/// off the top of their head. Without this, the savings figure is only as accurate as a
/// guess; this computes the real per-pouch cost from numbers someone can actually supply.
struct PouchCostEntryView: View {
    @Binding var unitCost: Double
    let currencyCode: String

    private enum Mode: Hashable { case perPouch, perCan }
    @State private var mode: Mode = .perPouch
    @State private var costPerCan: Double
    @State private var pouchesPerCan: Double

    init(unitCost: Binding<Double>, currencyCode: String, pouchesPerCan: Double = 15) {
        _unitCost = unitCost
        self.currencyCode = currencyCode
        _pouchesPerCan = State(initialValue: pouchesPerCan)
        _costPerCan = State(initialValue: (unitCost.wrappedValue * pouchesPerCan * 100).rounded() / 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HorizonLayout.control) {
            Picker("How do you know the cost?", selection: $mode) {
                Text("Per pouch").tag(Mode.perPouch)
                Text("Per can").tag(Mode.perCan)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Cost entry method")

            if mode == .perPouch {
                HStack {
                    Text("Cost per pouch")
                    Spacer()
                    TextField("0.35", value: $unitCost, format: .currency(code: currencyCode))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                }
            } else {
                HStack {
                    Text("Cost per can")
                    Spacer()
                    TextField("6.00", value: $costPerCan, format: .currency(code: currencyCode))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                }
                Stepper("Pouches per can: \(Int(pouchesPerCan))", value: $pouchesPerCan, in: 1...50)
                HStack {
                    Text("Cost per pouch")
                    Spacer()
                    Text(AppCurrency.format(unitCost, code: currencyCode))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint("Calculated automatically from the can price and count")
            }
        }
        .onChange(of: costPerCan) { _, _ in recompute() }
        .onChange(of: pouchesPerCan) { _, _ in recompute() }
        .onChange(of: mode) { _, newMode in if newMode == .perCan { recompute() } }
    }

    private func recompute() {
        unitCost = PouchCostCalculator.perPouchCost(costPerCan: costPerCan, pouchesPerCan: pouchesPerCan)
    }
}
