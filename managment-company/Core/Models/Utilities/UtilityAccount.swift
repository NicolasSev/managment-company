import Foundation

// `GET/POST/PATCH/DELETE /v1/properties/:id/utility-accounts` and `.../utility-expectations`.

/// The default account of a property (R2: one).
struct UtilityAccount: Codable, Hashable, Identifiable {
    let id: String
    let propertyId: String
    let providerName: String?
    let providerCode: String?
    let accountNumber: String
    let isDefault: Bool
    let isActive: Bool
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case propertyId = "property_id"
        case providerName = "provider_name"
        case providerCode = "provider_code"
        case accountNumber = "account_number"
        case isDefault = "is_default"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// The months a bill is expected: a rule of one property.
struct UtilityExpectation: Codable, Hashable, Identifiable {
    let id: String
    let propertyId: String
    let leaseId: String?
    let months: [Int]
    let activeFrom: String
    let activeTo: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, months
        case propertyId = "property_id"
        case leaseId = "lease_id"
        case activeFrom = "active_from"
        case activeTo = "active_to"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// The rule is open at the end: it still produces expected bills.
    var isOpen: Bool { activeTo == nil }
}
