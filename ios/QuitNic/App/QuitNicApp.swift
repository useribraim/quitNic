import SwiftData
import SwiftUI

@main
struct QuitNicApp: App {
    private let container: ModelContainer

    init() {
        let schema = Schema([QuitPlan.self, CravingCheckIn.self, RescueSession.self, ChatMessage.self, ActiveCoachingPlan.self, PendingOperation.self, CachedPayload.self])
        let arguments = ProcessInfo.processInfo.arguments
        let isUITesting = arguments.contains("-ui-testing-reset")
        if isUITesting {
            KeychainStore.deleteToken()
            NotificationService.removeAll()
        }
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting)
        do { container = try ModelContainer(for: schema, configurations: [configuration]) }
        catch { fatalError("Unable to create local store: \(error.localizedDescription)") }

        if isUITesting && (arguments.contains("-ui-testing-seed-plan") || arguments.contains("-ui-testing-seed-progress")) {
            let context = ModelContext(container)
            context.insert(QuitPlan(
                nicotineType: "cigarettes",
                dailyConsumption: 10,
                unitCost: 0.75,
                quitDate: Date().addingTimeInterval(-172_800),
                motivation: "More energy and freedom",
                reminderHour: nil
            ))
            if arguments.contains("-ui-testing-seed-progress") {
                context.insert(CravingCheckIn(
                    intensity: 5,
                    trigger: "A long craving trigger after morning coffee",
                    copingAction: "A deliberately long walk around the neighbourhood",
                    note: nil,
                    resisted: true
                ))
            }
            try? context.save()
        }
    }

    var body: some Scene {
        WindowGroup { RootView() }
            .modelContainer(container)
    }
}
