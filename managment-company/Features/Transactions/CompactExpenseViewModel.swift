import Combine
import Foundation

/// Body for the protected owner-expense workflow (`POST /v1/expenses` and
/// `/v1/expenses/duplicate-check`). Type is always expense.
struct ExpenseWorkflowInput: Encodable {
    let propertyId: String
    let categoryId: String
    let amount: Double
    let currency: String
    let transactionDate: String
    let description: String?
    let payee: String?
    let allowDuplicate: Bool
    let duplicateCandidateIds: [String]

    enum CodingKeys: String, CodingKey {
        case amount, currency, description, payee
        case propertyId = "property_id"
        case categoryId = "category_id"
        case transactionDate = "transaction_date"
        case allowDuplicate = "allow_duplicate"
        case duplicateCandidateIds = "duplicate_candidate_ids"
    }
}

/// A likely-duplicate expense surfaced before creation (GAP-045).
struct DuplicateExpenseCandidate: Identifiable, Decodable, Equatable {
    let id: String
    let propertyName: String
    let categoryName: String
    let amount: Double
    let currency: String
    let transactionDate: String
    let payee: String?
    let score: Int
    let reasons: [String]

    enum CodingKeys: String, CodingKey {
        case id, amount, currency, payee, score, reasons
        case propertyName = "property_name"
        case categoryName = "category_name"
        case transactionDate = "transaction_date"
    }
}

@MainActor
protocol CompactExpenseClient {
    func fetchCategories() async throws -> [Category]
    func fetchProperties() async throws -> [Property]
    func fetchRecentExpenses(propertyIds: [String]) async throws -> [Transaction]
    func checkDuplicates(_ input: ExpenseWorkflowInput) async throws -> [DuplicateExpenseCandidate]
    /// Returns the created transaction id (for Undo).
    func createExpense(_ input: ExpenseWorkflowInput) async throws -> String
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
                tokenProvider: token, refreshAndRetry: refresh
            ) {
                merged.append(contentsOf: rows.filter { $0.type == "expense" })
            }
        }
        return merged
    }
    func checkDuplicates(_ input: ExpenseWorkflowInput) async throws -> [DuplicateExpenseCandidate] {
        let env: APIListEnvelope<DuplicateExpenseCandidate> = try await APIClient.shared.requestRoot(
            "/v1/expenses/duplicate-check", method: "POST", body: input, tokenProvider: token, refreshAndRetry: refresh
        )
        return env.data
    }
    func createExpense(_ input: ExpenseWorkflowInput) async throws -> String {
        let data = try await APIClient.shared.requestData("/v1/expenses", method: "POST", body: input, tokenProvider: token, refreshAndRetry: refresh)
        struct Envelope: Decodable { let data: Transaction }
        if let env = try? JSONDecoder().decode(Envelope.self, from: data) { return env.data.id }
        return (try? JSONDecoder().decode(Transaction.self, from: data).id) ?? ""
    }
    func deleteTransaction(id: String) async throws {
        _ = try await APIClient.shared.requestData("/v1/transactions/\(id)", method: "DELETE", tokenProvider: token, refreshAndRetry: refresh)
    }
}

/// Compact `Добавить расход` capture (GAP-033) with duplicate detection (GAP-045).
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
    @Published private(set) var lastCreatedId: String?
    @Published private(set) var didSaveOnce = false
    /// Likely duplicates surfaced before creation; non-empty means the user must
    /// decide (cancel / open existing / create anyway).
    @Published private(set) var duplicateCandidates: [DuplicateExpenseCandidate] = []

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
            recentExpenses: recent, expenseCategoryIds: Set(expenseCategories.map(\.id)), limit: 5
        )
        if selectedPropertyId.isEmpty {
            selectedPropertyId = Self.preselectedProperty(context: contextPropertyId, recentExpenses: recent, properties: properties) ?? ""
        }
        if selectedCategoryId == nil {
            selectedCategoryId = recentCategoryIds.first ?? expenseCategories.first?.id
        }
    }

    /// Attempts to save. Returns `true` when created; `false` either on validation
    /// error (errorMessage set) or when likely duplicates need a decision
    /// (`duplicateCandidates` populated, no error).
    func save(now: Date = Date()) async -> Bool {
        guard let input = makeInput(now: now, allowDuplicate: false, candidateIds: []) else {
            errorMessage = "Введите сумму, выберите категорию и объект."
            return false
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let candidates = try await client.checkDuplicates(input)
            if !candidates.isEmpty {
                duplicateCandidates = candidates
                return false
            }
            return try await persist(input)
        } catch {
            errorMessage = "Не удалось сохранить расход."
            return false
        }
    }

    /// Creates the expense despite duplicates, recording the override.
    func createAnyway(now: Date = Date()) async -> Bool {
        guard let input = makeInput(now: now, allowDuplicate: true, candidateIds: duplicateCandidates.map(\.id)) else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let ok = try await persist(input)
            if ok { duplicateCandidates = [] }
            return ok
        } catch {
            errorMessage = "Не удалось сохранить расход."
            return false
        }
    }

    func dismissDuplicates() { duplicateCandidates = [] }

    private func persist(_ input: ExpenseWorkflowInput) async throws -> Bool {
        lastCreatedId = try await client.createExpense(input)
        didSaveOnce = true
        ExpenseReminderController.shared.markExpenseRecorded(now: Date())
        return true
    }

    func undoLast() async -> Bool {
        guard let id = lastCreatedId, !id.isEmpty else { return false }
        do { try await client.deleteTransaction(id: id); lastCreatedId = nil; return true }
        catch { errorMessage = "Не удалось отменить расход."; return false }
    }

    func resetForAnother() {
        amountText = ""
        note = ""
        lastCreatedId = nil
        errorMessage = nil
        duplicateCandidates = []
    }

    private func makeInput(now: Date, allowDuplicate: Bool, candidateIds: [String]) -> ExpenseWorkflowInput? {
        guard let amount = parsedAmount, amount > 0,
              let categoryId = selectedCategoryId,
              let propertyId = emptyToNil(selectedPropertyId) else { return nil }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return ExpenseWorkflowInput(
            propertyId: propertyId,
            categoryId: categoryId,
            amount: amount,
            currency: currency,
            transactionDate: AppFormatting.dayKey(for: showOptionalFields ? date : now, timeZoneIdentifier: timeZoneIdentifier),
            description: trimmedNote.isEmpty ? nil : trimmedNote,
            payee: nil,
            allowDuplicate: allowDuplicate,
            duplicateCandidateIds: candidateIds
        )
    }

    // MARK: - Pure logic (unit-tested)

    nonisolated static func canSave(amount: Double?, categoryId: String?, propertyId: String?) -> Bool {
        guard let amount, amount > 0 else { return false }
        return categoryId != nil && propertyId != nil
    }

    nonisolated static func recentExpenseCategoryIds(
        recentExpenses: [Transaction], expenseCategoryIds: Set<String>, limit: Int
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

    nonisolated static func preselectedProperty(
        context: String?, recentExpenses: [Transaction], properties: [Property]
    ) -> String? {
        if let context, properties.contains(where: { $0.id == context }) { return context }
        let lastUsed = recentExpenses
            .sorted { ($0.transactionDate, $0.id) > ($1.transactionDate, $1.id) }
            .first(where: { txn in properties.contains { $0.id == txn.propertyId } })?.propertyId
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
