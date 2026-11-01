import Foundation

/// Server-side rules of the lease domain (`docs/product/lease-v2-spec.md` §2, §4, §5, §6)
/// reduced to what `MockLeaseV2Service` needs: derived values are recomputed from the
/// charges, payments and deposit ledger after every command, exactly as the API does.
///
/// Pure functions over `inout LeaseAggregate`, so they are unit-testable without a service.
enum LeaseV2MockEngine {

    // MARK: Derived values (spec §6)

    /// Recomputes every derived field from the primary rows (charges, payments, ledger).
    static func recalculate(_ lease: inout LeaseAggregate, today: String) {
        let currency = lease.currency
        let zero = Money.zero(currency)

        // Per charge.
        for index in lease.charges.indices {
            var charge = lease.charges[index]
            if charge.state == .void {
                charge.allocated = zero
                charge.outstanding = zero
                charge.paymentStatus = .void
                charge.isOverdue = false
                charge.daysOverdue = 0
                charge.canPay = false
                charge.canWaive = false
                charge.canUnwaive = false
                lease.charges[index] = charge
                continue
            }
            let allocated = allocatedAmount(chargeId: charge.id, payments: lease.payments, currency: currency)
            charge.allocated = allocated
            if charge.state == .waived { charge.waivedAmount = charge.amount }
            charge.outstanding = (charge.amount - charge.waivedAmount - allocated).nonNegative
            if charge.state == .waived && allocated.isZero {
                charge.paymentStatus = .waived
            } else if charge.outstanding.isZero {
                charge.paymentStatus = .paid
            } else if allocated.isPositive {
                charge.paymentStatus = .partial
            } else {
                charge.paymentStatus = .unpaid
            }
            let overdue = charge.outstanding.isPositive && charge.dueDate < today
            charge.isOverdue = overdue
            charge.daysOverdue = overdue ? max(0, LeaseDay.days(from: charge.dueDate, to: today) ?? 0) : 0
            charge.canPay = charge.state == .open && charge.outstanding.isPositive && lease.status.allowsMoneyCommands
            charge.canWaive = charge.canPay
            charge.canUnwaive = charge.state == .waived
            lease.charges[index] = charge
        }

        // Per payment.
        for index in lease.payments.indices {
            var payment = lease.payments[index]
            if payment.direction == .incoming && !payment.isReversed {
                let allocated = payment.allocations.reduce(zero) { $0 + $1.amount }
                payment.unallocated = (payment.amount - allocated).nonNegative
            } else {
                payment.unallocated = zero
            }
            payment.depositPart = payment.allocations.filter { $0.kind == .deposit }.reduce(zero) { $0 + $1.amount }
            lease.payments[index] = payment
        }

        // Balance.
        let live = lease.charges.filter { $0.state != .void }
        let due = live.filter { $0.dueDate <= today }
        let overdueCharges = live.filter { $0.dueDate < today && $0.outstanding.isPositive }
        let future = live.filter { $0.dueDate > today }
        let received = lease.payments.filter { !$0.isReversed }
        let totalIn = received.filter { $0.direction == .incoming }.reduce(zero) { $0 + $1.amount }
        let totalOut = received.filter { $0.direction == .outgoing }.reduce(zero) { $0 + $1.amount }
        let allocatedInTotal = received.filter { $0.direction == .incoming }
            .flatMap(\.allocations).reduce(zero) { $0 + $1.amount }
        let next = live
            .filter { $0.dueDate >= today && $0.outstanding.isPositive }
            .sorted { fifoOrder($0, $1) }
            .first
        lease.balance = LeaseBalance(
            currency: currency,
            asOf: today,
            chargedToDate: due.reduce(zero) { $0 + $1.amount },
            waivedToDate: due.reduce(zero) { $0 + $1.waivedAmount },
            paidToDate: due.reduce(zero) { $0 + $1.allocated },
            outstanding: due.reduce(zero) { $0 + $1.outstanding },
            overdue: overdueCharges.reduce(zero) { $0 + $1.outstanding },
            overdueCharges: overdueCharges.count,
            upcoming: future.reduce(zero) { $0 + $1.outstanding },
            prepaid: future.reduce(zero) { $0 + $1.allocated },
            tenantCredit: (totalIn - allocatedInTotal - totalOut).nonNegative,
            receivedTotal: totalIn - totalOut,
            nextCharge: next.flatMap { charge in
                charge.id.map {
                    LeaseNextCharge(id: $0, kind: charge.kind, dueDate: charge.dueDate, amount: charge.amount, outstanding: charge.outstanding)
                }
            }
        )

        // Deposit ledger (spec §5): reversed entries and reversal entries are excluded.
        let effective = lease.deposit.ledger.filter { !$0.isReversed && $0.reversesEntryId == nil }
        func sum(_ type: DepositEntryType) -> Money {
            effective.filter { $0.entryType == type }.reduce(zero) { $0 + $1.amount }
        }
        let depositReceived = sum(.received)
        let depositReturned = sum(.returned)
        let depositForfeited = sum(.forfeited)
        let depositApplied = sum(.appliedToDebt)
        let held = depositReceived - depositReturned - depositForfeited - depositApplied
        lease.deposit.received = depositReceived
        lease.deposit.returned = depositReturned
        lease.deposit.forfeited = depositForfeited
        lease.deposit.appliedToDebt = depositApplied
        lease.deposit.held = held
        if let chargeId = lease.deposit.chargeId, let charge = lease.charges.first(where: { $0.id == chargeId }) {
            lease.deposit.outstanding = charge.outstanding
        } else {
            lease.deposit.outstanding = (lease.deposit.amount - depositReceived).nonNegative
        }
        if depositReceived.isZero && effective.isEmpty {
            lease.deposit.status = .expected
        } else if held.isZero && depositForfeited.isPositive {
            lease.deposit.status = .forfeited
        } else if held.isZero && (depositReturned + depositApplied).isPositive {
            lease.deposit.status = .returned
        } else if held.isPositive && held < depositReceived {
            lease.deposit.status = .partiallyReturned
        } else if held.isPositive {
            lease.deposit.status = .held
        } else {
            lease.deposit.status = .expected
        }
        lease.deposit.suggestedApplyToDebt = Money(minor: max(0, min(held.minor, lease.balance.outstanding.minor)), currency: currency)

        // Top-level.
        lease.currentRentAmount = currentRent(lease: lease, today: today)
        if let end = lease.endDate, let remaining = LeaseDay.days(from: today, to: end) {
            lease.endsInDays = remaining
            lease.isEndingSoon = remaining <= lease.renewalReminderDays
        } else {
            lease.endsInDays = nil
            lease.isEndingSoon = false
        }
        if lease.status != .active {
            lease.nextPeriodStart = nil
        }
        lease.availableActions = availableActions(for: lease)
    }

