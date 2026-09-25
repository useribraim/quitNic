import SwiftUI

struct CheckInHistoryEditor: View {
    private enum Outcome: String, CaseIterable, Identifiable {
        case movedThrough = "Moved through"
        case usedNicotine = "Used nicotine"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    let checkIn: CravingCheckIn
    let onSave: (Bool) -> Void

    @State private var intensity: Double
    @State private var trigger: String
    @State private var copingAction: String
    @State private var occurredAt: Date
    @State private var outcome: Outcome
    private let originalUsedNicotine: Bool
    private let originalOccurredAt: Date

    init(checkIn: CravingCheckIn, onSave: @escaping (Bool) -> Void) {
        self.checkIn = checkIn
        self.onSave = onSave
        _intensity = State(initialValue: Double(checkIn.intensity))
        _trigger = State(initialValue: checkIn.trigger == "Not specified" ? "" : checkIn.trigger)
        _copingAction = State(initialValue: checkIn.copingAction == "Quick log" ? "" : checkIn.copingAction)
        _occurredAt = State(initialValue: checkIn.occurredAt)
        _outcome = State(initialValue: checkIn.usedNicotine == true ? .usedNicotine : .movedThrough)
        originalUsedNicotine = checkIn.usedNicotine == true
        originalOccurredAt = checkIn.occurredAt
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What happened") {
                    Picker("Outcome", selection: $outcome) {
                        ForEach(Outcome.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("historyOutcomeEditor")
                    DatePicker("When", selection: $occurredAt, in: ...Date.now)
                }
                .listRowBackground(HorizonTheme.surface)

                Section("Details") {
                    VStack(alignment: .leading, spacing: HorizonLayout.compact) {
                        Text("Intensity: \(Int(intensity))/10")
                        Slider(value: $intensity, in: 1...10, step: 1)
                            .accessibilityIdentifier("historyIntensityEditor")
                    }
                    TextField("Trigger", text: $trigger)
                        .accessibilityIdentifier("historyTriggerEditor")
                    TextField("What helped? (optional)", text: $copingAction)
                        .accessibilityIdentifier("historyCopingEditor")
                }
                .listRowBackground(HorizonTheme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(HorizonBackdrop())
            .navigationTitle("Correct check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .accessibilityIdentifier("saveHistoryCorrection")
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(HorizonTheme.accent)
    }

    private func save() {
        let nowUsesNicotine = outcome == .usedNicotine
        let changesStreak = nowUsesNicotine != originalUsedNicotine
            || (nowUsesNicotine && occurredAt != originalOccurredAt)
        let cleanedTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedCoping = copingAction.trimmingCharacters(in: .whitespacesAndNewlines)
        checkIn.intensity = Int(intensity)
        checkIn.trigger = cleanedTrigger.isEmpty ? "Not specified" : cleanedTrigger
        checkIn.copingAction = cleanedCoping.isEmpty ? "Quick log" : cleanedCoping
        checkIn.occurredAt = occurredAt
        checkIn.usedNicotine = nowUsesNicotine
        checkIn.resisted = !nowUsesNicotine
        checkIn.synced = false
        onSave(changesStreak)
        dismiss()
    }
}
