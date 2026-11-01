import Foundation

/// `deposit.ledger[]` entry (spec §1.5, §5).
struct DepositLedgerEntry: Hashable {
    var id: String
    var entryType: DepositEntryType
    var amount: Money
    var entryDate: String
    var reason: String?
    var transactionId: String?
    var leasePaymentId: String?
    var reversesEntryId: String?
    var reversedByEntryId: String?
    var createdAt: String

    var isReversed: Bool { reversedByEntryId != nil }
}

private struct LedgerWire: Codable {
    var id: String
    var entryType: DepositEntryType
    var amount: Decimal
    var entryDate: String
    var reason: String?
    var transactionId: String?
    var leasePaymentId: String?
    var reversesEntryId: String?
    var reversedByEntryId: String?
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, amount, reason
        case entryType = "entry_type"
        case entryDate = "entry_date"
        case transactionId = "transaction_id"
        case leasePaymentId = "lease_payment_id"
        case reversesEntryId = "reverses_entry_id"
        case reversedByEntryId = "reversed_by_entry_id"
        case createdAt = "created_at"
    }
}

/// `deposit` block of the aggregate: the charge (what the tenant owes) and the ledger (what
/// the owner holds). `held = received - returned - forfeited - applied_to_debt`.
struct LeaseDeposit: Codable, Hashable {
    var amount: Money
    var chargeId: String?
    var received: Money
    var returned: Money
    var forfeited: Money
    var appliedToDebt: Money
    var held: Money
    var outstanding: Money
    var status: DepositStatus
    /// `min(held, balance.outstanding)`: offered to the owner on return, never applied by itself.
    var suggestedApplyToDebt: Money
    var ledger: [DepositLedgerEntry]

    var currency: String { amount.currency }

    enum CodingKeys: String, CodingKey {
        case amount, currency, received, returned, forfeited, held, outstanding, status, ledger
        case chargeId = "charge_id"
        case appliedToDebt = "applied_to_debt"
        case suggestedApplyToDebt = "suggested_apply_to_debt"
    }

    init(
        amount: Money,
        chargeId: String?,
        received: Money? = nil,
        returned: Money? = nil,
        forfeited: Money? = nil,
        appliedToDebt: Money? = nil,
        held: Money? = nil,
        outstanding: Money? = nil,
        status: DepositStatus = .expected,
        suggestedApplyToDebt: Money? = nil,
        ledger: [DepositLedgerEntry] = []
    ) {
        let zero = Money.zero(amount.currency)
        self.amount = amount
        self.chargeId = chargeId
        self.received = received ?? zero
        self.returned = returned ?? zero
        self.forfeited = forfeited ?? zero
        self.appliedToDebt = appliedToDebt ?? zero
        self.held = held ?? zero
        self.outstanding = outstanding ?? zero
        self.status = status
        self.suggestedApplyToDebt = suggestedApplyToDebt ?? zero
        self.ledger = ledger
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let currency = try c.decode(String.self, forKey: .currency)
        amount = try c.decodeMoney(.amount, currency: currency)
        chargeId = try c.decodeIfPresent(String.self, forKey: .chargeId)
        received = try c.decodeMoney(.received, currency: currency)
        returned = try c.decodeMoney(.returned, currency: currency)
        forfeited = try c.decodeMoney(.forfeited, currency: currency)
        appliedToDebt = try c.decodeMoney(.appliedToDebt, currency: currency)
        held = try c.decodeMoney(.held, currency: currency)
        outstanding = try c.decodeMoney(.outstanding, currency: currency)
        status = try c.decode(DepositStatus.self, forKey: .status)
        suggestedApplyToDebt = try c.decodeMoney(.suggestedApplyToDebt, currency: currency)
        ledger = try c.decode([LedgerWire].self, forKey: .ledger).map {
            DepositLedgerEntry(
                id: $0.id,
                entryType: $0.entryType,
                amount: Money(major: $0.amount, currency: currency),
                entryDate: $0.entryDate,
                reason: $0.reason,
                transactionId: $0.transactionId,
                leasePaymentId: $0.leasePaymentId,
                reversesEntryId: $0.reversesEntryId,
                reversedByEntryId: $0.reversedByEntryId,
                createdAt: $0.createdAt
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeMoney(amount, forKey: .amount)
        try c.encode(amount.currency, forKey: .currency)
        try c.encode(chargeId, forKey: .chargeId)
        try c.encodeMoney(received, forKey: .received)
        try c.encodeMoney(returned, forKey: .returned)
        try c.encodeMoney(forfeited, forKey: .forfeited)
        try c.encodeMoney(appliedToDebt, forKey: .appliedToDebt)
        try c.encodeMoney(held, forKey: .held)
        try c.encodeMoney(outstanding, forKey: .outstanding)
        try c.encode(status, forKey: .status)
        try c.encodeMoney(suggestedApplyToDebt, forKey: .suggestedApplyToDebt)
        try c.encode(
            ledger.map {
                LedgerWire(
                    id: $0.id,
                    entryType: $0.entryType,
                    amount: $0.amount.major,
                    entryDate: $0.entryDate,
                    reason: $0.reason,
                    transactionId: $0.transactionId,
                    leasePaymentId: $0.leasePaymentId,
                    reversesEntryId: $0.reversesEntryId,
                    reversedByEntryId: $0.reversedByEntryId,
                    createdAt: $0.createdAt
                )
            },
            forKey: .ledger
        )
    }
}