    /// Rent in force on `today`: the newest amendment with a rent whose `effective_from` has
    /// started, else the base rent.
    static func currentRent(lease: LeaseAggregate, today: String) -> Money {
        let started = lease.amendments
            .filter { $0.rentAmount != nil && $0.effectiveFrom <= today }
            .sorted { $0.effectiveFrom < $1.effectiveFrom }
        return started.last?.rentAmount ?? lease.rentAmount
    }

    /// Spec §2.2.
    static func availableActions(for lease: LeaseAggregate) -> [LeaseAction] {
        switch lease.status {
        case .draft:
            return [.update, .sendForSignature, .markSigned, .activate, .cancel, .delete, .generateContract]
        case .pendingSignature:
            var actions: [LeaseAction] = [.update]
            if lease.lifecycle.signedOn == nil { actions.append(.markSigned) }
            actions += [.activate, .cancel, .generateContract, .uploadSignedScan]
            return actions
        case .active:
            var actions: [LeaseAction] = [.update, .amendRent, .addExtraCharge, .recordPayment, .terminate]
            if lease.endDate != nil { actions += [.prolong, .replaceWithNew] }
            if lease.deposit.held.isPositive { actions.append(.returnDeposit) }
            if lease.balance.tenantCredit.isPositive { actions.append(.refundCredit) }
            actions.append(.uploadSignedScan)
            return actions
        case .ended, .terminated:
            var actions: [LeaseAction] = []
            if lease.replacedByLeaseId == nil { actions.append(.reopen) }
            actions += [.recordPayment, .addExtraCharge]
            if lease.deposit.held.isPositive { actions += [.returnDeposit, .forfeitDeposit] }
            if lease.balance.tenantCredit.isPositive { actions.append(.refundCredit) }
            return actions
        case .cancelled:
            return [.delete]
        case .unknown:
            return []
        }
    }

    // MARK: Allocation (spec §4)

