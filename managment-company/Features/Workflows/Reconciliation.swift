import Combine
import Foundation

/// One imported bank statement row awaiting reconciliation (GAP-042).
struct BankStatementRow: Identifiable, Decodable, Equatable {
    let id: String
    let importId: String
    let rowIndex: Int
    let fingerprint: String
    let transactionDate: String
    let amount: Double
    let currency: String
    let description: String
    let status: String
    let suggestedPropertyId: String?
    let suggestedCategoryId: String?
    let suggestedScheduleId: String?
    let suggestedTransactionId: String?

    enum CodingKeys: String, CodingKey {
        case id, fingerprint, amount, currency, description, status
        case importId = "import_id"
        case rowIndex = "row_index"
        case transactionDate = "transaction_date"
        case suggestedPropertyId = "suggested_property_id"
        case suggestedCategoryId = "suggested_category_id"
        case suggestedScheduleId = "suggested_schedule_id"
        case suggestedTransactionId = "suggested_transaction_id"
    }
}

/// One parsed row to import.
struct BankImportRow: Encodable, Equatable {
    let transactionDate: String
    let amount: Double
    let currency: String
    let description: String

    enum CodingKeys: String, CodingKey {
        case amount, currency, description
        case transactionDate = "transaction_date"
    }
}

struct BankImportRequest: Encodable {
    let filename: String
    let rows: [BankImportRow]
}

struct BankImportResult: Decodable, Equatable {
    let importId: String
    let insertedRows: Int
    let duplicateRows: Int

    enum CodingKeys: String, CodingKey {
        case importId = "import_id"
        case insertedRows = "inserted_rows"
        case duplicateRows = "duplicate_rows"
    }
}

/// One target of a (possibly split) confirm decision.
struct BankDecisionPart: Encodable, Equatable {
    let propertyId: String
    let categoryId: String
    let type: String
    let amount: Double
    let description: String?
    let scheduleId: String?
    let transactionId: String?

    nonisolated init(
        propertyId: String,
        categoryId: String,
        type: String,
        amount: Double,
        description: String?,
        scheduleId: String? = nil,
        transactionId: String? = nil
    ) {
        self.propertyId = propertyId
        self.categoryId = categoryId
        self.type = type
        self.amount = amount
        self.description = description
        self.scheduleId = scheduleId
        self.transactionId = transactionId
    }

    enum CodingKeys: String, CodingKey {
        case type, amount, description
        case propertyId = "property_id"
        case categoryId = "category_id"
        case scheduleId = "schedule_id"
        case transactionId = "transaction_id"
    }
}

struct BankDecisionInput: Encodable {
    let action: String
    let note: String?
    let parts: [BankDecisionPart]
}

@MainActor
protocol ReconciliationClient {
    func importRows(filename: String, rows: [BankImportRow]) async throws -> BankImportResult
    func listRows(status: String) async throws -> [BankStatementRow]
    func decide(rowId: String, input: BankDecisionInput) async throws
    func listRentSchedules(months: Int) async throws -> [PaymentQueueItem]
}

@MainActor
struct LiveReconciliationClient: ReconciliationClient {
    let authManager: AuthManager
    private var token: () async -> String? { { await MainActor.run { authManager.accessToken } } }
    private var refresh: () async -> Bool { { await authManager.refreshToken() } }

    func importRows(filename: String, rows: [BankImportRow]) async throws -> BankImportResult {
        let data = try await APIClient.shared.requestData("/v1/bank-imports", method: "POST", body: BankImportRequest(filename: filename, rows: rows), tokenProvider: token, refreshAndRetry: refresh)
        struct Envelope: Decodable { let data: BankImportResult }
        if let env = try? JSONDecoder().decode(Envelope.self, from: data) { return env.data }
        return try JSONDecoder().decode(BankImportResult.self, from: data)
    }
    func listRows(status: String) async throws -> [BankStatementRow] {
        let env: APIListEnvelope<BankStatementRow> = try await APIClient.shared.requestRoot("/v1/bank-rows?status=\(status)", tokenProvider: token, refreshAndRetry: refresh)
        return env.data
    }
    func decide(rowId: String, input: BankDecisionInput) async throws {
        _ = try await APIClient.shared.requestData("/v1/bank-rows/\(rowId)/decision", method: "POST", body: input, tokenProvider: token, refreshAndRetry: refresh)
    }
    func listRentSchedules(months: Int = 24) async throws -> [PaymentQueueItem] {
        let env: APIListEnvelope<PaymentQueueItem> = try await APIClient.shared.requestRoot("/v1/payment-queue?scope=upcoming&months=\(months)", tokenProvider: token, refreshAndRetry: refresh)
        return env.data
    }
}

/// Bank statement import + reconciliation (GAP-042): CSV preview before import,
/// pending-row triage with confirm (single or split)/ignore.
@MainActor
final class ReconciliationViewModel: ObservableObject {
    @Published private(set) var pending: [BankStatementRow] = []
    @Published private(set) var confirmed: [BankStatementRow] = []
    @Published private(set) var lastImport: BankImportResult?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client: ReconciliationClient

