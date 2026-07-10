import Foundation
import XCTest
@testable import QuitNic

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do { let (response, data) = try Self.handler!(request); client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed); client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self) }
        catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class APIClientTests: XCTestCase {
    func testRegistrationDecodesSnakeCase() async throws {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"device_id":"d1","access_token":"secret","token_type":"bearer"}"#.utf8))
        }
        let client = APIClient(baseURL: URL(string: "https://example.test")!, session: URLSession(configuration: configuration))
        let registration = try await client.register()
        XCTAssertEqual(registration.deviceId, "d1")
        XCTAssertEqual(registration.accessToken, "secret")
    }
}

