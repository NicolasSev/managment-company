//
//  RecurringExpensesTests.swift
//  managment-companyTests
//
//  Mirrored tests for GAP-039 (recurring expense templates): active/paused
//  grouping, due filtering, pause/resume status flip, and confirm/create flow.
//

import Foundation
import Testing
@testable import managment_company

private func template(
    id: String,
    status: String = "active",
    next: String = "2026-06-01",
    amount: Double = 50000,
    cadence: String = "monthly"
) -> RecurringExpenseTemplate {
    RecurringExpenseTemplate(
        id: id, propertyId: "p1", propertyName: "Алматы", categoryId: "c1", categoryName: "Интернет",
        amount: amount, currency: "KZT", payee: nil, description: nil, cadence: cadence,
        dayOfMonth: 1, timezone: "Asia/Almaty", nextOccurrence: next, status: status
    )
}

@MainActor
private final class MockRecurringClient: RecurringExpenseClient {
    var templates: [RecurringExpenseTemplate] = []
    var due: [RecurringExpenseTemplate] = []
    var confirmed: [String] = []
    var skipped: [String] = []
    var deleted: [String] = []
    var updated: [(id: String, status: String)] = []
    var created: [RecurringExpenseInput] = []

    func list() async throws -> [RecurringExpenseTemplate] { templates }
    func listDue() async throws -> [RecurringExpenseTemplate] { due }
    func create(_ input: RecurringExpenseInput) async throws { created.append(input) }
    func update(id: String, _ input: RecurringExpenseInput) async throws { updated.append((id, input.status)) }
    func delete(id: String) async throws { deleted.append(id) }
    func confirm(id: String) async throws { confirmed.append(id) }
    func skip(id: String) async throws { skipped.append(id) }
}

@Suite(.serialized)
struct RecurringExpensesTests {

    @Test func dueFiltersActiveOnOrBeforeToday() {
        let all = [
            template(id: "a", status: "active", next: "2026-06-01"),
            template(id: "b", status: "active", next: "2026-07-01"),
            template(id: "c", status: "paused", next: "2026-06-01"),
        ]
        let due = RecurringExpensesViewModel.dueTemplates(all, today: "2026-06-17")
        #expect(due.map(\.id) == ["a"])
    }

    @Test func toggleStatusFlipsActiveAndPaused() {
        let active = template(id: "a", status: "active")
        #expect(RecurringExpensesViewModel.toggleStatusInput(for: active).status == "paused")
        let paused = template(id: "b", status: "paused")
        #expect(RecurringExpensesViewModel.toggleStatusInput(for: paused).status == "active")
    }

    @MainActor
    @Test func loadGroupsActiveAndPaused() async {
        let client = MockRecurringClient()
        client.templates = [
            template(id: "a", status: "active"),
            template(id: "b", status: "paused"),
            template(id: "c", status: "active"),
        ]
        let vm = RecurringExpensesViewModel(client: client)
        await vm.load()
        #expect(vm.activeTemplates.map(\.id) == ["a", "c"])
        #expect(vm.pausedTemplates.map(\.id) == ["b"])
    }

    @MainActor
    @Test func confirmAndTogglePauseCallClientAndReload() async {
        let client = MockRecurringClient()
        client.templates = [template(id: "a", status: "active")]
        let vm = RecurringExpensesViewModel(client: client)
        await vm.load()

        let confirmed = await vm.confirm(template(id: "a"))
        #expect(confirmed)
        #expect(client.confirmed == ["a"])

        let toggled = await vm.togglePause(template(id: "a", status: "active"))
        #expect(toggled)
        #expect(client.updated.last?.status == "paused")
    }
}
