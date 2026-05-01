import Foundation

/// One expected rent instalment (`PaymentSchedule` in OpenAPI). List: `GET /v1/leases/:id/payment-schedule`.
struct LeasePaymentSchedule: Identifiable, Codable {
    let id: String
    let leaseId: String
    let dueDate: String
    let periodStartDate: String?
    let periodEndDate: String?
    let notificationDueDate: String?
    let notificationSentAt: String?
    let expectedAmount: Double
    let currency: String
    let actualPaymentId: String?
    let actualAmount: Double?
    let paidAt: String?
    let transactionId: String?
    let status: String
    let isOverdue: Bool
    let daysOverdue: Int

    enum CodingKeys: String, CodingKey {
        case id, status, currency
        case leaseId = "lease_id"
        case dueDate = "due_date"
        case periodStartDate = "period_start_date"
        case periodEndDate = "period_end_date"
        case notificationDueDate = "notification_due_date"
        case notificationSentAt = "notification_sent_at"
        case expectedAmount = "expected_amount"
        case actualPaymentId = "actual_payment_id"
        case actualAmount = "actual_amount"
        case paidAt = "paid_at"
        case transactionId = "transaction_id"
        case isOverdue = "is_overdue"
        case daysOverdue = "days_overdue"
    }
}
