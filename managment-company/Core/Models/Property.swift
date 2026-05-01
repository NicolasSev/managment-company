import Foundation

struct Property: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let propertyType: String
    let country: String?
    let city: String?
    let address: String?
    let district: String?
    let areaSqm: Double?
    let rooms: Int?
    let floor: Int?
    let purchaseDate: String?
    let purchasePrice: Double?
    let purchaseCurrency: String?
    let currentValue: Double?
    let currentValueCurrency: String?
    let status: String
    let notes: String?
    let tags: [String]?
    /// Лицевой счёт для сопоставления квитанций ЖКХ (OCR).
    let utilityAccountNumber: String?

    enum CodingKeys: String, CodingKey {
        case id, name, status, notes, tags
        case propertyType = "property_type"
        case country, city, address, district
        case areaSqm = "area_sqm"
        case rooms, floor
        case purchaseDate = "purchase_date"
        case purchasePrice = "purchase_price"
        case purchaseCurrency = "purchase_currency"
        case currentValue = "current_value"
        case currentValueCurrency = "current_value_currency"
        case utilityAccountNumber = "utility_account_number"
    }
    
    var displayAddress: String? {
        [address, city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
