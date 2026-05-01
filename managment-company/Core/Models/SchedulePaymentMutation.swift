import Foundation

/// Body for `POST /v1/payment-schedules/:id/mark-paid` (optional fields mirror OpenAPI).
struct MarkSchedulePaidRequest: Encodable {
    var amount: Double?
    var currency: String?
    var paymentDate: String?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case amount, currency, notes
        case paymentDate = "payment_date"
    }
}

/// Tenant payment row embedded in schedule mark-paid response.
struct TenantRentPayment: Decodable {
    let id: String
    let leaseId: String
    let amount: Double
    let currency: String
    let paymentDate: String
    let periodYear: Int
    let periodMonth: Int
    let status: String
    let transactionId: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, amount, currency, status, notes
        case leaseId = "lease_id"
        case paymentDate = "payment_date"
        case periodYear = "period_year"
        case periodMonth = "period_month"
        case transactionId = "transaction_id"
    }
}

/// `{ "data": { "schedule", "payment" } }` body type for decoding after mark-paid (HTTP 201).
struct SchedulePaymentResult: Decodable {
    let schedule: LeasePaymentSchedule
    let payment: TenantRentPayment
}
