//
//  TodayTests.swift
//  managment-companyTests
//
//  Mirrored tests for GAP-031 (iOS Сегодня operating screen): Attention block
//  ordering/counts, money summary, urgent-task rule, partial-error degradation,
//  and resolved-item disappearance.
//

import Foundation
import Testing
@testable import managment_company

@MainActor
private func queueItem(
    id: String,
    dueDate: String = "2026-06-17",
    expectedAmount: Double = 95000,
    currency: String = "KZT",
    status: String = "pending",
    isOverdue: Bool = false,
    daysOverdue: Int = 0,
    propertyName: String = "Flat A",
    tenantName: String = "Иван"
) -> PaymentQueueItem {
    PaymentQueueItem(
        id: id,
        leaseId: "lease-\(id)",
        dueDate: dueDate,
        periodStartDate: nil,
        periodEndDate: nil,
        expectedAmount: expectedAmount,
        currency: currency,
        actualAmount: nil,
        paidAt: nil,
        status: status,
        isOverdue: isOverdue,
        daysOverdue: daysOverdue,
        propertyId: "prop-1",
        propertyName: propertyName,
        propertyAddress: nil,
        tenantId: "ten-1",
        tenantName: tenantName,
        paymentDay: 5
    )
}

private func task(
    id: String,
    title: String = "Задача",
    status: String = "pending",
    priority: String = "medium",
    dueDate: String? = nil
) -> AppTask {
    AppTask(
        id: id,
        propertyId: nil,
        title: title,
        description: nil,
        priority: priority,
        status: status,
        dueDate: dueDate,
        reminderAt: nil,
        completedAt: nil
    )
}

@MainActor
private final class MockTodayClient: TodayDataClient {
    var queue: [PaymentQueueItem] = []
    var tasks: [AppTask] = []
    var renewals: [UpcomingRenewal] = []
    var receipts: [UtilityReceiptPayload] = []
    var dashboard: AnalyticsDashboard?
    var properties: [Property] = []
    var tenants: [Tenant] = []
    var recent: [Transaction] = []
    var failing: Set<TodaySource> = []
    var markPaidCalls: [String] = []
    var completedTasks: [String] = []

    private struct Boom: Error {}

    func fetchUpcomingQueue() async throws -> [PaymentQueueItem] {
        if failing.contains(.payments) { throw Boom() }
        return queue
    }
    func fetchTasks() async throws -> [AppTask] {
        if failing.contains(.tasks) { throw Boom() }
        return tasks
    }
    func fetchRenewals(days: Int) async throws -> [UpcomingRenewal] {
        if failing.contains(.renewals) { throw Boom() }
        return renewals
    }
    func fetchReceipts() async throws -> [UtilityReceiptPayload] {
        if failing.contains(.receipts) { throw Boom() }
        return receipts
    }
    func fetchDashboard() async throws -> AnalyticsDashboard {
        if failing.contains(.dashboard) { throw Boom() }
        guard let dashboard else { throw Boom() }
        return dashboard
    }
    func fetchProperties() async throws -> [Property] { properties }
    func fetchTenants() async throws -> [Tenant] { tenants }
    func fetchRecentTransactions(propertyIds: [String]) async throws -> [Transaction] { recent }
    var profitability = ProfitabilityReport(groupBy: "month", from: "", to: "", points: [], totals: [])
    func fetchProfitability(from: String, to: String) async throws -> ProfitabilityReport { profitability }
    var dueRecurring: [RecurringExpenseTemplate] = []
    func fetchDueRecurring() async throws -> [RecurringExpenseTemplate] { dueRecurring }
    func confirmRecurring(id: String) async throws {}
    func skipRecurring(id: String) async throws {}
    func markPaid(scheduleId: String, body: MarkSchedulePaidRequest, idempotencyKey: String) async throws {
        markPaidCalls.append(scheduleId)
        queue.removeAll { $0.id == scheduleId }
    }
    func completeTask(id: String) async throws {
        completedTasks.append(id)
        tasks.removeAll { $0.id == id }
    }
}

@Suite(.serialized)
struct TodayTests {

    // MARK: Pure aggregation

    @MainActor
    @Test func attentionItemsOrderAcrossKinds() {
        let items = TodayViewModel.attentionItems(
            today: "2026-06-17",
            queue: [
                queueItem(id: "due", dueDate: "2026-06-17"),
                queueItem(id: "over", dueDate: "2026-05-01", isOverdue: true, daysOverdue: 47),
            ],
            tasks: [task(id: "t1", status: "pending", priority: "urgent")],
            renewals: [UpcomingRenewal(leaseId: "l1", propertyId: "prop-1", tenantId: "ten-1", endDate: "2026-07-01")],
            receipts: [UtilityReceiptPayload(id: "r1", status: "parsed", fileId: "f1")],
            propertyNames: ["prop-1": "Flat A"],
            tenantNames: ["ten-1": "Иван"]
        )
        // Overdue rent → due-today rent → task → renewal → receipt.
        #expect(items.map(\.kind) == [.overdueRent, .dueTodayRent, .task, .renewal, .receipt])
        #expect(items.count == 5)
    }

    @MainActor
    @Test func attentionEmptyWhenNothingUrgent() {
        let items = TodayViewModel.attentionItems(
            today: "2026-06-17",
            queue: [queueItem(id: "future", dueDate: "2026-09-01")],
            tasks: [task(id: "t", status: "done", priority: "high")],
            renewals: [],
            receipts: [UtilityReceiptPayload(id: "r", status: "confirmed", fileId: "f")],
            propertyNames: [:],
            tenantNames: [:]
        )
        #expect(items.isEmpty)
    }

