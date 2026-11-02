import Foundation

// Identity-document recognition (briefs/_recognition-contract.md): the service seam, the upload
// value and the failures the settle wizard reacts to. Live over `APIClient`, Mock with the
// answer of the contract until the API (T4) is merged.

/// A photo or PDF of an identity document, ready to upload.
struct RecognitionUpload: Equatable {
    var data: Data
    var fileName: String
    var mimeType: String

    /// Limit of the endpoint (`file`, jpeg|png|heic|pdf, up to 10 MB).
    static let maxBytes = 10 * 1024 * 1024
}

/// Failures of `POST /v1/recognition/identity-document`.
enum RecognitionError: Error, Equatable {
    /// `429 RECOGNITION_QUOTA_EXCEEDED`: the daily limit of the user.
    case quotaExceeded
    /// `502 RECOGNITION_UNAVAILABLE`: the provider failed; the photo is saved (`file_id`).
    case unavailable(fileId: String?, extractionId: String?)
    /// `503 RECOGNITION_DISABLED`: no provider configured on this server.
    case disabled
    /// `400 VALIDATION_ERROR`: type, size or no file. `message` is ready for the UI.
    case validation(message: String)
    /// `404 NOT_FOUND`: the `tenant_id` is not the owner's.
    case notFound
    /// `403`: a token that may not recognise (assistant scope).
    case forbidden
    case unauthorized
    case transport
    case unknown

    /// The photo the server kept, when it kept one: it still goes to settle.
    var fileId: String? {
        if case .unavailable(let fileId, _) = self { return fileId }
        return nil
    }

    /// 429, 502 and 503 end in «Заполнить вручную»; the owner can always type the fields.
    var offersManualEntry: Bool {
        switch self {
        case .quotaExceeded, .unavailable, .disabled, .transport: return true
        default: return false
        }
    }

    var userMessage: String {
        switch self {
        case .quotaExceeded: return "Дневной лимит распознавания исчерпан. Заполните данные вручную."
        case .unavailable: return "Не удалось распознать документ. Фото сохранено, заполните данные вручную."
        case .disabled: return "Распознавание на сервере не настроено. Заполните данные вручную."
        case .validation(let message): return message
        case .notFound: return "Арендатор не найден."
        case .forbidden: return "Для этого доступа распознавание недоступно."
        case .unauthorized: return "Сессия истекла. Войдите снова."
        case .transport: return "Нет связи с сервером. Повторите или заполните данные вручную."
        case .unknown: return "Не удалось распознать документ."
        }
    }
}

/// What the settle wizard needs from the recognition API.
protocol RecognitionService {
    /// `POST /v1/recognition/identity-document` (multipart `file`, optional `tenant_id`).
    func recognizeIdentityDocument(_ upload: RecognitionUpload, tenantId: String?) async throws -> IdentityRecognitionResult
}

/// Picks the service: the live one by default; the contract-shaped mock when the lease screens
/// run on mocks (`LEASE_V2_MOCKS=1`) or recognition alone is mocked (`RECOGNITION_MOCKS=1`,
/// launch argument `-recognition_mocks 1`), e.g. while the API route is not deployed.
@MainActor
enum RecognitionServiceProvider {
    static var useMocks: Bool = {
        ProcessInfo.processInfo.environment["RECOGNITION_MOCKS"] == "1"
            || UserDefaults.standard.bool(forKey: "recognition_mocks")
    }()

    static func makeService(authManager: AuthManager) -> RecognitionService {
        if useMocks || LeaseV2ServiceProvider.useMocks {
            return MockRecognitionService.shared
        }
        return LiveRecognitionService(authManager: authManager)
    }
}
