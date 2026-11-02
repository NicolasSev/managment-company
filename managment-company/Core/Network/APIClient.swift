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
        idempotencyKey: String? = nil,
        extraHeaders: [String: String] = [:],
        typedErrors: Bool = false,
        tokenProvider: () async -> String?,
        refreshAndRetry: () async -> Bool
    ) async throws -> T {
        let data = try await requestData(
            path,
            method: method,
            body: body,
            idempotencyKey: idempotencyKey,
            extraHeaders: extraHeaders,
            typedErrors: typedErrors,
            tokenProvider: tokenProvider,
            refreshAndRetry: refreshAndRetry
        )
        let decoder = JSONDecoder()
        let wrapped = try decoder.decode(APIResponse<T>.self, from: data)
        return wrapped.data
    }

    /// Декодирует тело ответа как `T` без обёртки `{ "data": … }` (например `GET /v1/notifications` с пагинацией в корне).
    func requestRoot<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: Encodable? = nil,
        idempotencyKey: String? = nil,
        tokenProvider: () async -> String?,
        refreshAndRetry: () async -> Bool
    ) async throws -> T {
        let data = try await requestData(
            path,
            method: method,
            body: body,
            idempotencyKey: idempotencyKey,
            tokenProvider: tokenProvider,
            refreshAndRetry: refreshAndRetry
        )
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    /// Performs an authorized request returning raw data.
    ///
    /// A non-2xx answer throws `APIError.httpStatus(status)`. With `typedErrors` and a body of the
    /// shape `{"error":{"code","message","details?"}}` it throws `APIError.server` instead, so the
    /// caller can branch on the machine-readable `code`. Opt-in: existing call sites match on
    /// `.httpStatus` and keep working unchanged.
    func requestData(
        _ path: String,
        method: String = "GET",
        body: Encodable? = nil,
        idempotencyKey: String? = nil,
        extraHeaders: [String: String] = [:],
        typedErrors: Bool = false,
        tokenProvider: () async -> String?,
        refreshAndRetry: () async -> Bool
    ) async throws -> Data {
        guard let token = await tokenProvider() else {
            throw APIError.unauthorized
        }
        var req = buildRequest(path: path, method: method, body: body, token: token, idempotencyKey: idempotencyKey, extraHeaders: extraHeaders)
        var (data, response) = try await session.data(for: req)
        var httpResponse = response as? HTTPURLResponse
        
        if httpResponse?.statusCode == 401 {
            let refreshed = await refreshAndRetry()
            guard refreshed, let newToken = await tokenProvider() else {
                throw APIError.unauthorized
            }
            req = buildRequest(path: path, method: method, body: body, token: newToken, idempotencyKey: idempotencyKey, extraHeaders: extraHeaders)
            (data, response) = try await session.data(for: req)
            httpResponse = response as? HTTPURLResponse
        }
        
        guard let status = httpResponse?.statusCode else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(status) else {
            throw APIError.make(status: status, body: data, typed: typedErrors)
        }
        return data
    }

    /// `POST multipart/form-data` with a single file field — response body is decoded without `{ "data": … }` wrapper (e.g. `202 Accepted` uploads).
    func uploadMultipartUnwrapped<T: Decodable>(
        _ path: String,
        fieldName: String,
        fileData: Data,
        fileName: String,
        mimeType: String,
        tokenProvider: () async -> String?,
        refreshAndRetry: () async -> Bool
    ) async throws -> T {
        func performUpload(token: String) async throws -> Data {
            let boundary = "Boundary-\(UUID().uuidString)"
            var body = Data()
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n")
            body.appendString("Content-Type: \(mimeType)\r\n\r\n")
            body.append(fileData)
            body.appendString("\r\n--\(boundary)--\r\n")

            let url = URL(string: "\(baseURL)\(path)")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            request.httpBody = body
            let (data, response) = try await session.data(for: request)
            let httpResponse = response as? HTTPURLResponse

            if httpResponse?.statusCode == 401 {
                throw APIError.unauthorized
            }
            guard let status = httpResponse?.statusCode else {
                throw APIError.invalidResponse
            }
            guard (200...299).contains(status) else {
                throw APIError.httpStatus(status)
            }
            return data
        }

        guard let token = await tokenProvider() else {
            throw APIError.unauthorized
        }

        do {
            let data = try await performUpload(token: token)
            return try JSONDecoder().decode(T.self, from: data)
        } catch APIError.unauthorized {
            let refreshed = await refreshAndRetry()
            guard refreshed, let next = await tokenProvider() else {
                throw APIError.unauthorized
            }
            let data = try await performUpload(token: next)
            return try JSONDecoder().decode(T.self, from: data)
        }
    }

    /// `POST multipart/form-data` with text fields and a single file field.
    /// Decodes the standard `{ "data": T }` API wrapper. With `typedErrors` a non-2xx answer that
    /// carries the error envelope throws `APIError.server` (see `requestData`).
    func uploadMultipart<T: Decodable>(
        _ path: String,
        fields: [String: String],
        fileFieldName: String,
        fileData: Data,
        fileName: String,
        mimeType: String,
        typedErrors: Bool = false,
        tokenProvider: () async -> String?,
        refreshAndRetry: () async -> Bool
    ) async throws -> T {
        func multipartBody(boundary: String) -> Data {
            var body = Data()
            for (key, value) in fields {
                body.appendString("--\(boundary)\r\n")
                body.appendString("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
                body.appendString("\(value)\r\n")
            }
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(fileName)\"\r\n")
            body.appendString("Content-Type: \(mimeType)\r\n\r\n")
            body.append(fileData)
            body.appendString("\r\n--\(boundary)--\r\n")
            return body
        }

        func performUpload(token: String) async throws -> Data {
            let boundary = "Boundary-\(UUID().uuidString)"
            let url = URL(string: "\(baseURL)\(path)")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = multipartBody(boundary: boundary)

            let (data, response) = try await session.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            if httpResponse?.statusCode == 401 {
                throw APIError.unauthorized
            }
            guard let status = httpResponse?.statusCode else {
                throw APIError.invalidResponse
            }
            guard (200...299).contains(status) else {
                throw APIError.make(status: status, body: data, typed: typedErrors)
            }
            return data
        }

        guard let token = await tokenProvider() else {
            throw APIError.unauthorized
        }

        do {
            let data = try await performUpload(token: token)
            return try JSONDecoder().decode(APIResponse<T>.self, from: data).data
        } catch APIError.unauthorized {
            let refreshed = await refreshAndRetry()
            guard refreshed, let next = await tokenProvider() else {
                throw APIError.unauthorized
            }
            let data = try await performUpload(token: next)
            return try JSONDecoder().decode(APIResponse<T>.self, from: data).data
        }
    }

    private func buildRequest(
        path: String,
        method: String,
        body: Encodable?,
        token: String,
        idempotencyKey: String?,
        extraHeaders: [String: String] = [:]
    ) -> URLRequest {
        let url = URL(string: "\(baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        for (name, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
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
    /// Non-2xx answer whose body carries the API error envelope (only with `typedErrors: true`).
    case server(status: Int, error: APIErrorBody)

    /// HTTP status of `.httpStatus` and `.server`.
    var statusCode: Int? {
        switch self {
        case .httpStatus(let status): return status
        case .server(let status, _): return status
        case .unauthorized, .invalidResponse: return nil
        }
    }

    /// Error to throw for a non-2xx answer: typed when asked for and the body parses.
    static func make(status: Int, body: Data, typed: Bool) -> APIError {
        guard typed, let parsed = APIErrorBody.parse(body) else { return .httpStatus(status) }
        return .server(status: status, error: parsed)
    }
}

/// `{"error": {"code", "message", "details?"}}` (lease-v2 spec, "Errors").
struct APIErrorBody: Decodable, Equatable {
    let code: String
    let message: String?
    let details: JSONValue?

    private struct Envelope: Decodable {
        let error: APIErrorBody
    }

    /// `nil` when the body is not the error envelope (HTML from a proxy, empty body, ...).
    static func parse(_ data: Data) -> APIErrorBody? {
        guard !data.isEmpty, let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return nil }
        return envelope.error
    }

    /// `details.<key>` when `details` is an object.
    func detail(_ key: String) -> JSONValue? {
        if case .object(let object) = details { return object[key] }
        return nil
    }

    /// `details[0].message` of field validation errors (`[{field, message}]`).
    var firstFieldError: (field: String?, message: String)? {
        guard case .array(let items) = details, case .object(let first)? = items.first,
              case .string(let message)? = first["message"] else { return nil }
        var field: String?
        if case .string(let name)? = first["field"] { field = name }
        return (field, message)
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let chunk = string.data(using: .utf8) {
            append(chunk)
        }
    }
}
