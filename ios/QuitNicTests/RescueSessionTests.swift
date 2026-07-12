import SwiftData
import XCTest
@testable import QuitNic

final class RescueSessionTests: XCTestCase {
    @MainActor
    func testCompletedRescueSessionPersistsOutcome() throws {
        let schema = Schema([RescueSession.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let completedAt = Date()
        let session = RescueSession(
            startingIntensity: 8,
            endingIntensity: 5,
            trigger: "Coffee",
            intervention: "Two-minute breathing reset",
            startedAt: completedAt.addingTimeInterval(-120),
            completedAt: completedAt,
            resisted: true,
            durationSeconds: 120
        )

        context.insert(session)
        try context.save()

        let stored = try XCTUnwrap(context.fetch(FetchDescriptor<RescueSession>()).first)
        XCTAssertEqual(stored.startingIntensity, 8)
        XCTAssertEqual(stored.endingIntensity, 5)
        XCTAssertEqual(stored.trigger, "Coffee")
        XCTAssertEqual(stored.intervention, "Two-minute breathing reset")
        XCTAssertEqual(stored.durationSeconds, 120)
        XCTAssertEqual(stored.resisted, true)
        XCTAssertFalse(stored.synced)
    }
}
