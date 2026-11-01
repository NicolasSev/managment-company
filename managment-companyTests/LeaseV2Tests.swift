//
//  LeaseV2Tests.swift
//  managment-companyTests
//
//  Lease v2 (task L12): contract fixtures decode into the models, the fixture-backed mock
//  imitates the status machine and money rules, and LeaseDetailViewModel drives it.
//  Canonical source: apps/ios/PropManager/Tests (mirrored into the wrapper test target by
//  `make ios-sync`). Fixtures come from the app bundle (Core/Resources/LeaseV2Fixtures).
//

import Foundation
import Testing
@testable import managment_company

private let activeLeaseId = "7c1e2a40-5b3d-4f8e-9a61-2d4c8b1f0a01"
private let pendingLeaseId = "2d9f6b14-8a3c-4e71-b5d0-6c1e9a7f3b02"
/// Partially paid, overdue rent charge of the active fixture (380 000, paid 200 000).
private let partialChargeId = "f2a6d9c3-8e14-4b7a-a5d0-3c9e1b6f2a88"
/// Overdue extra charge (25 000).
private let extraChargeId = "c8a3e1d0-5f2b-4a7c-9e61-0e0261020001"
/// Next unpaid rent charge (380 000, due 2026-11-10).
private let nextChargeId = "d8b5c2e9-1f47-4a3b-9e6d-0c2a7f4b8e19"

private func kzt(_ major: Int) -> Money {
    Money(minor: Int64(major) * 100, currency: "KZT")
}

private func fixtureData(_ name: String) throws -> Data {
    try LeaseV2Fixtures.data(named: name)
}

private func makeMock() throws -> MockLeaseV2Service {
    try MockLeaseV2Service.fromFixtures()
}

@MainActor
private final class RecordingQueue: LeaseChargePaymentQueueing {
    var enqueued: [(chargeId: String, leaseId: String, body: PayChargeRequest, key: String)] = []

    func enqueueLeaseChargePayment(chargeId: String, leaseId: String, body: PayChargeRequest, idempotencyKey: String) throws {
        enqueued.append((chargeId, leaseId, body, idempotencyKey))
    }
}

@MainActor
private func makeViewModel(
    leaseId: String = activeLeaseId,
    service: MockLeaseV2Service? = nil,
    queue: LeaseChargePaymentQueueing? = nil
) async throws -> (LeaseDetailViewModel, MockLeaseV2Service) {
    let mock = try service ?? makeMock()
    let viewModel = LeaseDetailViewModel(
        leaseId: leaseId,
        service: mock,
        paymentQueue: queue,
        today: { LeaseDay.pickerDate("2026-11-01") ?? Date() }
    )
    await viewModel.load()
    return (viewModel, mock)
}

// MARK: - Decoding

@MainActor
@Suite(.serialized)
struct LeaseV2DecodingTests {
    @Test func decodesActiveAggregateFixture() throws {
        let lease = try LeaseV2Fixtures.aggregate(named: LeaseV2Fixtures.activeName)

        #expect(lease.id == activeLeaseId)
        #expect(lease.status == .active)
        #expect(lease.version == 15)
        #expect(lease.rentAmount == kzt(350_000))
        #expect(lease.currentRentAmount == kzt(380_000))
        #expect(lease.depositAmount == kzt(350_000))
        #expect(lease.dueDay == 10)
        #expect(lease.prolongationCount == 0)
        #expect(lease.activationDate == "2026-03-15")
        #expect(lease.endDate == "2027-03-14")
        #expect(lease.property.name == "ЖК «Есентай Парк», кв. 47")
        #expect(lease.tenant.fullName == "Касымова Айгерим Нурлановна")
        #expect(lease.lifecycle.signedOn == "2026-03-14")
        #expect(lease.amendments.count == 1)
        #expect(lease.amendments[0].rentAmount == kzt(380_000))
        #expect(lease.amendments[0].dueDay == nil)

        #expect(lease.balance.outstanding == kzt(205_000))
        #expect(lease.balance.overdueCharges == 2)
        #expect(lease.balance.nextCharge?.id == nextChargeId)

        #expect(lease.charges.count == 13)
        #expect(Set(lease.charges.map(\.kind)) == [.rent, .deposit, .extra])
        let extra = try #require(lease.charge(id: extraChargeId))
        #expect(extra.description == "Повреждён смеситель на кухне, замена")
        #expect(extra.outstanding == kzt(25_000))
        #expect(extra.isOverdue)
        #expect(extra.canPay)

        #expect(lease.payments.count == 8)
        let reversed = try #require(lease.payments.first { $0.isReversed })
        #expect(reversed.allocations.isEmpty)
        #expect(reversed.reverseReason == "Ошибочно внесён дважды")
        let combined = try #require(lease.payments.first { $0.allocations.count == 2 && $0.depositPart.isPositive })
        #expect(combined.depositPart == kzt(350_000))
        #expect(combined.allocations.map(\.kind) == [.deposit, .rent])

        #expect(lease.deposit.status == .held)
        #expect(lease.deposit.held == kzt(350_000))
        #expect(lease.deposit.suggestedApplyToDebt == kzt(205_000))
        #expect(lease.deposit.ledger.count == 1)
        #expect(lease.deposit.ledger[0].entryType == .received)

        #expect(lease.events.count == 15)
        #expect(lease.events[0].type == .chargesGenerated)
        #expect(lease.events.contains { $0.type == .paymentReversed })
        #expect(lease.availableActions.contains(.returnDeposit))
        #expect(lease.chargesPreview.isEmpty)
    }

