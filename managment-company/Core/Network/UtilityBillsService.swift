import Foundation

// Utility bills v2 (docs/architecture/utilities-v2.md §6, ai/context/utility-bills-api.md): the
// service seam of the grid, the review sheet, the upload flow and the property settings. Live over
// `APIClient`, Mock over the contract fixtures (the same pattern as `RecognitionService`).

/// What an upload is about: the bill it belongs to, or the property and month, and the role of the file.
nonisolated struct UtilityUploadTarget: Equatable {
    var propertyId: String?
    var period: String?
    var billId: String?
    var role: UtilityFileRole?

    init(propertyId: String? = nil, period: String? = nil, billId: String? = nil, role: UtilityFileRole? = nil) {
        self.propertyId = propertyId
        self.period = period
        self.billId = billId
        self.role = role
    }

    /// Multipart text fields; only what is given.
    var fields: [String: String] {
        var out: [String: String] = [:]
        if let propertyId, !propertyId.isEmpty { out["property_id"] = propertyId }
        if let period, !period.isEmpty { out["period"] = period }
        if let billId, !billId.isEmpty { out["bill_id"] = billId }
        if let role { out["role"] = role.rawValue }
        return out
    }
}

/// A page of the review inbox (`{data, page, per_page, total}`).
struct UtilityInboxPage: Equatable {
    var entries: [UtilityInboxEntry]
    var page: Int
    var perPage: Int
    var total: Int
}

nonisolated struct UtilityFieldError: Equatable {
    var field: String?
    var message: String
}

/// Failures of the utility endpoints, by `error.code` first and by HTTP status second.
enum UtilityBillsError: Error, Equatable {
    /// `404`: not found, or not the owner's.
    case notFound
    /// `400 VALIDATION_ERROR` and `422` on the settings: `fields` are `details[]`.
    case validation(fields: [UtilityFieldError])
    /// `409 BILL_EXISTS`: the property already has a bill for the month.
    case billExists(billId: String?)
    /// `409 INVALID_STATE_TRANSITION`: the status does not allow the action (the screen is stale).
    case invalidTransition
    /// `409 FILE_ALREADY_ATTACHED`: the same file is on another bill.
    case fileAlreadyAttached
    /// `422 BILL_INCOMPLETE`: `details.missing` (`property`, `currency`, `items`, ...).
    case incomplete(missing: [String])
    /// `429 RECOGNITION_QUOTA_EXCEEDED`.
    case quotaExceeded(limit: Int?)
    /// Other `409`s with a code of their own (`ACCOUNT_EXISTS`, `ACCOUNT_NUMBER_IN_USE`, `EXPECTATION_OVERLAP`, ...).
    case conflict(code: String)
    /// `410 GONE`: a retired v1 endpoint.
    case gone
    case unauthorized
    case transport
    case unknown

    /// Message for a screen banner or an alert.
    var userMessage: String {
        switch self {
        case .notFound:
            return "Счёт не найден. Возможно, он уже удалён."
        case .validation(let fields):
            if let first = fields.first(where: { !$0.message.isEmpty }) {
                return Self.validationText(field: first.field, message: first.message)
            }
            return "Проверьте введённые данные."
        case .billExists:
            return "За этот месяц у объекта уже есть счёт."
        case .invalidTransition:
            return "Статус счёта изменился. Обновите экран и повторите."
        case .fileAlreadyAttached:
            return "Этот файл уже прикреплён к другому счёту."
        case .incomplete(let missing):
            return Self.incompleteText(missing)
        case .quotaExceeded:
            return "Дневной лимит распознавания исчерпан. Введите счёт вручную или загрузите файл завтра."
        case .conflict(let code):
            switch code {
            case "ACCOUNT_EXISTS": return "У объекта уже есть лицевой счёт."
            case "ACCOUNT_NUMBER_IN_USE": return "Этот лицевой счёт уже указан у другого объекта."
            case "EXPECTATION_OVERLAP": return "Правило пересекается с уже существующим."
            case "PROPERTY_REQUIRED": return "Сначала выберите объект."
            default: return "Действие конфликтует с текущими данными."
            }
        case .gone:
            return "Эта версия приложения больше не поддерживает действие. Обновите приложение."
        case .unauthorized:
            return "Сессия истекла. Войдите снова."
        case .transport:
            return "Нет связи с сервером. Повторите позже."
        case .unknown:
            return "Не удалось выполнить действие."
        }
    }

