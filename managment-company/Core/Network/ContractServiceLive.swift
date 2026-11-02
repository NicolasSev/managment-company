import Foundation

/// `ContractService` over the real `/v1` API (spec §9.9).
///
/// `APIClient` drops the body of a failed answer, but the contract screens need it (the 422
/// `details.fields` of CONTRACT_DATA_INCOMPLETE, the error `code` of TEMPLATE_INVALID), and the
/// preview returns bytes with a `Content-Disposition`. So this service talks to `URLSession`
/// itself, with the same bearer token and the same one 401 refresh-and-retry as `APIClient`.
final class LiveContractService: ContractService {
    private let authManager: AuthManager
    private let session: URLSession
    private let baseURL: String

    init(authManager: AuthManager, session: URLSession = .shared, baseURL: String = AppEnvironment.apiBaseURL) {
        self.authManager = authManager
        self.session = session
        self.baseURL = baseURL
    }

    // MARK: ContractService

    func preview(leaseId: String, format: ContractFormat, request: ContractRequest) async throws -> ContractFile {
        let query = Self.previewQuery(format: format, request: request)
        let (data, response) = try await send(path: "/v1/leases/\(leaseId)/contract/preview", query: query)
        return Self.file(data: data, response: response, fallbackName: "dogovor.\(format.fileExtension)", format: format)
    }

    func generate(
        leaseId: String,
        request: ContractRequest,
        formats: [ContractFormat],
        idempotencyKey: String
    ) async throws -> ContractGenerateResponse {
        let act = request.act.normalized
        let body = ContractGenerateBody(
            templateId: request.templateId,
            contractDate: request.contractDate,
            formats: formats,
            act: act.isEmpty ? nil : act
        )
        let (data, _) = try await send(
            path: "/v1/leases/\(leaseId)/contract",
            method: "POST",
            body: try JSONEncoder().encode(body),
            headers: ["Content-Type": "application/json", "Idempotency-Key": idempotencyKey]
        )
        return try decodeData(data)
    }

    func listTemplates() async throws -> [DocumentTemplate] {
        let (data, _) = try await send(path: "/v1/document-templates")
        return try decodeData(data)
    }

    func templateFile(id: String, format: ContractFormat) async throws -> ContractFile {
        let (data, response) = try await send(
            path: "/v1/document-templates/\(id)/file",
            query: [URLQueryItem(name: "format", value: format.rawValue)]
        )
        return Self.file(data: data, response: response, fallbackName: "shablon.\(format.fileExtension)", format: format)
    }

