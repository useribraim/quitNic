import SwiftData
import SwiftUI

@main
struct QuitNicApp: App {
    private let container: ModelContainer = {
        let schema = Schema([QuitPlan.self, CravingCheckIn.self, ChatMessage.self, PendingOperation.self, CachedPayload.self])
        let configuration = ModelConfiguration(schema: schema)
        do { return try ModelContainer(for: schema, configurations: [configuration]) }
        catch { fatalError("Unable to create local store: \(error.localizedDescription)") }
    }()

    var body: some Scene {
        WindowGroup { RootView() }
            .modelContainer(container)
    }
}

