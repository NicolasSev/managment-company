//
//  DepositTests.swift
//  managment-companyTests
//
//  Mirrored tests for GAP-041 (security-deposit lifecycle): held-balance guard,
//  active-event filtering, summary decoding, and event/reversal flow.
//

import Foundation
import Testing
@testable import managment_company

private func event(id: String, type: String, amount: Double, reversed: Bool = false) -> LeaseDepositEvent {
    LeaseDepositEvent(
        id: id, leaseId: "l1", eventType: type, amount: amount, currency: "KZT",
        eventDate: "2026-06-01", reason: nil, transactionId: nil,
        reversedAt: reversed ? "2026-06-02T00:00:00Z" : nil
    )
}

@MainActor
private final class MockDepositClient: DepositClient {
    var summary: DepositSummary
    var created: [DepositEventInput] = []
    var reversed: [String] = []

    init(summary: DepositSummary) { self.summary = summary }

    func summary(leaseId: String) async throws -> DepositSummary { summary }
    func createEvent(leaseId: String, input: DepositEventInput) async throws { created.append(input) }
    func reverseEvent(eventId: String) async throws { reversed.append(eventId) }
}

private func makeSummary(held: Double, events: [LeaseDepositEvent]) -> DepositSummary {
    DepositSummary(
        leaseId: "l1", expected: 100000, received: 100000, deductions: 0, refunded: 0,
        held: held, outstanding: held, currency: "KZT", status: "held", events: events
    )
}

@Suite(.serialized)
struct DepositTests {

    @Test func canApplyGuardsHeldForDeductionAndRefund() {
        #expect(DepositViewModel.canApply(eventType: "received", amount: 50000, held: 0))
        #expect(DepositViewModel.canApply(eventType: "deduction", amount: 40000, held: 100000))
        #expect(!DepositViewModel.canApply(eventType: "deduction", amount: 120000, held: 100000))
        #expect(!DepositViewModel.canApply(eventType: "refunded", amount: 0, held: 100000))
    }

    @Test func decodesSummaryEnvelopeAndEvents() throws {
        let json = """
        {"lease_id":"l1","expected":100000,"received":100000,"deductions":20000,"refunded":80000,
        "held":0,"outstanding":0,"currency":"KZT","status":"refunded",
        "events":[{"id":"e1","lease_id":"l1","event_type":"received","amount":100000,"currency":"KZT",
        "event_date":"2026-01-01","reason":null,"transaction_id":"t1","reversed_at":null}]}
        """
        let summary = try JSONDecoder().decode(DepositSummary.self, from: json.data(using: .utf8)!)
        #expect(summary.refunded == 80000)
        #expect(summary.status == "refunded")
        #expect(summary.events.count == 1)
        #expect(summary.events[0].eventType == "received")
    }

    @MainActor
    @Test func activeEventsExcludeReversed() async {
        let client = MockDepositClient(summary: makeSummary(held: 100000, events: [
            event(id: "a", type: "received", amount: 100000),
            event(id: "b", type: "deduction", amount: 20000, reversed: true),
        ]))
        let vm = DepositViewModel(client: client, leaseId: "l1", baseCurrency: "KZT")
        await vm.load()
        #expect(vm.activeEvents.map(\.id) == ["a"])
    }

    @MainActor
    @Test func addEventAndReverseCallClient() async {
        let client = MockDepositClient(summary: makeSummary(held: 100000, events: [
            event(id: "a", type: "received", amount: 100000),
        ]))
        let vm = DepositViewModel(client: client, leaseId: "l1", baseCurrency: "KZT")
        await vm.load()

        let added = await vm.addEvent(type: "deduction", amount: 30000, reason: "Ремонт", now: Date(), timeZoneIdentifier: "Asia/Almaty")
        #expect(added)
        #expect(client.created.count == 1)
        #expect(client.created[0].eventType == "deduction")
        #expect(client.created[0].amount == 30000)

        let reversed = await vm.reverse(event(id: "a", type: "received", amount: 100000))
        #expect(reversed)
        #expect(client.reversed == ["a"])
    }
}
