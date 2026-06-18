import Foundation

/// One payment applied to a single schedule row.
/// List: `GET /v1/payment-schedules/:id/allocations` (oldest first).
/// Reversing: `DELETE /v1/payments/:id` soft-deletes the linked income transaction
/// and recalculates the schedule's pending/partial/paid status (GAP-048).
struct PaymentScheduleAllocation: Identifiable, Decodable, Equatable {
    let id: String
    let amount: Double
    let currency: String
    let paymentDate: String
    let status: String
    let transactionId: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, amount, currency, status, notes
        case paymentDate = "payment_date"
        case transactionId = "transaction_id"
    }
}
