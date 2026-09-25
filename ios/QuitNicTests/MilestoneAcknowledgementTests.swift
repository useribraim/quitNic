import Foundation
import SwiftData
import XCTest
@testable import QuitNic

@MainActor
final class MilestoneAcknowledgementTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        let schema = Schema([QuitPlan.self, CravingCheckIn.self, MilestoneAcknowledgement.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    private func acknowledgedHours() throws -> Set<Int> {
        Set(try context.fetch(FetchDescriptor<MilestoneAcknowledgement>()).map(\.hours))
    }

    /// The regression that shipped: backdating a quit date swept past several checkpoints
    /// at once and fired a "1 Week" celebration for time that had not been lived.
    func testBackdatingMarksSweptCheckpointsSeenSoNoCelebrationFires() throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let backdatedStart = now.addingTimeInterval(-8 * 86_400)

        MilestoneAcknowledgement.backfill(streakStart: backdatedStart, context: context, now: now)

        let acknowledged = try acknowledgedHours()
        // Everything at or under 8 days (192h) must be pre-acknowledged.
        for milestone in ProgressCalculator.milestones where milestone.hours <= 192 {
            XCTAssertTrue(acknowledged.contains(milestone.hours), "\(milestone.title) should be silently acknowledged")
        }
    }

    func testCheckpointsStillAheadAreLeftUnacknowledged() throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        MilestoneAcknowledgement.backfill(streakStart: now.addingTimeInterval(-8 * 86_400), context: context, now: now)

        let acknowledged = try acknowledgedHours()
        // A future checkpoint must stay unacknowledged so it can still be earned.
        for milestone in ProgressCalculator.milestones where milestone.hours > 192 {
            XCTAssertFalse(acknowledged.contains(milestone.hours), "\(milestone.title) has not happened yet")
        }
    }

    func testBackfillIsIdempotent() throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let start = now.addingTimeInterval(-8 * 86_400)

        MilestoneAcknowledgement.backfill(streakStart: start, context: context, now: now)
        let first = try context.fetch(FetchDescriptor<MilestoneAcknowledgement>()).count
        MilestoneAcknowledgement.backfill(streakStart: start, context: context, now: now)
        let second = try context.fetch(FetchDescriptor<MilestoneAcknowledgement>()).count

        XCTAssertEqual(first, second, "re-running must not duplicate acknowledgements")
    }

    func testAFreshStreakAcknowledgesNothing() throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        MilestoneAcknowledgement.backfill(streakStart: now, context: context, now: now)
        XCTAssertTrue(try acknowledgedHours().isEmpty, "a brand new streak has earned nothing yet")
    }

    func testAFutureQuitDateAcknowledgesNothing() throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        MilestoneAcknowledgement.backfill(streakStart: now.addingTimeInterval(86_400), context: context, now: now)
        XCTAssertTrue(try acknowledgedHours().isEmpty)
    }
}
