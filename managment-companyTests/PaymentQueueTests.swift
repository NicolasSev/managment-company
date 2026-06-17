//
//  PaymentQueueTests.swift
//  managment-companyTests
//
//  Mirrored tests for GAP-026/027 (cross-portfolio payment queue): wire
//  decoding, PATCH intent encoding, queue/history presentation rules, and the
//  view-model action flow against a mock transport.
//

import Foundation
import Testing
@testable import managment_company

@MainActor
private final class MockPaymentQueueClient: PaymentQueueClient {
    var queue: [PaymentQueueItem] = []
    var fetchedScopes: [PaymentQueueScope] = []
    var fetchedMonths: [Int] = []
    var updates: [(scheduleId: String, body: PaymentScheduleUpdateRequest)] = []
    var markPaidCalls: [(scheduleId: String, body: MarkSchedulePaidRequest, idempotencyKey: String)] = []
    var updateError: Error?

    func fetchQueue(scope: PaymentQueueScope, months: Int) async throws -> [PaymentQueueItem] {
        fetchedScopes.append(scope)
        fetchedMonths.append(months)
        return queue
    }

    func updateSchedule(scheduleId: String, body: PaymentScheduleUpdateRequest) async throws {
        if let updateError { throw updateError }
        updates.append((scheduleId, body))
    }

    func markPaid(scheduleId: String, body: MarkSchedulePaidRequest, idempotencyKey: String) async throws {
        if let updateError { throw updateError }
        markPaidCalls.append((scheduleId, body, idempotencyKey))
    }
}

@MainActor
private func makeItem(
    id: String = "00000000-0000-0000-0000-00000000000a",
    dueDate: String = "2026-07-05",
    periodStartDate: String? = "2026-07-01",
    expectedAmount: Double = 95000,
    currency: String = "KZT",
    actualAmount: Double? = nil,
    paidAt: String? = nil,
    status: String = "pending",
    isOverdue: Bool = false
) -> PaymentQueueItem {
    PaymentQueueItem(
        id: id,
        leaseId: "00000000-0000-0000-0000-00000000000b",
        dueDate: dueDate,
        periodStartDate: periodStartDate,
        periodEndDate: nil,
        expectedAmount: expectedAmount,
        currency: currency,
        actualAmount: actualAmount,
        paidAt: paidAt,
        status: status,
        isOverdue: isOverdue,
        daysOverdue: 0,
        propertyId: "00000000-0000-0000-0000-00000000000c",
        propertyName: "Flat A",
        propertyAddress: "Street 1",
        tenantId: "00000000-0000-0000-0000-00000000000d",
        tenantName: "Иван",
        paymentDay: 5
    )
}

@Suite(.serialized)
struct PaymentQueueTests {

    // MARK: Wire decoding

    @Test func decodesPaymentQueueListEnvelope() throws {
        let json = """
        {"data":[{"id":"00000000-0000-0000-0000-000000000001","lease_id":"00000000-0000-0000-0000-000000000002",
        "due_date":"2026-07-05","period_start_date":"2026-07-01","period_end_date":"2026-07-31",
        "notification_due_date":null,"notification_sent_at":null,
        "expected_amount":95000,"currency":"KZT",
        "actual_payment_id":null,"actual_amount":null,"paid_at":null,"transaction_id":null,
        "status":"pending","is_overdue":true,"days_overdue":3,
        "property_id":"00000000-0000-0000-0000-000000000003","property_name":"Flat A","property_address":"Street 1",
        "tenant_id":"00000000-0000-0000-0000-000000000004","tenant_name":"Иван","payment_day":5}],
        "page":1,"per_page":100,"total":1}
        """
        let decoded = try JSONDecoder().decode(APIListEnvelope<PaymentQueueItem>.self, from: json.data(using: .utf8)!)
        #expect(decoded.data.count == 1)
        let item = try #require(decoded.data.first)
        #expect(item.propertyName == "Flat A")
        #expect(item.tenantName == "Иван")
        #expect(item.paymentDay == 5)
        #expect(item.expectedAmount == 95000)
        #expect(item.isOverdue)
        #expect(decoded.total == 1)
    }

    @MainActor
    @Test func bridgesQueueItemToLeaseScheduleForMarkPaidReuse() {
        let item = makeItem(actualAmount: 90000, paidAt: "2026-07-06", status: "paid")
        let schedule = item.asLeaseSchedule
        #expect(schedule.id == item.id)
        #expect(schedule.leaseId == item.leaseId)
        #expect(schedule.dueDate == item.dueDate)
        #expect(schedule.expectedAmount == item.expectedAmount)
        #expect(schedule.currency == item.currency)
        #expect(schedule.status == "paid")
        #expect(schedule.actualAmount == 90000)
    }

    // MARK: PATCH /v1/payment-schedules/:id — exactly one intent per call

