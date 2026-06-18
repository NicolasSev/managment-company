import Combine
import Foundation

/// One row of the cross-portfolio document hub (GAP-044), mirrors the API
/// `FileResponse` from `GET /v1/files`.
struct DocumentFile: Identifiable, Decodable, Equatable {
    let id: String
    let entityType: String
    let entityId: String
    let fileType: String
    let originalName: String?
    let mimeType: String?
    let sizeBytes: Int64?
    let downloadURL: String?
    let contextName: String?
    let propertyId: String?
    let propertyName: String?
    let createdAt: String

    var displayName: String {
        originalName?.trimmingCharacters(in: .whitespaces).isEmpty == false ? originalName! : fileType
    }

    enum CodingKeys: String, CodingKey {
        case id
        case entityType = "entity_type"
        case entityId = "entity_id"
        case fileType = "file_type"
        case originalName = "original_name"
        case mimeType = "mime_type"
        case sizeBytes = "size_bytes"
        case downloadURL = "download_url"
        case contextName = "context_name"
        case propertyId = "property_id"
        case propertyName = "property_name"
        case createdAt = "created_at"
    }
}

@MainActor
protocol DocumentHubClient {
    func fetch(search: String, entityType: String, fileType: String,
               propertyId: String, tenantId: String, dateFrom: String, dateTo: String,
               page: Int, perPage: Int) async throws -> (files: [DocumentFile], total: Int)
    func fetchProperties() async throws -> [Property]
    func fetchTenants() async throws -> [Tenant]
    func delete(id: String) async throws
}

@MainActor
struct LiveDocumentHubClient: DocumentHubClient {
    let authManager: AuthManager
    private var token: () async -> String? { { await MainActor.run { authManager.accessToken } } }
    private var refresh: () async -> Bool { { await authManager.refreshToken() } }

    func fetch(search: String, entityType: String, fileType: String,
               propertyId: String, tenantId: String, dateFrom: String, dateTo: String,
               page: Int, perPage: Int) async throws -> (files: [DocumentFile], total: Int) {
        let path = DocumentHubViewModel.listPath(
            search: search, entityType: entityType, fileType: fileType,
            propertyId: propertyId, tenantId: tenantId, dateFrom: dateFrom, dateTo: dateTo,
            page: page, perPage: perPage
        )
        let envelope: APIListEnvelope<DocumentFile> = try await APIClient.shared.requestRoot(path, tokenProvider: token, refreshAndRetry: refresh)
        return (envelope.data, envelope.total)
    }

    func fetchProperties() async throws -> [Property] {
        try await APIClient.shared.request("/v1/properties", tokenProvider: token, refreshAndRetry: refresh)
    }

    func fetchTenants() async throws -> [Tenant] {
        let envelope: APIListEnvelope<Tenant> = try await APIClient.shared.requestRoot("/v1/tenants?per_page=200", tokenProvider: token, refreshAndRetry: refresh)
        return envelope.data
    }

    func delete(id: String) async throws {
        _ = try await APIClient.shared.requestData("/v1/files/\(id)", method: "DELETE", tokenProvider: token, refreshAndRetry: refresh)
    }
}

/// Searchable cross-portfolio document workspace (GAP-044/GAP-047).
@MainActor
final class DocumentHubViewModel: ObservableObject {
    @Published var search = ""
    @Published var entityTypeFilter = ""
    @Published var fileTypeFilter = ""
    @Published var propertyIdFilter = ""
    @Published var tenantIdFilter = ""
    @Published var dateFromFilter: Date? = nil
    @Published var dateToFilter: Date? = nil
    @Published private(set) var files: [DocumentFile] = []
    @Published private(set) var total = 0
    @Published private(set) var isLoading = false
    @Published private(set) var properties: [Property] = []
    @Published private(set) var tenants: [Tenant] = []
    @Published var errorMessage: String?

    private let client: DocumentHubClient
    private var page = 1
    private let perPage = 50

    init(client: DocumentHubClient) {
        self.client = client
    }

    nonisolated static let entityTypes: [(value: String, label: String)] = [
        ("", "Все"),
        ("property", "Объект"),
        ("tenant", "Арендатор"),
        ("lease", "Договор"),
        ("transaction", "Операция"),
    ]

    var canLoadMore: Bool { files.count < total }

    var hasActiveFilters: Bool {
        !entityTypeFilter.isEmpty || !propertyIdFilter.isEmpty ||
        !tenantIdFilter.isEmpty || dateFromFilter != nil || dateToFilter != nil
    }

    func clearFilters() {
        entityTypeFilter = ""
        propertyIdFilter = ""
        tenantIdFilter = ""
        dateFromFilter = nil
        dateToFilter = nil
    }

    func reload() async {
        page = 1
        await fetch(reset: true)
    }

    func loadMore() async {
        guard canLoadMore, !isLoading else { return }
        page += 1
        await fetch(reset: false)
    }

    func loadFilterOptions() async {
        async let propsResult = try? client.fetchProperties()
        async let tenantsResult = try? client.fetchTenants()
        if let props = await propsResult { properties = props }
        if let ts = await tenantsResult { tenants = ts }
    }

    private func fetch(reset: Bool) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await client.fetch(
                search: search,
                entityType: entityTypeFilter,
                fileType: fileTypeFilter,
                propertyId: propertyIdFilter,
                tenantId: tenantIdFilter,
                dateFrom: Self.isoDate(dateFromFilter),
                dateTo: Self.isoDate(dateToFilter),
                page: page,
                perPage: perPage
            )
            if reset { files = result.files } else { files.append(contentsOf: result.files) }
            total = result.total
        } catch {
            errorMessage = "Не удалось загрузить документы."
        }
    }

    func delete(_ file: DocumentFile) async -> Bool {
        errorMessage = nil
        do {
            try await client.delete(id: file.id)
            await reload()
            return true
        } catch {
            errorMessage = "Не удалось удалить документ."
            return false
        }
    }

    // MARK: - Pure logic (unit-tested)

    /// Builds the canonical paginated list path with optional filters.
    nonisolated static func listPath(search: String, entityType: String, fileType: String,
                                     propertyId: String = "", tenantId: String = "",
                                     dateFrom: String = "", dateTo: String = "",
                                     page: Int, perPage: Int) -> String {
        var query = "page=\(page)&per_page=\(perPage)"
        let trimmedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty {
            let encoded = trimmedSearch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmedSearch
            query += "&search=\(encoded)"
        }
        if !entityType.isEmpty { query += "&entity_type=\(entityType)" }
        if !fileType.isEmpty { query += "&file_type=\(fileType)" }
        if !propertyId.isEmpty { query += "&property_id=\(propertyId)" }
        if !tenantId.isEmpty { query += "&tenant_id=\(tenantId)" }
        if !dateFrom.isEmpty { query += "&date_from=\(dateFrom)" }
        if !dateTo.isEmpty { query += "&date_to=\(dateTo)" }
        return "/v1/files?\(query)"
    }

    nonisolated static func entityTypeLabel(_ type: String) -> String {
        entityTypes.first { $0.value == type }?.label ?? type
    }

    nonisolated private static func isoDate(_ date: Date?) -> String {
        guard let date else { return "" }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: date)
    }
}
