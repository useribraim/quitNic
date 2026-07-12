import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    let plan: QuitPlan
    @State private var reminderEnabled: Bool
    @State private var reminderHour: Int
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    init(plan: QuitPlan) { self.plan = plan; _reminderEnabled = State(initialValue: plan.reminderHour != nil); _reminderHour = State(initialValue: plan.reminderHour ?? 20) }
    var body: some View {
        NavigationStack {
            Form {
                Section("Reminders") { Toggle("Daily check-in", isOn: $reminderEnabled); if reminderEnabled { Picker("Hour", selection: $reminderHour) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } } }; Button("Apply reminder") { Task { await applyReminder() } } }
                Section("Privacy") { Text("Your plan and check-ins are stored on this device. Coaching messages are sent securely to the QuitNic service and its configured AI provider. QuitNic is supportive coaching, not medical care."); Button("Delete account and local data", role: .destructive) { confirmDelete = true } }
                Section("About") { LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }.navigationTitle("Settings").confirmationDialog("Delete all QuitNic data?", isPresented: $confirmDelete, titleVisibility: .visible) { Button("Delete permanently", role: .destructive) { Task { await deleteAll() } }; Button("Cancel", role: .cancel) {} } message: { Text("This cannot be undone.") }
        }
    }
    private func applyReminder() async { plan.reminderHour = reminderEnabled ? reminderHour : nil; try? context.save(); if reminderEnabled { try? await NotificationService.scheduleDaily(hour: reminderHour) } else { NotificationService.removeAll() } }
    private func deleteAll() async {
        do { if KeychainStore.readToken() != nil { try await APIClient.shared.deleteAccount() } }
        catch { errorMessage = "The server could not be reached. Local data was not deleted so you can retry safely."; return }
        do {
            try context.delete(model: ChatMessage.self); try context.delete(model: CravingCheckIn.self); try context.delete(model: RescueSession.self); try context.delete(model: PendingOperation.self); try context.delete(model: CachedPayload.self); try context.delete(model: QuitPlan.self); try context.save()
            KeychainStore.deleteToken(); NotificationService.removeAll()
        } catch { errorMessage = "Local data could not be deleted." }
    }
}
