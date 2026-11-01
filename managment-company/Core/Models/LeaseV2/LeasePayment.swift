import Foundation

/// `payments[].allocations[]`: the part of a payment that closed (part of) a charge.
struct LeasePaymentAllocation: Hashable {
    var chargeId: String
    var kind: ChargeKind
    var amount: Money
}

private struct AllocationWire: Codable {
    var chargeId: String
    var kind: ChargeKind
    var amount: Decimal

    enum CodingKeys: String, CodingKey {
        case kind, amount
        case chargeId = "charge_id"
    }
}

/// `lease_payments` row (spec §1.4). Reversed payments stay in the list with `reversed_at`.
struct LeasePayment: Codable, Hashable {
    var id: String
    var direction: PaymentDirection
    var receivedOn: String
    var amount: Money
    var method: String?
    var source: String?
    var transactionId: String?
    var depositPart: Money
    var notes: String?
    var reversedAt: String?
    var reverseReason: String?
    var allocations: [LeasePaymentAllocation]
    var unallocated: Money
    var canReverse: Bool

    var isReversed: Bool { reversedAt != nil }

    enum CodingKeys: String, CodingKey {
        case id, direction, amount, currency, method, source, notes, allocations, unallocated
        case receivedOn = "received_on"
        case transactionId = "transaction_id"
        case depositPart = "deposit_part"
        case reversedAt = "reversed_at"
        case reverseReason = "reverse_reason"
        case canReverse = "can_reverse"
    }

    init(
        id: String,
        direction: PaymentDirection = .incoming,
        receivedOn: String,
        amount: Money,
        method: String?,
        source: String? = "manual",
        transactionId: String? = nil,
        depositPart: Money? = nil,
        notes: String? = nil,
        reversedAt: String? = nil,
        reverseReason: String? = nil,
        allocations: [LeasePaymentAllocation] = [],
        unallocated: Money? = nil,
        canReverse: Bool = true
    ) {
        self.id = id
        self.direction = direction
        self.receivedOn = receivedOn
        self.amount = amount
        self.method = method
        self.source = source
        self.transactionId = transactionId
        self.depositPart = depositPart ?? .zero(amount.currency)
        self.notes = notes
        self.reversedAt = reversedAt
        self.reverseReason = reverseReason
        self.allocations = allocations
        self.unallocated = unallocated ?? .zero(amount.currency)
        self.canReverse = canReverse
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let currency = try c.decode(String.self, forKey: .currency)
        id = try c.decode(String.self, forKey: .id)
        direction = try c.decode(PaymentDirection.self, forKey: .direction)
        receivedOn = try c.decode(String.self, forKey: .receivedOn)
        amount = try c.decodeMoney(.amount, currency: currency)
        method = try c.decodeIfPresent(String.self, forKey: .method)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        transactionId = try c.decodeIfPresent(String.self, forKey: .transactionId)
        depositPart = try c.decodeMoney(.depositPart, currency: currency)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        reversedAt = try c.decodeIfPresent(String.self, forKey: .reversedAt)
        reverseReason = try c.decodeIfPresent(String.self, forKey: .reverseReason)
        allocations = try c.decode([AllocationWire].self, forKey: .allocations).map {
            LeasePaymentAllocation(chargeId: $0.chargeId, kind: $0.kind, amount: Money(major: $0.amount, currency: currency))
        }
        unallocated = try c.decodeMoney(.unallocated, currency: currency)
        canReverse = try c.decode(Bool.self, forKey: .canReverse)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(direction, forKey: .direction)
        try c.encode(receivedOn, forKey: .receivedOn)
        try c.encodeMoney(amount, forKey: .amount)
        try c.encode(amount.currency, forKey: .currency)
        try c.encode(method, forKey: .method)
        try c.encode(source, forKey: .source)
        try c.encode(transactionId, forKey: .transactionId)
        try c.encodeMoney(depositPart, forKey: .depositPart)
        try c.encode(notes, forKey: .notes)
        try c.encode(reversedAt, forKey: .reversedAt)
        try c.encode(reverseReason, forKey: .reverseReason)
        try c.encode(
            allocations.map { AllocationWire(chargeId: $0.chargeId, kind: $0.kind, amount: $0.amount.major) },
            forKey: .allocations
        )
        try c.encodeMoney(unallocated, forKey: .unallocated)
        try c.encode(canReverse, forKey: .canReverse)
    }
}
