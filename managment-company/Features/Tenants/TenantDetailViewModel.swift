import Combine
import Foundation

/// Request body of `POST /v1/tenants` and `PUT /v1/tenants/:id`.
///
/// The server replaces the whole record on `PUT`: a key that is missing clears the stored value.
/// So the body always carries every field, including the T1 identity ones, filled from what the
/// user sees on the form (which starts from the stored record).
struct TenantUpsertBody: Encodable, Equatable {
    let firstName: String
    let lastName: String?
    let phone: String?
    let email: String?
    let cohabitants: String?
    let notes: String?
    let middleName: String?
    let iin: String?
    let documentType: String?
    let documentNumber: String?
    let documentIssuedBy: String?
    let documentIssuedAt: String?
    let birthDate: String?
    let registrationAddress: String?

    enum CodingKeys: String, CodingKey {
        case phone, email, cohabitants, notes, iin
        case firstName = "first_name"
        case lastName = "last_name"
        case middleName = "middle_name"
        case documentType = "document_type"
        case documentNumber = "document_number"
        case documentIssuedBy = "document_issued_by"
        case documentIssuedAt = "document_issued_at"
        case birthDate = "birth_date"
        case registrationAddress = "registration_address"
    }
}

/// Document kinds accepted by the API (`document_type`).
enum TenantDocumentType: String, CaseIterable, Identifiable {
    case idCard = "id_card"
    case passport
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .idCard: return "Удостоверение личности"
        case .passport: return "Паспорт"
        case .other: return "Другой документ"
        }
    }

    static func title(for raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return TenantDocumentType(rawValue: raw)?.title ?? raw
    }
}

/// Text state of the tenant form. Starts from the stored `Tenant` and turns back into a
/// `TenantUpsertBody` that keeps every field the user did not touch.
struct TenantEditForm: Equatable {
    var firstName = ""
    var lastName = ""
    var middleName = ""
    var phone = ""
    var email = ""
    var cohabitants = ""
    var notes = ""
    var iin = ""
    var documentType = ""
    var documentNumber = ""
    var documentIssuedBy = ""
    var documentIssuedAt = ""
    var birthDate = ""
    var registrationAddress = ""

    init() {}

    init(tenant: Tenant?) {
        guard let tenant else { return }
        firstName = tenant.firstName
        lastName = tenant.lastName ?? ""
        middleName = tenant.middleName ?? ""
        phone = tenant.phone ?? ""
        email = tenant.email ?? ""
        cohabitants = tenant.cohabitants ?? ""
        notes = tenant.notes ?? ""
        iin = tenant.iin ?? ""
        documentType = tenant.documentType ?? ""
        documentNumber = tenant.documentNumber ?? ""
        documentIssuedBy = tenant.documentIssuedBy ?? ""
        documentIssuedAt = tenant.documentIssuedAt.map { String($0.prefix(10)) } ?? ""
        birthDate = tenant.birthDate.map { String($0.prefix(10)) } ?? ""
        registrationAddress = tenant.registrationAddress ?? ""
    }

    var canSubmit: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func body() -> TenantUpsertBody {
        TenantUpsertBody(
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: Self.optional(lastName),
            phone: Self.optional(phone),
            email: Self.optional(email),
            cohabitants: Self.optional(cohabitants),
            notes: Self.optional(notes),
            middleName: Self.optional(middleName),
            iin: Self.optional(iin),
            documentType: Self.optional(documentType),
            documentNumber: Self.optional(documentNumber),
            documentIssuedBy: Self.optional(documentIssuedBy),
            documentIssuedAt: Self.optional(documentIssuedAt),
            birthDate: Self.optional(birthDate),
            registrationAddress: Self.optional(registrationAddress)
        )
    }

    private static func optional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Everything the tenant screens need from the API.
protocol TenantClient {
    func fetchOverview(tenantId: String, months: Int) async throws -> TenantOverview
    func fetchTenant(id: String) async throws -> Tenant
    /// `id == nil` creates (`POST`), otherwise replaces (`PUT`).
    func saveTenant(id: String?, body: TenantUpsertBody) async throws -> Tenant
    func deleteTenant(id: String) async throws
}

struct LiveTenantClient: TenantClient {
    let authManager: AuthManager

    func fetchOverview(tenantId: String, months: Int) async throws -> TenantOverview {
        try await APIClient.shared.request(
            "/v1/tenants/\(tenantId)/overview?months=\(months)",
            tokenProvider: { await MainActor.run { authManager.accessToken } },
            refreshAndRetry: { await authManager.refreshToken() }
        )
    }

    func fetchTenant(id: String) async throws -> Tenant {
        try await APIClient.shared.request(
            "/v1/tenants/\(id)",
            tokenProvider: { await MainActor.run { authManager.accessToken } },
            refreshAndRetry: { await authManager.refreshToken() }
        )
    }

    func saveTenant(id: String?, body: TenantUpsertBody) async throws -> Tenant {
        try await APIClient.shared.request(
            id.map { "/v1/tenants/\($0)" } ?? "/v1/tenants",
            method: id == nil ? "POST" : "PUT",
            body: body,
            typedErrors: true,
            tokenProvider: { await MainActor.run { authManager.accessToken } },
            refreshAndRetry: { await authManager.refreshToken() }
        )
    }

