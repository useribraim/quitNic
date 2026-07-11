import SwiftData
import SwiftUI

@main
struct QuitNicApp: App {
    private let container: ModelContainer

    init() {
        let schema = Schema([QuitPlan.self, CravingCheckIn.self, ChatMessage.self, PendingOperation.self, CachedPayload.self])
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing-reset")
        if isUITesting {
            KeychainStore.deleteToken()
            NotificationService.removeAll()
        }
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting)
        do { container = try ModelContainer(for: schema, configurations: [configuration]) }
        catch { fatalError("Unable to create local store: \(error.localizedDescription)") }
    }

    var body: some Scene {
        WindowGroup { RootView() }
            .modelContainer(container)
    }
}
