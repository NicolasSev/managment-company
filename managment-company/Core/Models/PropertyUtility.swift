import Foundation

struct PropertyUtility: Identifiable, Codable {
    let id: String
    let propertyId: String
    let propertyName: String?
    let periodYear: Int
    let periodMonth: Int
    let utilityType: String
    let provider: String?
    let amount: Double
    let currency: String
    let dueDate: String?
    let paidAt: String?
    let status: String
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, provider, amount, currency, status, notes
        case propertyId = "property_id"
        case propertyName = "property_name"
        case periodYear = "period_year"
        case periodMonth = "period_month"
        case utilityType = "utility_type"
        case dueDate = "due_date"
        case paidAt = "paid_at"
    }
}
