import SwiftData
import SwiftUI
import UIKit

final class QuitNicAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if let url = launchOptions?[.url] as? URL {
            _ = HorizonURLRouter.shared.accept(url)
        }
        return true
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        HorizonURLRouter.shared.accept(url)
    }
}

@main
struct QuitNicApp: App {
    @UIApplicationDelegateAdaptor(QuitNicAppDelegate.self) private var appDelegate
    private let container: ModelContainer

    init() {
        let schema = Schema([QuitPlan.self, CravingCheckIn.self, RescueSession.self, ChatMessage.self, ActiveCoachingPlan.self, PendingOperation.self, MilestoneAcknowledgement.self])
        let arguments = ProcessInfo.processInfo.arguments
        let isUITesting = arguments.contains("-ui-testing-reset") || arguments.contains("-ui-testing-persistent")
        let usesPersistentUITestStore = arguments.contains("-ui-testing-persistent")
        if isUITesting {
            KeychainStore.deleteToken()
            NotificationService.removeAll()
            if arguments.contains("-ui-testing-reset") {
                UserDefaults.standard.removeObject(forKey: "checkInDraftV1")
            }
        } else {
            // Keychain items survive app deletion; a reinstall must not silently inherit
            // the previous install's anonymous account.
            KeychainStore.resetIfFreshInstall()
        }
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isUITesting && !usesPersistentUITestStore
        )
        do { container = try ModelContainer(for: schema, configurations: [configuration]) }
        catch { fatalError("Unable to create local store: \(error.localizedDescription)") }

        // Most UI tests use an in-memory store. A small relaunch suite opts into the
        // application sandbox's persistent store so it can prove a saved craving
        // survives process death. Reset that store only on the first launch.
        if usesPersistentUITestStore && arguments.contains("-ui-testing-reset") {
            let context = ModelContext(container)
            try? context.delete(model: MilestoneAcknowledgement.self)
            try? context.delete(model: PendingOperation.self)
            try? context.delete(model: ActiveCoachingPlan.self)
            try? context.delete(model: ChatMessage.self)
            try? context.delete(model: RescueSession.self)
            try? context.delete(model: CravingCheckIn.self)
            try? context.delete(model: QuitPlan.self)
            try? context.save()
        }

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
            if arguments.contains("-ui-testing-seed-history") {
                let fixtures: [(Int, String, String, Bool, Bool?, TimeInterval)] = [
                    (7, "Stress", "Two-minute breathing reset", true, false, -600),
                    (5, "Coffee", "Quick log", true, false, -86_400),
                    (8, "Social", "Called a friend", false, true, -172_800),
                    (4, "Stress", "Short walk", true, false, -259_200),
                    (6, "After a meal", "Drank water", true, false, -604_800)
                ]
                for fixture in fixtures {
                    context.insert(CravingCheckIn(
                        intensity: fixture.0,
                        trigger: fixture.1,
                        copingAction: fixture.2,
                        note: nil,
                        resisted: fixture.3,
                        usedNicotine: fixture.4,
                        occurredAt: Date().addingTimeInterval(fixture.5)
                    ))
                }
            }
            if let historyCount = Self.largeHistoryCount(in: arguments) {
                Self.seedHistory(count: historyCount, context: context)
            }
            if arguments.contains("-ui-testing-seed-coach") {
                context.insert(ChatMessage(role: "user", content: "Coffee breaks are still difficult."))
                context.insert(ChatMessage(role: "assistant", content: "Change the scene for five minutes: step outside, drink water, and let the urge crest without arguing with it."))
                context.insert(ChatMessage(role: "user", content: "I can take a short walk."))
                context.insert(ChatMessage(role: "assistant", content: "Good. Put your shoes by the door now, then make the walk your default response to the next coffee craving."))
            }
            if arguments.contains("-ui-testing-seed-coach-long") {
                Self.seedCoachTranscript(count: 1_000, context: context)
            }
            try? context.save()
        }
    }

    private static func largeHistoryCount(in arguments: [String]) -> Int? {
        if arguments.contains("-ui-testing-seed-history-5000") { return 5_000 }
        if arguments.contains("-ui-testing-seed-history-500") { return 500 }
        return nil
    }

    /// Deterministic scale fixtures exercise the same bounded production queries against
    /// stores that are large enough to expose accidental full-history materialization.
    private static func seedHistory(count: Int, context: ModelContext) {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let triggers = ["Stress", "Coffee", "After a meal", "Boredom", "Social"]
        let actions = ["Two-minute breathing reset", "Drank water", "Short walk", "Called a friend"]
        for index in 0..<count {
            let usedNicotine = index > 0 && index.isMultiple(of: 17)
            context.insert(CravingCheckIn(
                intensity: 1 + index % 10,
                trigger: triggers[index % triggers.count],
                copingAction: actions[index % actions.count],
                note: index.isMultiple(of: 23) ? "Deterministic history fixture \(index)" : nil,
                resisted: !usedNicotine,
                usedNicotine: usedNicotine,
                occurredAt: base.addingTimeInterval(-TimeInterval(index * 3_600)),
                synced: !index.isMultiple(of: 11)
            ))
            if index > 0 && index.isMultiple(of: 500) { try? context.save() }
        }
    }

    private static func seedCoachTranscript(count: Int, context: ModelContext) {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<count {
            let role = index.isMultiple(of: 2) ? "user" : "assistant"
            let message = ChatMessage(
                role: role,
                content: "Deterministic long transcript message \(index): breathe, change the scene, and choose the next small action."
            )
            message.createdAt = base.addingTimeInterval(TimeInterval(index))
            context.insert(message)
            if index > 0 && index.isMultiple(of: 500) { try? context.save() }
        }
    }

    var body: some Scene {
        // RootView owns SwiftUI's running-scene URL handler; the app delegate above is
        // only the cold-launch bridge. Keeping one live-scene handler prevents a single
        // link from presenting the same sheet twice.
        WindowGroup { RootView() }
            .modelContainer(container)
    }
}
