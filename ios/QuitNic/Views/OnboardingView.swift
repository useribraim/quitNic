import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @State private var nicotineType = "cigarettes"
    @State private var dailyConsumption = 10.0
    @State private var unitCost = 0.75
    @State private var quitDate = Date()
    @State private var motivation = ""
    @State private var reminders = true
    @State private var reminderHour = 20
    @State private var isSaving = false
    @State private var warning: String?

    private var canStart: Bool {
        !isSaving && !motivation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("A steadier way forward")
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .foregroundStyle(QuitNicTheme.ink)
                        Text("Set a quit date, notice your patterns, and get support when a craving shows up.")
                            .font(.subheadline)
                            .foregroundStyle(QuitNicTheme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                }
                .listRowBackground(Color.clear)

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nicotine type")
                        Picker("Nicotine type", selection: $nicotineType) {
                            Text("Nicotine Pouches").tag("pouches")
                            Text("Cigarettes").tag("cigarettes")
                            Text("Vape").tag("vape")
                        }
                        .labelsHidden()
                        .tint(.primary)
                    }
                    Stepper("Daily units: \(Int(dailyConsumption))", value: $dailyConsumption, in: 1...100)
                    HStack { Text("Cost per unit"); Spacer(); TextField("0.75", value: $unitCost, format: .currency(code: "EUR")).multilineTextAlignment(.trailing).keyboardType(.decimalPad) }
                    DatePicker("Quit date", selection: $quitDate, displayedComponents: [.date, .hourAndMinute])
                    TextField("Why do you want to quit?", text: $motivation, axis: .vertical)
                        .lineLimit(3...5)
                        .accessibilityIdentifier("motivationField")
                } header: {
                    Text("Your plan")
                        .foregroundStyle(.primary)
                }
                .headerProminence(.increased)
                Section {
                    Toggle("Daily check-in", isOn: $reminders)
                    if reminders {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hour")
                            Picker("Hour", selection: $reminderHour) {
                                ForEach(0..<24, id: \.self) {
                                    Text(String(format: "%02d:00", $0)).tag($0)
                                }
                            }
                            .labelsHidden()
                            .tint(.primary)
                        }
                    }
                } header: {
                    Text("Reminders")
                        .foregroundStyle(.primary)
                }
                .headerProminence(.increased)
                if let warning { Text(warning).foregroundStyle(.orange).accessibilityLabel("Connection warning: \(warning)") }
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Text(isSaving ? "Saving…" : "Start my plan")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .foregroundStyle(canStart ? .white : QuitNicTheme.secondaryInk)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(canStart ? QuitNicTheme.actionTeal : QuitNicTheme.secondaryInk.opacity(0.12))
                )
                .buttonStyle(.plain)
                .disabled(!canStart)
                .accessibilityHint(canStart ? "Saves your quit plan" : "Enter why you want to quit before starting")
            }
            .scrollContentBackground(.hidden)
            .background(QuitNicTheme.warmBackground)
            .navigationTitle("QuitNic")
        }
    }

    @MainActor private func save() async {
        isSaving = true; warning = nil
        let plan = QuitPlan(nicotineType: nicotineType, dailyConsumption: dailyConsumption, unitCost: unitCost, quitDate: quitDate, motivation: motivation, reminderHour: reminders ? reminderHour : nil)
        context.insert(plan); try? context.save()
        if reminders { try? await NotificationService.scheduleDaily(hour: reminderHour) }
        do {
            if KeychainStore.readToken() == nil { let registration = try await APIClient.shared.register(); try KeychainStore.saveToken(registration.accessToken) }
            try await APIClient.shared.save(plan: QuitPlanRequest(nicotineType: nicotineType, dailyConsumption: dailyConsumption, unitCost: unitCost, quitDate: quitDate, motivation: motivation, reminderHour: reminders ? reminderHour : nil))
        } catch { warning = "Your plan is saved on this device and will connect when the service is available." }
        isSaving = false
    }
}
