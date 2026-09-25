import Foundation
import XCTest
@testable import QuitNic

final class ZoomDepthTests: XCTestCase {
    private let tolerance = 0.001

    // MARK: - The curve

    func testQuittingStartsAtTheTopOfTheChain() {
        XCTAssertEqual(ZoomDepth.depth(hoursFree: 0), 0, accuracy: tolerance)
        // Time before the quit date cannot pull the camera further out than the start.
        XCTAssertEqual(ZoomDepth.depth(hoursFree: -50), 0, accuracy: tolerance)
    }

    /// The table that fixes the whole feel of the product: which scale each milestone
    /// lands on. `k` is fitted so two months is exactly one complete traversal.
    func testEveryMilestoneLandsWhereTheSpecSaysItDoes() {
        let expected: [Double: Double] = [
            2: 0.527,
            8: 1.223,
            24: 1.949,     // day one, not a milestone but the shape depends on it
            48: 2.446,
            72: 2.744,
            120: 3.123,
            168: 3.376,
            336: 3.898,
            672: 4.422,
            1_440: 5.000,
            8_760: 6.371,  // one year
            87_600: 8.120  // ten years
        ]
        for (hours, depth) in expected {
            XCTAssertEqual(ZoomDepth.depth(hoursFree: hours), depth, accuracy: tolerance, "\(hours)h")
        }
    }

    /// Read the hours from the checkpoint set rather than restating them, so moving a
    /// checkpoint moves the world with it instead of silently disagreeing.
    func testTheCheckpointSetSpansExactlyOneTraversal() {
        let hours = ProgressCalculator.milestones.map { Double($0.hours) }
        XCTAssertEqual(hours.first, 2, "the curve's h0 is the first checkpoint")
        XCTAssertEqual(ZoomDepth.depth(hoursFree: hours.first ?? 0), ZoomDepth.k, accuracy: tolerance)
        XCTAssertEqual(
            ZoomDepth.depth(hoursFree: hours.last ?? 0),
            Double(ZoomChain.count),
            accuracy: tolerance,
            "the last checkpoint must complete one full loop of the chain"
        )
        XCTAssertEqual(ZoomDepth.traversalHours, hours.last ?? 0, accuracy: 0.001)
    }

    /// Checkpoints are spread along the axis rather than bunched. With nine checkpoints
    /// over five plates several share a plate, which is fine — but no two may land close
    /// enough together to read as the same moment.
    func testCheckpointsAreSpreadAlongTheAxis() {
        let depths = ProgressCalculator.milestones.map { ZoomDepth.depth(hoursFree: Double($0.hours)) }
        XCTAssertEqual(depths, depths.sorted())
        for (earlier, later) in zip(depths, depths.dropFirst()) {
            XCTAssertGreaterThan(later - earlier, 0.2, "checkpoints at \(earlier) and \(later) are indistinguishable")
        }
    }

    func testDepthIsMonotonicAndUnbounded() {
        var previous = ZoomDepth.depth(hoursFree: 0)
        for hours in stride(from: 1.0, through: 100_000, by: 137) {
            let depth = ZoomDepth.depth(hoursFree: hours)
            XCTAssertGreaterThan(depth, previous, "depth went backwards at \(hours)h")
            previous = depth
        }
        // Nobody finishes quitting: there is no ceiling to arrive at.
        XCTAssertGreaterThan(ZoomDepth.depth(hoursFree: 1_000_000), Double(ZoomChain.count))
    }

    /// Day one has to move visibly and year two must not. This is the number that makes
    /// opening the app twice on day one worth doing.
    func testDayOneTravelsFarAndLaterYearsBarelyMove() {
        let dayOne = ZoomDepth.depth(hoursFree: 24) - ZoomDepth.depth(hoursFree: 0)
        let dayTwo = ZoomDepth.depth(hoursFree: 48) - ZoomDepth.depth(hoursFree: 24)
        let aDayInYearTwo = ZoomDepth.depth(hoursFree: 17_544) - ZoomDepth.depth(hoursFree: 17_520)
        XCTAssertGreaterThan(dayOne, Double(ZoomChain.count) * 0.35)
        XCTAssertLessThan(dayTwo, dayOne / 3)
        XCTAssertLessThan(aDayInYearTwo, 0.01)
    }

