import Foundation

private struct UploadedFileRef: Decodable {
    let id: String
}

/// `LeaseV2Service` over the real `/v1` API (lease-v2 spec §9.1). Not used yet: the app runs on
/// `MockLeaseV2Service` until `LeaseV2ServiceProvider.useLiveAPI` is switched on (task L8).
///
/// Notes for L8:
/// - `APIClient` throws `APIError.httpStatus(code)` and drops the body, so the v2 error `code`
///   (spec §11) is not available yet; statuses map to the coarse `LeaseV2Error` cases below.
///   Reading `{error:{code,details}}` from the failed response would let `USE_AMENDMENT`,
///   `LEASE_OVERLAP`, `AMOUNT_EXCEEDS_OUTSTANDING` etc. produce precise messages.
/// - `If-Match: "<version>"` goes out on every `/v1/leases/:id/*` command.
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
        idempotencyKey: String?
    ) async throws -> T {
        let auth = authManager
        do {
            return try await APIClient.shared.request(
                path,
                method: method,
                body: body,
                idempotencyKey: idempotencyKey,
                extraHeaders: version.map { ["If-Match": "\"\($0)\""] } ?? [:],
                tokenProvider: { await MainActor.run { auth.accessToken } },
                refreshAndRetry: { await auth.refreshToken() }
            )
        } catch {
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

    /// Coarse status mapping; see the class note about the missing error body.
    static func map(_ error: Error) -> LeaseV2Error {
        if let known = error as? LeaseV2Error { return known }
        if let api = error as? APIError {
            switch api {
            case .unauthorized: return .unauthorized
            case .invalidResponse: return .unknown
            case .httpStatus(let code):
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
        if PendingMutationQueue.isRetryableTransportError(error) { return .transport }
        return .unknown
    }
}
