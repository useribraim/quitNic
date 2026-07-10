import Foundation
import XCTest
@testable import QuitNic

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
        catch { client?.urlProtocol(self, didFailWithError: error) }
    }

    override func stopLoading() {}
}

final class APIClientTests: XCTestCase {
    func testRegistrationDecodesSnakeCase() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"device_id":"d1","access_token":"secret","token_type":"bearer"}"#.utf8))
        }
        let registration = try await makeClient().register()
        XCTAssertEqual(registration.deviceId, "d1")
        XCTAssertEqual(registration.accessToken, "secret")
    }

    func testMalformedSuccessfulResponseReportsDecodingError() async {
        await assertRegistrationError(status: 201, data: Data("not-json".utf8), expected: .decoding)
    }

    func testUnauthorizedResponseIsDistinguished() async {
        await assertRegistrationError(status: 401, expected: .unauthorized)
    }

    func testRateLimitedResponseIsDistinguished() async {
        await assertRegistrationError(status: 429, expected: .rateLimited)
    }

    func testServerResponsePreservesStatusCode() async {
        await assertRegistrationError(status: 503, expected: .server(503))
    }

    func testOfflineTransportHasRecoverableError() async {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await makeClient().register()
            XCTFail("Expected an offline transport error")
        } catch APIError.transport(_) {
            // Expected: the app can present its offline recovery message.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeClient() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return APIClient(
            baseURL: URL(string: "https://example.test")!,
            session: URLSession(configuration: configuration)
        )
    }

    private func assertRegistrationError(
        status: Int,
        data: Data = Data(),
        expected: APIError
    ) async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }
        do {
            _ = try await makeClient().register()
            XCTFail("Expected \(expected)")
        } catch let error as APIError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