    @Test func decodesPendingAggregateFixture() throws {
        let lease = try LeaseV2Fixtures.aggregate(named: LeaseV2Fixtures.pendingName)

        #expect(lease.id == pendingLeaseId)
        #expect(lease.status == .pendingSignature)
        #expect(lease.activationDate == nil)
        #expect(lease.dueDay == 31)
        #expect(lease.charges.isEmpty)
        #expect(lease.chargesPreview.count == 5)
        #expect(lease.chargesPreview.allSatisfy { $0.id == nil })
        #expect(lease.chargesPreview[0].kind == .deposit)
        #expect(lease.deposit.status == .expected)
        #expect(lease.deposit.chargeId == nil)
        #expect(lease.balance.nextCharge == nil)
        #expect(lease.documents.signedFile == nil)
        #expect(lease.documents.contractFile?.filename.hasPrefix("Договор аренды") == true)
        #expect(lease.availableActions == [.update, .markSigned, .activate, .cancel, .generateContract, .uploadSignedScan])
    }

    @Test func aggregateRoundTripsThroughEncoding() throws {
        for name in [LeaseV2Fixtures.activeName, LeaseV2Fixtures.pendingName] {
            let lease = try LeaseV2Fixtures.aggregate(named: name)
            let data = try JSONEncoder().encode(lease)
            #expect(try JSONDecoder().decode(LeaseAggregate.self, from: data) == lease)
        }
    }

    @Test func decodesTenantOverviewFixture() throws {
        let overview = try LeaseV2Fixtures.tenantOverview()

        #expect(overview.asOf == "2026-11-01")
        #expect(overview.windowFrom == "2026-06")
        #expect(overview.windowTo == "2027-02")
        #expect(overview.tenant.fullName == "Касымова Айгерим Нурлановна")
        #expect(overview.tenant.cohabitants == "Касымов Тимур (супруг)")
        #expect(overview.currentLease?.id == activeLeaseId)
        #expect(overview.currentLease?.balance.outstanding == kzt(205_000))
        #expect(overview.currentLease?.balance.nextCharge?.id == nextChargeId)
        #expect(overview.currentLease?.deposit.held == kzt(350_000))
        #expect(overview.leases.count == 1)
        #expect(overview.totals.count == 1)
        #expect(overview.totals[0].depositHeld == kzt(350_000))
        #expect(overview.months.count == 9)
        #expect(overview.months[4].period == "2026-10")
        #expect(overview.months[4].status == .overdue)
        #expect(overview.months[4].kinds == [.rent, .extra])
        #expect(overview.months[4].outstanding == kzt(205_000))
        let empty = try #require(overview.months.last)
        #expect(empty.status == .noCharges)
        #expect(empty.leaseId == nil)
    }

    @Test func decodesPaymentQueueFixture() throws {
        let items = try LeaseV2Fixtures.paymentQueue()

        #expect(items.count == 5)
        let partial = try #require(items.first { $0.chargeId == partialChargeId })
        #expect(partial.kind == .rent)
        #expect(partial.paymentStatus == .partial)
        #expect(partial.allocated == kzt(200_000))
        #expect(partial.outstanding == kzt(180_000))
        #expect(partial.leaseStatus == .active)
        #expect(items.contains { $0.leaseStatus == .terminated })
        #expect(items.contains { $0.kind == .extra && $0.description != nil })

        // The v1 `PaymentQueueItem` keeps decoding the same payload (superset shape).
        let legacy = try JSONDecoder().decode(APIListEnvelope<PaymentQueueItem>.self, from: fixtureData(LeaseV2Fixtures.paymentQueueName))
        #expect(legacy.data.count == 5)
        #expect(legacy.total == 5)
    }

    @Test func unknownValuesDoNotBreakDecoding() throws {
        var json = try #require(JSONSerialization.jsonObject(with: fixtureData(LeaseV2Fixtures.activeName)) as? [String: Any])
        var data = try #require(json["data"] as? [String: Any])
        data["status"] = "frozen_by_court"
        data["available_actions"] = ["record_payment", "teleport"]
        var charges = try #require(data["charges"] as? [[String: Any]])
        charges[1]["kind"] = "penalty"
        charges[1]["payment_status"] = "disputed"
        data["charges"] = charges
        json["data"] = data

        let patched = try JSONSerialization.data(withJSONObject: json)
        let lease = try JSONDecoder().decode(APIResponse<LeaseAggregate>.self, from: patched).data

        #expect(lease.status == .unknown("frozen_by_court"))
        #expect(lease.status.rawValue == "frozen_by_court")
        #expect(lease.status.title == "frozen_by_court")
        #expect(lease.availableActions == [.recordPayment, .unknown("teleport")])
        #expect(lease.charges[1].kind == .unknown("penalty"))
        #expect(lease.charges[1].paymentStatus == .unknown("disputed"))
        #expect(!lease.status.isKnown)

        // Unknown status: no money commands, no buttons.
        #expect(!lease.status.allowsMoneyCommands)
    }

