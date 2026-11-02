import Foundation

/// `UtilityBillsService` over the real `/v1` API. Every call asks for typed errors, so the
/// `error.code` of the envelope reaches `UtilityBillsError`.
final class LiveUtilityBillsService: UtilityBillsService {
    private let authManager: AuthManager
    private var cachedMeta: UtilityMeta?

    init(authManager: AuthManager) {
        self.authManager = authManager
    }

    // MARK: Reads

    func meta() async throws -> UtilityMeta {
        if let cachedMeta { return cachedMeta }
        let fresh: UtilityMeta = try await send("/v1/utility-bills/meta")
        cachedMeta = fresh
        return fresh
    }

    func grid(year: Int, propertyId: String?) async throws -> UtilityGrid {
        var query = "year=\(year)"
        if let propertyId { query += "&property_id=\(propertyId)" }
        return try await send("/v1/utility-bills/grid?\(query)")
    }

    func inbox(page: Int, perPage: Int) async throws -> UtilityInboxPage {
        let data = try await sendData("/v1/utility-bills/review-inbox?page=\(page)&per_page=\(perPage)")
        do {
            let envelope = try JSONDecoder().decode(APIListEnvelope<UtilityInboxEntry>.self, from: data)
            return UtilityInboxPage(entries: envelope.data, page: envelope.page, perPage: envelope.perPage, total: envelope.total)
        } catch {
            throw Self.map(error)
        }
    }

    func bill(id: String) async throws -> UtilityBill {
        try await send("/v1/utility-bills/\(id)")
    }

    func comparison(year: Int, propertyId: String?) async throws -> UtilityComparison {
        var query = "year=\(year)"
        if let propertyId { query += "&property_id=\(propertyId)" }
        return try await send("/v1/analytics/utilities/comparison?\(query)")
    }

    func propertyPayer(propertyId: String) async throws -> UtilityPayer? {
        let property: Property = try await send("/v1/properties/\(propertyId)")
        return property.utilityPayer
    }

    // MARK: Bill commands

    func createBill(_ body: UtilityBillCreate) async throws -> UtilityBill {
        try await send("/v1/utility-bills", method: "POST", body: body)
    }

    func patchBill(id: String, _ patch: UtilityBillPatch) async throws -> UtilityBill {
        try await send("/v1/utility-bills/\(id)", method: "PATCH", body: patch)
    }

    func confirm(id: String) async throws -> UtilityBill {
        try await send("/v1/utility-bills/\(id)/confirm", method: "POST", body: EmptyJSONBody())
    }

    func markPaid(id: String, _ body: UtilityMarkPaid) async throws -> UtilityBill {
        try await send("/v1/utility-bills/\(id)/mark-paid", method: "POST", body: body)
    }

    func unmarkPaid(id: String) async throws -> UtilityBill {
        try await send("/v1/utility-bills/\(id)/unmark-paid", method: "POST", body: EmptyJSONBody())
    }

    func deleteBill(id: String) async throws {
        _ = try await sendData("/v1/utility-bills/\(id)", method: "DELETE")
    }

    func tenantMessage(id: String) async throws -> UtilityTenantMessage {
        try await send("/v1/utility-bills/\(id)/tenant-message?lang=ru")
    }

    func reextract(id: String) async throws -> UtilityUploadResult {
        try await send("/v1/utility-bills/\(id)/reextract", method: "POST", body: EmptyJSONBody())
    }

    // MARK: Uploads

    func upload(_ upload: RecognitionUpload, target: UtilityUploadTarget) async throws -> UtilityUploadResult {
        let auth = authManager
        do {
            return try await APIClient.shared.uploadMultipart(
                "/v1/utility-bills/uploads",
                fields: target.fields,
                fileFieldName: "file",
                fileData: upload.data,
                fileName: upload.fileName,
                mimeType: upload.mimeType,
                typedErrors: true,
                tokenProvider: { await MainActor.run { auth.accessToken } },
                refreshAndRetry: { await auth.refreshToken() }
            )
        } catch {
            throw Self.map(error)
        }
    }

    func uploadState(id: String) async throws -> UtilityUploadState {
        try await send("/v1/utility-bills/uploads/\(id)")
    }

    func rejectUpload(id: String) async throws -> UtilityUploadState {
        try await send("/v1/utility-bills/uploads/\(id)/reject", method: "POST", body: EmptyJSONBody())
    }

    // MARK: Account and expectations

    func account(propertyId: String) async throws -> UtilityAccount? {
        let data = try await sendData("/v1/properties/\(propertyId)/utility-accounts")
        do {
            let envelope = try JSONDecoder().decode(APIListEnvelope<UtilityAccount>.self, from: data)
            return envelope.data.first(where: { $0.isDefault && $0.isActive }) ?? envelope.data.first
        } catch {
            throw Self.map(error)
        }
    }

    func saveAccount(propertyId: String, existing: UtilityAccount?, input: UtilityAccountInput) async throws -> UtilityAccount {
        if let existing {
            return try await send("/v1/properties/\(propertyId)/utility-accounts/\(existing.id)", method: "PATCH", body: input)
        }
        return try await send("/v1/properties/\(propertyId)/utility-accounts", method: "POST", body: input)
    }

