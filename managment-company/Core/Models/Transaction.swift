import Foundation

struct Transaction: Identifiable, Codable {
    let id: String
    let propertyId: String
    let type: String
    let categoryId: String
    let amount: Double
    let currency: String
    let amountBase: Double
    let exchangeRate: Double?
    let transactionDate: String
    let periodYear: Int
    let periodMonth: Int
    let description: String?
    let tenantId: String?
    let leaseId: String?
    
    enum CodingKeys: String, CodingKey {
        case id, type, amount, currency, description
        case propertyId = "property_id"
        case categoryId = "category_id"
        case amountBase = "amount_base"
        case exchangeRate = "exchange_rate"
        case transactionDate = "transaction_date"
        case periodYear = "period_year"
        case periodMonth = "period_month"
        case tenantId = "tenant_id"
        case leaseId = "lease_id"
    }
}