    @Test func leaseStatusRawValuesMatchTheWire() throws {
        let pairs: [(LeaseStatus, String)] = [
            (.draft, "draft"), (.pendingSignature, "pending_signature"), (.active, "active"),
            (.ended, "ended"), (.terminated, "terminated"), (.cancelled, "cancelled"),
        ]
        for (status, raw) in pairs {
            #expect(status.rawValue == raw)
            #expect(LeaseStatus(rawValue: raw) == status)
        }
        #expect(LeaseStatus(rawValue: "weird") == .unknown("weird"))
    }
}

// MARK: - Money and dates

@MainActor
struct LeaseV2MoneyTests {
    @Test func minorUnitsRoundHalfUp() {
        #expect(Money(major: Decimal(string: "350000")!, currency: "KZT").minor == 35_000_000)
        #expect(Money(major: Decimal(string: "1234.56")!, currency: "KZT").minor == 123_456)
        #expect(Money(major: Decimal(string: "0.005")!, currency: "KZT").minor == 1)
        #expect(Money(major: Decimal(string: "0.004")!, currency: "KZT").minor == 0)
    }

    @Test func parsesUserInput() {
        #expect(Money.parse("380 000", currency: "KZT") == kzt(380_000))
        #expect(Money.parse("1500,5", currency: "KZT")?.minor == 150_050)
        #expect(Money.parse("", currency: "KZT") == nil)
        #expect(Money.parse("abc", currency: "KZT") == nil)
        // More than two decimals would lose precision: rejected.
        #expect(Money.parse("1.005", currency: "KZT") == nil)
    }

    @Test func editableTextHasNoGrouping() {
        #expect(kzt(380_000).editableText == "380000")
        #expect(Money(minor: 150_050, currency: "KZT").editableText == "1500.5")
    }

    @Test func dueDateIsClampedToTheLastDayOfShortMonths() {
        #expect(LeaseDay.dueDate(periodStart: "2027-02-15", dueDay: 31) == "2027-02-28")
        #expect(LeaseDay.dueDate(periodStart: "2028-02-15", dueDay: 31) == "2028-02-29")
        #expect(LeaseDay.dueDate(periodStart: "2026-10-15", dueDay: 10) == "2026-10-10")
        #expect(LeaseDay.days(from: "2026-11-01", to: "2026-11-15") == 14)
    }
}

// MARK: - Mock rules (engine)

@MainActor
struct LeaseV2MockEngineTests {
    @Test func recalculationReproducesTheFixtureDerivedValues() throws {
        for name in [LeaseV2Fixtures.activeName, LeaseV2Fixtures.pendingName] {
            let fixture = try LeaseV2Fixtures.aggregate(named: name)
            var recomputed = fixture
            LeaseV2MockEngine.recalculate(&recomputed, today: fixture.balance.asOf)

            #expect(recomputed.balance == fixture.balance)
            #expect(recomputed.deposit == fixture.deposit)
            #expect(recomputed.charges == fixture.charges)
            #expect(recomputed.payments == fixture.payments)
            #expect(recomputed.currentRentAmount == fixture.currentRentAmount)
            #expect(recomputed.endsInDays == fixture.endsInDays)
            #expect(recomputed.availableActions == fixture.availableActions)
        }
    }

    @Test func fifoAllocationClosesSeveralPeriodsAndLeavesCredit() throws {
        let lease = try LeaseV2Fixtures.aggregate(named: LeaseV2Fixtures.activeName)
        let target = try #require(lease.charge(id: partialChargeId))

        // 180 000 target + 25 000 extra (due earlier than the next rent) + 380 000 + 380 000 + 380 000 = 1 345 000.
        let result = LeaseV2MockEngine.allocate(amount: kzt(1_400_000), target: target, among: lease.charges)

        #expect(result.lines.first?.chargeId == partialChargeId)
        #expect(result.lines.first?.amount == kzt(180_000))
        #expect(result.lines.map(\.amount).reduce(Money.zero("KZT"), +) == kzt(1_345_000))
        #expect(result.remainder == kzt(55_000))
    }
}

// MARK: - Mock service

