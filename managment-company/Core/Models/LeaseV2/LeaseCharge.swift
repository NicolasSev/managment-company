import Foundation

/// One row of the charge queue (`lease_charges`, spec §1.3). Rent, deposit and extra charges
/// share the shape; `id` is `nil` only for `charges_preview` rows of draft/pending leases.
struct LeaseCharge: Codable, Hashable {
    var id: String?
    var kind: ChargeKind
    var periodStart: String
    var periodEnd: String
    var dueDate: String
    var amount: Money
    var description: String?
    var state: ChargeState
    var waivedAmount: Money
    var allocated: Money
    var outstanding: Money
    var paymentStatus: ChargePaymentStatus
    var isOverdue: Bool
    var daysOverdue: Int
    var replacesChargeId: String?
    var canPay: Bool
    var canWaive: Bool
    var canUnwaive: Bool

    var currency: String { amount.currency }

    /// Stable `ForEach` identity, also for preview rows without a server id.
    var rowKey: String {
        id ?? "preview-\(kind.rawValue)-\(periodStart)"
    }

    var isVoid: Bool { state == .void }

    enum CodingKeys: String, CodingKey {
        case id, kind, amount, description, state, allocated, outstanding, currency
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case dueDate = "due_date"
        case waivedAmount = "waived_amount"
        case paymentStatus = "payment_status"
        case isOverdue = "is_overdue"
        case daysOverdue = "days_overdue"
        case replacesChargeId = "replaces_charge_id"
        case canPay = "can_pay"
        case canWaive = "can_waive"
        case canUnwaive = "can_unwaive"
    }

    init(
        id: String?,
        kind: ChargeKind,
        periodStart: String,
        periodEnd: String,
        dueDate: String,
        amount: Money,
        description: String? = nil,
        state: ChargeState = .open,
        waivedAmount: Money? = nil,
        allocated: Money? = nil,
        outstanding: Money? = nil,
        paymentStatus: ChargePaymentStatus = .unpaid,
        isOverdue: Bool = false,
        daysOverdue: Int = 0,
        replacesChargeId: String? = nil,
        canPay: Bool = false,
        canWaive: Bool = false,
        canUnwaive: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.dueDate = dueDate
        self.amount = amount
        self.description = description
        self.state = state
        self.waivedAmount = waivedAmount ?? .zero(amount.currency)
        self.allocated = allocated ?? .zero(amount.currency)
        self.outstanding = outstanding ?? amount
        self.paymentStatus = paymentStatus
        self.isOverdue = isOverdue
        self.daysOverdue = daysOverdue
        self.replacesChargeId = replacesChargeId
        self.canPay = canPay
        self.canWaive = canWaive
        self.canUnwaive = canUnwaive
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let currency = try c.decode(String.self, forKey: .currency)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        kind = try c.decode(ChargeKind.self, forKey: .kind)
        periodStart = try c.decode(String.self, forKey: .periodStart)
        periodEnd = try c.decode(String.self, forKey: .periodEnd)
        dueDate = try c.decode(String.self, forKey: .dueDate)
        amount = try c.decodeMoney(.amount, currency: currency)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        state = try c.decode(ChargeState.self, forKey: .state)
        waivedAmount = try c.decodeMoney(.waivedAmount, currency: currency)
        allocated = try c.decodeMoney(.allocated, currency: currency)
        outstanding = try c.decodeMoney(.outstanding, currency: currency)
        paymentStatus = try c.decode(ChargePaymentStatus.self, forKey: .paymentStatus)
        isOverdue = try c.decode(Bool.self, forKey: .isOverdue)
        daysOverdue = try c.decode(Int.self, forKey: .daysOverdue)
        replacesChargeId = try c.decodeIfPresent(String.self, forKey: .replacesChargeId)
        canPay = try c.decode(Bool.self, forKey: .canPay)
        canWaive = try c.decode(Bool.self, forKey: .canWaive)
        canUnwaive = try c.decode(Bool.self, forKey: .canUnwaive)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(periodStart, forKey: .periodStart)
        try c.encode(periodEnd, forKey: .periodEnd)
        try c.encode(dueDate, forKey: .dueDate)
        try c.encodeMoney(amount, forKey: .amount)
        try c.encode(amount.currency, forKey: .currency)
        try c.encode(description, forKey: .description)
        try c.encode(state, forKey: .state)
        try c.encodeMoney(waivedAmount, forKey: .waivedAmount)
        try c.encodeMoney(allocated, forKey: .allocated)
        try c.encodeMoney(outstanding, forKey: .outstanding)
        try c.encode(paymentStatus, forKey: .paymentStatus)
        try c.encode(isOverdue, forKey: .isOverdue)
        try c.encode(daysOverdue, forKey: .daysOverdue)
        try c.encode(replacesChargeId, forKey: .replacesChargeId)
        try c.encode(canPay, forKey: .canPay)
        try c.encode(canWaive, forKey: .canWaive)
        try c.encode(canUnwaive, forKey: .canUnwaive)
    }
}

/// `balance.next_charge` (spec §6). Decoded by `LeaseBalance`, which owns the currency.
struct LeaseNextCharge: Encodable, Hashable {
    var id: String
    var kind: ChargeKind
    var dueDate: String
    var amount: Money
    var outstanding: Money

    enum CodingKeys: String, CodingKey {
        case id, kind, amount, outstanding
        case dueDate = "due_date"
    }

    /// `next_charge` has no currency of its own; the enclosing `balance` supplies it.
    init(id: String, kind: ChargeKind, dueDate: String, amount: Money, outstanding: Money) {
        self.id = id
        self.kind = kind
        self.dueDate = dueDate
        self.amount = amount
        self.outstanding = outstanding
    }

    init(from decoder: Decoder, currency: String) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(ChargeKind.self, forKey: .kind)
        dueDate = try c.decode(String.self, forKey: .dueDate)
        amount = try c.decodeMoney(.amount, currency: currency)
        outstanding = try c.decodeMoney(.outstanding, currency: currency)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(dueDate, forKey: .dueDate)
        try c.encodeMoney(amount, forKey: .amount)
        try c.encodeMoney(outstanding, forKey: .outstanding)
    }
}
