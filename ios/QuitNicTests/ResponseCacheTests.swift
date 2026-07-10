import SwiftData
import XCTest
@testable import QuitNic

@MainActor
final class ResponseCacheTests: XCTestCase {
    func testCacheRoundTripAndExpiry() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: CachedPayload.self, configurations: configuration)
        let context = container.mainContext
        try ResponseCache.put(["message": "cached"], key: "coach", lifetime: 60, context: context)
        let value: [String: String]? = ResponseCache.get([String: String].self, key: "coach", context: context)
        XCTAssertEqual(value?["message"], "cached")
        let expired: [String: String]? = ResponseCache.get([String: String].self, key: "coach", context: context, now: .now.addingTimeInterval(61))
        XCTAssertNil(expired)
    }
}

