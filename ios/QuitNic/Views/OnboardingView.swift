import SwiftData
import SwiftUI

enum QuitPlanInputValidator {
    static func metricsError(dailyConsumption: Double, unitCost: Double) -> String? {
        guard dailyConsumption.isFinite, unitCost.isFinite else { return "Enter ordinary numeric values." }
        guard (1...100).contains(dailyConsumption) else { return "Daily amount must be between 1 and 100." }
        guard unitCost > 0 else { return "Enter a cost greater than zero." }
        guard unitCost <= 1_000 else { return "Check the cost—it looks unusually high." }
        return nil
    }
}

struct OnboardingView: View {
    let onPlanCreated: (QuitPlan) -> Void
    @Environment(\.modelContext) private var context
    @State private var nicotineType = "cigarettes"
    @State private var dailyConsumption = 10.0
    @State private var unitCost = 0.75
    @State private var quitDate = Date()
    @State private var motivation = ""
    @State private var reminders = false
    @State private var reminderHour = 20
    @State private var isSaving = false
    @State private var warning: String?
    @State private var completedPlan: QuitPlan?
    @State private var currencyCode = QuitPlan.deviceCurrencyCode
    @FocusState private var motivationFocused: Bool

    private var canStart: Bool {
        !isSaving
            && !motivation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && metricsError == nil
    }

    private var selectedType: NicotineType { NicotineType(storedValue: nicotineType) }
    private var unitNoun: String { selectedType.unitNounPlural }
    private var metricsError: String? {
        QuitPlanInputValidator.metricsError(dailyConsumption: dailyConsumption, unitCost: unitCost)
    }

    var body: some View {
        if let completedPlan {
            // Local persistence is the completion boundary. Registration and sync are
            // deliberately non-blocking so a new plan is useful immediately offline.
            HorizonTabView(plan: completedPlan, lastNicotineUse: nil, destination: .constant(nil))
        } else {
            NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: HorizonLayout.micro) {
                        Text("Nicotine type")
                        Picker("Nicotine type", selection: $nicotineType) {
                            ForEach(NicotineType.allCases) { type in
                                Text(type.displayName).tag(type.storedValue)
                            }
                        }
                        .labelsHidden()
                        .tint(.primary)
                    }
                    TextField("Why do you want to quit?", text: $motivation, axis: .vertical)
                        .lineLimit(3...5)
                        .focused($motivationFocused)
                        .accessibilityIdentifier("motivationField")
                    Stepper("\(unitNoun.capitalized) per day: \(Int(dailyConsumption))", value: $dailyConsumption, in: 1...100)
                    CurrencyPicker(selection: $currencyCode)
                    if selectedType.supportsPerContainerPricing {
                        PouchCostEntryView(unitCost: $unitCost, currencyCode: currencyCode)
                    } else {
                        HStack {
                            Text("Cost per \(selectedType.unitNounSingular)")
                            Spacer()
                            TextField(AppCurrency.placeholderExample(code: currencyCode), value: $unitCost, format: .currency(code: currencyCode))
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                        }
                    }
                    DatePicker("Quit date", selection: $quitDate, displayedComponents: [.date, .hourAndMinute])
                } header: {
                    Text("Your plan")
                        .foregroundStyle(.primary)
                } footer: {
                    VStack(alignment: .leading, spacing: HorizonLayout.tight) {
                        Text("Your daily amount and cost are only used to estimate what you are saving. You can change them any time in Settings.")
                            .foregroundStyle(HorizonTheme.paperInk.opacity(0.72))
                        if let metricsError {
                            Label(metricsError, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .headerProminence(.increased)
                Section {
                    Toggle("Daily check-in", isOn: $reminders)
                    if reminders {
                        VStack(alignment: .leading, spacing: HorizonLayout.micro) {
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
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(HorizonTheme.paper)
            .navigationTitle("QuitNic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(HorizonTheme.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: HorizonLayout.tight) {
                    Button {
                        save()
                    } label: {
                        HStack {
                            Text(isSaving ? "Saving…" : "Start my plan")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .font(.headline)
                        .foregroundStyle(canStart ? .white : HorizonTheme.paperInk.opacity(0.62))
                        .padding(.horizontal, HorizonLayout.content)
                        .padding(.vertical, HorizonLayout.content)
                        .frame(maxWidth: .infinity)
                        .background(
                            canStart ? HorizonTheme.cobalt : HorizonTheme.paperInk.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: HorizonLayout.controlRadius, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canStart)
                    .accessibilityHint(startButtonHint)

                    if !canStart {
                        Text("Add your reason above to start. It is the thing QuitNic reminds you of when a craving hits.")
                            .font(.footnote)
                            .foregroundStyle(HorizonTheme.paperInk.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, HorizonLayout.content)
                .padding(.top, HorizonLayout.control)
                .padding(.bottom, HorizonLayout.compact)
                .background(HorizonTheme.paper.opacity(0.98))
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { motivationFocused = false }
                }
            }
            // This screen deliberately uses a light paper surface. Pinning its semantic
            // controls to the matching scheme prevents white system labels on cream when
            // the device itself is using Dark Mode.
            .preferredColorScheme(.light)
            }
        }
    }

    @MainActor private func save() {
        guard canStart else { return }
        isSaving = true; warning = nil
        motivationFocused = false
        let plan = QuitPlan(nicotineType: nicotineType, dailyConsumption: dailyConsumption, unitCost: unitCost, quitDate: quitDate, motivation: motivation, reminderHour: reminders ? reminderHour : nil, currencyCode: currencyCode)
        context.insert(plan)
        do { try context.save() }
        catch {
            isSaving = false
            warning = "Your plan could not be saved on this device. Please try again."
            return
        }
        isSaving = false
        completedPlan = plan
        onPlanCreated(plan)

        Task { @MainActor in
            if reminders { try? await NotificationService.scheduleDaily(hour: reminderHour) }
            // If notifications were just granted, lay down the milestone celebrations now
            // rather than waiting for the next app foreground.
            await NotificationService.refreshForeground(streakStart: quitDate, nicotineType: selectedType)
            // Registration failing here is not the person's problem to solve — the plan
            // already works offline — but it must leave queued work behind rather than
            // vanishing, which is what the old `try?` swallow did.
            await SyncCoordinator.registerAndSyncNewPlan(plan, context: context)
        }
    }

    private var startButtonHint: String {
        if canStart { return "Saves your quit plan" }
        if let metricsError { return metricsError }
        return "Enter why you want to quit before starting"
    }
}
