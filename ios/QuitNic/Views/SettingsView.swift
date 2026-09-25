import SwiftData
import SwiftUI
import UIKit
import UserNotifications

enum TranscriptionMode: String, CaseIterable, Identifiable {
    case onDevice
    case enhancedCloud

    var id: String { rawValue }
    var title: String { self == .onDevice ? "On-device" : "Enhanced cloud" }
    var detail: String {
        self == .onDevice
            ? "Private speech recognition on this iPhone."
            : "Sends the pressed audio clip securely for higher-quality transcription."
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let plan: QuitPlan
    let lastNicotineUse: Date?
    @AppStorage("transcriptionMode") private var transcriptionMode = TranscriptionMode.onDevice.rawValue
    @AppStorage("voiceInputEnabled") private var voiceInputEnabled = false
    @State private var reminderEnabled: Bool
    @State private var reminderHour: Int
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var pendingOperationCount = 0
    @State private var hasPendingDeletion = false
    @State private var confirmDelete = false
    @State private var confirmDeleteHistory = false
    @State private var showPlanEditor = false
    @State private var errorMessage: String?
    @State private var reminderMessage: String?
    @State private var reminderUpdateTask: Task<Void, Never>?
    @State private var isApplyingReminder = false

    init(plan: QuitPlan, lastNicotineUse: Date? = nil) {
        self.plan = plan
        self.lastNicotineUse = lastNicotineUse
        _reminderEnabled = State(initialValue: plan.reminderHour != nil)
        _reminderHour = State(initialValue: plan.reminderHour ?? 20)
    }

    var body: some View {
        NavigationStack {
            Form {
                planSection.listRowBackground(HorizonTheme.surface)
                reminderSection.listRowBackground(HorizonTheme.surface)
                voiceSection.listRowBackground(HorizonTheme.surface)
                syncSection.listRowBackground(HorizonTheme.surface)
                privacySection.listRowBackground(HorizonTheme.surface)
                deleteSection.listRowBackground(HorizonTheme.surface)
                developerSection.listRowBackground(HorizonTheme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(HorizonBackdrop())
            .foregroundStyle(HorizonTheme.primaryText)
            .tint(HorizonTheme.accent)
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .task {
                // Let the sheet finish its first frame before asking system services or
                // counting outbox rows. Settings should feel immediate even on old data.
                try? await Task.sleep(for: .milliseconds(220))
                pendingOperationCount = (try? context.fetchCount(FetchDescriptor<PendingOperation>())) ?? 0
                hasPendingDeletion = UserDefaults.standard.bool(forKey: "pendingCoachingDeletion")
                    || UserDefaults.standard.bool(forKey: "pendingAccountDeletion")
                notificationStatus = await NotificationService.authorizationStatus()
            }
            .sheet(isPresented: $showPlanEditor) { EditQuitPlanView(plan: plan) }
            .onAppear { PerformanceSignposts.settingsAppeared() }
            .onDisappear { reminderUpdateTask?.cancel() }
            .confirmationDialog("Delete all QuitNic data?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete permanently", role: .destructive) { Task { await deleteAll() } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This cannot be undone.") }
            .confirmationDialog("Delete coaching history everywhere?", isPresented: $confirmDeleteHistory, titleVisibility: .visible) {
                Button("Delete coaching history", role: .destructive) { Task { await deleteCoachingHistory() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes coaching messages from this device and the QuitNic service. Your quit plan and Rescue history stay intact.")
            }
        }
        .preferredColorScheme(.dark)
        .tint(HorizonTheme.accent)
    }

    private var planSection: some View {
        Section("Your plan") {
            LabeledContent("Quitting", value: plan.nicotineTypeValue.displayName)
            LabeledContent("Quit date", value: plan.quitDate.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("Daily amount", value: "\(Int(plan.dailyConsumption)) \(plan.nicotineTypeValue.unitNounPlural) per day")
            LabeledContent("Cost per \(plan.nicotineTypeValue.unitNounSingular)", value: AppCurrency.format(plan.unitCost, code: plan.currencyCode))
            Button("Edit quit plan") { showPlanEditor = true }
        }
    }

    private var reminderSection: some View {
        Section("Reminders") {
            Toggle("Daily check-in", isOn: $reminderEnabled)
                .onChange(of: reminderEnabled) { _, _ in scheduleReminderUpdate() }
            if reminderEnabled {
                Picker("Hour", selection: $reminderHour) {
                    ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                }
                .onChange(of: reminderHour) { _, _ in scheduleReminderUpdate() }
            }
            if let reminderMessage {
                Label(reminderMessage, systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(HorizonTheme.accentText)
            }
            if let celebration = nextCelebration {
                LabeledContent("Next celebration") {
                    Text("\(celebration.title) · \(celebration.date, format: .relative(presentation: .named))")
                        .foregroundStyle(HorizonTheme.accentText)
                }
            }
            LabeledContent("Permission", value: notificationStatusText)
                .foregroundStyle(notificationStatus == .denied ? .orange : HorizonTheme.secondaryText)
            if notificationStatus == .denied {
                Text("Notifications are off. You can enable them in iPhone Settings when you are ready.")
                    .font(.footnote)
                    .foregroundStyle(HorizonTheme.secondaryText)
                Button("Open iPhone Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    private var voiceSection: some View {
        Section("Voice input") {
            Toggle("Enable voice input", isOn: $voiceInputEnabled)
            if voiceInputEnabled {
                Picker("Transcription", selection: $transcriptionMode) {
                    ForEach(TranscriptionMode.allCases) { mode in Text(mode.title).tag(mode.rawValue) }
                }
                Text(selectedTranscriptionMode.detail)
                    .font(.footnote)
                    .foregroundStyle(HorizonTheme.secondaryText)
                if selectedTranscriptionMode == .enhancedCloud {
                    Label("Audio is sent only when you hold and release Push to Talk.", systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(HorizonTheme.secondaryText)
                }
            }
        }
    }

    @ViewBuilder private var syncSection: some View {
        if pendingOperationCount > 0 || hasPendingDeletion {
            Section("Sync") {
                LabeledContent("Status", value: "Waiting for connection")
                if pendingOperationCount > 0 {
                    Text("\(pendingOperationCount) change\(pendingOperationCount == 1 ? "" : "s") saved on this iPhone will retry automatically.")
                        .font(.footnote)
                        .foregroundStyle(HorizonTheme.secondaryText)
                }
                if hasPendingDeletion {
                    Text("A deletion request will also retry automatically.")
                        .font(.footnote)
                        .foregroundStyle(HorizonTheme.secondaryText)
                }
            }
        }
    }

    private var privacySection: some View {
        Section("Privacy") {
            NavigationLink("Privacy and data use") { PrivacyDetailsView() }
            Text("Your quit plan and check-ins stay on this iPhone. Coaching messages use the QuitNic service.")
                .font(.footnote)
                .foregroundStyle(HorizonTheme.secondaryText)
        }
    }

    private var deleteSection: some View {
        Section {
            Button("Delete coaching history everywhere", role: .destructive) { confirmDeleteHistory = true }
                .foregroundStyle(HorizonTheme.accent)
            Button("Delete account and local data", role: .destructive) { confirmDelete = true }
                .foregroundStyle(HorizonTheme.accent)
        } header: {
            Text("Delete data")
        } footer: {
            VStack(alignment: .leading, spacing: HorizonLayout.tight) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                Text("QuitNic \(appVersion)")
            }
            .font(.footnote)
        }
    }

    @ViewBuilder private var developerSection: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-show-developer-tools") {
            Section { NavigationLink("Developer tools") { DeveloperSettingsView() } }
        }
        #endif
    }

    private var selectedTranscriptionMode: TranscriptionMode {
        TranscriptionMode(rawValue: transcriptionMode) ?? .onDevice
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var nextCelebration: (title: String, date: Date)? {
        let streakStart = ProgressCalculator.streakStart(quitDate: plan.quitDate, lastSlip: lastNicotineUse)
        guard let milestone = ProgressCalculator.calculate(plan: plan, lastNicotineUse: lastNicotineUse).nextMilestone else { return nil }
        return (milestone.title, streakStart.addingTimeInterval(TimeInterval(milestone.hours) * 3_600))
    }

    private var notificationStatusText: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: "Allowed"
        case .denied: "Not allowed"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }

    private func applyReminder() async {
        guard !isApplyingReminder else { return }
        isApplyingReminder = true
        defer { isApplyingReminder = false }
        reminderMessage = nil
        plan.reminderHour = reminderEnabled ? reminderHour : nil
        try? context.save()
        if reminderEnabled {
            do {
                try await NotificationService.scheduleDaily(hour: reminderHour)
                reminderMessage = "Daily check-in set for \(String(format: "%02d:00", reminderHour))."
            } catch {
                reminderEnabled = false
                plan.reminderHour = nil
                try? context.save()
                reminderMessage = "Reminder could not be scheduled. Check notification permission."
            }
        } else {
            NotificationService.removeDailyCheckIn()
            reminderMessage = "Daily check-in turned off."
        }
        await SyncCoordinator.savePlan(plan, context: context)
        notificationStatus = await NotificationService.authorizationStatus()
    }

    private func scheduleReminderUpdate() {
        guard !isApplyingReminder else { return }
        reminderUpdateTask?.cancel()
        reminderUpdateTask = Task {
            do { try await Task.sleep(for: .milliseconds(300)) }
            catch { return }
            guard !Task.isCancelled else { return }
            await applyReminder()
        }
    }

    private func deleteAll() async {
        let deletedEverywhere = (try? await SyncCoordinator.deleteAccount()) != nil
        if !deletedEverywhere { UserDefaults.standard.set(true, forKey: "pendingAccountDeletion") }
        do {
            try context.delete(model: ChatMessage.self)
            try context.delete(model: ActiveCoachingPlan.self)
            try context.delete(model: CravingCheckIn.self)
            try context.delete(model: RescueSession.self)
            try context.delete(model: PendingOperation.self)
            try context.delete(model: QuitPlan.self)
            try context.save()
            NotificationService.removeAll()
        } catch { errorMessage = "Local data could not be deleted." }
    }

    private func deleteCoachingHistory() async {
        errorMessage = nil
        let deletedEverywhere = (try? await SyncCoordinator.deleteCoachingHistory()) != nil
        if !deletedEverywhere { UserDefaults.standard.set(true, forKey: "pendingCoachingDeletion") }
        do {
            try context.delete(model: ChatMessage.self)
            try context.delete(model: ActiveCoachingPlan.self)
            try context.save()
        } catch {
            errorMessage = "Coaching history could not be removed from this device."
        }
    }
}

#if DEBUG
private struct DeveloperSettingsView: View {
    @AppStorage("debugAPIURL") private var debugAPIURL = ""
    @State private var serviceStatus = "Not checked"

    var body: some View {
        Form {
            Section("API") {
                TextField("API URL", text: $debugAPIURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                Text("For a physical iPhone, enter your Mac’s Wi-Fi address. Your Mac and iPhone must be on the same network.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Check API connection") { Task { await checkAPIConnection() } }
                LabeledContent("API status", value: serviceStatus)
            }
        }
        .navigationTitle("Developer tools")
    }

    private func checkAPIConnection() async {
        serviceStatus = "Checking…"
        do {
            try await APIClient.shared.healthCheck()
            serviceStatus = "Connected"
        } catch {
            serviceStatus = "Unavailable"
        }
    }
}
#endif

private struct EditQuitPlanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let plan: QuitPlan

    @State private var nicotineType: String
    @State private var dailyConsumption: Double
    @State private var unitCost: Double
    @State private var quitDate: Date
    @State private var motivation: String
    @State private var saveMessage: String?
    @State private var currencyCode: String
    @State private var confirmedHonestBackdate = false
    private let originalQuitDate: Date

    init(plan: QuitPlan) {
        self.plan = plan
        _nicotineType = State(initialValue: plan.nicotineType)
        _dailyConsumption = State(initialValue: plan.dailyConsumption)
        _unitCost = State(initialValue: plan.unitCost)
        _quitDate = State(initialValue: plan.quitDate)
        _motivation = State(initialValue: plan.motivation)
        _currencyCode = State(initialValue: plan.currencyCode)
        originalQuitDate = plan.quitDate
    }

    private var selectedType: NicotineType { NicotineType(storedValue: nicotineType) }

    /// Moving the date earlier makes the streak and savings look bigger without it having
    /// actually happened — the one direction of this edit that's worth friction over.
    private var isBackdating: Bool {
        ProgressCalculator.isBackdate(original: originalQuitDate, edited: quitDate)
    }

    /// Where the streak now begins after this edit. A recorded slip still wins if it is
    /// later than the edited quit date, matching the dashboard timer.
    private var streakStart: Date {
        ProgressCalculator.streakStart(quitDate: quitDate, context: context)
    }

    private var canSave: Bool {
        metricsError == nil && (!isBackdating || confirmedHonestBackdate)
    }

    private var metricsError: String? {
        QuitPlanInputValidator.metricsError(dailyConsumption: dailyConsumption, unitCost: unitCost)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What you’re quitting") {
                    Picker("Nicotine type", selection: $nicotineType) {
                        ForEach(NicotineType.allCases) { type in
                            Text(type.displayName).tag(type.storedValue)
                        }
                    }
                    if let metricsError {
                        Label(metricsError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    Stepper("\(selectedType.unitNounPlural.capitalized) per day: \(Int(dailyConsumption))", value: $dailyConsumption, in: 1...100)
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
                }
                Section {
                    DatePicker("Quit date", selection: $quitDate, displayedComponents: [.date, .hourAndMinute])
                        // Any further change to the date invalidates a prior confirmation —
                        // it should attest to the specific value being saved, not a past one.
                        .onChange(of: quitDate) { _, _ in confirmedHonestBackdate = false }
                    TextField("Why do you want to quit?", text: $motivation, axis: .vertical)
                        .lineLimit(3...5)
                } header: {
                    Text("Your reason")
                } footer: {
                    if isBackdating {
                        VStack(alignment: .leading, spacing: HorizonLayout.control) {
                            Label("Did this actually happen?", systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.red)
                            Text("Moving your quit date earlier makes your streak and savings look bigger than they really are. Only do this to correct a genuine mistake — QuitNic is only useful to you if the numbers are true.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Toggle("Yes — this is really when I stopped", isOn: $confirmedHonestBackdate)
                                .font(.footnote.weight(.semibold))
                                .tint(.red)
                        }
                        .padding(HorizonLayout.control)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: HorizonLayout.controlRadius))
                        .padding(.top, HorizonLayout.micro)
                    }
                }
                if let saveMessage {
                    Text(saveMessage)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            .navigationTitle("Edit quit plan")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
        }
    }

    @MainActor private func save() async {
        guard canSave else { return }
        plan.nicotineType = nicotineType
        plan.dailyConsumption = dailyConsumption
        plan.unitCost = unitCost
        plan.quitDate = quitDate
        plan.motivation = motivation
        plan.currencyCode = currencyCode
        plan.updatedAt = .now
        do {
            try context.save()
        } catch {
            saveMessage = "Your changes could not be saved on this device."
            return
        }
        // Moving the quit date earlier sweeps past checkpoints instantly. Those were not
        // earned by elapsed time, so mark them seen rather than firing a celebration that
        // congratulates somebody for editing a date field.
        MilestoneAcknowledgement.backfill(streakStart: streakStart, context: context)
        Task { await NotificationService.refreshMilestones(streakStart: streakStart, nicotineType: selectedType) }
        if await SyncCoordinator.savePlan(plan, context: context) {
            dismiss()
        } else {
            saveMessage = "Saved on this device. The service will update when it is available."
        }
    }
}

private struct PrivacyDetailsView: View {
    var body: some View {
        List {
            Section("On this device") {
                Text("Your quit plan, check-ins, Rescue sessions, and conversation display are stored locally so the app remains useful offline.")
            }
            Section("When you use Coach") {
                Text("Your current message and a small, relevant coaching context are sent to QuitNic’s service. The service forwards only what is needed to its configured AI provider.")
            }
            Section("When enhanced transcription is selected") {
                Text("Only audio recorded while you use Push to Talk is sent for transcription. On-device transcription keeps speech recognition on your iPhone.")
            }
            Section("Your control") {
                Text("You can delete the anonymous account and local data from Settings. QuitNic is supportive coaching, not medical care.")
            }
        }
        .navigationTitle("Privacy details")
    }
}
