import XCTest
import UIKit
import SwiftData
@testable import QuitNic

final class HorizonNavigationTests: XCTestCase {
    @MainActor
    func testLicensedProductTypefaceIsRegistered() {
        XCTAssertNotNil(UIFont(name: "SatoshiVariable-Bold_Regular", size: 17))
    }

    @MainActor
    func testCoachFetchesOnlyTheMostRecentTranscriptWindow() throws {
        let container = try ModelContainer(
            for: Schema([ChatMessage.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        for index in 0..<150 {
            let message = ChatMessage(role: "user", content: "Message \(index)")
            message.createdAt = Date(timeIntervalSince1970: TimeInterval(index))
            context.insert(message)
        }
        try context.save()

        let fetched = try context.fetch(CoachingView.recentMessageDescriptor())
        XCTAssertEqual(fetched.count, CoachingView.transcriptWindow)
        XCTAssertEqual(fetched.first?.content, "Message 149")
        XCTAssertEqual(fetched.last?.content, "Message 50")
    }

    @MainActor
    func testRouterPublishesValidDestinationAndRejectsInvalidURL() throws {
        let router = HorizonURLRouter.shared
        router.destination = nil

        XCTAssertTrue(router.accept(try XCTUnwrap(URL(string: "quitnic://journey"))))
        XCTAssertEqual(router.destination, .journey)
        XCTAssertFalse(router.accept(try XCTUnwrap(URL(string: "https://example.com/journey"))))
        XCTAssertEqual(router.destination, .journey, "Rejecting a URL must not erase pending navigation")
        router.destination = nil
    }

    func testEverySupportedDeepLinkResolvesToItsDestination() throws {
        for destination in HorizonDestination.allCases {
            let url = try XCTUnwrap(URL(string: "quitnic://\(destination.rawValue)"))
            XCTAssertEqual(HorizonDestination(url: url), destination)
        }
    }

    func testPathStyleLinksAndInvalidSchemesAreHandledSafely() throws {
        XCTAssertEqual(
            HorizonDestination(url: try XCTUnwrap(URL(string: "quitnic:///quick-log"))),
            .quickLog
        )
        XCTAssertNil(HorizonDestination(url: try XCTUnwrap(URL(string: "https://example.com/journey"))))
        XCTAssertNil(HorizonDestination(url: try XCTUnwrap(URL(string: "quitnic://unknown"))))
    }
}
