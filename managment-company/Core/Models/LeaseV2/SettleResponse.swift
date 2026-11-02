import Foundation

/// The tenant of a settle answer: found by id or IIN, or just created. Same identity fields as
/// `TenantResponse` in the contract (`Tenant` of the v1 screens does not carry the passport data).
nonisolated struct SettleTenant: Codable, Hashable, Identifiable {
    var id: String
    var firstName: String
    var lastName: String?
    var middleName: String?
    var phone: String?
    var email: String?
    var cohabitants: String?
    var notes: String?
    var iin: String?
    var documentType: String?
    var documentNumber: String?
    var documentIssuedBy: String?
    var documentIssuedAt: String?
    var birthDate: String?
    var registrationAddress: String?

    enum CodingKeys: String, CodingKey {
        case id, phone, email, cohabitants, notes, iin
        case firstName = "first_name"
        case lastName = "last_name"
        case middleName = "middle_name"
        case documentType = "document_type"
        case documentNumber = "document_number"
        case documentIssuedBy = "document_issued_by"
        case documentIssuedAt = "document_issued_at"
        case birthDate = "birth_date"
        case registrationAddress = "registration_address"
    }
}

/// `data` of the 201 answer of `POST /v1/workflows/settle` (contract schema `SettleResult`).
struct SettleResponse: Codable, Hashable {
    var tenantCreated: Bool
    var tenant: SettleTenant
    /// The lease as the last command of the chain left it (draft, pending_signature or active).
    var lease: LeaseAggregate

    enum CodingKeys: String, CodingKey {
        case tenant, lease
        case tenantCreated = "tenant_created"
    }
}
