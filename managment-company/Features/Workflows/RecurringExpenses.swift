import Combine
import Foundation

/// Recurring owner-expense template (GAP-039), mirrors the API
/// `RecurringExpenseTemplate`.
struct RecurringExpenseTemplate: Identifiable, Decodable, Equatable {
    let id: String
    let propertyId: String
    let propertyName: String
    let categoryId: String
    let categoryName: String
    let amount: Double
    let currency: String
    let payee: String?
    let description: String?
    let cadence: String
    let dayOfMonth: Int?
    let timezone: String
    let nextOccurrence: String
    let status: String

    var isPaused: Bool { status == "paused" }

    enum CodingKeys: String, CodingKey {
        case id, amount, currency, payee, description, cadence, timezone, status
        case propertyId = "property_id"
        case propertyName = "property_name"
        case categoryId = "category_id"
        case categoryName = "category_name"
        case dayOfMonth = "day_of_month"
        case nextOccurrence = "next_occurrence"
    }
}

/// Body for create/update of a recurring template.
struct RecurringExpenseInput: Encodable {
    let propertyId: String
    let categoryId: String
    let amount: Double
    let currency: String
    let payee: String?
    let description: String?
    let cadence: String
    let timezone: String
    let nextOccurrence: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case amount, currency, payee, description, cadence, timezone, status
        case propertyId = "property_id"
        case categoryId = "category_id"
        case nextOccurrence = "next_occurrence"
    }
}

@MainActor
protocol RecurringExpenseClient {
    func list() async throws -> [RecurringExpenseTemplate]
    func listDue() async throws -> [RecurringExpenseTemplate]
    func create(_ input: RecurringExpenseInput) async throws
    func update(id: String, _ input: RecurringExpenseInput) async throws
    func delete(id: String) async throws
    func confirm(id: String) async throws
    func skip(id: String) async throws
}

@MainActor
struct LiveRecurringExpenseClient: RecurringExpenseClient {
    let authManager: AuthManager
    private var token: () async -> String? { { await MainActor.run { authManager.accessToken } } }
    private var refresh: () async -> Bool { { await authManager.refreshToken() } }

    private struct Envelope<T: Decodable>: Decodable { let data: T }

    private func decodeList(_ data: Data) -> [RecurringExpenseTemplate] {
        if let env = try? JSONDecoder().decode(Envelope<[RecurringExpenseTemplate]>.self, from: data) {
            return env.data
        }
        return (try? JSONDecoder().decode([RecurringExpenseTemplate].self, from: data)) ?? []
    }

    func list() async throws -> [RecurringExpenseTemplate] {
        let data = try await APIClient.shared.requestData("/v1/recurring-expenses", tokenProvider: token, refreshAndRetry: refresh)
        return decodeList(data)
    }
    func listDue() async throws -> [RecurringExpenseTemplate] {
        let data = try await APIClient.shared.requestData("/v1/recurring-expenses/due", tokenProvider: token, refreshAndRetry: refresh)
        return decodeList(data)
    }
    func create(_ input: RecurringExpenseInput) async throws {
        _ = try await APIClient.shared.requestData("/v1/recurring-expenses", method: "POST", body: input, tokenProvider: token, refreshAndRetry: refresh)
    }
    func update(id: String, _ input: RecurringExpenseInput) async throws {
        _ = try await APIClient.shared.requestData("/v1/recurring-expenses/\(id)", method: "PUT", body: input, tokenProvider: token, refreshAndRetry: refresh)
    }
    func delete(id: String) async throws {
        _ = try await APIClient.shared.requestData("/v1/recurring-expenses/\(id)", method: "DELETE", tokenProvider: token, refreshAndRetry: refresh)
    }
    func confirm(id: String) async throws {
        _ = try await APIClient.shared.requestData("/v1/recurring-expenses/\(id)/confirm", method: "POST", tokenProvider: token, refreshAndRetry: refresh)
    }
    func skip(id: String) async throws {
        _ = try await APIClient.shared.requestData("/v1/recurring-expenses/\(id)/skip", method: "POST", tokenProvider: token, refreshAndRetry: refresh)
    }
}

/// Manages recurring expense templates (GAP-039): list/create/edit/pause/resume/
/// delete plus confirm/skip of due occurrences.
@MainActor
final class RecurringExpensesViewModel: ObservableObject {
    @Published private(set) var templates: [RecurringExpenseTemplate] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client: RecurringExpenseClient

    init(client: RecurringExpenseClient) {
        self.client = client
    }

    var activeTemplates: [RecurringExpenseTemplate] { templates.filter { !$0.isPaused } }
    var pausedTemplates: [RecurringExpenseTemplate] { templates.filter { $0.isPaused } }

    func dueTemplates(today: String) -> [RecurringExpenseTemplate] {
        Self.dueTemplates(templates, today: today)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            templates = try await client.list()
        } catch {
            errorMessage = "Не удалось загрузить шаблоны."
        }
    }

    func confirm(_ template: RecurringExpenseTemplate) async -> Bool {
        await act { try await self.client.confirm(id: template.id) }
    }

    func skip(_ template: RecurringExpenseTemplate) async -> Bool {
        await act { try await self.client.skip(id: template.id) }
    }

    func delete(_ template: RecurringExpenseTemplate) async -> Bool {
        await act { try await self.client.delete(id: template.id) }
    }

    /// Pause an active template or resume a paused one (status flip).
    func togglePause(_ template: RecurringExpenseTemplate) async -> Bool {
        let input = Self.toggleStatusInput(for: template)
        return await act { try await self.client.update(id: template.id, input) }
    }

    func create(_ input: RecurringExpenseInput) async -> Bool {
        await act { try await self.client.create(input) }
    }

    func update(id: String, _ input: RecurringExpenseInput) async -> Bool {
        await act { try await self.client.update(id: id, input) }
    }

    private func act(_ work: @escaping () async throws -> Void) async -> Bool {
        errorMessage = nil
        do {
            try await work()
            await load()
            return true
        } catch {
            errorMessage = "Не удалось выполнить действие."
            return false
        }
    }

    // MARK: - Pure logic (unit-tested)

    /// Due = active templates whose next occurrence is on/before today.
    nonisolated static func dueTemplates(_ all: [RecurringExpenseTemplate], today: String) -> [RecurringExpenseTemplate] {
        all.filter { !$0.isPaused && $0.nextOccurrence.prefix(10) <= today }
    }

    /// Builds the update body that flips a template between active and paused.
    nonisolated static func toggleStatusInput(for template: RecurringExpenseTemplate) -> RecurringExpenseInput {
        RecurringExpenseInput(
            propertyId: template.propertyId,
            categoryId: template.categoryId,
            amount: template.amount,
            currency: template.currency,
            payee: template.payee,
            description: template.description,
            cadence: template.cadence,
            timezone: template.timezone,
            nextOccurrence: template.nextOccurrence,
            status: template.isPaused ? "active" : "paused"
        )
    }
}
