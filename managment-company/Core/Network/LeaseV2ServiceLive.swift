import Foundation

private struct UploadedFileRef: Decodable {
    let id: String
}

/// `LeaseV2Service` over the real `/v1` API (lease-v2 spec §9.1). Default service of the app
/// (`LeaseV2ServiceProvider`); the mock is for previews and tests only.
///
/// - Requests are sent with `typedErrors`, so the v2 error `code` and `details` of spec §11 reach
///   `map(_:)`: `USE_AMENDMENT`, `LEASE_OVERLAP`, `AMOUNT_EXCEEDS_OUTSTANDING`, ... produce precise
///   `LeaseV2Error`s; unknown codes fall back to the HTTP status.
/// - `If-Match: "<version>"` goes out on every `/v1/leases/:id/*` command; the version comes
///   from the aggregate the user saw (`ETag` and `data.version` carry the same number).
/// - `confirm: true` is for assistant-scope tokens only, so it is never sent from the app.
final class LiveLeaseV2Service: LeaseV2Service {
    private let authManager: AuthManager

    init(authManager: AuthManager) {
        self.authManager = authManager
    }

    func fetchLease(id: String) async throws -> LeaseAggregate {
        try await send("/v1/leases/\(id)")
    }

    func markSigned(leaseId: String, version: Int, request: MarkSignedRequest, scan: LeaseScanAttachment?) async throws -> LeaseAggregate {
        var body = request
        if let scan {
            body.signedFileId = try await uploadSignedScan(scan, leaseId: leaseId)
        }
        return try await send("/v1/leases/\(leaseId)/mark-signed", method: "POST", body: body, version: version)
    }

    func activate(leaseId: String, version: Int, request: ActivateLeaseRequest) async throws -> LeaseAggregate {
        try await send("/v1/leases/\(leaseId)/activate", method: "POST", body: request, version: version)
    }

    func cancel(leaseId: String, version: Int, request: CancelLeaseRequest) async throws -> LeaseAggregate {
        try await send("/v1/leases/\(leaseId)/cancel", method: "POST", body: request, version: version)
    }

    func terminate(leaseId: String, version: Int, request: TerminateLeaseRequest) async throws -> LeaseAggregate {
        try await send("/v1/leases/\(leaseId)/terminate", method: "POST", body: request, version: version)
    }

    func amendRent(leaseId: String, version: Int, request: AmendRentRequest) async throws -> LeaseAggregate {
        try await send("/v1/leases/\(leaseId)/amendments", method: "POST", body: request, version: version)
    }

    func addExtraCharge(leaseId: String, version: Int, request: AddExtraChargeRequest, idempotencyKey: String) async throws -> LeaseAggregate {
        let result: LeaseCommandResult = try await sendWrapped(
            "/v1/leases/\(leaseId)/extra-charges",
            method: "POST",
            body: request,
            version: version,
            idempotencyKey: idempotencyKey
        )
        return result.lease
    }

    func payCharge(leaseId: String, chargeId: String, request: PayChargeRequest, idempotencyKey: String) async throws -> LeaseAggregate {
        let result: LeaseCommandResult = try await sendWrapped(
            "/v1/lease-charges/\(chargeId)/payments",
            method: "POST",
            body: request,
            version: nil,
            idempotencyKey: idempotencyKey
        )
        return result.lease
    }

    func returnDeposit(leaseId: String, version: Int, request: ReturnDepositRequest, idempotencyKey: String) async throws -> LeaseAggregate {
        let result: LeaseCommandResult = try await sendWrapped(
            "/v1/leases/\(leaseId)/deposit/return",
            method: "POST",
            body: request,
            version: version,
            idempotencyKey: idempotencyKey
        )
        return result.lease
    }

    func settle(_ request: SettleRequest, idempotencyKey: String) async throws -> SettleResponse {
        do {
            return try await sendWrapped(
                "/v1/workflows/settle",
                method: "POST",
                body: request,
                version: nil,
                idempotencyKey: idempotencyKey,
                mapsErrors: false
            )
        } catch {
            throw Self.mapSettle(error)
        }
    }

    // MARK: Transport

    private func send(
        _ path: String,
        method: String = "GET",
        body: Encodable? = nil,
        version: Int? = nil
    ) async throws -> LeaseAggregate {
        try await sendWrapped(path, method: method, body: body, version: version, idempotencyKey: nil)
    }

    private func sendWrapped<T: Decodable>(
        _ path: String,
        method: String,
        body: Encodable?,
        version: Int?,
        idempotencyKey: String?,
        mapsErrors: Bool = true
    ) async throws -> T {
        let auth = authManager
        do {
            return try await APIClient.shared.request(
                path,
                method: method,
                body: body,
                idempotencyKey: idempotencyKey,
                extraHeaders: version.map { ["If-Match": "\"\($0)\""] } ?? [:],
                typedErrors: true,
                tokenProvider: { await MainActor.run { auth.accessToken } },
                refreshAndRetry: { await auth.refreshToken() }
            )
        } catch {
            if !mapsErrors { throw error }
            throw Self.map(error)
        }
    }

    private func uploadSignedScan(_ scan: LeaseScanAttachment, leaseId: String) async throws -> String {
        let auth = authManager
        do {
            let file: UploadedFileRef = try await APIClient.shared.uploadMultipart(
                "/v1/files",
                fields: [
                    "entity_type": "lease",
                    "entity_id": leaseId,
                    "file_type": "signed_contract",
                ],
                fileFieldName: "file",
                fileData: scan.data,
                fileName: scan.fileName,
                mimeType: scan.mimeType,
                tokenProvider: { await MainActor.run { auth.accessToken } },
                refreshAndRetry: { await auth.refreshToken() }
            )
            return file.id
        } catch {
            throw Self.map(error)
        }
    }