@MainActor
struct MockLeaseV2ServiceTests {
    @Test func servesFixtureLeasesAndRejectsUnknownIds() async throws {
        let mock = try makeMock()
        let active = try await mock.fetchLease(id: activeLeaseId)
        #expect(active.status == .active)
        await #expect(throws: LeaseV2Error.notFound) {
            _ = try await mock.fetchLease(id: "missing")
        }
    }

    @Test func staleVersionIsRejected() async throws {
        let mock = try makeMock()
        await #expect(throws: LeaseV2Error.versionMismatch(currentVersion: 15)) {
            _ = try await mock.cancel(leaseId: activeLeaseId, version: 3, request: CancelLeaseRequest(reason: "x", confirm: nil))
        }
    }

    @Test func commandsOutsideTheStatusMachineAreRejected() async throws {
        let mock = try makeMock()
        await #expect(throws: LeaseV2Error.invalidStateTransition(command: "cancel")) {
            _ = try await mock.cancel(leaseId: activeLeaseId, version: 15, request: CancelLeaseRequest(reason: "x", confirm: nil))
        }
        await #expect(throws: LeaseV2Error.invalidStateTransition(command: "payments")) {
            _ = try await mock.payCharge(
                leaseId: pendingLeaseId,
                chargeId: "none",
                request: PayChargeRequest(amount: nil, receivedOn: "2026-11-01", method: "cash", notes: nil),
                idempotencyKey: "k"
            )
        }
    }

    @Test func markSignedThenActivateCreatesTheChargeQueue() async throws {
        let mock = try makeMock()

        let signed = try await mock.markSigned(
            leaseId: pendingLeaseId,
            version: 3,
            request: MarkSignedRequest(signedOn: "2026-10-30", signedFileId: nil),
            scan: LeaseScanAttachment(fileName: "scan.pdf", mimeType: "application/pdf", data: Data([1, 2, 3]))
        )
        #expect(signed.status == .pendingSignature)
        #expect(signed.version == 4)
        #expect(signed.lifecycle.signedOn == "2026-10-30")
        #expect(signed.documents.signedFile?.filename == "scan.pdf")
        #expect(!signed.can(.markSigned))
        #expect(signed.events.first?.type == .signedScanUploaded)

        let active = try await mock.activate(
            leaseId: pendingLeaseId,
            version: 4,
            request: ActivateLeaseRequest(activationDate: "2026-11-15", signedOn: nil, signedFileId: nil)
        )
        #expect(active.status == .active)
        #expect(active.activationDate == "2026-11-15")
        #expect(active.chargesPreview.isEmpty)
        #expect(active.charges.count == 5)
        #expect(active.charges.allSatisfy { $0.id != nil })
        let deposit = try #require(active.charges.first { $0.kind == .deposit })
        #expect(active.deposit.chargeId == deposit.id)
        #expect(deposit.dueDate == "2026-11-15")
        #expect(active.availableActions.contains(.recordPayment))
        #expect(!active.availableActions.contains(.activate))
        #expect(active.balance.outstanding == Money.zero("KZT"))  // nothing due yet on 2026-11-01
    }

    @Test func activateRequiresASignatureDate() async throws {
        let mock = try makeMock()
        await #expect(throws: LeaseV2Error.self) {
            _ = try await mock.activate(
                leaseId: pendingLeaseId,
                version: 3,
                request: ActivateLeaseRequest(activationDate: "2026-11-15", signedOn: nil, signedFileId: nil)
            )
        }
        // Signing and activating in one go is allowed.
        let active = try await mock.activate(
            leaseId: pendingLeaseId,
            version: 3,
            request: ActivateLeaseRequest(activationDate: "2026-11-15", signedOn: "2026-11-01", signedFileId: nil)
        )
        #expect(active.status == .active)
        #expect(active.lifecycle.signedOn == "2026-11-01")
    }

    @Test func cancelClosesAPendingLease() async throws {
        let mock = try makeMock()
        let cancelled = try await mock.cancel(leaseId: pendingLeaseId, version: 3, request: CancelLeaseRequest(reason: "Передумал", confirm: nil))
        #expect(cancelled.status == .cancelled)
        #expect(cancelled.lifecycle.cancelReason == "Передумал")
        #expect(cancelled.availableActions == [.delete])
        #expect(cancelled.chargesPreview.isEmpty)
    }

    @Test func earlyTerminationVoidsLaterPeriodsAndForfeitsTheDeposit() async throws {
        let mock = try makeMock()
        let terminated = try await mock.terminate(
            leaseId: activeLeaseId,
            version: 15,
            request: TerminateLeaseRequest(moveOutDate: "2026-11-20", reason: "Переезд", forfeitAmount: nil, confirm: nil)
        )

        #expect(terminated.status == .terminated)
        #expect(terminated.moveOutDate == "2026-11-20")
        // Periods starting after 2026-11-20 (12-15, 01-15) are void; 11-15..12-14 stays whole.
        let voided = terminated.charges.filter { $0.state == .void }
        #expect(Set(voided.map(\.periodStart)) == ["2026-12-15", "2027-01-15"])
        let kept = try #require(terminated.charges.first { $0.periodStart == "2026-11-15" })
        #expect(kept.state == .open)
        #expect(kept.amount == kzt(380_000))
        // Debt up to move-out stays visible.
        #expect(terminated.balance.outstanding == kzt(205_000))
        #expect(terminated.balance.upcoming == kzt(380_000))
        // Deposit stays with the owner.
        #expect(terminated.deposit.status == .forfeited)
        #expect(terminated.deposit.forfeited == kzt(350_000))
        #expect(terminated.deposit.held == Money.zero("KZT"))
        #expect(terminated.availableActions.contains(.recordPayment))
        #expect(!terminated.availableActions.contains(.returnDeposit))
        #expect(!terminated.availableActions.contains(.terminate))
    }

    @Test func terminationAtTheEndOfTermEndsTheLeaseAndKeepsTheDepositHeld() async throws {
        let mock = try makeMock()
        let ended = try await mock.terminate(
            leaseId: activeLeaseId,
            version: 15,
            request: TerminateLeaseRequest(moveOutDate: "2026-11-30", reason: "Конец срока", forfeitAmount: nil, confirm: nil)
        )
        // end_date is 2027-03-14, 11-30 is earlier -> terminated. Use a lease whose end_date has passed:
        #expect(ended.status == .terminated)

        var lease = try LeaseV2Fixtures.aggregate(named: LeaseV2Fixtures.activeName)
        lease.endDate = "2026-11-10"
        let shortMock = MockLeaseV2Service(leases: [lease])
        let result = try await shortMock.terminate(
            leaseId: activeLeaseId,
            version: 15,
            request: TerminateLeaseRequest(moveOutDate: "2026-11-10", reason: "Конец срока", forfeitAmount: nil, confirm: nil)
        )
        #expect(result.status == .ended)
        #expect(result.deposit.held == kzt(350_000))
        #expect(result.deposit.status == .held)
        await #expect(throws: LeaseV2Error.self) {
            _ = try await MockLeaseV2Service(leases: [lease]).terminate(
                leaseId: activeLeaseId,
                version: 15,
                request: TerminateLeaseRequest(moveOutDate: "2026-11-10", reason: "x", forfeitAmount: Decimal(1), confirm: nil)
            )
        }
    }

    @Test func terminationRejectsAForfeitAboveTheHeldDeposit() async throws {
        let mock = try makeMock()
        await #expect(throws: LeaseV2Error.depositBalanceExceeded(held: kzt(350_000))) {
            _ = try await mock.terminate(
                leaseId: activeLeaseId,
                version: 15,
                request: TerminateLeaseRequest(moveOutDate: "2026-11-20", reason: "x", forfeitAmount: Decimal(400_000), confirm: nil)
            )
        }
    }

    @Test func amendmentRepricesOnlyUnpaidChargesFromTheEffectiveDate() async throws {
        let mock = try makeMock()
        let amended = try await mock.amendRent(
            leaseId: activeLeaseId,
            version: 15,
            request: AmendRentRequest(effectiveFrom: "2026-10-15", rentAmount: Decimal(400_000), dueDay: 12, note: "Индексация")
        )

        #expect(amended.dueDay == 12)
        #expect(amended.amendments.count == 2)
        // The partially paid 10-15 period is kept untouched.
        let partial = try #require(amended.charge(id: partialChargeId))
        #expect(partial.amount == kzt(380_000))
        #expect(partial.state == .open)
        // Unpaid later periods are voided and reissued at the new rate and due day.
        let reissued = amended.charges.filter { $0.state == .open && $0.kind == .rent && $0.periodStart >= "2026-11-15" }
        #expect(reissued.count == 3)
        #expect(reissued.allSatisfy { $0.amount == kzt(400_000) && $0.replacesChargeId != nil })
        #expect(reissued.map(\.dueDate) == ["2026-11-12", "2026-12-12", "2027-01-12"])
        #expect(amended.charges.filter { $0.state == .void }.count == 3)
        #expect(amended.events.first?.type == .amended)
    }

    @Test func amendmentValidatesEffectiveDateAndContent() async throws {
        let mock = try makeMock()
        await #expect(throws: LeaseV2Error.self) {
            _ = try await mock.amendRent(
                leaseId: activeLeaseId, version: 15,
                request: AmendRentRequest(effectiveFrom: "2026-01-01", rentAmount: Decimal(1), dueDay: nil, note: nil)
            )
        }
        await #expect(throws: LeaseV2Error.self) {
            _ = try await mock.amendRent(
                leaseId: activeLeaseId, version: 15,
                request: AmendRentRequest(effectiveFrom: "2026-11-15", rentAmount: nil, dueDay: nil, note: nil)
            )
        }
    }

    @Test func extraChargeJoinsTheQueue() async throws {
        let mock = try makeMock()
        let lease = try await mock.addExtraCharge(
            leaseId: activeLeaseId,
            version: 15,
            request: AddExtraChargeRequest(amount: Decimal(100_000), chargedOn: "2026-11-01", dueDate: nil, description: "Порванные обои"),
            idempotencyKey: "extra-1"
        )
        let charge = try #require(lease.charges.first { $0.description == "Порванные обои" })
        #expect(charge.kind == .extra)
        #expect(charge.outstanding == kzt(100_000))
        #expect(charge.dueDate == "2026-11-01")
        #expect(charge.canPay)
        #expect(lease.balance.outstanding == kzt(305_000))
        #expect(lease.events.first?.type == .chargeAdded)

        await #expect(throws: LeaseV2Error.self) {
            _ = try await mock.addExtraCharge(
                leaseId: activeLeaseId, version: lease.version,
                request: AddExtraChargeRequest(amount: Decimal(10), chargedOn: "2026-11-01", dueDate: nil, description: "  "),
                idempotencyKey: "extra-2"
            )
        }
    }

    @Test func returnDepositRecordsLedgerAndOptionalSetOff() async throws {
        let mock = try makeMock()
        let lease = try await mock.returnDeposit(
            leaseId: activeLeaseId,
            version: 15,
            request: ReturnDepositRequest(
                amount: Decimal(145_000), returnedOn: "2026-11-01", method: "kaspi",
                applyToDebt: Decimal(205_000), notes: "Зачёт долга", confirm: nil
            ),
            idempotencyKey: "dep-1"
        )

        #expect(lease.deposit.returned == kzt(145_000))
        #expect(lease.deposit.appliedToDebt == kzt(205_000))
        #expect(lease.deposit.held == Money.zero("KZT"))
        #expect(lease.deposit.status == .returned)
        #expect(lease.deposit.ledger.map(\.entryType) == [.received, .appliedToDebt, .returned])
        // The set-off closed the overdue rent and the extra charge.
        #expect(lease.balance.outstanding == Money.zero("KZT"))
        #expect(lease.payments.first { $0.source == "deposit" }?.amount == kzt(205_000))
        #expect(!lease.availableActions.contains(.returnDeposit))
    }

    @Test func returnDepositRejectsMoreThanHeld() async throws {
        let mock = try makeMock()
        await #expect(throws: LeaseV2Error.depositBalanceExceeded(held: kzt(350_000))) {
            _ = try await mock.returnDeposit(
                leaseId: activeLeaseId,
                version: 15,
                request: ReturnDepositRequest(amount: Decimal(300_000), returnedOn: "2026-11-01", method: "cash", applyToDebt: Decimal(100_000), notes: nil, confirm: nil),
                idempotencyKey: "dep-2"
            )
        }
    }

    @Test func idempotencyKeyReplaysTheSameIntentAndRejectsAChangedBody() async throws {
        let mock = try makeMock()
        let request = PayChargeRequest(amount: Decimal(100_000), receivedOn: "2026-11-01", method: "cash", notes: nil)

        let first = try await mock.payCharge(leaseId: activeLeaseId, chargeId: partialChargeId, request: request, idempotencyKey: "pay-1")
        let replay = try await mock.payCharge(leaseId: activeLeaseId, chargeId: partialChargeId, request: request, idempotencyKey: "pay-1")
        #expect(replay == first)
        let stored = try await mock.fetchLease(id: activeLeaseId)
        #expect(stored.payments.count == 9)  // 8 fixture payments + exactly one new
        #expect(stored.version == 16)

        let changed = PayChargeRequest(amount: Decimal(50_000), receivedOn: "2026-11-01", method: "cash", notes: nil)
        await #expect(throws: LeaseV2Error.idempotencyKeyReused) {
            _ = try await mock.payCharge(leaseId: activeLeaseId, chargeId: partialChargeId, request: changed, idempotencyKey: "pay-1")
        }
    }

    @Test func overpaymentBecomesTenantCredit() async throws {
        let mock = try makeMock()
        // Everything outstanding or generated: 180k + 25k + 3 x 380k = 1 345k. Pay 1.4M.
        let lease = try await mock.payCharge(
            leaseId: activeLeaseId,
            chargeId: partialChargeId,
            request: PayChargeRequest(amount: Decimal(1_400_000), receivedOn: "2026-11-01", method: "bank", notes: nil),
            idempotencyKey: "pay-big"
        )
        #expect(lease.balance.tenantCredit == kzt(55_000))
        #expect(lease.balance.outstanding == Money.zero("KZT"))
        #expect(lease.payments.first?.unallocated == kzt(55_000))
        #expect(lease.availableActions.contains(.refundCredit))
        #expect(lease.charges.filter { $0.state == .open }.allSatisfy { !$0.outstanding.isPositive })
    }
}