    func deleteTenant(id: String) async throws {
        _ = try await APIClient.shared.requestData(
            "/v1/tenants/\(id)",
            method: "DELETE",
            tokenProvider: { await MainActor.run { authManager.accessToken } },
            refreshAndRetry: { await authManager.refreshToken() }
        )
    }
}

enum TenantDetailState: Equatable {
    case loading
    case loaded(TenantOverview)
    case error(String)
}

/// One calendar month row of the tenant screen.
struct TenantMonthRow: Identifiable, Equatable {
    let month: TenantMonth
    var id: String { "\(month.period)-\(month.leaseId ?? "none")" }
}

/// State of `TenantDetailView`: the overview (`GET /v1/tenants/:id/overview`) plus the full
/// stored record used for editing.
@MainActor
final class TenantDetailViewModel: ObservableObject {
    /// Window of the overview request: this many months back through three months ahead.
    static let overviewMonths = 12

    @Published private(set) var state: TenantDetailState = .loading
    /// Full record (`GET /v1/tenants/:id`): carries `document_issued_by/at`, which the overview
    /// profile does not.
    @Published private(set) var tenant: Tenant?
    @Published private(set) var isDeleting = false
    /// Non-blocking problem while a screen is already showing data.
    @Published var banner: String?

    let tenantId: String
    private let client: TenantClient

    init(tenantId: String, client: TenantClient) {
        self.tenantId = tenantId
        self.client = client
    }

    var overview: TenantOverview? {
        if case .loaded(let overview) = state { return overview }
        return nil
    }

    func load() async {
        banner = nil
        if overview == nil { state = .loading }
        do {
            state = .loaded(try await client.fetchOverview(tenantId: tenantId, months: Self.overviewMonths))
        } catch {
            if overview == nil {
                state = .error("Не удалось загрузить арендатора.")
            } else {
                banner = "Не удалось обновить данные арендатора."
            }
            return
        }
        tenant = try? await client.fetchTenant(id: tenantId)
    }

    /// The record to put on the edit form: always re-read, so the `PUT` that follows starts
    /// from what the server stores right now.
    func tenantForEditing() async -> Tenant? {
        if let fresh = try? await client.fetchTenant(id: tenantId) {
            tenant = fresh
            return fresh
        }
        banner = "Не удалось открыть редактирование. Повторите."
        return nil
    }

    // MARK: Derived data

    /// Leases the tenant has now (`active`), counted from the overview cards.
    var activeLeaseCount: Int {
        overview?.leases.filter { $0.status == .active }.count ?? 0
    }

    /// Lease cards newest first as the API sends them, current lease excluded.
    var historyLeases: [LeaseCard] {
        guard let overview else { return [] }
        let currentId = overview.currentLease?.id
        return overview.leases.filter { $0.id != currentId }
    }

    /// Months that carry charges, newest first.
    var monthRows: [TenantMonthRow] {
        guard let overview else { return [] }
        return overview.months
            .filter { $0.status != .noCharges }
            .sorted { $0.period > $1.period }
            .map(TenantMonthRow.init)
    }

    /// Totals of the currency of the current lease, else the first one.
    var primaryTotals: TenantTotals? {
        guard let overview else { return nil }
        if let currency = overview.currentLease?.balance.currency,
           let match = overview.totals.first(where: { $0.currency == currency }) {
            return match
        }
        return overview.totals.first
    }

    var displayName: String {
        overview?.tenant.fullName ?? tenant?.displayName ?? "Арендатор"
    }

    // MARK: Commands

    func delete() async -> Bool {
        guard !isDeleting else { return false }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await client.deleteTenant(id: tenantId)
            return true
        } catch {
            banner = "Не удалось удалить арендатора."
            return false
        }
    }
}

/// State of `TenantFormSheet`.
@MainActor
final class TenantEditViewModel: ObservableObject {
    @Published var form: TenantEditForm
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?

    let tenantId: String?

    init(tenant: Tenant?) {
        self.tenantId = tenant?.id
        self.form = TenantEditForm(tenant: tenant)
    }

    /// Saves the form; `true` when the server accepted it.
    func save(client: TenantClient) async -> Bool {
        guard form.canSubmit, !isSaving else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            _ = try await client.saveTenant(id: tenantId, body: form.body())
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    /// Russian message for a failed save, by the field the server complains about.
    static func message(for error: Error) -> String {
        guard let api = error as? APIError else { return "Не удалось сохранить арендатора." }
        switch api {
        case .server(let status, let body):
            if status == 409 { return "Арендатор с таким ИИН уже есть." }
            if status == 400 || status == 422 {
                if let field = body.firstFieldError?.field {
                    switch field {
                    case "iin": return "Проверьте ИИН: 12 цифр с верной контрольной суммой."
                    case "document_type": return "Выберите тип документа из списка."
                    case "birth_date": return "Проверьте дату рождения."
                    case "document_issued_at": return "Проверьте дату выдачи документа."
                    case "email": return "Проверьте email."
                    default: break
                    }
                }
                return "Проверьте имя, email и данные удостоверения."
            }
            return "Не удалось сохранить арендатора."
        case .httpStatus(let status):
            return status == 400 ? "Проверьте имя, email и данные удостоверения." : "Не удалось сохранить арендатора."
        case .unauthorized:
            return "Сессия истекла. Войдите снова."
        case .invalidResponse:
            return "Не удалось сохранить арендатора."
        }
    }
}
