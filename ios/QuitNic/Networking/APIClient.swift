import Foundation

enum APIError: LocalizedError, Equatable {
    case invalidResponse, unauthorized, rateLimited, server(Int), decoding, transport(String)
    case recordingTooLong

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The service returned an invalid response."
        case .unauthorized: "Your private session expired. Please reconnect."
        case .rateLimited: "Too many coaching requests. Please wait a moment."
        case .server: "The service is temporarily unavailable."
        case .decoding: "The service returned information the app could not read."
        case .transport: "You appear to be offline. Your progress remains saved on this device."
        case .recordingTooLong: "That recording is too long to send. Try a shorter message."
        }
    }

    /// Whether retrying the identical request could ever succeed. The outbox used to
    /// decide this inline and got it wrong for `.unauthorized` and `.decoding`, which is
    /// how a single dead token became an unbounded retry loop.
    var isTransient: Bool {
        switch self {
        case .transport, .rateLimited: true
        case .server(let status): status >= 500
        // A rejected token is fixed by re-registering, not by resending. A body the
        // server cannot parse, or one we cannot decode, will fail identically forever.
        case .unauthorized, .decoding, .invalidResponse, .recordingTooLong: false
        }
    }
}

actor APIClient {
    static let shared = APIClient()
    private let session: URLSession
    private let baseURLOverride: URL?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: URL? = nil, session: URLSession = .shared) {
        baseURLOverride = baseURL; self.session = session
        encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.keyEncodingStrategy = .convertToSnakeCase
        decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    nonisolated private static var configuredBaseURL: URL {
#if DEBUG
        if let override = UserDefaults.standard.string(forKey: "debugAPIURL"),
           let url = URL(string: override),
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme) {
            return url
        }
#endif
        let configured = Bundle.main.object(forInfoDictionaryKey: "QuitNicAPIURL") as? String
        return URL(string: configured ?? "http://localhost:8000")!
    }

    private var baseURL: URL { baseURLOverride ?? APIClient.configuredBaseURL }

    func register() async throws -> RegistrationResponse { try await send(path: "/v1/devices/register", method: "POST", body: Optional<String>.none, authenticated: false) }
    func save(plan: QuitPlanRequest) async throws { let _: QuitPlanRequest = try await send(path: "/v1/quit-plan", method: "PUT", body: plan) }
    func post(checkIn: CheckInRequest, idempotencyKey: String) async throws -> CheckInResponse { try await send(path: "/v1/check-ins", method: "POST", body: checkIn, extraHeaders: ["Idempotency-Key": idempotencyKey]) }
    func deleteCheckIn(id: UUID) async throws {
        let _: DeleteResponse = try await send(path: "/v1/check-ins/\(id.uuidString)", method: "DELETE", body: Optional<String>.none)
    }
    func coach(_ request: CoachingRequest) async throws -> CoachingResponse { try await send(path: "/v1/coaching/messages", method: "POST", body: request) }

    /// An upload this size has no business being assembled in memory. The multipart
    /// envelope is written to a temp file and streamed, so peak usage stays flat
    /// regardless of how long the button was held.
    // Match the API's hard limit so an oversized clip is rejected on-device before a
    // multipart body is assembled or any bandwidth is spent.
    static let maximumUploadBytes = 8 * 1_024 * 1_024

    func transcribe(audioURL: URL) async throws -> TranscriptionResponse {
        let attributes = try? FileManager.default.attributesOfItem(atPath: audioURL.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        guard size <= Self.maximumUploadBytes else { throw APIError.recordingTooLong }

        let boundary = "QuitNic-\(UUID().uuidString)"
        let filename = audioURL.lastPathComponent
        // The declared type must match what the recorder actually wrote. This previously
        // claimed m4a while shipping raw PCM, which no transcription backend can read.
        let mimeType = Self.mimeType(forPathExtension: audioURL.pathExtension)
        let envelope = FileManager.default.temporaryDirectory
            .appending(path: "quitnic-upload-\(UUID().uuidString)")

        var header = Data()
        header.append(Data("--\(boundary)\r\n".utf8))
        header.append(Data("Content-Disposition: form-data; name=\"audio\"; filename=\"\(filename)\"\r\n".utf8))
        header.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        let footer = Data("\r\n--\(boundary)--\r\n".utf8)

        FileManager.default.createFile(atPath: envelope.path, contents: nil)
        let handle = try FileHandle(forWritingTo: envelope)
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: envelope)
        }
        do {
            try handle.write(contentsOf: header)
            let reader = try FileHandle(forReadingFrom: audioURL)
            defer { try? reader.close() }
            while let chunk = try reader.read(upToCount: 256 * 1_024), !chunk.isEmpty {
                try handle.write(contentsOf: chunk)
            }
            try handle.write(contentsOf: footer)
            try handle.close()
        } catch {
            throw APIError.transport(error.localizedDescription)
        }

        var request = URLRequest(url: baseURL.appending(path: "/v1/transcriptions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        guard let token = KeychainStore.readToken() else { throw APIError.unauthorized }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data: Data; let response: URLResponse
        do { (data, response) = try await session.upload(for: request, fromFile: envelope) }
        catch { throw APIError.transport(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch http.statusCode { case 200..<300: break; case 401: throw APIError.unauthorized; case 429: throw APIError.rateLimited; default: throw APIError.server(http.statusCode) }
        do { return try decoder.decode(TranscriptionResponse.self, from: data) }
        catch { throw APIError.decoding }
    }

    nonisolated static func mimeType(forPathExtension pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "m4a", "mp4": "audio/mp4"
        case "caf": "audio/x-caf"
        case "wav": "audio/wav"
        default: "application/octet-stream"
        }
    }
    func deleteAccount() async throws { let _: [String: Bool] = try await send(path: "/v1/account", method: "DELETE", body: Optional<String>.none) }
    func deleteCoachingHistory() async throws { let _: DeleteResponse = try await send(path: "/v1/coaching/messages", method: "DELETE", body: Optional<String>.none) }

    func healthCheck() async throws {
        var request = URLRequest(url: baseURL.appending(path: "/health"))
        request.timeoutInterval = 8
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
    }

    private func send<Response: Decodable, Body: Encodable>(path: String, method: String, body: Body?, authenticated: Bool = true, extraHeaders: [String: String] = [:]) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path)); request.httpMethod = method
        request.timeoutInterval = 20; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        extraHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        if authenticated {
            guard let token = KeychainStore.readToken() else { throw APIError.unauthorized }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body { request.httpBody = try encoder.encode(body) }
        let data: Data; let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw APIError.transport(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch http.statusCode { case 200..<300: break; case 401: throw APIError.unauthorized; case 429: throw APIError.rateLimited; default: throw APIError.server(http.statusCode) }
        do { return try decoder.decode(Response.self, from: data) } catch { throw APIError.decoding }
    }
}
