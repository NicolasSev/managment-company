//
//  CompactExpenseTests.swift
//  managment-companyTests
//
//  Mirrored tests for GAP-033 (compact expense capture): validation, recent
//  category ordering, property preselection, save (today/expense) + Undo, and
//  «Добавить ещё» reset.
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

@MainActor
private final class MockCompactExpenseClient: CompactExpenseClient {
    var categories: [Category] = []
    var properties: [Property] = []
    var recent: [Transaction] = []
    var createdId = "tx-new"
    var createdBodies: [CompactExpenseInput] = []
    var deleted: [String] = []
    var failCreate = false

    private struct Boom: Error {}

    func fetchCategories() async throws -> [Category] { categories }
    func fetchProperties() async throws -> [Property] { properties }
    func fetchRecentExpenses(propertyIds: [String]) async throws -> [Transaction] { recent }
    func createExpense(propertyId: String, body: CompactExpenseInput) async throws -> String {
        if failCreate { throw Boom() }
        createdBodies.append(body)
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
            recentExpenses: recent,
            expenseCategoryIds: ["repairs", "utilities"],
            limit: 5
        )
        // unknown filtered out; repairs is most recent (06-16), then utilities (06-15).
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
    @Test func loadPreselectsPropertyAndRecentCategory() async {
        let client = MockCompactExpenseClient()
        client.categories = [category("repairs", "Ремонт", sort: 1), category("utilities", "Коммуналка", sort: 2)]
        client.properties = [property("p1"), property("p2")]
        client.recent = [expenseTxn(id: "1", propertyId: "p2", categoryId: "utilities", date: "2026-06-16")]
        let vm = CompactExpenseViewModel(client: client, baseCurrency: "KZT", timeZoneIdentifier: "Asia/Almaty")

        await vm.load()

        #expect(vm.selectedPropertyId == "p2")
        #expect(vm.selectedCategoryId == "utilities")
        #expect(vm.recentChips.map(\.id) == ["utilities"])
    }

    @MainActor
    @Test func saveSendsExpenseTodayAndStoresUndoId() async throws {
        let client = MockCompactExpenseClient()
        client.createdId = "tx-42"
        let vm = CompactExpenseViewModel(client: client, baseCurrency: "KZT", timeZoneIdentifier: "Asia/Almaty")
        vm.amountText = "12500"
        vm.selectedCategoryId = "repairs"
        vm.selectedPropertyId = "p1"

        let iso = ISO8601DateFormatter()
        let now = try #require(iso.date(from: "2026-06-17T06:00:00Z"))
        let ok = await vm.save(now: now)

        #expect(ok)
        #expect(vm.lastCreatedId == "tx-42")
        let body = try #require(client.createdBodies.first)
        #expect(body.type == "expense")
        #expect(body.amount == 12500)
        #expect(body.currency == "KZT")
        #expect(body.transactionDate == "2026-06-17")
    }

    @MainActor
    @Test func undoDeletesLastCreated() async {
        let client = MockCompactExpenseClient()
        client.createdId = "tx-9"
        let vm = CompactExpenseViewModel(client: client, baseCurrency: "KZT", timeZoneIdentifier: "Asia/Almaty")
        vm.amountText = "100"
        vm.selectedCategoryId = "c"
        vm.selectedPropertyId = "p"
        _ = await vm.save()

        let undone = await vm.undoLast()

        #expect(undone)
        #expect(client.deleted == ["tx-9"])
        #expect(vm.lastCreatedId == nil)
    }

    @MainActor
    @Test func resetForAnotherKeepsPropertyAndDate() async {
        let client = MockCompactExpenseClient()
        let vm = CompactExpenseViewModel(client: client, baseCurrency: "KZT", timeZoneIdentifier: "Asia/Almaty")
        vm.amountText = "500"
        vm.selectedPropertyId = "p1"
        vm.note = "такси"

        vm.resetForAnother()

        #expect(vm.amountText == "")
        #expect(vm.note == "")
        #expect(vm.selectedPropertyId == "p1")
    }
}