    @Test func updateRequestEncodesSingleIntentPerCall() throws {
        func encodedKeys(_ body: PaymentScheduleUpdateRequest) throws -> [String: Any] {
            let data = try JSONEncoder().encode(body)
            return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }

        let day = try encodedKeys(.day(10))
        #expect(day.count == 1)
        #expect(day["due_day"] as? Int == 10)

        let amount = try encodedKeys(.amount(120000))
        #expect(amount.count == 1)
        #expect(amount["expected_amount"] as? Double == 120000)

        let skip = try encodedKeys(.skip)
        #expect(skip.count == 1)
        #expect(skip["action"] as? String == "skip")

        let restore = try encodedKeys(.restore)
        #expect(restore.count == 1)
        #expect(restore["action"] as? String == "restore")
    }

    // MARK: Presentation rules

    @MainActor
    @Test func upcomingTotalsSumExpectedAmountsPerCurrency() {
        let items = [
            makeItem(id: "1", expectedAmount: 100, currency: "KZT"),
            makeItem(id: "2", expectedAmount: 50, currency: "USD"),
            makeItem(id: "3", expectedAmount: 200, currency: "KZT"),
        ]
        let totals = PaymentsQueueViewModel.totalsByCurrency(items: items, scope: .upcoming)
        #expect(totals.count == 2)
        #expect(totals[0].currency == "KZT")
        #expect(totals[0].total == 300)
        #expect(totals[1].currency == "USD")
        #expect(totals[1].total == 50)
    }

    @MainActor
    @Test func pastTotalsCountOnlyReceivedMoneyExcludingSkipped() {
        let items = [
            makeItem(id: "1", expectedAmount: 100, actualAmount: 90, paidAt: "2026-05-06", status: "paid"),
            makeItem(id: "2", expectedAmount: 100, actualAmount: nil, status: "skipped"),
            makeItem(id: "3", expectedAmount: 100, actualAmount: 110, paidAt: "2026-06-06", status: "paid"),
        ]
        let totals = PaymentsQueueViewModel.totalsByCurrency(items: items, scope: .past)
        #expect(totals.count == 1)
        #expect(totals[0].total == 200)
    }

    @MainActor
    @Test func skippedHistoryRowsHaveNoRecordDate() {
        let skipped = makeItem(status: "skipped")
        #expect(PaymentsQueueViewModel.recordedDate(of: skipped) == nil)

        let paid = makeItem(actualAmount: 95000, paidAt: "2026-05-06", status: "paid")
        #expect(PaymentsQueueViewModel.recordedDate(of: paid) == "2026-05-06")

        let paidWithoutTimestamp = makeItem(status: "paid")
        #expect(PaymentsQueueViewModel.recordedDate(of: paidWithoutTimestamp) == paidWithoutTimestamp.dueDate)
    }