    private static func incompleteText(_ missing: [String]) -> String {
        let names: [String: String] = [
            "property": "объект",
            "currency": "валюту",
            "items": "хотя бы одну строку",
            "paid_at": "дату оплаты",
            "payment_proof_or_no_receipt": "подтверждение оплаты",
        ]
        let list = missing.map { names[$0] ?? $0 }
        guard !list.isEmpty else { return "Счёт заполнен не полностью." }
        return "Чтобы подтвердить, укажите: " + list.joined(separator: ", ") + "."
    }

    private static func validationText(field: String?, message: String) -> String {
        let names: [String: String] = [
            "period": "Период",
            "currency": "Валюта",
            "paid_at": "Дата оплаты",
            "issued_at": "Дата квитанции",
            "total_due": "Сумма к оплате",
            "total_paid": "Сумма оплаты",
            "account_number": "Лицевой счёт",
            "file": "Файл",
        ]
        if let field, let name = names[field] { return "\(name): проверьте значение." }
        if let field, field.hasPrefix("items") { return "Проверьте строки счёта: у каждой нужны услуга и сумма." }
        if message == "cannot be in the future" { return "Дата оплаты не может быть в будущем." }
        return "Проверьте введённые данные."
    }

    /// The upload endpoint answers a wrong file with `file`; its text is more precise.
    var isFileProblem: Bool {
        if case .validation(let fields) = self { return fields.contains(where: { $0.field == "file" }) }
        return false
    }
}

/// What the utility screens need from the API.
protocol UtilityBillsService {
    // Catalogue and reads.
    func meta() async throws -> UtilityMeta
    func grid(year: Int, propertyId: String?) async throws -> UtilityGrid
    func inbox(page: Int, perPage: Int) async throws -> UtilityInboxPage
    func bill(id: String) async throws -> UtilityBill
    func comparison(year: Int, propertyId: String?) async throws -> UtilityComparison
    /// `utility_payer` of a property (`GET /v1/properties/:id`), `nil` when the answer has none.
    func propertyPayer(propertyId: String) async throws -> UtilityPayer?

    // Commands on a bill.
    func createBill(_ body: UtilityBillCreate) async throws -> UtilityBill
    func patchBill(id: String, _ patch: UtilityBillPatch) async throws -> UtilityBill
    func confirm(id: String) async throws -> UtilityBill
    func markPaid(id: String, _ body: UtilityMarkPaid) async throws -> UtilityBill
    func unmarkPaid(id: String) async throws -> UtilityBill
    func deleteBill(id: String) async throws
    func tenantMessage(id: String) async throws -> UtilityTenantMessage
    func reextract(id: String) async throws -> UtilityUploadResult

    // Uploads.
    func upload(_ upload: RecognitionUpload, target: UtilityUploadTarget) async throws -> UtilityUploadResult
    func uploadState(id: String) async throws -> UtilityUploadState
    func rejectUpload(id: String) async throws -> UtilityUploadState

    // The account and the expectation rules of a property.
    func account(propertyId: String) async throws -> UtilityAccount?
    func saveAccount(propertyId: String, existing: UtilityAccount?, input: UtilityAccountInput) async throws -> UtilityAccount
    func deleteAccount(propertyId: String, id: String) async throws
    func expectations(propertyId: String) async throws -> [UtilityExpectation]
    func saveExpectation(propertyId: String, existing: UtilityExpectation?, input: UtilityExpectationInput) async throws -> UtilityExpectation
    func deleteExpectation(propertyId: String, id: String) async throws
}

/// Picks the service: the live one by default; the fixture-backed mock when the utility screens run
/// on mocks (`UTILITY_BILLS_MOCKS=1`, launch argument `-utility_bills_mocks 1`) or the lease screens
/// do (`LEASE_V2_MOCKS=1`), so one switch makes the whole app demo-able without a server.
@MainActor
enum UtilityBillsServiceProvider {
    static var useMocks: Bool = {
        ProcessInfo.processInfo.environment["UTILITY_BILLS_MOCKS"] == "1"
            || UserDefaults.standard.bool(forKey: "utility_bills_mocks")
    }()

    private static var sharedMock: MockUtilityBillsService?

    static var isMocked: Bool { useMocks || LeaseV2ServiceProvider.useMocks }

    static func makeService(authManager: AuthManager) -> UtilityBillsService {
        if isMocked { return mock() }
        return LiveUtilityBillsService(authManager: authManager)
    }

    /// One mock for the whole process: the grid, the sheet and the inbox see the same bills.
    static func mock() -> MockUtilityBillsService {
        if let sharedMock { return sharedMock }
        let mock = MockUtilityBillsService.fromFixtures(latency: .milliseconds(250))
        sharedMock = mock
        return mock
    }

    static func resetMock() {
        sharedMock = nil
    }
}
