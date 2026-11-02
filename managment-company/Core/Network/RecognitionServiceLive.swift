import Foundation

/// `RecognitionService` over the real `/v1` API. The upload goes through `APIClient`
/// (`uploadMultipart` with typed errors, so `code` and `details.file_id` of a 502 reach the wizard).
final class LiveRecognitionService: RecognitionService {
    private let authManager: AuthManager

    init(authManager: AuthManager) {
        self.authManager = authManager
    }

    func recognizeIdentityDocument(_ upload: RecognitionUpload, tenantId: String?) async throws -> IdentityRecognitionResult {
        let auth = authManager
        var fields: [String: String] = [:]
        if let tenantId, !tenantId.isEmpty { fields["tenant_id"] = tenantId }
        do {
            return try await APIClient.shared.uploadMultipart(
                "/v1/recognition/identity-document",
                fields: fields,
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

    /// Maps a transport or API failure by `error.code`, else by HTTP status.
    static func map(_ error: Error) -> RecognitionError {
        if let known = error as? RecognitionError { return known }
        if error is DecodingError { return .unknown }
        if let api = error as? APIError {
            switch api {
            case .unauthorized: return .unauthorized
            case .invalidResponse: return .unknown
            case .httpStatus(let status):
                return mapStatus(status, body: nil)
            case .server(let status, let body):
                return mapCode(body, status: status) ?? mapStatus(status, body: body)
            }
        }
        if PendingMutationQueue.isRetryableTransportError(error) { return .transport }
        return .unknown
    }

    private static func mapCode(_ body: APIErrorBody, status: Int) -> RecognitionError? {
        switch body.code {
        case "RECOGNITION_QUOTA_EXCEEDED":
            return .quotaExceeded
        case "RECOGNITION_UNAVAILABLE":
            return unavailable(body)
        case "RECOGNITION_DISABLED":
            return .disabled
        case "NOT_FOUND":
            return .notFound
        case "VALIDATION_ERROR":
            return .validation(message: validationMessage(body))
        case "UNAUTHORIZED":
            return .unauthorized
        case "FORBIDDEN":
            return .forbidden
        default:
            return nil
        }
    }

    private static func mapStatus(_ status: Int, body: APIErrorBody?) -> RecognitionError {
        switch status {
        case 400: return .validation(message: body.map(validationMessage) ?? "Файл не подошёл. Загрузите JPEG, PNG, HEIC или PDF до 10 МБ.")
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 429: return .quotaExceeded
        case 502: return unavailable(body)
        case 503: return .disabled
        case 504: return .unavailable(fileId: nil, extractionId: nil)
        default: return .unknown
        }
    }

    private static func unavailable(_ body: APIErrorBody?) -> RecognitionError {
        .unavailable(fileId: body?.detail("file_id")?.stringValue, extractionId: body?.detail("extraction_id")?.stringValue)
    }

    private static func validationMessage(_ body: APIErrorBody) -> String {
        if let first = body.firstFieldError, !first.message.isEmpty {
            return "Файл не подошёл: \(first.message)"
        }
        return "Файл не подошёл. Загрузите JPEG, PNG, HEIC или PDF до 10 МБ."
    }
}