    @Test func urgentTaskRuleCoversDueAndPriorityAndExcludesClosed() {
        #expect(TodayViewModel.isUrgentTask(task(id: "1", status: "pending", priority: "low", dueDate: "2026-06-17"), today: "2026-06-17"))
        #expect(TodayViewModel.isUrgentTask(task(id: "2", status: "pending", priority: "high"), today: "2026-06-17"))
        #expect(!TodayViewModel.isUrgentTask(task(id: "3", status: "pending", priority: "low", dueDate: "2026-12-31"), today: "2026-06-17"))
        #expect(!TodayViewModel.isUrgentTask(task(id: "4", status: "done", priority: "urgent"), today: "2026-06-17"))
    }

    @Test func moneySummarySplitsRentAndOtherIncome() {
        let dashboard = AnalyticsDashboard(
            totalIncome: 300000, totalExpense: 50000, netCashflow: 250000,
            expectedRent: 280000, rentReceived: 250000, rentOutstanding: 30000,
            depositIncome: 0, periodYear: 2026, periodMonth: 6, period: "month",
            periodLabel: "Июнь 2026", periodFrom: "2026-06-01", periodTo: "2026-06-30"
        )
        let summary = TodayViewModel.moneySummary(from: dashboard, baseCurrency: "KZT")
        #expect(summary.rentReceived == 250000)
        #expect(summary.otherIncome == 50000)
        #expect(summary.expenses == 50000)
        #expect(summary.net == 250000)
        #expect(summary.currency == "KZT")
    }

    // MARK: View-model load

    @MainActor
    @Test func loadPopulatesBlocksWithoutPartialError() async {
        let client = MockTodayClient()
        client.queue = [queueItem(id: "over", dueDate: "2026-05-01", isOverdue: true, daysOverdue: 10)]
        client.dashboard = AnalyticsDashboard(
            totalIncome: 100, totalExpense: 20, netCashflow: 80, expectedRent: 100,
            rentReceived: 90, rentOutstanding: 10, depositIncome: 0, periodYear: 2026,
            periodMonth: 6, period: "month", periodLabel: "Июнь 2026", periodFrom: nil, periodTo: nil
        )
        let vm = TodayViewModel(client: client, timeZoneIdentifier: "Asia/Almaty", baseCurrency: "KZT")

        await vm.load()

        #expect(vm.attentionCount == 1)
        #expect(!vm.hasPartialError)
        #expect(vm.moneySummary?.otherIncome == 10)
    }

    @MainActor
    @Test func partialFailureDegradesOnlyThatSource() async {
        let client = MockTodayClient()
        client.queue = [queueItem(id: "over", isOverdue: true, daysOverdue: 3)]
        client.failing = [.renewals]
        let vm = TodayViewModel(client: client, timeZoneIdentifier: "Asia/Almaty", baseCurrency: "KZT")

        await vm.load()

        #expect(vm.hasPartialError)
        #expect(vm.failedSources.contains(.renewals))
        // The rest of the page still works.
        #expect(vm.attentionCount == 1)
    }

    // MARK: GAP-035 — property-performance drilldown

    @Test func propertyPerformanceAggregatesByPropertyAndSorts() {
        func point(_ pid: String, _ name: String, income: Double, expense: Double) -> ProfitabilityPoint {
            ProfitabilityPoint(
                propertyId: pid, propertyName: name, periodKey: "2026-06", periodLabel: "Июнь",
                periodYear: 2026, periodMonth: 6, periodQuarter: nil, periodSeason: nil,
                totalIncome: income, totalExpense: expense, utilityExpense: 0, operatingCost: 0,
                netCashflow: income - expense, profitMarginPct: 0
            )
        }
        let rows = TodayViewModel.propertyPerformance(points: [
            point("p1", "Алматы", income: 300000, expense: 100000),
            point("p2", "Астана", income: 150000, expense: 200000),
            point("p1", "Алматы", income: 50000, expense: 0), // second period for p1
        ])
        // p1 aggregated: income 350000, expense 100000, net 250000.
        let p1 = rows.first { $0.id == "p1" }
        #expect(p1?.income == 350000)
        #expect(p1?.net == 250000)

        let byNet = TodayViewModel.sortPerformance(rows, by: .net)
        #expect(byNet.first?.id == "p1")
        let byName = TodayViewModel.sortPerformance(rows, by: .name)
        #expect(byName.first?.name == "Алматы")
        let byExpense = TodayViewModel.sortPerformance(rows, by: .expense)
        #expect(byExpense.first?.id == "p2") // 200000 highest expense
    }

    @MainActor
    @Test func resolvedRentRowDisappearsAfterMarkPaid() async {
        let client = MockTodayClient()
        let item = queueItem(id: "over", dueDate: "2026-05-01", isOverdue: true, daysOverdue: 30)
        client.queue = [item]
        let vm = TodayViewModel(client: client, timeZoneIdentifier: "Asia/Almaty", baseCurrency: "KZT")
        await vm.load()
        #expect(vm.attentionCount == 1)

        let ok = await vm.markPaidToday(item)

        #expect(ok)
        #expect(client.markPaidCalls == ["over"])
        #expect(vm.attentionCount == 0)
    }
}