    init(client: ReconciliationClient) {
        self.client = client
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            pending = try await client.listRows(status: "pending")
            confirmed = try await client.listRows(status: "confirmed")
        }
        catch { errorMessage = "Не удалось загрузить строки выписки." }
    }

    func importCSV(_ text: String, filename: String) async -> Bool {
        let rows = Self.parseCSV(text)
        guard !rows.isEmpty else { errorMessage = "Не удалось распознать строки CSV."; return false }
        errorMessage = nil
        do {
            lastImport = try await client.importRows(filename: filename, rows: rows)
            await load()
            return true
        } catch {
            errorMessage = "Не удалось импортировать выписку."
            return false
        }
    }

    func confirm(_ row: BankStatementRow, parts: [BankDecisionPart]) async -> Bool {
        guard !parts.isEmpty else { errorMessage = "Добавьте хотя бы одну часть."; return false }
        return await decide(row, input: BankDecisionInput(action: "confirm", note: nil, parts: parts))
    }

    func ignore(_ row: BankStatementRow) async -> Bool {
        await decide(row, input: BankDecisionInput(action: "ignore", note: nil, parts: []))
    }

    func rollback(_ row: BankStatementRow) async -> Bool {
        await decide(row, input: BankDecisionInput(
            action: "rollback",
            note: "Откат из iOS: строка возвращена для повторной сверки.",
            parts: []
        ))
    }

    private func decide(_ row: BankStatementRow, input: BankDecisionInput) async -> Bool {
        errorMessage = nil
        do { try await client.decide(rowId: row.id, input: input); await load(); return true }
        catch { errorMessage = "Не удалось обработать строку."; return false }
    }

    // MARK: - Pure logic (unit-tested)

    /// Parses a documented CSV (`date,amount,currency,description`; a leading
    /// header row is skipped). Invalid rows are dropped.
    nonisolated static func parseCSV(_ text: String) -> [BankImportRow] {
        var rows: [BankImportRow] = []
        let lines = text.split(whereSeparator: \.isNewline)
        for rawLine in lines {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            // Split on the first three commas only; the description keeps any
            // remaining commas verbatim.
            let cols = line.split(separator: ",", maxSplits: 3, omittingEmptySubsequences: false)
            guard cols.count >= 4 else { continue }
            let dateStr = cols[0].trimmingCharacters(in: .whitespaces)
            // Skip header / non-data rows (first column not an ISO date).
            guard isISODate(dateStr) else { continue }
            guard let amount = Double(cols[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) else { continue }
            let currencyRaw = cols[2].trimmingCharacters(in: .whitespaces)
            let currency = currencyRaw.isEmpty ? "KZT" : currencyRaw.uppercased()
            let description = cols[3].trimmingCharacters(in: .whitespaces)
            rows.append(BankImportRow(transactionDate: dateStr, amount: amount, currency: currency, description: description))
        }
        return rows
    }

    nonisolated static func isISODate(_ value: String) -> Bool {
        guard value.count == 10 else { return false }
        let parts = value.split(separator: "-")
        return parts.count == 3 && parts[0].count == 4 && Int(parts[0]) != nil && Int(parts[1]) != nil && Int(parts[2]) != nil
    }

    /// Builds a single-part confirm from a row + a chosen property/category.
    nonisolated static func singlePart(row: BankStatementRow, propertyId: String, categoryId: String) -> BankDecisionPart {
        BankDecisionPart(
            propertyId: propertyId,
            categoryId: categoryId,
            type: row.amount >= 0 ? "income" : "expense",
            amount: abs(row.amount),
            description: row.description.isEmpty ? nil : row.description
        )
    }

    /// Builds a reconciliation decision that posts the bank row as a rent
    /// allocation for one schedule (`schedule_id`). The backend owns the actual
    /// rent transaction/category/tenant linkage through MarkSchedulePaid.
    nonisolated static func rentAllocationPart(row: BankStatementRow, scheduleId: String, amount: Double? = nil) -> BankDecisionPart {
        BankDecisionPart(
            propertyId: "",
            categoryId: "",
            type: "income",
            amount: amount ?? abs(row.amount),
            description: row.description.isEmpty ? nil : row.description,
            scheduleId: scheduleId
        )
    }

    /// Links the bank row to an existing transaction instead of creating a
    /// duplicate operation. Rollback later removes only this bank-row link.
    nonisolated static func existingTransactionPart(row: BankStatementRow, transactionId: String, amount: Double? = nil) -> BankDecisionPart {
        BankDecisionPart(
            propertyId: "",
            categoryId: "",
            type: row.amount >= 0 ? "income" : "expense",
            amount: amount ?? abs(row.amount),
            description: row.description.isEmpty ? nil : row.description,
            transactionId: transactionId
        )
    }
}
