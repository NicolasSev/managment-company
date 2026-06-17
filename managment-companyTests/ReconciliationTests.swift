//
//  ReconciliationTests.swift
//  managment-companyTests
//
//  Mirrored tests for GAP-042 (bank statement import/reconciliation): CSV
//  parsing (header skip, invalid drop, split description), single-part decision
//  building, import preview, and confirm/ignore flow.
//

import Foundation
import Testing
@testable import managment_company

private func bankRow(_ id: String, amount: Double, desc: String = "Платёж", suggestedProperty: String? = nil, status: String = "pending") -> BankStatementRow {
    BankStatementRow(
        id: id, importId: "imp", rowIndex: 0, fingerprint: "fp-\(id)", transactionDate: "2026-06-01",
        amount: amount, currency: "KZT", description: desc, status: status,
        suggestedPropertyId: suggestedProperty, suggestedCategoryId: nil, suggestedScheduleId: nil,
        suggestedTransactionId: nil
    )
}

@MainActor
private final class MockReconciliationClient: ReconciliationClient {
    var pending: [BankStatementRow] = []
    var confirmed: [BankStatementRow] = []
    var importResult = BankImportResult(importId: "imp", insertedRows: 0, duplicateRows: 0)
    var importedRows: [BankImportRow] = []
    var decisions: [(rowId: String, action: String, parts: Int)] = []

    func importRows(filename: String, rows: [BankImportRow]) async throws -> BankImportResult {
        importedRows = rows
        return importResult
    }
    func listRows(status: String) async throws -> [BankStatementRow] {
        status == "confirmed" ? confirmed : pending
    }
    func decide(rowId: String, input: BankDecisionInput) async throws {
        decisions.append((rowId, input.action, input.parts.count))
    }
    func listRentSchedules(months: Int) async throws -> [PaymentQueueItem] { [] }
}

@Suite(.serialized)
struct ReconciliationTests {

    @Test func parseCSVSkipsHeaderAndInvalidRows() {
        let csv = """
        date,amount,currency,description
        2026-06-01,12500,KZT,Аренда
        bad,row,here,nope
        2026-06-02,-3000,KZT,Коммуналка, июнь
        """
        let rows = ReconciliationViewModel.parseCSV(csv)
        #expect(rows.count == 2)
        #expect(rows[0].transactionDate == "2026-06-01")
        #expect(rows[0].amount == 12500)
        // Split description preserves trailing commas.
        #expect(rows[1].description == "Коммуналка, июнь")
        #expect(rows[1].amount == -3000)
    }

    @Test func singlePartDerivesTypeFromSign() {
        let income = ReconciliationViewModel.singlePart(row: bankRow("a", amount: 5000), propertyId: "p", categoryId: "c")
        #expect(income.type == "income")
        #expect(income.amount == 5000)
        let expense = ReconciliationViewModel.singlePart(row: bankRow("b", amount: -4000), propertyId: "p", categoryId: "c")
        #expect(expense.type == "expense")
        #expect(expense.amount == 4000)
    }

    @Test func decodesScheduleSuggestionAndBuildsRentAllocationPart() throws {
        let json = """
        {
          "id":"row-1","import_id":"imp","row_index":1,"fingerprint":"fp",
          "transaction_date":"2026-06-01","amount":100000,"currency":"KZT",
          "description":"Аренда Иванов","status":"pending",
          "suggested_property_id":null,"suggested_category_id":null,
          "suggested_schedule_id":"schedule-1",
          "suggested_transaction_id":"transaction-1"
        }
        """.data(using: .utf8)!

        let row = try JSONDecoder().decode(BankStatementRow.self, from: json)
        #expect(row.suggestedScheduleId == "schedule-1")
        #expect(row.suggestedTransactionId == "transaction-1")

        let part = ReconciliationViewModel.rentAllocationPart(row: row, scheduleId: "schedule-1", amount: 75000)
        #expect(part.scheduleId == "schedule-1")
        #expect(part.type == "income")
        #expect(part.amount == 75000)
        #expect(part.propertyId.isEmpty)
        #expect(part.categoryId.isEmpty)

        let existing = ReconciliationViewModel.existingTransactionPart(row: row, transactionId: "transaction-1")
        #expect(existing.transactionId == "transaction-1")
        #expect(existing.scheduleId == nil)
        #expect(existing.amount == 100000)
    }

    @MainActor
    @Test func importCSVSendsParsedRowsAndReloads() async {
        let client = MockReconciliationClient()
        client.importResult = BankImportResult(importId: "imp", insertedRows: 2, duplicateRows: 1)
        let vm = ReconciliationViewModel(client: client)

        let ok = await vm.importCSV("2026-06-01,100,KZT,A\n2026-06-02,200,KZT,B", filename: "stmt.csv")
        #expect(ok)
        #expect(client.importedRows.count == 2)
        #expect(vm.lastImport?.insertedRows == 2)
    }

    @MainActor
    @Test func loadConfirmIgnoreAndRollbackCallClient() async {
        let client = MockReconciliationClient()
        client.pending = [bankRow("r1", amount: -5000)]
        client.confirmed = [bankRow("r3", amount: 10000, status: "confirmed")]
        let vm = ReconciliationViewModel(client: client)
        await vm.load()
        #expect(vm.pending.count == 1)
        #expect(vm.confirmed.count == 1)

        let part = ReconciliationViewModel.singlePart(row: bankRow("r1", amount: -5000), propertyId: "p", categoryId: "c")
        let confirmed = await vm.confirm(bankRow("r1", amount: -5000), parts: [part])
        #expect(confirmed)
        #expect(client.decisions.last?.action == "confirm")
        #expect(client.decisions.last?.parts == 1)

        let ignored = await vm.ignore(bankRow("r2", amount: 100))
        #expect(ignored)
        #expect(client.decisions.last?.action == "ignore")

        let rolledBack = await vm.rollback(bankRow("r3", amount: 10000, status: "confirmed"))
        #expect(rolledBack)
        #expect(client.decisions.last?.action == "rollback")
        #expect(client.decisions.last?.parts == 0)
    }

    @MainActor
    @Test func confirmRequiresParts() async {
        let client = MockReconciliationClient()
        let vm = ReconciliationViewModel(client: client)
        let ok = await vm.confirm(bankRow("r", amount: 1), parts: [])
        #expect(!ok)
        #expect(vm.errorMessage != nil)
    }
}
