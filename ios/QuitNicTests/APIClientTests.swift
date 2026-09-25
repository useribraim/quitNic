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

    // MARK: - Voice upload

    /// The recorder writes AAC in an MPEG-4 container. It previously wrote raw float32
    /// PCM to a file named `.m4a` and declared `audio/m4a`, so the bytes, the extension
    /// and the content type all disagreed and no decoder could read the result.
    func testUploadDeclaresTheContainerTypeItActuallySends() {
        XCTAssertEqual(APIClient.mimeType(forPathExtension: "m4a"), "audio/mp4")
        XCTAssertEqual(APIClient.mimeType(forPathExtension: "M4A"), "audio/mp4")
        XCTAssertEqual(APIClient.mimeType(forPathExtension: "wav"), "audio/wav")
        XCTAssertEqual(APIClient.mimeType(forPathExtension: "bin"), "application/octet-stream")
    }

    func testOversizedRecordingIsRejectedBeforeAnyRequestIsMade() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "oversized-\(UUID().uuidString).m4a")
        // One byte past the ceiling, written sparsely so the test stays cheap.
        let handle = try {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            return try FileHandle(forWritingTo: url)
        }()
        try handle.truncate(atOffset: UInt64(APIClient.maximumUploadBytes + 1))
        try handle.close()
        defer { try? FileManager.default.removeItem(at: url) }

        let attempted = Counter()
        MockURLProtocol.handler = { request in
            _ = attempted.next()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
        }

        do {
            _ = try await makeClient().transcribe(audioURL: url)
            XCTFail("Expected the upload to be refused")
        } catch let error as APIError {
            XCTAssertEqual(error, .recordingTooLong)
        }
        XCTAssertEqual(attempted.next(), 0)
    }

    func testAnAbandonedUploadIsNotRetriedByTheOutbox() {
        // A body the server cannot accept will be rejected identically forever.
        XCTAssertFalse(APIError.recordingTooLong.isTransient)
        XCTAssertFalse(APIError.unauthorized.isTransient)
        XCTAssertFalse(APIError.decoding.isTransient)
        XCTAssertFalse(APIError.server(422).isTransient)
        XCTAssertTrue(APIError.server(503).isTransient)
        XCTAssertTrue(APIError.rateLimited.isTransient)
        XCTAssertTrue(APIError.transport("offline").isTransient)
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
