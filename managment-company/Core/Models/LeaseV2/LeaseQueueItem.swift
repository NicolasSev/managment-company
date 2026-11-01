import Foundation

/// Row of `GET /v1/payment-queue` in its v2 shape (spec §9.6): the v1 `PaymentQueueItem`
/// fields plus the charge fields. The existing `PaymentQueueItem` keeps decoding the same
/// payload (extra keys are ignored); this type exposes the v2 fields for the lease screens.
struct LeaseQueueItem: Decodable, Hashable, Identifiable {
    var id: String
    var leaseId: String
    var chargeId: String
    var kind: ChargeKind
    var description: String?
    var dueDate: String
    var periodStart: String
    var periodEnd: String
    var amount: Money
    var allocated: Money
    var outstanding: Money
    var waivedAmount: Money
    var tenantCredit: Money
    var paymentStatus: ChargePaymentStatus
    var leaseStatus: LeaseStatus
    var isOverdue: Bool
    var daysOverdue: Int
    var propertyId: String
    var propertyName: String
    var propertyAddress: String?
    var tenantId: String
    var tenantName: String
    var tenantPhone: String?
    var tenantEmail: String?
    var paymentDay: Int?
    var notificationDueDate: String?
    var notificationSentAt: String?
    var paidAt: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, description, amount, allocated, outstanding, currency
        case leaseId = "lease_id"
        case chargeId = "charge_id"
        case dueDate = "due_date"
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case waivedAmount = "waived_amount"
        case tenantCredit = "tenant_credit"
        case paymentStatus = "payment_status"
        case leaseStatus = "lease_status"
        case isOverdue = "is_overdue"
        case daysOverdue = "days_overdue"
        case propertyId = "property_id"
        case propertyName = "property_name"
        case propertyAddress = "property_address"
        case tenantId = "tenant_id"
        case tenantName = "tenant_name"
        case tenantPhone = "tenant_phone"
        case tenantEmail = "tenant_email"
        case paymentDay = "payment_day"
        case notificationDueDate = "notification_due_date"
        case notificationSentAt = "notification_sent_at"
        case paidAt = "paid_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let cur = try c.decode(String.self, forKey: .currency)
        id = try c.decode(String.self, forKey: .id)
        leaseId = try c.decode(String.self, forKey: .leaseId)
        chargeId = try c.decode(String.self, forKey: .chargeId)
        kind = try c.decode(ChargeKind.self, forKey: .kind)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        dueDate = try c.decode(String.self, forKey: .dueDate)
        periodStart = try c.decode(String.self, forKey: .periodStart)
        periodEnd = try c.decode(String.self, forKey: .periodEnd)
        amount = try c.decodeMoney(.amount, currency: cur)
        allocated = try c.decodeMoney(.allocated, currency: cur)
        outstanding = try c.decodeMoney(.outstanding, currency: cur)
        waivedAmount = try c.decodeMoney(.waivedAmount, currency: cur)
        tenantCredit = try c.decodeMoney(.tenantCredit, currency: cur)
        paymentStatus = try c.decode(ChargePaymentStatus.self, forKey: .paymentStatus)
        leaseStatus = try c.decode(LeaseStatus.self, forKey: .leaseStatus)
        isOverdue = try c.decode(Bool.self, forKey: .isOverdue)
        daysOverdue = try c.decode(Int.self, forKey: .daysOverdue)
        propertyId = try c.decode(String.self, forKey: .propertyId)
        propertyName = try c.decode(String.self, forKey: .propertyName)
        propertyAddress = try c.decodeIfPresent(String.self, forKey: .propertyAddress)
        tenantId = try c.decode(String.self, forKey: .tenantId)
        tenantName = try c.decode(String.self, forKey: .tenantName)
        tenantPhone = try c.decodeIfPresent(String.self, forKey: .tenantPhone)
        tenantEmail = try c.decodeIfPresent(String.self, forKey: .tenantEmail)
        paymentDay = try c.decodeIfPresent(Int.self, forKey: .paymentDay)
        notificationDueDate = try c.decodeIfPresent(String.self, forKey: .notificationDueDate)
        notificationSentAt = try c.decodeIfPresent(String.self, forKey: .notificationSentAt)
        paidAt = try c.decodeIfPresent(String.self, forKey: .paidAt)
    }
}