    func testHoursAndDepthAreInverses() {
        for hours in [0.0, 2, 24, 168, 1_440, 8_760] {
            let roundTrip = ZoomDepth.hours(atDepth: ZoomDepth.depth(hoursFree: hours))
            XCTAssertEqual(roundTrip, hours, accuracy: max(0.001, hours * 0.0001), "\(hours)h did not survive the round trip")
        }
    }

    func testDepthFromAStreakStartMeasuresElapsedTime() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let now = start.addingTimeInterval(48 * 3_600)
        XCTAssertEqual(ZoomDepth.depth(streakStart: start, now: now), 2.446, accuracy: tolerance)
        // A quit date in the future is not negative progress.
        XCTAssertEqual(ZoomDepth.depth(streakStart: start, now: start.addingTimeInterval(-3_600)), 0, accuracy: tolerance)
    }

    // MARK: - The chain

    func testTheChainWrapsInBothDirections() {
        let count = ZoomChain.count
        XCTAssertEqual(count, 5)
        XCTAssertEqual(ZoomChain.level(0).id, 0)
        XCTAssertEqual(ZoomChain.level(count - 1).id, count - 1)
        // Past the last plate the world comes round again.
        XCTAssertEqual(ZoomChain.level(count).id, 0)
        XCTAssertEqual(ZoomChain.level(count * 2 + 3).id, 3)
        // Rescue's outward drift runs the camera past the start.
        XCTAssertEqual(ZoomChain.level(-1).id, count - 1)
        XCTAssertEqual(ZoomChain.level(-count).id, 0)
        XCTAssertEqual(ZoomChain.level(-count - 2).id, count - 2)
    }

    /// Two levels pointing at the same image would silently make the chain shorter than
    /// the depth curve is fitted for.
    func testEveryPlateIsADistinctImage() {
        XCTAssertEqual(Set(ZoomChain.levels.map(\.assetName)).count, ZoomChain.count, "two plates share an image")
    }

    func testTheDissolveHasNoCornerAtEitherEnd() {
        XCTAssertEqual(ZoomWorldView.smoothstep(0.5, from: 0.74, to: 1), 0, accuracy: tolerance)
        XCTAssertEqual(ZoomWorldView.smoothstep(0.74, from: 0.74, to: 1), 0, accuracy: tolerance)
        XCTAssertEqual(ZoomWorldView.smoothstep(0.87, from: 0.74, to: 1), 0.5, accuracy: 0.01)
        XCTAssertEqual(ZoomWorldView.smoothstep(1, from: 0.74, to: 1), 1, accuracy: tolerance)
        XCTAssertEqual(ZoomWorldView.smoothstep(1.4, from: 0.74, to: 1), 1, accuracy: tolerance)
    }

    // MARK: - Light

    func testLightIsContinuousAcrossMidnight() {
        let lateNight = HorizonLight.grade(atHour: 23.9)
        let earlyMorning = HorizonLight.grade(atHour: 0.1)
        XCTAssertEqual(lateNight.opacity, earlyMorning.opacity, accuracy: 0.02)
        // The small hours hold steady dark rather than drifting toward dawn all night.
        XCTAssertEqual(HorizonLight.grade(atHour: 3).opacity, 0.56, accuracy: 0.01)
    }

    func testMiddayIsUngradedAndDuskIsNot() {
        XCTAssertEqual(HorizonLight.grade(atHour: 12).opacity, 0, accuracy: 0.01)
        XCTAssertGreaterThan(HorizonLight.grade(atHour: 20.5).opacity, 0.4)
        XCTAssertGreaterThan(HorizonLight.grade(atHour: 6).opacity, 0.3)
    }

}
