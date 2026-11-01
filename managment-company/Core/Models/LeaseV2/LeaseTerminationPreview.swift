import Foundation

/// What `terminate` would do (spec §3.7), computed on the client for the confirmation sheet.
/// The server remains the source of truth; the response aggregate replaces local state.
struct LeaseTerminationPreview: Equatable {
    /// Charges that would be voided: non-void, any kind, `period_start > move_out_date`.
    var voidedCharges: [LeaseCharge]
    var voidedTotal: Money
    /// The rent charge whose period contains the move-out date; it stays whole (no proration).
    var keptPeriodCharge: LeaseCharge?
    /// `terminated` when moving out before `end_date`, otherwise `ended`.
    var resultingStatus: LeaseStatus
    /// Deposit written to the ledger as `forfeited` (only for `terminated`).
    var forfeitedDeposit: Money
    /// Deposit that stays held until «Депозит возвращён».
    var remainingHeld: Money
    /// Outstanding on the charges that remain (everything up to move-out): stays visible and owed.
    var debtStaysVisible: Money

    static func make(lease: LeaseAggregate, moveOutDate: String, forfeitAmount: Money?) -> LeaseTerminationPreview {
        let currency = lease.currency
        let voided = lease.charges.filter { $0.state != .void && $0.periodStart > moveOutDate }
        let voidedIds = Set(voided.compactMap(\.id))
        let kept = lease.charges.first {
            $0.kind == .rent && $0.state != .void && $0.periodStart <= moveOutDate && moveOutDate <= $0.periodEnd
        }
        let earlyMoveOut: Bool
        if let end = lease.endDate {
            earlyMoveOut = moveOutDate < end
        } else {
            earlyMoveOut = false
        }
        let held = lease.deposit.held
        let forfeited: Money
        if earlyMoveOut {
            forfeited = Money(minor: min(max(forfeitAmount?.minor ?? held.minor, 0), held.minor), currency: currency)
        } else {
            forfeited = .zero(currency)
        }
        let debt = lease.charges
            .filter { $0.state != .void && !voidedIds.contains($0.id ?? "") }
            .reduce(Money.zero(currency)) { $0 + $1.outstanding }
        return LeaseTerminationPreview(
            voidedCharges: voided,
            voidedTotal: voided.reduce(Money.zero(currency)) { $0 + $1.amount },
            keptPeriodCharge: kept,
            resultingStatus: earlyMoveOut ? .terminated : .ended,
            forfeitedDeposit: forfeited,
            remainingHeld: held - forfeited,
            debtStaysVisible: debt
        )
    }
}