    func deleteAccount(propertyId: String, id: String) async throws {
        _ = try await sendData("/v1/properties/\(propertyId)/utility-accounts/\(id)", method: "DELETE")
    }

    func expectations(propertyId: String) async throws -> [UtilityExpectation] {
        let data = try await sendData("/v1/properties/\(propertyId)/utility-expectations")
        do {
            return try JSONDecoder().decode(APIListEnvelope<UtilityExpectation>.self, from: data).data
        } catch {
            throw Self.map(error)
        }
    }

    func saveExpectation(propertyId: String, existing: UtilityExpectation?, input: UtilityExpectationInput) async throws -> UtilityExpectation {
        if let existing {
            return try await send("/v1/properties/\(propertyId)/utility-expectations/\(existing.id)", method: "PATCH", body: input)
        }
        return try await send("/v1/properties/\(propertyId)/utility-expectations", method: "POST", body: input)
    }

    func deleteExpectation(propertyId: String, id: String) async throws {
        _ = try await sendData("/v1/properties/\(propertyId)/utility-expectations/\(id)", method: "DELETE")
    }

    // MARK: Transport

    private func send<T: Decodable>(_ path: String, method: String = "GET", body: Encodable? = nil) async throws -> T {
        let auth = authManager
        do {
            return try await APIClient.shared.request(
                path,
                method: method,
                body: body,
                typedErrors: true,
                tokenProvider: { await MainActor.run { auth.accessToken } },
                refreshAndRetry: { await auth.refreshToken() }
            )
        } catch {
            throw Self.map(error)
        }
    }

    private func sendData(_ path: String, method: String = "GET") async throws -> Data {
        let auth = authManager
        do {
            return try await APIClient.shared.requestData(
                path,
                method: method,
                typedErrors: true,
                tokenProvider: { await MainActor.run { auth.accessToken } },
                refreshAndRetry: { await auth.refreshToken() }
            )
        } catch {
            throw Self.map(error)
        }
    }

    /// Maps a transport or API failure by `error.code`, else by HTTP status.
    static func map(_ error: Error) -> UtilityBillsError {
        if let known = error as? UtilityBillsError { return known }
        if error is DecodingError { return .unknown }
        if let api = error as? APIError {
            switch api {
            case .unauthorized: return .unauthorized
            case .invalidResponse: return .unknown
            case .httpStatus(let status): return mapStatus(status, body: nil)
            case .server(let status, let body): return mapCode(body) ?? mapStatus(status, body: body)
            }
        }
        if PendingMutationQueue.isRetryableTransportError(error) { return .transport }
        return .unknown
    }

    private static func mapCode(_ body: APIErrorBody) -> UtilityBillsError? {
        switch body.code {
        case "NOT_FOUND": return .notFound
        case "VALIDATION_ERROR": return .validation(fields: fieldErrors(body))
        case "BILL_EXISTS": return .billExists(billId: body.detail("bill_id")?.stringValue)
        case "INVALID_STATE_TRANSITION": return .invalidTransition
        case "FILE_ALREADY_ATTACHED": return .fileAlreadyAttached
        case "BILL_INCOMPLETE": return .incomplete(missing: strings(body.detail("missing")))
        case "RECOGNITION_QUOTA_EXCEEDED":
            return .quotaExceeded(limit: body.detail("limit")?.doubleValue.map { Int($0) })
        case "ACCOUNT_EXISTS", "ACCOUNT_NUMBER_IN_USE", "EXPECTATION_OVERLAP", "PROPERTY_REQUIRED":
            return .conflict(code: body.code)
        case "GONE": return .gone
        case "UNAUTHORIZED": return .unauthorized
        default: return nil
        }
    }

    private static func mapStatus(_ status: Int, body: APIErrorBody?) -> UtilityBillsError {
        switch status {
        case 400, 422: return .validation(fields: body.map(fieldErrors) ?? [])
        case 401: return .unauthorized
        case 404: return .notFound
        case 409: return body.map { .conflict(code: $0.code) } ?? .invalidTransition
        case 410: return .gone
        case 429: return .quotaExceeded(limit: nil)
        default: return .unknown
        }
    }

    /// `details: [{field, message}]` of a validation answer (the settings answer carries `tag`).
    private static func fieldErrors(_ body: APIErrorBody) -> [UtilityFieldError] {
        guard case .array(let items) = body.details else {
            return [UtilityFieldError(field: nil, message: body.message ?? "")]
        }
        return items.compactMap { item in
            guard case .object(let object) = item else { return nil }
            let message = object["message"]?.stringValue ?? object["tag"]?.stringValue ?? ""
            return UtilityFieldError(field: object["field"]?.stringValue, message: message)
        }
    }

    private static func strings(_ value: JSONValue?) -> [String] {
        guard case .array(let items)? = value else { return [] }
        return items.compactMap(\.stringValue)
    }
}