    func uploadTemplate(name: String, isDefault: Bool, fileData: Data, fileName: String) async throws -> DocumentTemplate {
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = Self.multipartBody(
            boundary: boundary,
            fields: [("name", name), ("is_default", isDefault ? "true" : "false")],
            fileField: "file",
            fileName: fileName,
            mimeType: ContractFormat.docx.mimeType,
            fileData: fileData
        )
        let (data, _) = try await send(
            path: "/v1/document-templates",
            method: "POST",
            body: body,
            headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)"]
        )
        return try decodeData(data)
    }

    func landlordProfile() async throws -> LandlordProfile {
        let (data, _) = try await send(path: "/v1/landlord-profile")
        return try decodeData(data)
    }

    func saveLandlordProfile(_ input: LandlordProfileInput) async throws -> LandlordProfile {
        let (data, _) = try await send(
            path: "/v1/landlord-profile",
            method: "PUT",
            body: try JSONEncoder().encode(input),
            headers: ["Content-Type": "application/json"]
        )
        return try decodeData(data)
    }

    // MARK: Transport

    private func send(
        path: String,
        query: [URLQueryItem] = [],
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String] = [:]
    ) async throws -> (Data, HTTPURLResponse) {
        guard var components = URLComponents(string: baseURL + path) else { throw ContractServiceError.unknown }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw ContractServiceError.unknown }

        func attempt(token: String) async throws -> (Data, HTTPURLResponse) {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.httpBody = body
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw ContractServiceError.unknown }
                return (data, http)
            } catch let error as ContractServiceError {
                throw error
            } catch {
                throw ContractServiceError.transport
            }
        }

        guard let token = authManager.accessToken else { throw ContractServiceError.unauthorized }
        var (data, response) = try await attempt(token: token)
        if response.statusCode == 401 {
            guard await authManager.refreshToken(), let fresh = authManager.accessToken else {
                throw ContractServiceError.unauthorized
            }
            (data, response) = try await attempt(token: fresh)
        }
        guard (200...299).contains(response.statusCode) else {
            throw Self.mapError(status: response.statusCode, data: data)
        }
        return (data, response)
    }

    private func decodeData<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(APIResponse<T>.self, from: data).data
        } catch {
            throw ContractServiceError.unknown
        }
    }

    // MARK: Pure helpers (unit tested)

    /// Query of `GET /v1/leases/:id/contract/preview`.
    static func previewQuery(format: ContractFormat, request: ContractRequest) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "format", value: format.rawValue)]
        if let templateId = request.templateId, !templateId.isEmpty {
            items.append(URLQueryItem(name: "template_id", value: templateId))
        }
        if let date = request.contractDate, !date.isEmpty {
            items.append(URLQueryItem(name: "contract_date", value: date))
        }
        let act = request.act.normalized
        if !act.meterElectricity.isEmpty { items.append(URLQueryItem(name: "meter_electricity", value: act.meterElectricity)) }
        if !act.meterWater.isEmpty { items.append(URLQueryItem(name: "meter_water", value: act.meterWater)) }
        if !act.inventory.isEmpty { items.append(URLQueryItem(name: "inventory", value: act.inventory.joined(separator: ","))) }
        if let keys = act.keysCount { items.append(URLQueryItem(name: "keys_count", value: String(keys))) }
        return items
    }

    /// Maps a non-2xx answer to a failure: `{"error": {code, message, details}}`, else the status.
    static func mapError(status: Int, data: Data) -> ContractServiceError {
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let error = root?["error"] as? [String: Any]
        let code = error?["code"] as? String
        let message = error?["message"] as? String

        switch (status, code) {
        case (_, "CONTRACT_DATA_INCOMPLETE"):
            if let envelope = try? JSONDecoder().decode(ContractErrorEnvelope.self, from: data),
               let fields = envelope.error.details?.fields {
                return .incomplete(fields)
            }
            return .incomplete([])
        case (_, "TEMPLATE_INVALID"):
            let details = (try? JSONDecoder().decode(ContractErrorEnvelope.self, from: data))?.error.details
            return .templateInvalid(
                reason: details?.reason,
                unknownPlaceholders: details?.unknownPlaceholders ?? [],
                splitPlaceholders: details?.splitPlaceholders ?? []
            )
        case (_, "PDF_CONVERSION_UNAVAILABLE"):
            return .pdfUnavailable
        case (_, "PDF_CONVERSION_FAILED"):
            return .pdfFailed
        case (_, "INVALID_STATE_TRANSITION"):
            return .invalidState
        case (401, _):
            return .unauthorized
        case (404, _):
            return .notFound
        case (501, _):
            return .pdfUnavailable
        case (502, _):
            return .pdfFailed
        case (412, _), (409, _):
            return .conflict(message: message ?? "Данные изменились. Повторите.")
        case (400, _), (422, _):
            return .validation(message: validationText(error: error, fallback: message))
        case (500..., _):
            return .transport
        default:
            return .unknown
        }
    }

    /// `details` of a 400 is a list of `{field, message}`; join them to one line.
    private static func validationText(error: [String: Any]?, fallback: String?) -> String {
        if let list = error?["details"] as? [[String: Any]] {
            let lines = list.compactMap { item -> String? in
                guard let text = item["message"] as? String else { return nil }
                if let field = item["field"] as? String { return "\(field): \(text)" }
                return text
            }
            if !lines.isEmpty { return lines.joined(separator: "; ") }
        }
        return fallback ?? "Проверьте введённые данные."
    }

    private static func file(data: Data, response: HTTPURLResponse, fallbackName: String, format: ContractFormat) -> ContractFile {
        let name = filename(fromContentDisposition: response.value(forHTTPHeaderField: "Content-Disposition")) ?? fallbackName
        let mime = response.value(forHTTPHeaderField: "Content-Type")?
            .split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? format.mimeType
        return ContractFile(data: data, filename: name, mimeType: mime)
    }

    /// `filename*=UTF-8''<percent-encoded>` wins over `filename="<ascii>"`.
    static func filename(fromContentDisposition header: String?) -> String? {
        guard let header else { return nil }
        let parts = header.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        if let star = parts.first(where: { $0.lowercased().hasPrefix("filename*=") }) {
            var value = String(star.dropFirst("filename*=".count))
            if let range = value.range(of: "''") { value = String(value[range.upperBound...]) }
            if let decoded = value.removingPercentEncoding, !decoded.isEmpty { return Self.safeFilename(decoded) }
        }
        if let plain = parts.first(where: { $0.lowercased().hasPrefix("filename=") }) {
            let value = String(plain.dropFirst("filename=".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !value.isEmpty { return Self.safeFilename(value) }
        }
        return nil
    }

    /// A name from the network is used as a file name in the temp folder: no path parts.
    static func safeFilename(_ name: String) -> String {
        let base = name.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? name
        let cleaned = base.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty || cleaned == ".." || cleaned == "." ? "dokument" : cleaned
    }

    static func multipartBody(
        boundary: String,
        fields: [(String, String)],
        fileField: String,
        fileName: String,
        mimeType: String,
        fileData: Data
    ) -> Data {
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        for (key, value) in fields {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n")
        }
        let escapedName = fileName.replacingOccurrences(of: "\"", with: "_")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(escapedName)\"\r\nContent-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")
        return body
    }
}
