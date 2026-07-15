import SwiftData
import SwiftUI
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
    @State private var showPrivacyDetails = false
    @State private var errorMessage: String?

    init(plan: QuitPlan) {
        self.plan = plan
        _reminderEnabled = State(initialValue: plan.reminderHour != nil)
        _reminderHour = State(initialValue: plan.reminderHour ?? 20)
    }

    var body: some View {
        NavigationStack {
            Form {
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
                    Button("Delete account and local data", role: .destructive) { confirmDelete = true }
                }

                #if DEBUG
                Section("Developer") {
                    Label("Coach service uses the configured local or production API.", systemImage: "ladybug")
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
            .confirmationDialog("Delete all QuitNic data?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete permanently", role: .destructive) { Task { await deleteAll() } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This cannot be undone.") }
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
        notificationStatus = await NotificationService.authorizationStatus()
    }

    private func deleteAll() async {
        do {
            if KeychainStore.readToken() != nil { try await APIClient.shared.deleteAccount() }
        } catch {
            errorMessage = "The server could not be reached. Local data was not deleted so you can retry safely."
            return
        }
        do {
            try context.delete(model: ChatMessage.self)
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
