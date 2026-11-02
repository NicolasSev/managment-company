//
//  PaymentFeedbackTests.swift
//  managment-company
//
//  D2.2: the lease view model raises one success signal per accepted payment (applied by the
//  server or parked in the offline queue) and one error signal per refused command. The view
//  maps them to haptics. Canonical source: apps/ios/PropManager/Tests.
//

import Foundation
import Testing
@testable import managment_company

private let leaseId = "7c1e2a40-5b3d-4f8e-9a61-2d4c8b1f0a01"
private let partialChargeId = "f2a6d9c3-8e14-4b7a-a5d0-3c9e1b6f2a88"

@MainActor
private final class ParkingQueue: LeaseChargePaymentQueueing {
    var count = 0
    func enqueueLeaseChargePayment(chargeId: String, leaseId: String, body: PayChargeRequest, idempotencyKey: String) throws {
        count += 1
    }
}

@MainActor
private func loadedViewModel(queue: LeaseChargePaymentQueueing?) async throws -> (LeaseDetailViewModel, MockLeaseV2Service) {
    let mock = try MockLeaseV2Service.fromFixtures()
    let viewModel = LeaseDetailViewModel(
        leaseId: leaseId,
        service: mock,
        paymentQueue: queue,
        today: { LeaseDay.pickerDate("2026-11-01") ?? Date() }
    )
    await viewModel.load()
    return (viewModel, mock)
}

@MainActor
struct PaymentFeedbackTests {
    @Test func acceptedPaymentRaisesOneSuccessSignal() async throws {
        let (viewModel, _) = try await loadedViewModel(queue: nil)
        #expect(viewModel.paidSignal == 0)
        viewModel.present(.payCharge(chargeId: partialChargeId))
        #expect(await viewModel.submitPayCharge(chargeId: partialChargeId, amount: Money(minor: 10_000_000, currency: "KZT"), receivedOn: "2026-11-01", method: .kaspi, notes: nil))
        #expect(viewModel.paidSignal == 1)
        #expect(viewModel.errorSignal == 0)
    }

    @Test func paymentParkedInTheQueueCountsAsApplied() async throws {
        let queue = ParkingQueue()
        let (viewModel, mock) = try await loadedViewModel(queue: queue)
        viewModel.present(.payCharge(chargeId: partialChargeId))
        mock.failNextCommand = .transport
        #expect(await viewModel.submitPayCharge(chargeId: partialChargeId, amount: nil, receivedOn: "2026-11-01", method: .cash, notes: nil))
        #expect(queue.count == 1)
        #expect(viewModel.paidSignal == 1)
        #expect(viewModel.errorSignal == 0)
    }

    @Test func refusedPaymentRaisesOnlyTheErrorSignal() async throws {
        let (viewModel, mock) = try await loadedViewModel(queue: nil)
        viewModel.present(.payCharge(chargeId: partialChargeId))
        mock.failNextCommand = .transport
        #expect(!(await viewModel.submitPayCharge(chargeId: partialChargeId, amount: nil, receivedOn: "2026-11-01", method: .cash, notes: nil)))
        #expect(viewModel.paidSignal == 0)
        #expect(viewModel.errorSignal == 1)
        #expect(viewModel.sheetError != nil)
    }

    @Test func otherCommandsDoNotRaiseTheSuccessSignal() async throws {
        let (viewModel, _) = try await loadedViewModel(queue: nil)
        viewModel.present(.amendRent)
        _ = await viewModel.submitAmendRent(effectiveFrom: "2026-12-01", rent: Money(minor: 40_000_000, currency: "KZT"), dueDay: nil, note: nil)
        #expect(viewModel.paidSignal == 0)
    }
}
