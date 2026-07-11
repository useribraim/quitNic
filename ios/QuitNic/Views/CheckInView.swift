import SwiftData
import SwiftUI

struct CheckInView: View {
    @Environment(\.modelContext) private var context
    @State private var intensity = 5.0
    @State private var trigger = ""
    @State private var copingAction = ""
    @State private var note = ""
    @State private var resisted = true
    @State private var confirmation = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading) { Text("Intensity: \(Int(intensity))/10"); Slider(value: $intensity, in: 1...10, step: 1).accessibilityLabel("Craving intensity") }
                    TextField("What triggered it?", text: $trigger, axis: .vertical)
                        .lineLimit(1...2)
                        .accessibilityIdentifier("triggerField")
                    TextField("What did you try?", text: $copingAction, axis: .vertical)
                        .lineLimit(1...2)
                        .accessibilityIdentifier("copingActionField")
                    TextField("Optional note", text: $note, axis: .vertical)
                    Toggle("I resisted the craving", isOn: $resisted)
                } header: {
                    Text("Craving")
                        .foregroundStyle(.primary)
                }
                .headerProminence(.increased)
                Button("Save check-in") { save() }
                    .tint(Color(red: 0, green: 0.25, blue: 0.65))
                    .disabled(trigger.isEmpty || copingAction.isEmpty)
            }.navigationTitle("Check In").alert("Check-in saved", isPresented: $confirmation) { Button("OK", role: .cancel) {} } message: { Text("It is safely stored and will sync when you’re online.") }
        }
    }
    private func save() {
        let item = CravingCheckIn(intensity: Int(intensity), trigger: trigger, copingAction: copingAction, note: note.isEmpty ? nil : note, resisted: resisted)
        context.insert(item); try? OutboxService.enqueue(checkIn: item, context: context)
        confirmation = true; trigger = ""; copingAction = ""; note = ""; intensity = 5
        Task { await OutboxService.flush(context: context) }
    }
}
