import Combine
import Foundation

/// Body for `POST /v1/properties/:id/transactions` from the compact expense flow.
/// Type is always `expense`; rent-specific fields never apply here.
struct CompactExpenseInput: Encodable {
    let type = "expense"
    let categoryId: String
    let amount: Double
    let currency: String
    let transactionDate: String
    let description: String?

    enum CodingKeys: String, CodingKey {
        case type, amount, currency, description
        case categoryId = "category_id"
        case transactionDate = "transaction_date"
    }
}

@MainActor
protocol CompactExpenseClient {
    func fetchCategories() async throws -> [Category]
    func fetchProperties() async throws -> [Property]
    func fetchRecentExpenses(propertyIds: [String]) async throws -> [Transaction]
    /// Returns the created transaction id (for Undo).
    func createExpense(propertyId: String, body: CompactExpenseInput) async throws -> String
    func deleteTransaction(id: String) async throws
}

@MainActor
struct LiveCompactExpenseClient: CompactExpenseClient {
    let authManager: AuthManager

    private var token: () async -> String? { { await MainActor.run { authManager.accessToken } } }
    private var refresh: () async -> Bool { { await authManager.refreshToken() } }

    func fetchCategories() async throws -> [Category] {
        try await APIClient.shared.request("/v1/categories", tokenProvider: token, refreshAndRetry: refresh)
    }

    func fetchProperties() async throws -> [Property] {
        try await APIClient.shared.request("/v1/properties", tokenProvider: token, refreshAndRetry: refresh)
    }

    func fetchRecentExpenses(propertyIds: [String]) async throws -> [Transaction] {
        var merged: [Transaction] = []
        for id in propertyIds.prefix(20) {
            if let rows: [Transaction] = try? await APIClient.shared.request(
                "/v1/properties/\(id)/transactions?per_page=20",
                tokenProvider: token,
                refreshAndRetry: refresh
            ) {
                merged.append(contentsOf: rows.filter { $0.type == "expense" })
            }
        }
        return merged
    }

    func createExpense(propertyId: String, body: CompactExpenseInput) async throws -> String {
        let data = try await APIClient.shared.requestData(
            "/v1/properties/\(propertyId)/transactions",
            method: "POST",
            body: body,
            tokenProvider: token,
            refreshAndRetry: refresh
        )
        struct Envelope: Decodable { let data: Transaction }
        if let env = try? JSONDecoder().decode(Envelope.self, from: data) { return env.data.id }
        return try JSONDecoder().decode(Transaction.self, from: data).id
    }

    func deleteTransaction(id: String) async throws {
        _ = try await APIClient.shared.requestData(
            "/v1/transactions/\(id)",
            method: "DELETE",
            tokenProvider: token,
            refreshAndRetry: refresh
        )
    }
}

/// Compact `Добавить расход` capture (GAP-033): amount-first, type fixed to
/// expense, date today, base currency, last/context property preselected,
/// recent-category chips, optional collapsed fields, Undo, and «Добавить ещё».
@MainActor
final class CompactExpenseViewModel: ObservableObject {
    @Published var amountText = ""
    @Published var selectedCategoryId: String?
    @Published var selectedPropertyId: String = ""
    @Published var date: Date = Date()
    @Published var note = ""
    @Published var showOptionalFields = false
    @Published private(set) var currency: String
    @Published private(set) var categories: [Category] = []
    @Published private(set) var properties: [Property] = []
    @Published private(set) var recentCategoryIds: [String] = []
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?
    /// Id of the just-created expense, enabling the short-lived Undo.
    @Published private(set) var lastCreatedId: String?
    @Published private(set) var didSaveOnce = false

    private let client: CompactExpenseClient
    private let timeZoneIdentifier: String
    private let contextPropertyId: String?

    init(client: CompactExpenseClient, baseCurrency: String, timeZoneIdentifier: String, contextPropertyId: String? = nil) {
        self.client = client
        self.currency = baseCurrency
        self.timeZoneIdentifier = timeZoneIdentifier
        self.contextPropertyId = contextPropertyId
    }

