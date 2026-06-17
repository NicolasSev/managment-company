import Combine
import Foundation

/// Entity a quick-uploaded document can attach to (GAP-036). Mirrors the web
/// quick-document dialog targets (lease documents attach to their property).
enum DocumentTargetType: String, CaseIterable, Identifiable {
    case property
    case tenant
    case transaction

    var id: String { rawValue }

    var title: String {
        switch self {
        case .property: return "Объект"
        case .tenant: return "Арендатор"
        case .transaction: return "Операция"
        }
    }

    /// `entity_type` value for `POST /v1/files`.
    var apiEntityType: String { rawValue }
}

/// A selectable upload target row.
struct DocumentTargetItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
}

@MainActor
protocol QuickDocumentClient {
    func fetchProperties() async throws -> [Property]
    func fetchTenants() async throws -> [Tenant]
    func fetchTransactions(propertyIds: [String]) async throws -> [Transaction]
    func upload(entityType: String, entityId: String, fileType: String, fileData: Data, fileName: String, mimeType: String) async throws
}

@MainActor
struct LiveQuickDocumentClient: QuickDocumentClient {
    let authManager: AuthManager

    private var token: () async -> String? { { await MainActor.run { authManager.accessToken } } }
    private var refresh: () async -> Bool { { await authManager.refreshToken() } }

    private struct UploadedFile: Decodable { let id: String }

    func fetchProperties() async throws -> [Property] {
        try await APIClient.shared.request("/v1/properties", tokenProvider: token, refreshAndRetry: refresh)
    }

    func fetchTenants() async throws -> [Tenant] {
        try await APIClient.shared.request("/v1/tenants?per_page=100", tokenProvider: token, refreshAndRetry: refresh)
    }

    func fetchTransactions(propertyIds: [String]) async throws -> [Transaction] {
        var merged: [Transaction] = []
        for id in propertyIds.prefix(20) {
            if let rows: [Transaction] = try? await APIClient.shared.request(
                "/v1/properties/\(id)/transactions?per_page=20",
                tokenProvider: token,
                refreshAndRetry: refresh
            ) {
                merged.append(contentsOf: rows)
            }
        }
        return merged
    }

    func upload(entityType: String, entityId: String, fileType: String, fileData: Data, fileName: String, mimeType: String) async throws {
        _ = try await APIClient.shared.uploadMultipart(
            "/v1/files",
            fields: ["entity_type": entityType, "entity_id": entityId, "file_type": fileType],
            fileFieldName: "file",
            fileData: fileData,
            fileName: fileName,
            mimeType: mimeType,
            tokenProvider: token,
            refreshAndRetry: refresh
        ) as UploadedFile
    }
}

/// Drives the global quick-document upload (GAP-036): pick a target type, search
/// and select the entity, choose a file type, then upload — at most two
/// transitions before file selection.
@MainActor
final class QuickDocumentViewModel: ObservableObject {
    @Published var targetType: DocumentTargetType = .property {
        didSet { if targetType != oldValue { selectedEntityId = nil; Task { await loadTargets() } } }
    }
    @Published var searchText = ""
    @Published var selectedEntityId: String?
    @Published var fileType: String = "document"
    @Published private(set) var items: [DocumentTargetItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isUploading = false
    @Published var errorMessage: String?
    @Published private(set) var didUpload = false

    static let fileTypes: [(value: String, label: String)] = [
        ("document", "Документ"),
        ("contract", "Договор"),
        ("photo", "Фото"),
        ("other", "Другое"),
    ]

    private let client: QuickDocumentClient
    private var properties: [Property] = []
    private var tenants: [Tenant] = []
    private var transactions: [Transaction] = []
    private let contextPropertyId: String?

    init(client: QuickDocumentClient, contextPropertyId: String? = nil) {
        self.client = client
        self.contextPropertyId = contextPropertyId
        if contextPropertyId != nil {
            self.selectedEntityId = contextPropertyId
        }
    }

    var filteredItems: [DocumentTargetItem] {
        Self.search(items, query: searchText)
    }

    var canUpload: Bool { selectedEntityId != nil }

    func loadTargets() async {
        isLoading = true
        defer { isLoading = false }
        switch targetType {
        case .property:
            if properties.isEmpty { properties = (try? await client.fetchProperties()) ?? [] }
            items = properties.map { DocumentTargetItem(id: $0.id, title: $0.name, subtitle: $0.displayAddress) }
        case .tenant:
            if tenants.isEmpty { tenants = (try? await client.fetchTenants()) ?? [] }
            items = tenants.map { DocumentTargetItem(id: $0.id, title: $0.displayName, subtitle: $0.phone) }
        case .transaction:
            if properties.isEmpty { properties = (try? await client.fetchProperties()) ?? [] }
            if transactions.isEmpty {
                transactions = (try? await client.fetchTransactions(propertyIds: properties.map(\.id))) ?? []
            }
            let names = Dictionary(uniqueKeysWithValues: properties.map { ($0.id, $0.name) })
            items = transactions
                .sorted { ($0.transactionDate, $0.id) > ($1.transactionDate, $1.id) }
                .map {
                    DocumentTargetItem(
                        id: $0.id,
                        title: "\(AppFormatting.currency($0.amount, currency: $0.currency)) · \(names[$0.propertyId] ?? "Объект")",
                        subtitle: "\($0.transactionDate) · \($0.categoryName ?? $0.type)"
                    )
                }
        }
        // Keep a valid selection if the preset entity is in the loaded set.
        if let selectedEntityId, !items.contains(where: { $0.id == selectedEntityId }) {
            self.selectedEntityId = nil
        }
    }

    func upload(fileData: Data, fileName: String, mimeType: String) async -> Bool {
        guard let entityId = selectedEntityId else {
            errorMessage = "Выберите, к чему прикрепить документ."
            return false
        }
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }
        do {
            try await client.upload(
                entityType: targetType.apiEntityType,
                entityId: entityId,
                fileType: fileType,
                fileData: fileData,
                fileName: fileName,
                mimeType: mimeType
            )
            didUpload = true
            return true
        } catch APIError.httpStatus(let code) {
            errorMessage = code == 413 ? "Файл слишком большой." : "Не удалось загрузить документ."
            return false
        } catch {
            errorMessage = "Не удалось загрузить документ."
            return false
        }
    }

    // MARK: - Pure logic (unit-tested)

    nonisolated static func search(_ items: [DocumentTargetItem], query: String) -> [DocumentTargetItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return items }
        return items.filter {
            $0.title.lowercased().contains(trimmed) || ($0.subtitle?.lowercased().contains(trimmed) ?? false)
        }
    }
}
