import Foundation

enum APIError: LocalizedError, Equatable {
    case invalidResponse, unauthorized, rateLimited, server(Int), decoding, transport(String)
    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The service returned an invalid response."
        case .unauthorized: "Your private session expired. Please reconnect."
        case .rateLimited: "Too many coaching requests. Please wait a moment."
        case .server: "The service is temporarily unavailable."
        case .decoding: "The service returned information the app could not read."
        case .transport: "You appear to be offline. Your progress remains saved on this device."
        }
    }
}

actor APIClient {
    static let shared = APIClient()
    private let session: URLSession
    private let baseURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: URL = APIClient.configuredBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL; self.session = session
        encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.keyEncodingStrategy = .convertToSnakeCase
        decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    nonisolated private static var configuredBaseURL: URL {
        let configured = Bundle.main.object(forInfoDictionaryKey: "QuitNicAPIURL") as? String
        return URL(string: configured ?? "http://localhost:8000")!
    }

    func register() async throws -> RegistrationResponse { try await send(path: "/v1/devices/register", method: "POST", body: Optional<String>.none, authenticated: false) }
    func save(plan: QuitPlanRequest) async throws { let _: QuitPlanRequest = try await send(path: "/v1/quit-plan", method: "PUT", body: plan) }
    func progress() async throws -> ProgressResponse { try await send(path: "/v1/progress", method: "GET", body: Optional<String>.none) }
    func post(checkIn: CheckInRequest, idempotencyKey: String) async throws -> CheckInResponse { try await send(path: "/v1/check-ins", method: "POST", body: checkIn, extraHeaders: ["Idempotency-Key": idempotencyKey]) }
    func coach(_ request: CoachingRequest) async throws -> CoachingResponse { try await send(path: "/v1/coaching/messages", method: "POST", body: request) }
    func deleteAccount() async throws { let _: [String: Bool] = try await send(path: "/v1/account", method: "DELETE", body: Optional<String>.none) }

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
