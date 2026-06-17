import Foundation

/// One row of the cross-portfolio payment queue (`PaymentQueueItem` in OpenAPI).
/// List: `GET /v1/payment-queue?scope={upcoming|past}&months=N` (ADR-104 list envelope).
/// Extends the per-lease `PaymentSchedule` fields with property/tenant locators.
struct PaymentQueueItem: Identifiable, Decodable {
    let id: String
    let leaseId: String
    let dueDate: String
    let periodStartDate: String?
    let periodEndDate: String?
    let expectedAmount: Double
    let currency: String
    let actualAmount: Double?
    let paidAt: String?
    let status: String
    let isOverdue: Bool
    let daysOverdue: Int
    let propertyId: String
    let propertyName: String
    let propertyAddress: String?
    let tenantId: String
    let tenantName: String
    let paymentDay: Int?
    // GAP-034/040 collection context (optional: older API builds omit them).
    var tenantPhone: String? = nil
    var tenantEmail: String? = nil
    var paidToDate: Double? = nil
    var remainingAmount: Double? = nil
    var allocationCount: Int? = nil

    enum CodingKeys: String, CodingKey {
        case id, status, currency
        case leaseId = "lease_id"
        case dueDate = "due_date"
        case periodStartDate = "period_start_date"
        case periodEndDate = "period_end_date"
        case expectedAmount = "expected_amount"
        case actualAmount = "actual_amount"
        case paidAt = "paid_at"
        case isOverdue = "is_overdue"
        case daysOverdue = "days_overdue"
        case propertyId = "property_id"
        case propertyName = "property_name"
        case propertyAddress = "property_address"
        case tenantId = "tenant_id"
        case tenantName = "tenant_name"
        case paymentDay = "payment_day"
        case tenantPhone = "tenant_phone"
        case tenantEmail = "tenant_email"
        case paidToDate = "paid_to_date"
        case remainingAmount = "remaining_amount"
        case allocationCount = "allocation_count"
    }

    /// Outstanding amount: prefer the backend remaining balance (partial-aware),
    /// fall back to the expected installment for older payloads.
    var outstandingAmount: Double {
        remainingAmount ?? expectedAmount
    }

    /// Bridges a queue row to the per-lease schedule model so the existing
    /// `MarkSchedulePaidSheet` (offline-queue aware) can be reused as-is.
    var asLeaseSchedule: LeasePaymentSchedule {
        LeasePaymentSchedule(
            id: id,
            leaseId: leaseId,
            dueDate: dueDate,
            periodStartDate: periodStartDate,
            periodEndDate: periodEndDate,
            notificationDueDate: nil,
            notificationSentAt: nil,
            expectedAmount: expectedAmount,
            currency: currency,
            actualPaymentId: nil,
            actualAmount: actualAmount,
            paidAt: paidAt,
            transactionId: nil,
            status: status,
            isOverdue: isOverdue,
            daysOverdue: daysOverdue
        )
    }
}

/// Body for `PATCH /v1/payment-schedules/:id`. The backend applies exactly one
/// intent per call, so construction is restricted to single-intent factories:
/// `due_day` rewrites the lease payment day and regenerates the future schedule,
/// `expected_amount` rewrites the lease rent and regenerates, `action: "skip"`
/// drops a single installment, `action: "restore"` puts a row back to `pending`.
struct PaymentScheduleUpdateRequest: Codable, Equatable {
    let dueDay: Int?
    let expectedAmount: Double?
    let action: String?

    enum CodingKeys: String, CodingKey {
        case action
        case dueDay = "due_day"
        case expectedAmount = "expected_amount"
    }

    private init(dueDay: Int? = nil, expectedAmount: Double? = nil, action: String? = nil) {
        self.dueDay = dueDay
        self.expectedAmount = expectedAmount
        self.action = action
    }

    static func day(_ day: Int) -> PaymentScheduleUpdateRequest {
        PaymentScheduleUpdateRequest(dueDay: day)
    }

    static func amount(_ amount: Double) -> PaymentScheduleUpdateRequest {
        PaymentScheduleUpdateRequest(expectedAmount: amount)
    }

    static let skip = PaymentScheduleUpdateRequest(action: "skip")
    static let restore = PaymentScheduleUpdateRequest(action: "restore")

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Encode only the active intent so the API sees a single change per call.
        try container.encodeIfPresent(dueDay, forKey: .dueDay)
        try container.encodeIfPresent(expectedAmount, forKey: .expectedAmount)
        try container.encodeIfPresent(action, forKey: .action)
    }
}
