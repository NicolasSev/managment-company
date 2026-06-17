//
//  CompactExpenseTests.swift
//  managment-companyTests
//
//  Mirrored tests for GAP-033 (compact expense capture) and GAP-045 (duplicate
//  expense detection): validation, recent-category order, property preselection,
//  save (today), undo, reset, duplicate warning + create-anyway override.
//

import Foundation
import Testing
@testable import managment_company

private typealias Category = managment_company.Category

private func expenseTxn(id: String, propertyId: String, categoryId: String, date: String) -> Transaction {
    Transaction(
        id: id, propertyId: propertyId, type: "expense", categoryId: categoryId,
        categoryName: nil, amount: 100, currency: "KZT", amountBase: 100, exchangeRate: nil,
        transactionDate: date, periodYear: 2026, periodMonth: 6, description: nil,
        tenantId: nil, leaseId: nil
    )
}

private func category(_ id: String, _ name: String, type: String = "expense", sort: Int = 0) -> Category {
    Category(id: id, name: name, type: type, isSystem: false, icon: nil, sortOrder: sort)
}

private func property(_ id: String) -> Property {
    Property(
        id: id, name: "Объект \(id)", propertyType: "apartment", country: nil, city: nil,
        address: nil, district: nil, areaSqm: nil, rooms: nil, floor: nil, purchaseDate: nil,
        purchasePrice: nil, purchaseCurrency: nil, currentValue: nil, currentValueCurrency: nil,
        status: "vacant", notes: nil, tags: nil, utilityAccountNumber: nil, wifiLogin: nil,
        wifiPassword: nil
    )
}

private func candidate(_ id: String) -> DuplicateExpenseCandidate {
    DuplicateExpenseCandidate(
        id: id, propertyName: "Алматы", categoryName: "Интернет", amount: 12500, currency: "KZT",
        transactionDate: "2026-06-17", payee: nil, score: 90, reasons: ["amount", "date"]
    )
}

@MainActor
private final class MockCompactExpenseClient: CompactExpenseClient {
    var categories: [Category] = []
    var properties: [Property] = []
    var recent: [Transaction] = []
    var duplicates: [DuplicateExpenseCandidate] = []
    var createdId = "tx-new"
    var createdInputs: [ExpenseWorkflowInput] = []
    var checkedInputs: [ExpenseWorkflowInput] = []
    var deleted: [String] = []

    func fetchCategories() async throws -> [Category] { categories }
    func fetchProperties() async throws -> [Property] { properties }
    func fetchRecentExpenses(propertyIds: [String]) async throws -> [Transaction] { recent }
    func checkDuplicates(_ input: ExpenseWorkflowInput) async throws -> [DuplicateExpenseCandidate] {
        checkedInputs.append(input)
        return duplicates
    }
    func createExpense(_ input: ExpenseWorkflowInput) async throws -> String {
        createdInputs.append(input)
        return createdId
    }
    func deleteTransaction(id: String) async throws { deleted.append(id) }
}

@Suite(.serialized)
struct CompactExpenseTests {

    @Test func canSaveRequiresAmountCategoryAndProperty() {
        #expect(!CompactExpenseViewModel.canSave(amount: nil, categoryId: "c", propertyId: "p"))
        #expect(!CompactExpenseViewModel.canSave(amount: 0, categoryId: "c", propertyId: "p"))
        #expect(!CompactExpenseViewModel.canSave(amount: 10, categoryId: nil, propertyId: "p"))
        #expect(!CompactExpenseViewModel.canSave(amount: 10, categoryId: "c", propertyId: nil))
        #expect(CompactExpenseViewModel.canSave(amount: 10, categoryId: "c", propertyId: "p"))
    }

    @Test func recentCategoriesAreRecencyOrderedDedupedAndFiltered() {
        let recent = [
            expenseTxn(id: "1", propertyId: "p1", categoryId: "repairs", date: "2026-06-10"),
            expenseTxn(id: "2", propertyId: "p1", categoryId: "utilities", date: "2026-06-15"),
            expenseTxn(id: "3", propertyId: "p1", categoryId: "repairs", date: "2026-06-16"),
            expenseTxn(id: "4", propertyId: "p1", categoryId: "unknown", date: "2026-06-17"),
        ]
        let ids = CompactExpenseViewModel.recentExpenseCategoryIds(
            recentExpenses: recent, expenseCategoryIds: ["repairs", "utilities"], limit: 5
        )
        #expect(ids == ["repairs", "utilities"])
    }

