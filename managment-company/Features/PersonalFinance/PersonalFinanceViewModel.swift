import Combine
import Foundation

/// Quick-add личной траты/дохода: сумма → категория → счёт → POST в portfolio-dashboard.
/// Никакой записи в PropManager; локально держим только кэш справочников.
@MainActor
final class PersonalFinanceViewModel: ObservableObject {
    enum EntryType: String, CaseIterable, Identifiable {
        case expense
        case income
        var id: String { rawValue }
        var title: String { self == .expense ? "Трата" : "Доход" }
    }

    @Published var amountText = ""
    @Published var note = ""
    @Published var entryType: EntryType = .expense
    @Published var selectedCategoryId: String?
    @Published var selectedAccountId: String?

    @Published private(set) var accounts: [PFAccount] = []
    @Published private(set) var categories: [PFCategory] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var successMessage: String?
    @Published private(set) var isConfigured = PersonalFinanceSettings.isConfigured

    private let client: PersonalFinanceClient

    init(client: PersonalFinanceClient = LivePersonalFinanceClient()) {
        self.client = client
        accounts = PersonalFinanceSettings.cachedAccounts
        categories = PersonalFinanceSettings.cachedCategories
    }

    var selectedAccount: PFAccount? {
        accounts.first { $0.id == selectedAccountId }
    }

    var canSubmit: Bool {
        !isSubmitting && selectedAccountId != nil && PFAmount.validated(amountText) != nil
    }

    func refreshConfiguration() {
        isConfigured = PersonalFinanceSettings.isConfigured
    }

    func load() async {
        refreshConfiguration()
        guard isConfigured else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let accountsTask = client.fetchAccounts()
            async let categoriesTask = client.fetchCategories()
            async let defaultsTask = client.fetchDefaults()
            let (fetchedAccounts, fetchedCategories, defaults) =
                try await (accountsTask, categoriesTask, defaultsTask)

            accounts = fetchedAccounts
            categories = Self.ordered(fetchedCategories, topIds: defaults.topCategoryIds)
            PersonalFinanceSettings.cachedAccounts = fetchedAccounts
            PersonalFinanceSettings.cachedCategories = categories

            if selectedAccountId == nil {
                selectedAccountId = defaults.lastAccountId ?? fetchedAccounts.first?.id
            }
        } catch {
            // Справочники из кэша позволяют вводить и при недоступном сервере;
            // сам POST при этом честно упадёт с ошибкой.
            if accounts.isEmpty && categories.isEmpty {
                errorMessage = describe(error)
            }
            if selectedAccountId == nil {
                selectedAccountId = accounts.first?.id
            }
        }
    }

    func submit() async {
        guard let accountId = selectedAccountId,
              let amount = PFAmount.validated(amountText) else { return }
        isSubmitting = true
        errorMessage = nil
        successMessage = nil
        defer { isSubmitting = false }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = PFTransactionRequest(
            accountId: accountId,
            transactionType: entryType.rawValue,
            amount: amount,
            categoryId: selectedCategoryId,
            merchant: nil,
            note: trimmedNote.isEmpty ? nil : trimmedNote
        )

        do {
            let created = try await client.submitTransaction(request)
            let categoryName = categories.first { $0.id == created.categoryId }?.name
            successMessage = Self.confirmation(
                amount: created.amount,
                currencyCode: created.currencyCode,
                categoryName: categoryName,
                entryType: entryType
            )
            amountText = ""
            note = ""
            selectedCategoryId = nil
        } catch {
            errorMessage = describe(error)
        }
    }

    /// Топ-категории из defaults — первыми (как плитки частых), остальные по sortOrder.
    static func ordered(_ categories: [PFCategory], topIds: [String]) -> [PFCategory] {
        let byId = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let top = topIds.compactMap { byId[$0] }
        let topSet = Set(topIds)
        let rest = categories
            .filter { !topSet.contains($0.id) }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        return top + rest
    }

    static func confirmation(
        amount: String,
        currencyCode: String,
        categoryName: String?,
        entryType: EntryType
    ) -> String {
        // "12500.500000000000" → "12500.5" для человекочитаемого подтверждения.
        let display = Decimal(string: amount).map { "\($0)" } ?? amount
        let verb = entryType == .expense ? "Трата записана" : "Доход записан"
        if let categoryName {
            return "\(verb): \(display) \(currencyCode), \(categoryName)"
        }
        return "\(verb): \(display) \(currencyCode)"
    }

    private func describe(_ error: Error) -> String {
        if let pfError = error as? PFError {
            return pfError.errorDescription ?? "Неизвестная ошибка."
        }
        return "Сервер личных финансов недоступен. Проверьте сеть и адрес сервера."
    }
}
