import Foundation

struct Lease: Identifiable, Codable {
    let id: String
    let propertyId: String
    /// Present when lease is embedded in property-scoped list responses (optional on wire).
    let propertyName: String?
    let tenantId: String
    let startDate: String
    let endDate: String?
    let moveInDate: String?
    let rentAmount: Double
    let rentCurrency: String
    let depositAmount: Double?
    let depositCurrency: String?
    let paymentDay: Int?
    let paymentWindowStartDay: Int?
    let paymentWindowEndDay: Int?
    let paymentDueDay: Int?
    let status: String
    let terminatedAt: String?
    let terminationReason: String?
    let notes: String?
    let renewalReminderDays: Int?
    let autoRenew: Bool?
    /// `"owner"` | `"tenant"` | `"split"` per contract `UtilitiesPaidBy`.
    let utilitiesPaidBy: String?

    enum CodingKeys: String, CodingKey {
        case id, status, notes
        case propertyId = "property_id"
        case propertyName = "property_name"
        case tenantId = "tenant_id"
        case startDate = "start_date"
        case endDate = "end_date"
        case moveInDate = "move_in_date"
        case rentAmount = "rent_amount"
        case rentCurrency = "rent_currency"
        case depositAmount = "deposit_amount"
        case depositCurrency = "deposit_currency"
        case paymentDay = "payment_day"
        case paymentWindowStartDay = "payment_window_start_day"
        case paymentWindowEndDay = "payment_window_end_day"
        case paymentDueDay = "payment_due_day"
        case terminatedAt = "terminated_at"
        case terminationReason = "termination_reason"
        case renewalReminderDays = "renewal_reminder_days"
        case autoRenew = "auto_renew"
        case utilitiesPaidBy = "utilities_paid_by"
    }
}