    @MainActor
    @Test func onlyPaidHistoryRestoreRequiresConfirmation() {
        #expect(!PaymentsQueueViewModel.restoreRequiresConfirmation(for: makeItem(status: "skipped")))
        #expect(PaymentsQueueViewModel.restoreRequiresConfirmation(
            for: makeItem(actualAmount: 95000, paidAt: "2026-05-06", status: "paid")
        ))
    }

    @MainActor
    @Test func overdueWinsOverPendingOnlyInUpcomingQueue() {
        let overdue = makeItem(status: "pending", isOverdue: true)
        #expect(PaymentsQueueViewModel.displayStatus(of: overdue, scope: .upcoming) == "overdue")

        let paid = makeItem(actualAmount: 95000, status: "paid", isOverdue: true)
        #expect(PaymentsQueueViewModel.displayStatus(of: paid, scope: .past) == "paid")
    }

    @MainActor
    @Test func extractsDueDayFromISODateForEditSeed() {
        #expect(PaymentsQueueViewModel.dueDay(fromISODate: "2026-07-05") == 5)
        #expect(PaymentsQueueViewModel.dueDay(fromISODate: "2026-12-28") == 28)
        #expect(PaymentsQueueViewModel.dueDay(fromISODate: "bad") == nil)
    }

    @MainActor
    @Test func periodLabelUsesPeriodStartWithDueDateFallback() {
        let withPeriod = makeItem(periodStartDate: "2026-05-01")
        #expect(PaymentsQueueViewModel.periodLabel(of: withPeriod) == "Май 2026")

        let withoutPeriod = makeItem(dueDate: "2026-07-05", periodStartDate: nil)
        #expect(PaymentsQueueViewModel.periodLabel(of: withoutPeriod) == "Июль 2026")
    }

    // MARK: View-model action flow

    @MainActor
    @Test func loadFetchesQueueForScopeAndHorizon() async {
        let client = MockPaymentQueueClient()
        client.queue = [makeItem()]
        let vm = PaymentsQueueViewModel(client: client)
        vm.scope = .past
        vm.months = 6

        await vm.load()

        #expect(vm.items.count == 1)
        #expect(vm.errorMessage == nil)
        #expect(client.fetchedScopes == [.past])
        #expect(client.fetchedMonths == [6])
    }

    @MainActor
    @Test func skipSendsSkipIntentAndReloads() async {
        let client = MockPaymentQueueClient()
        let item = makeItem()
        client.queue = [item]
        let vm = PaymentsQueueViewModel(client: client)
        await vm.load()
        client.queue = []

        let ok = await vm.skip(item)

        #expect(ok)
        #expect(client.updates.count == 1)
        #expect(client.updates[0].scheduleId == item.id)
        #expect(client.updates[0].body == .skip)
        #expect(vm.items.isEmpty)
    }

    @MainActor
    @Test func restoreSendsRestoreIntentAndReloadsHistory() async {
        let client = MockPaymentQueueClient()
        let item = makeItem(status: "skipped")
        client.queue = [item]
        let vm = PaymentsQueueViewModel(client: client)
        vm.scope = .past
        await vm.load()
        client.queue = []

        let ok = await vm.restore(item)

        #expect(ok)
        #expect(client.updates.count == 1)
        #expect(client.updates[0].scheduleId == item.id)
        #expect(client.updates[0].body == .restore)
        #expect(client.fetchedScopes == [.past, .past])
        #expect(vm.items.isEmpty)
    }

    @MainActor
    @Test func applyEditSendsDayThenAmountAsSeparateIntents() async {
        let client = MockPaymentQueueClient()
        let item = makeItem()
        let vm = PaymentsQueueViewModel(client: client)

        let ok = await vm.applyEdit(to: item, day: 10, amount: 120000)

        #expect(ok)
        #expect(client.updates.count == 2)
        #expect(client.updates[0].body == .day(10))
        #expect(client.updates[1].body == .amount(120000))
    }

    @MainActor
    @Test func failedMutationSurfacesErrorAndReturnsFalse() async {
        let client = MockPaymentQueueClient()
        client.updateError = APIError.httpStatus(500)
        let vm = PaymentsQueueViewModel(client: client)

        let ok = await vm.skip(makeItem())

        #expect(!ok)
        #expect(vm.errorMessage != nil)
    }

    // MARK: GAP-030 — actual payment date correctness

    /// The shared day-key helper resolves "today" in the workspace timezone, not
    /// UTC: 20:30Z on 2026-06-16 is already 2026-06-17 in Asia/Almaty (UTC+5).
    @Test func dayKeyUsesWorkspaceTimezoneNotUTC() throws {
        let iso = ISO8601DateFormatter()
        let instant = try #require(iso.date(from: "2026-06-16T20:30:00Z"))
        #expect(AppFormatting.dayKey(for: instant, timeZoneIdentifier: "Asia/Almaty") == "2026-06-17")
        #expect(AppFormatting.dayKey(for: instant, timeZoneIdentifier: "UTC") == "2026-06-16")
    }

    /// Regression for the GAP-030 invariant: an installment due in a previous
    /// month but recorded today sends today's date — never the contractual due
    /// date — and carries the expected amount/currency.
    @MainActor
    @Test func fastMarkPaidBodyRecordsTodayNotDueDate() throws {
        let iso = ISO8601DateFormatter()
        let now = try #require(iso.date(from: "2026-06-16T09:00:00Z"))
        let overdue = makeItem(dueDate: "2026-04-05", expectedAmount: 95000, currency: "KZT", isOverdue: true)

        let body = PaymentsQueueViewModel.fastMarkPaidBody(
            for: overdue,
            timeZoneIdentifier: "Asia/Almaty",
            now: now
        )

        #expect(body.paymentDate == "2026-06-16")
        #expect(body.paymentDate != overdue.dueDate)
        #expect(body.amount == 95000)
        #expect(body.currency == "KZT")
    }

    @MainActor
    @Test func markPaidTodaySendsTodayDatedBodyAndReloads() async throws {
        let iso = ISO8601DateFormatter()
        let now = try #require(iso.date(from: "2026-06-16T09:00:00Z"))
        let client = MockPaymentQueueClient()
        let item = makeItem(dueDate: "2026-04-05", expectedAmount: 95000, currency: "KZT", isOverdue: true)
        client.queue = [item]
        let vm = PaymentsQueueViewModel(client: client)
        await vm.load()
        client.queue = []

        let ok = await vm.markPaidToday(item, timeZoneIdentifier: "Asia/Almaty", now: now)

        #expect(ok)
        #expect(client.markPaidCalls.count == 1)
        #expect(client.markPaidCalls[0].scheduleId == item.id)
        #expect(client.markPaidCalls[0].body.paymentDate == "2026-06-16")
        #expect(client.markPaidCalls[0].idempotencyKey == "ios-queue-\(item.id)-2026-06-16")
        #expect(vm.items.isEmpty)
    }

    @MainActor
    @Test func markPaidTodayFailureSurfacesError() async {
        let client = MockPaymentQueueClient()
        client.updateError = APIError.httpStatus(500)
        let vm = PaymentsQueueViewModel(client: client)

        let ok = await vm.markPaidToday(makeItem(), timeZoneIdentifier: "Asia/Almaty")

        #expect(!ok)
        #expect(vm.errorMessage != nil)
    }
}