    var expenseCategories: [Category] {
        categories.filter { $0.type == "expense" }.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Recent expense-category chips: recency first, then catalog order.
    var recentChips: [Category] {
        let byId = Dictionary(uniqueKeysWithValues: expenseCategories.map { ($0.id, $0) })
        return recentCategoryIds.compactMap { byId[$0] }
    }

    var parsedAmount: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    var canSave: Bool {
        Self.canSave(amount: parsedAmount, categoryId: selectedCategoryId, propertyId: emptyToNil(selectedPropertyId))
    }

    func load() async {
        async let categoriesR = capture { try await self.client.fetchCategories() }
        async let propertiesR = capture { try await self.client.fetchProperties() }
        let categories = (try? await categoriesR.get()) ?? []
        let properties = (try? await propertiesR.get()) ?? []
        self.categories = categories
        self.properties = properties

        let recent = (try? await client.fetchRecentExpenses(propertyIds: properties.map(\.id))) ?? []
        recentCategoryIds = Self.recentExpenseCategoryIds(
            recentExpenses: recent,
            expenseCategoryIds: Set(expenseCategories.map(\.id)),
            limit: 5
        )

        if selectedPropertyId.isEmpty {
            selectedPropertyId = Self.preselectedProperty(
                context: contextPropertyId,
                recentExpenses: recent,
                properties: properties
            ) ?? ""
        }
        if selectedCategoryId == nil {
            selectedCategoryId = recentCategoryIds.first ?? expenseCategories.first?.id
        }
    }

    /// Saves the expense and returns success. Stores the new id for Undo.
    func save(now: Date = Date()) async -> Bool {
        guard let amount = parsedAmount, amount > 0,
              let categoryId = selectedCategoryId,
              let propertyId = emptyToNil(selectedPropertyId) else {
            errorMessage = "Введите сумму, выберите категорию и объект."
            return false
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = CompactExpenseInput(
            categoryId: categoryId,
            amount: amount,
            currency: currency,
            transactionDate: AppFormatting.dayKey(for: showOptionalFields ? date : now, timeZoneIdentifier: timeZoneIdentifier),
            description: trimmedNote.isEmpty ? nil : trimmedNote
        )
        do {
            lastCreatedId = try await client.createExpense(propertyId: propertyId, body: body)
            didSaveOnce = true
            // GAP-038: an owner expense today suppresses the daily reminder.
            ExpenseReminderController.shared.markExpenseRecorded(now: now)
            return true
        } catch {
            errorMessage = "Не удалось сохранить расход."
            return false
        }
    }

    /// Reverses the last created expense (short-lived Undo).
    func undoLast() async -> Bool {
        guard let id = lastCreatedId else { return false }
        do {
            try await client.deleteTransaction(id: id)
            lastCreatedId = nil
            return true
        } catch {
            errorMessage = "Не удалось отменить расход."
            return false
        }
    }

    /// «Добавить ещё»: clears amount/note for a new entry, keeps property/date.
    func resetForAnother() {
        amountText = ""
        note = ""
        lastCreatedId = nil
        errorMessage = nil
    }

    // MARK: - Pure logic (unit-tested)

    nonisolated static func canSave(amount: Double?, categoryId: String?, propertyId: String?) -> Bool {
        guard let amount, amount > 0 else { return false }
        return categoryId != nil && propertyId != nil
    }

    /// Expense category ids ordered by most-recent use, limited to known expense
    /// categories. Each id appears once.
    nonisolated static func recentExpenseCategoryIds(
        recentExpenses: [Transaction],
        expenseCategoryIds: Set<String>,
        limit: Int
    ) -> [String] {
        let ordered = recentExpenses.sorted { ($0.transactionDate, $0.id) > ($1.transactionDate, $1.id) }
        var seen = Set<String>()
        var result: [String] = []
        for txn in ordered where expenseCategoryIds.contains(txn.categoryId) {
            if seen.insert(txn.categoryId).inserted {
                result.append(txn.categoryId)
                if result.count == limit { break }
            }
        }
        return result
    }

    /// Property preselection: explicit context → last-used (most recent expense)
    /// → first available.
    nonisolated static func preselectedProperty(
        context: String?,
        recentExpenses: [Transaction],
        properties: [Property]
    ) -> String? {
        if let context, properties.contains(where: { $0.id == context }) { return context }
        let lastUsed = recentExpenses
            .sorted { ($0.transactionDate, $0.id) > ($1.transactionDate, $1.id) }
            .first(where: { txn in properties.contains { $0.id == txn.propertyId } })?
            .propertyId
        return lastUsed ?? properties.first?.id
    }

    // MARK: - Helpers

    private func emptyToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func capture<T>(_ work: @escaping () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }
}