// MARK: - View model

@MainActor
struct LeaseDetailViewModelTests {
    @Test func loadsIntoTheLoadedState() async throws {
        let (viewModel, _) = try await makeViewModel()
        guard case .loaded(let lease) = viewModel.state else {
            Issue.record("expected .loaded, got \(viewModel.state)")
            return
        }
        #expect(lease.id == activeLeaseId)
    }

    @Test func unknownLeaseEndsInTheErrorState() async throws {
        let (viewModel, _) = try await makeViewModel(leaseId: "missing")
        #expect(viewModel.state == .error(LeaseV2Error.notFound.userMessage))
        #expect(viewModel.lease == nil)
        #expect(viewModel.actionButtons.isEmpty)
    }

    @Test func availableActionsDriveTheButtonSet() async throws {
        let (active, _) = try await makeViewModel(leaseId: activeLeaseId)
        #expect(active.actionButtons.map(\.action) == [
            .recordPayment, .addExtraCharge, .amendRent, .returnDeposit, .replaceWithNew, .terminate,
        ])
        #expect(active.actionButtons.first { $0.action == .terminate }?.isDestructive == true)
        // `update`, `prolong`, `upload_signed_scan` have no UI on this screen.
        #expect(!active.actionButtons.contains { $0.action == .update })

        let (pending, _) = try await makeViewModel(leaseId: pendingLeaseId)
        #expect(pending.actionButtons.map(\.action) == [.markSigned, .activate, .cancel])
    }

    @Test func buttonsFollowTheStateAfterATransition() async throws {
        let (viewModel, _) = try await makeViewModel(leaseId: pendingLeaseId)

        #expect(await viewModel.submitMarkSigned(signedOn: "2026-11-01", scan: nil))
        #expect(viewModel.actionButtons.map(\.action) == [.activate, .cancel])

        #expect(await viewModel.submitActivate(activationDate: "2026-11-15", signedOn: nil))
        #expect(viewModel.lease?.status == .active)
        #expect(viewModel.actionButtons.map(\.action) == [.recordPayment, .addExtraCharge, .amendRent, .replaceWithNew, .terminate])
        #expect(viewModel.activeSheet == nil)

        let (cancelled, _) = try await makeViewModel(leaseId: pendingLeaseId)
        #expect(await cancelled.submitCancel(reason: "Передумал"))
        #expect(cancelled.actionButtons.isEmpty)
    }

    @Test func payingAChargeReducesItsOutstanding() async throws {
        let (viewModel, _) = try await makeViewModel()
        let before = try #require(viewModel.lease)
        #expect(before.charge(id: partialChargeId)?.outstanding == kzt(180_000))
        #expect(before.balance.outstanding == kzt(205_000))

        viewModel.present(.payCharge(chargeId: partialChargeId))
        #expect(await viewModel.submitPayCharge(chargeId: partialChargeId, amount: kzt(100_000), receivedOn: "2026-11-01", method: .kaspi, notes: nil))

        let after = try #require(viewModel.lease)
        #expect(after.charge(id: partialChargeId)?.outstanding == kzt(80_000))
        #expect(after.charge(id: partialChargeId)?.paymentStatus == .partial)
        #expect(after.balance.outstanding == kzt(105_000))
        #expect(after.version == before.version + 1)
        #expect(after.payments.first?.amount == kzt(100_000))
        #expect(after.payments.first?.allocations == [
            LeasePaymentAllocation(chargeId: partialChargeId, kind: .rent, amount: kzt(100_000)),
        ])
        #expect(viewModel.activeSheet == nil)
    }

    @Test func payingTheFullOutstandingClosesTheCharge() async throws {
        let (viewModel, _) = try await makeViewModel()
        viewModel.present(.payCharge(chargeId: partialChargeId))
        // `amount == nil` pays the outstanding.
        #expect(await viewModel.submitPayCharge(chargeId: partialChargeId, amount: nil, receivedOn: "2026-11-01", method: .cash, notes: "Остаток"))

        let lease = try #require(viewModel.lease)
        let charge = try #require(lease.charge(id: partialChargeId))
        #expect(charge.outstanding == Money.zero("KZT"))
        #expect(charge.paymentStatus == .paid)
        #expect(!charge.canPay)
        #expect(lease.balance.outstanding == kzt(25_000))
        #expect(lease.balance.overdueCharges == 1)
    }

    @Test func recordPaymentOpensTheOldestPayableCharge() async throws {
        let (viewModel, _) = try await makeViewModel()
        viewModel.perform(.recordPayment)
        #expect(viewModel.activeSheet == .payCharge(chargeId: partialChargeId))
    }

    @Test func eachPaymentSheetGetsItsOwnIdempotencyKeyAndKeepsItAcrossRetries() async throws {
        let (viewModel, _) = try await makeViewModel()
        let sheet = LeaseSheet.payCharge(chargeId: partialChargeId)

        viewModel.present(sheet)
        let first = viewModel.idempotencyKey(for: sheet)
        #expect(viewModel.idempotencyKey(for: sheet) == first)

        viewModel.dismissSheet()
        viewModel.present(sheet)
        #expect(viewModel.idempotencyKey(for: sheet) != first)
    }

    @Test func networkFailureParksThePaymentInTheQueueWithTheSameKey() async throws {
        let queue = RecordingQueue()
        let (viewModel, mock) = try await makeViewModel(queue: queue)
        let sheet = LeaseSheet.payCharge(chargeId: partialChargeId)

        viewModel.present(sheet)
        let key = viewModel.idempotencyKey(for: sheet)
        mock.failNextCommand = .transport
        #expect(await viewModel.submitPayCharge(chargeId: partialChargeId, amount: kzt(50_000), receivedOn: "2026-11-01", method: .kaspi, notes: nil))

        #expect(queue.enqueued.count == 1)
        #expect(queue.enqueued[0].key == key)
        #expect(queue.enqueued[0].chargeId == partialChargeId)
        #expect(queue.enqueued[0].leaseId == activeLeaseId)
        #expect(queue.enqueued[0].body.amount == Decimal(50_000))
        #expect(queue.enqueued[0].body.receivedOn == "2026-11-01")
        #expect(viewModel.activeSheet == nil)
        #expect(viewModel.banner != nil)
        // Nothing was applied locally: the queue delivers it later.
        #expect(viewModel.lease?.charge(id: partialChargeId)?.outstanding == kzt(180_000))
    }

    @Test func networkFailureWithoutAQueueKeepsTheSheetOpenWithAnError() async throws {
        let (viewModel, mock) = try await makeViewModel(queue: nil)
        viewModel.present(.payCharge(chargeId: partialChargeId))
        mock.failNextCommand = .transport
        #expect(!(await viewModel.submitPayCharge(chargeId: partialChargeId, amount: kzt(1), receivedOn: "2026-11-01", method: .cash, notes: nil)))
        #expect(viewModel.sheetError == LeaseV2Error.transport.userMessage)
        #expect(viewModel.activeSheet == .payCharge(chargeId: partialChargeId))
    }

    @Test func staleVersionReloadsAndKeepsTheSheet() async throws {
        let (viewModel, mock) = try await makeViewModel()
        // Someone else changes the lease: the screen's copy is now stale.
        _ = try await mock.addExtraCharge(
            leaseId: activeLeaseId, version: 15,
            request: AddExtraChargeRequest(amount: Decimal(1_000), chargedOn: "2026-11-01", dueDate: nil, description: "Чужое"),
            idempotencyKey: "other"
        )

        viewModel.present(.amendRent)
        #expect(!(await viewModel.submitAmendRent(effectiveFrom: "2026-11-15", rent: kzt(400_000), dueDay: nil, note: nil)))
        #expect(viewModel.sheetError == LeaseV2Error.versionMismatch(currentVersion: nil).userMessage)
        #expect(viewModel.activeSheet == .amendRent)
        #expect(viewModel.lease?.version == 16)

        // Retry on the fresh version succeeds.
        #expect(await viewModel.submitAmendRent(effectiveFrom: "2026-11-15", rent: kzt(400_000), dueDay: nil, note: nil))
        #expect(viewModel.lease?.amendments.count == 2)
    }

    @Test func terminationPreviewMatchesTheOutcome() async throws {
        let (viewModel, _) = try await makeViewModel()

        let preview = try #require(viewModel.terminationPreview(moveOutDate: "2026-11-20", forfeitAmount: nil))
        #expect(preview.resultingStatus == .terminated)
        #expect(preview.voidedCharges.count == 2)
        #expect(preview.voidedTotal == kzt(760_000))
        #expect(preview.keptPeriodCharge?.periodStart == "2026-11-15")
        #expect(preview.forfeitedDeposit == kzt(350_000))
        #expect(preview.remainingHeld == Money.zero("KZT"))
        // 180 000 + 25 000 overdue + 380 000 of the period that contains move-out.
        #expect(preview.debtStaysVisible == kzt(585_000))

        let partialForfeit = try #require(viewModel.terminationPreview(moveOutDate: "2026-11-20", forfeitAmount: kzt(100_000)))
        #expect(partialForfeit.forfeitedDeposit == kzt(100_000))
        #expect(partialForfeit.remainingHeld == kzt(250_000))

        // Executing it gives what the preview promised.
        #expect(await viewModel.submitTerminate(moveOutDate: "2026-11-20", reason: "Переезд", forfeitAmount: kzt(100_000)))
        let lease = try #require(viewModel.lease)
        #expect(lease.status == .terminated)
        #expect(lease.deposit.forfeited == kzt(100_000))
        #expect(lease.deposit.held == kzt(250_000))
        #expect(lease.deposit.status == .partiallyReturned)
        #expect(lease.can(.returnDeposit))
    }

    @Test func returnDepositThroughTheViewModel() async throws {
        let (viewModel, _) = try await makeViewModel()
        viewModel.present(.returnDeposit)
        #expect(await viewModel.submitReturnDeposit(amount: kzt(350_000), returnedOn: "2026-11-01", method: .kaspi, applyToDebt: nil, notes: nil))
        let lease = try #require(viewModel.lease)
        #expect(lease.deposit.status == .returned)
        #expect(lease.deposit.returned == kzt(350_000))
        #expect(lease.balance.outstanding == kzt(205_000))  // no automatic set-off
        #expect(!viewModel.actionButtons.contains { $0.action == .returnDeposit })
    }

    @Test func extraChargeThroughTheViewModelAppearsInTheQueue() async throws {
        let (viewModel, _) = try await makeViewModel()
        viewModel.present(.addExtraCharge)
        #expect(await viewModel.submitAddExtraCharge(amount: kzt(100_000), chargedOn: "2026-11-01", dueDate: "2026-11-05", description: "Порванные обои"))
        let lease = try #require(viewModel.lease)
        let charge = try #require(lease.charges.first { $0.description == "Порванные обои" })
        #expect(charge.dueDate == "2026-11-05")
        #expect(lease.balance.upcoming == kzt(1_140_000 + 100_000))
    }

    @Test func requestBodiesEncodeLikeTheApiContract() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let pay = try encoder.encode(PayChargeRequest(amount: Decimal(180_000), receivedOn: "2026-11-01", method: "kaspi", notes: nil))
        #expect(String(decoding: pay, as: UTF8.self) == #"{"amount":180000,"method":"kaspi","received_on":"2026-11-01"}"#)

        let amend = try encoder.encode(AmendRentRequest(effectiveFrom: "2026-09-15", rentAmount: Decimal(380_000), dueDay: nil, note: "Индексация"))
        #expect(String(decoding: amend, as: UTF8.self) == #"{"effective_from":"2026-09-15","note":"Индексация","rent_amount":380000}"#)

        let terminate = try encoder.encode(TerminateLeaseRequest(moveOutDate: "2026-10-20", reason: "Переезд", forfeitAmount: nil, confirm: nil))
        #expect(String(decoding: terminate, as: UTF8.self) == #"{"move_out_date":"2026-10-20","reason":"Переезд"}"#)

        // Round trip through the persisted queue format.
        let decoded = try JSONDecoder().decode(PayChargeRequest.self, from: pay)
        #expect(decoded.amount == Decimal(180_000))
    }
}