    /// Maps a transport or API failure to `LeaseV2Error`: by `error.code` when the body carried
    /// one (spec §11), else by HTTP status.
    static func map(_ error: Error) -> LeaseV2Error {
        if let known = error as? LeaseV2Error { return known }
        if let api = error as? APIError {
            switch api {
            case .unauthorized: return .unauthorized
            case .invalidResponse: return .unknown
            case .server(let status, let body):
                return mapCode(body, status: status) ?? mapStatus(status)
            case .httpStatus(let code):
                return mapStatus(code)
            }
        }
        if PendingMutationQueue.isRetryableTransportError(error) { return .transport }
        return .unknown
    }

    /// Maps a settle failure: the codes the wizard answers by name, the rest as `LeaseV2Error`.
    static func mapSettle(_ error: Error) -> SettleError {
        if let known = error as? SettleError { return known }
        if case APIError.server(_, let body) = error {
            switch body.code {
            case "TENANT_IIN_CONFLICT":
                return .tenantIINConflict(stored: decode(body.detail("tenant")), provided: providedName(body.detail("provided")))
            case "LEASE_OVERLAP":
                var from: String?
                var to: String?
                if case .object(let range)? = body.detail("conflicting_range") {
                    from = range["from"]?.stringValue
                    to = range["to"]?.stringValue
                }
                return .leaseOverlap(conflictingLeaseId: body.detail("conflicting_lease_id")?.stringValue, from: from, to: to)
            case "TENANT_IDENTITY_INCOMPLETE":
                var missing: [String] = []
                if case .array(let items)? = body.detail("missing") { missing = items.compactMap(\.stringValue) }
                return .identityIncomplete(missing: missing)
            case "REPLACE_TARGET_INVALID":
                return .replaceTargetInvalid
            case "VALIDATION_ERROR":
                if case .array(let items) = body.details {
                    let fields = items.compactMap { item -> SettleFieldError? in
                        guard let field = item["field"]?.stringValue else { return nil }
                        return SettleFieldError(field: field, message: item["message"]?.stringValue ?? "")
                    }
                    if !fields.isEmpty { return .validation(fields: fields) }
                }
            default:
                break
            }
        }
        return .other(map(error))
    }

    private static func decode<T: Decodable>(_ value: JSONValue?) -> T? {
        guard let value, let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func providedName(_ value: JSONValue?) -> SettleProvidedName? {
        guard let value else { return nil }
        return SettleProvidedName(
            firstName: value["first_name"]?.stringValue,
            lastName: value["last_name"]?.stringValue,
            middleName: value["middle_name"]?.stringValue
        )
    }

    static func mapCode(_ body: APIErrorBody, status: Int) -> LeaseV2Error? {
        switch body.code {
        case "VERSION_MISMATCH":
            return .versionMismatch(currentVersion: intDetail(body, "current_version"))
        case "INVALID_STATE_TRANSITION":
            var command = ""
            if case .string(let value)? = body.detail("command") { command = value }
            return .invalidStateTransition(command: command)
        case "VALIDATION_ERROR":
            return .validation(message: "Проверьте введённые данные.")
        case "USE_AMENDMENT":
            return .validation(message: "Условия действующего договора меняются через допсоглашение.")
        case "AMENDMENT_EFFECTIVE_FROM_INVALID":
            return .validation(message: "Дата изменения раньше начала договора.")
        case "LEASE_OVERLAP":
            return .conflict(message: "Договор пересекается по датам с другим договором этого объекта.")
        case "LEASE_HAS_MONEY":
            return .conflict(message: "У договора есть платежи или депозит, его нельзя удалить.")
        case "CONCURRENT_UPDATE":
            return .conflict(message: "Договор обновляется одновременно. Повторите через секунду.")
        case "AMOUNT_EXCEEDS_OUTSTANDING", "CHARGE_NOT_OPEN":
            return .chargeNotPayable
        case "CURRENCY_MISMATCH":
            return .validation(message: "Валюта платежа не совпадает с валютой договора.")
        case "CREDIT_EXCEEDED":
            return .validation(message: "Сумма больше остатка переплаты арендатора.")
        case "DEPOSIT_BALANCE_EXCEEDED":
            return .depositBalanceExceeded(held: nil)
        case "IDEMPOTENCY_KEY_REUSED":
            return .idempotencyKeyReused
        case "TENANT_IDENTITY_INCOMPLETE":
            return .validation(message: "Заполните данные арендатора (ФИО, ИИН, документ, адрес).")
        case "NOT_FOUND":
            return .notFound
        case "UNAUTHORIZED":
            return .unauthorized
        default:
            return nil
        }
    }

    private static func intDetail(_ body: APIErrorBody, _ key: String) -> Int? {
        if case .number(let value)? = body.detail(key) { return Int(value) }
        return nil
    }

    private static func mapStatus(_ code: Int) -> LeaseV2Error {
        switch code {
        case 400: return .validation(message: "Проверьте введённые данные.")
        case 401: return .unauthorized
        case 404: return .notFound
        case 409: return .conflict(message: "Действие конфликтует с текущим состоянием договора.")
        case 412: return .versionMismatch(currentVersion: nil)
        case 422: return .validation(message: "Сервер отклонил действие: проверьте данные и статус договора.")
        case 502, 503, 504: return .transport
        default: return .unknown
        }
    }
}