    /// `(due_date, kind rank deposit < rent < extra, period_start, id)`.
    static func fifoOrder(_ a: LeaseCharge, _ b: LeaseCharge) -> Bool {
        if a.dueDate != b.dueDate { return a.dueDate < b.dueDate }
        if a.kind.rank != b.kind.rank { return a.kind.rank < b.kind.rank }
        if a.periodStart != b.periodStart { return a.periodStart < b.periodStart }
        return (a.id ?? "") < (b.id ?? "")
    }

    static func allocatedAmount(chargeId: String?, payments: [LeasePayment], currency: String) -> Money {
        guard let chargeId else { return .zero(currency) }
        return payments
            .filter { $0.direction == .incoming && !$0.isReversed }
            .flatMap(\.allocations)
            .filter { $0.chargeId == chargeId }
            .reduce(Money.zero(currency)) { $0 + $1.amount }
    }

    /// Splits `amount` over open charges: first `target` (up to its outstanding), then FIFO
    /// including future charges. `kinds` limits the FIFO walk (credit never goes to the deposit
    /// charge). Returns the allocation lines and the unallocated remainder (tenant credit).
    static func allocate(
        amount: Money,
        target: LeaseCharge?,
        among charges: [LeaseCharge],
        kinds: Set<Int>? = nil
    ) -> (lines: [LeasePaymentAllocation], remainder: Money) {
        var left = amount
        var lines: [LeasePaymentAllocation] = []

        func take(_ charge: LeaseCharge) {
            guard left.isPositive, let id = charge.id, charge.state == .open, charge.outstanding.isPositive else { return }
            let part = Money(minor: min(left.minor, charge.outstanding.minor), currency: amount.currency)
            if let existing = lines.firstIndex(where: { $0.chargeId == id }) {
                lines[existing].amount = lines[existing].amount + part
            } else {
                lines.append(LeasePaymentAllocation(chargeId: id, kind: charge.kind, amount: part))
            }
            left = left - part
        }

        if let target { take(target) }
        for charge in charges.sorted(by: { fifoOrder($0, $1) }) where charge.id != target?.id {
            if let kinds, !kinds.contains(charge.kind.rank) { continue }
            // `outstanding` was computed before this payment; lines already taken from the
            // same charge (the target) are excluded above, so no double counting.
            take(charge)
        }
        return (lines, left)
    }

    /// Spec §4.4: unallocated remainders of the oldest payments go FIFO to open rent and extra
    /// charges (never the deposit charge).
    static func applyCredit(_ lease: inout LeaseAggregate, today: String) {
        recalculate(&lease, today: today)
        let payments = lease.payments.indices
            .filter { lease.payments[$0].direction == .incoming && !lease.payments[$0].isReversed && lease.payments[$0].unallocated.isPositive }
            .sorted { lease.payments[$0].receivedOn < lease.payments[$1].receivedOn }
        for index in payments {
            let result = allocate(
                amount: lease.payments[index].unallocated,
                target: nil,
                among: lease.charges,
                kinds: [ChargeKind.rent.rank, ChargeKind.extra.rank]
            )
            guard !result.lines.isEmpty else { continue }
            merge(lines: result.lines, into: &lease.payments[index])
            recalculate(&lease, today: today)
        }
    }

    static func merge(lines: [LeasePaymentAllocation], into payment: inout LeasePayment) {
        for line in lines {
            if let existing = payment.allocations.firstIndex(where: { $0.chargeId == line.chargeId }) {
                payment.allocations[existing].amount = payment.allocations[existing].amount + line.amount
            } else {
                payment.allocations.append(line)
            }
        }
    }

    /// Spec §4.5: removes the allocations of a voided charge and re-routes them FIFO to the
    /// earliest open charges; any excess is left unallocated (tenant credit).
    static func moveAllocations(ofVoided chargeId: String, in lease: inout LeaseAggregate, today: String) {
        for index in lease.payments.indices {
            let removed = lease.payments[index].allocations.filter { $0.chargeId == chargeId }
            guard !removed.isEmpty else { continue }
            lease.payments[index].allocations.removeAll { $0.chargeId == chargeId }
            let total = removed.reduce(Money.zero(lease.currency)) { $0 + $1.amount }
            recalculate(&lease, today: today)
            let result = allocate(amount: total, target: nil, among: lease.charges.filter { $0.id != chargeId })
            merge(lines: result.lines, into: &lease.payments[index])
            recalculate(&lease, today: today)
        }
    }
}
