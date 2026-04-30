import Foundation

/// API response wrapper: { "data": T }
struct APIResponse<T: Decodable>: Decodable {
    let data: T
}

/// Generic API client with Bearer token, 401 refresh retry, and configurable base URL.
///
/// This client does not own mutable shared state, so keeping it as a plain reference type
/// avoids unnecessary cross-actor isolation issues under the project's MainActor defaults.
final class APIClient {
    static let shared = APIClient()
    
    private let session: URLSession
    private let baseURL: String
    
    private init(session: URLSession = .shared) {
        self.session = session
        self.baseURL = AppEnvironment.apiBaseURL
    }
    
    /// Performs an authorized request. On 401, attempts refresh and retries once.
    /// Decodes API response wrapper { data: T } and returns T.
    func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: Encodable? = nil,
        tokenProvider: () async -> String?,
        refreshAndRetry: () async -> Bool
    ) async throws -> T {
        let data = try await requestData(path, method: method, body: body, tokenProvider: tokenProvider, refreshAndRetry: refreshAndRetry)
        let decoder = JSONDecoder()
        let wrapped = try decoder.decode(APIResponse<T>.self, from: data)
        return wrapped.data
    }
    
    /// Performs an authorized request returning raw data.
    func requestData(
        _ path: String,
        method: String = "GET",
        body: Encodable? = nil,
        tokenProvider: () async -> String?,
        refreshAndRetry: () async -> Bool
    ) async throws -> Data {
        guard let token = await tokenProvider() else {
            throw APIError.unauthorized
        }
        var req = buildRequest(path: path, method: method, body: body, token: token)
        var (data, response) = try await session.data(for: req)
        var httpResponse = response as? HTTPURLResponse
        
        if httpResponse?.statusCode == 401 {
            let refreshed = await refreshAndRetry()
            guard refreshed, let newToken = await tokenProvider() else {
                throw APIError.unauthorized
            }
            req = buildRequest(path: path, method: method, body: body, token: newToken)
            (data, response) = try await session.data(for: req)
            httpResponse = response as? HTTPURLResponse
        }
        
        guard let status = httpResponse?.statusCode else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(status) else {
            throw APIError.httpStatus(status)
        }
        return data
    }
    
    private func buildRequest(path: String, method: String, body: Encodable?, token: String) -> URLRequest {
        let url = URL(string: "\(baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body = body {
            request.httpBody = try? JSONEncoder().encode(AnyEncodable(body))
        }
        return request
    }
}

private struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void
    init<T: Encodable>(_ wrapped: T) {
        encode = wrapped.encode
    }
    func encode(to encoder: Encoder) throws {
        try encode(encoder)
    }
}

enum APIError: Error {
    case unauthorized
    case invalidResponse
    case httpStatus(Int)
}
