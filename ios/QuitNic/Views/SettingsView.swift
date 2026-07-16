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
    @Environment(\.modelContext) private var context
    let plan: QuitPlan
    @AppStorage("transcriptionMode") private var transcriptionMode = TranscriptionMode.onDevice.rawValue
    @State private var reminderEnabled: Bool
    @State private var reminderHour: Int
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var confirmDelete = false
    @State private var confirmDeleteHistory = false
    @State private var showPrivacyDetails = false
    @State private var showPlanEditor = false
    @State private var errorMessage: String?
#if DEBUG
    @AppStorage("debugAPIURL") private var debugAPIURL = ""
    @State private var serviceStatus = "Not checked"
#endif

    init(plan: QuitPlan) {
        self.plan = plan
        _reminderEnabled = State(initialValue: plan.reminderHour != nil)
        _reminderHour = State(initialValue: plan.reminderHour ?? 20)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Your plan") {
                    LabeledContent("Quitting", value: plan.nicotineType.displayName)
                    LabeledContent("Quit date", value: plan.quitDate.formatted(date: .abbreviated, time: .shortened))
                    Button("Edit quit plan") { showPlanEditor = true }
                }

                Section("Reminders") {
                    Toggle("Daily check-in", isOn: $reminderEnabled)
                    if reminderEnabled {
                        Picker("Hour", selection: $reminderHour) {
                            ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                        }
                    }
                    Button("Apply reminder") { Task { await applyReminder() } }
                    LabeledContent("Permission", value: notificationStatusText)
                        .foregroundStyle(notificationStatus == .denied ? .orange : QuitNicTheme.secondaryInk)
                    if notificationStatus == .denied {
                        Text("Notifications are off. You can enable them in iPhone Settings when you are ready.")
                            .font(.footnote)
                            .foregroundStyle(QuitNicTheme.secondaryInk)
                        Button("Open iPhone Settings") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            UIApplication.shared.open(url)
                        }
                    }
                }

                Section("Voice input") {
                    Picker("Transcription", selection: $transcriptionMode) {
                        ForEach(TranscriptionMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    Text(selectedTranscriptionMode.detail)
                        .font(.footnote)
                        .foregroundStyle(QuitNicTheme.secondaryInk)
                    if selectedTranscriptionMode == .enhancedCloud {
                        Label("Audio is sent only when you hold and release Push to Talk.", systemImage: "lock.fill")
                            .font(.footnote)
                            .foregroundStyle(QuitNicTheme.secondaryInk)
                    }
                }

                Section("Privacy") {
                    Text("Your plan and check-ins remain on this device. Coaching messages use the QuitNic service and its configured AI provider. QuitNic is supportive coaching, not medical care.")
                    Button("Read privacy details") { showPrivacyDetails = true }
                    Button("Delete coaching history everywhere", role: .destructive) { confirmDeleteHistory = true }
                    Button("Delete account and local data", role: .destructive) { confirmDelete = true }
                }

                #if DEBUG
                Section("Developer") {
                    TextField("API URL", text: $debugAPIURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    Text("For a physical iPhone, enter your Mac’s Wi-Fi address, such as http://192.168.1.24:8000. Your Mac and iPhone must be on the same network.")
                        .font(.footnote)
                        .foregroundStyle(QuitNicTheme.secondaryInk)
                    Button("Check API connection") { Task { await checkAPIConnection() } }
                    LabeledContent("API status", value: serviceStatus)
                        .font(.footnote)
                        .foregroundStyle(QuitNicTheme.secondaryInk)
                }
                #endif

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.1")
                }

                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle("Settings")
            .task { notificationStatus = await NotificationService.authorizationStatus() }
            .sheet(isPresented: $showPrivacyDetails) { PrivacyDetailsView() }
            .sheet(isPresented: $showPlanEditor) { EditQuitPlanView(plan: plan) }
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
    }

    private var selectedTranscriptionMode: TranscriptionMode {
        TranscriptionMode(rawValue: transcriptionMode) ?? .onDevice
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
        plan.reminderHour = reminderEnabled ? reminderHour : nil
        try? context.save()
        if reminderEnabled { try? await NotificationService.scheduleDaily(hour: reminderHour) }
        else { NotificationService.removeAll() }
        do {
            if KeychainStore.readToken() != nil {
                try await APIClient.shared.save(plan: QuitPlanRequest(
                    nicotineType: plan.nicotineType,
                    dailyConsumption: plan.dailyConsumption,
                    unitCost: plan.unitCost,
                    quitDate: plan.quitDate,
                    motivation: plan.motivation,
                    reminderHour: plan.reminderHour
                ))
            } else {
                try OutboxService.enqueue(plan: plan, context: context)
            }
        } catch {
            try? OutboxService.enqueue(plan: plan, context: context)
        }
        notificationStatus = await NotificationService.authorizationStatus()
    }

#if DEBUG
    private func checkAPIConnection() async {
        serviceStatus = "Checking…"
        do {
            try await APIClient.shared.healthCheck()
            serviceStatus = "Connected"
        } catch {
            serviceStatus = "Unavailable"
        }
    }
#endif

    private func deleteAll() async {
        do {
            if KeychainStore.readToken() != nil { try await APIClient.shared.deleteAccount() }
        } catch {
            errorMessage = "The server could not be reached. Local data was not deleted so you can retry safely."
            return
        }
        do {
            try context.delete(model: ChatMessage.self)
            try context.delete(model: ActiveCoachingPlan.self)
            try context.delete(model: CravingCheckIn.self)
            try context.delete(model: RescueSession.self)
            try context.delete(model: PendingOperation.self)
            try context.delete(model: CachedPayload.self)
            try context.delete(model: QuitPlan.self)
            try context.save()
            KeychainStore.deleteToken()
            NotificationService.removeAll()
        } catch { errorMessage = "Local data could not be deleted." }
    }

    private func deleteCoachingHistory() async {
        do {
            try await APIClient.shared.deleteCoachingHistory()
        } catch {
            errorMessage = "Coaching history could not be deleted from the service. Nothing was removed locally."
            return
        }
        do {
            try context.delete(model: ChatMessage.self)
            try context.save()
        } catch {
            errorMessage = "Coaching history was deleted from the service, but could not be removed from this device."
        }
    }
}