    @Test func preselectsContextThenLastUsedThenFirst() {
        let props = [property("p1"), property("p2"), property("p3")]
        #expect(CompactExpenseViewModel.preselectedProperty(context: "p2", recentExpenses: [], properties: props) == "p2")
        let recent = [expenseTxn(id: "1", propertyId: "p3", categoryId: "c", date: "2026-06-16")]
        #expect(CompactExpenseViewModel.preselectedProperty(context: nil, recentExpenses: recent, properties: props) == "p3")
        #expect(CompactExpenseViewModel.preselectedProperty(context: "missing", recentExpenses: [], properties: props) == "p1")
    }

    @MainActor
    @Test func saveCreatesTodayWhenNoDuplicate() async throws {
        let client = MockCompactExpenseClient()
        client.createdId = "tx-42"
        let vm = CompactExpenseViewModel(client: client, baseCurrency: "KZT", timeZoneIdentifier: "Asia/Almaty")
        vm.amountText = "12500"; vm.selectedCategoryId = "repairs"; vm.selectedPropertyId = "p1"

        let now = try #require(ISO8601DateFormatter().date(from: "2026-06-17T06:00:00Z"))
        let ok = await vm.save(now: now)

        #expect(ok)
        #expect(vm.lastCreatedId == "tx-42")
        #expect(client.checkedInputs.count == 1)
        let body = try #require(client.createdInputs.first)
        #expect(body.amount == 12500)
        #expect(body.transactionDate == "2026-06-17")
        #expect(!body.allowDuplicate)
    }

    @MainActor
    @Test func duplicatesBlockSaveThenCreateAnywayOverrides() async throws {
        let client = MockCompactExpenseClient()
        client.duplicates = [candidate("dup-1")]
        let vm = CompactExpenseViewModel(client: client, baseCurrency: "KZT", timeZoneIdentifier: "Asia/Almaty")
        vm.amountText = "12500"; vm.selectedCategoryId = "internet"; vm.selectedPropertyId = "p1"

        let created = await vm.save()
        #expect(!created)
        #expect(vm.duplicateCandidates.map(\.id) == ["dup-1"])
        #expect(client.createdInputs.isEmpty) // not created yet
        #expect(vm.errorMessage == nil)

        let overridden = await vm.createAnyway()
        #expect(overridden)
        let body = try #require(client.createdInputs.first)
        #expect(body.allowDuplicate)
        #expect(body.duplicateCandidateIds == ["dup-1"])
        #expect(vm.duplicateCandidates.isEmpty)
    }

    @MainActor
    @Test func undoDeletesLastCreated() async {
        let client = MockCompactExpenseClient()
        client.createdId = "tx-9"
        let vm = CompactExpenseViewModel(client: client, baseCurrency: "KZT", timeZoneIdentifier: "Asia/Almaty")
        vm.amountText = "100"; vm.selectedCategoryId = "c"; vm.selectedPropertyId = "p"
        _ = await vm.save()

        let undone = await vm.undoLast()
        #expect(undone)
        #expect(client.deleted == ["tx-9"])
        #expect(vm.lastCreatedId == nil)
    }

    @MainActor
    @Test func resetForAnotherKeepsPropertyClearsDuplicates() async {
        let client = MockCompactExpenseClient()
        let vm = CompactExpenseViewModel(client: client, baseCurrency: "KZT", timeZoneIdentifier: "Asia/Almaty")
        vm.amountText = "500"; vm.selectedPropertyId = "p1"; vm.note = "такси"

        vm.resetForAnother()
        #expect(vm.amountText == "")
        #expect(vm.note == "")
        #expect(vm.selectedPropertyId == "p1")
        #expect(vm.duplicateCandidates.isEmpty)
    }
}