private extension String {
    var displayName: String {
        switch self {
        case "pouches": "Nicotine Pouches"
        case "cigarettes": "Cigarettes"
        case "vape": "Vape"
        default: "Cigarettes"
        }
    }
}

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

    init(plan: QuitPlan) {
        self.plan = plan
        let supportedTypes = ["pouches", "cigarettes", "vape"]
        _nicotineType = State(initialValue: supportedTypes.contains(plan.nicotineType) ? plan.nicotineType : "cigarettes")
        _dailyConsumption = State(initialValue: plan.dailyConsumption)
        _unitCost = State(initialValue: plan.unitCost)
        _quitDate = State(initialValue: plan.quitDate)
        _motivation = State(initialValue: plan.motivation)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What you’re quitting") {
                    Picker("Nicotine type", selection: $nicotineType) {
                        Text("Nicotine Pouches").tag("pouches")
                        Text("Cigarettes").tag("cigarettes")
                        Text("Vape").tag("vape")
                    }
                    Stepper("Daily units: \(Int(dailyConsumption))", value: $dailyConsumption, in: 1...100)
                    HStack {
                        Text("Cost per unit")
                        Spacer()
                        TextField("0.75", value: $unitCost, format: .currency(code: "EUR"))
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                    }
                }
                Section("Your reason") {
                    DatePicker("Quit date", selection: $quitDate, displayedComponents: [.date, .hourAndMinute])
                    TextField("Why do you want to quit?", text: $motivation, axis: .vertical)
                        .lineLimit(3...5)
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
                ToolbarItem(placement: .topBarTrailing) { Button("Save") { Task { await save() } } }
            }
        }
    }

    @MainActor private func save() async {
        plan.nicotineType = nicotineType
        plan.dailyConsumption = dailyConsumption
        plan.unitCost = unitCost
        plan.quitDate = quitDate
        plan.motivation = motivation
        plan.updatedAt = .now
        do {
            try context.save()
        } catch {
            saveMessage = "Your changes could not be saved on this device."
            return
        }
        do {
            if KeychainStore.readToken() != nil {
                try await APIClient.shared.save(plan: QuitPlanRequest(
                    nicotineType: nicotineType,
                    dailyConsumption: dailyConsumption,
                    unitCost: unitCost,
                    quitDate: quitDate,
                    motivation: motivation,
                    reminderHour: plan.reminderHour
                ))
            }
            dismiss()
        } catch {
            try? OutboxService.enqueue(plan: plan, context: context)
            saveMessage = "Saved on this device. The service will update when it is available."
        }
    }
}

private struct PrivacyDetailsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
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
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}
