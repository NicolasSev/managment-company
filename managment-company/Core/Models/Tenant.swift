import Foundation

struct Tenant: Identifiable, Codable {
    let id: String
    let firstName: String
    let lastName: String?
    let phone: String?
    let email: String?
    let cohabitants: String?
    let notes: String?
    // Identity fields (T1). `PUT /v1/tenants/:id` replaces the whole record, so every one of
    // them must travel back on save (see `TenantUpsertBody`), otherwise an edit clears them.
    var middleName: String? = nil
    var iin: String? = nil
    var documentType: String? = nil
    var documentNumber: String? = nil
    var documentIssuedBy: String? = nil
    var documentIssuedAt: String? = nil
    var birthDate: String? = nil
    var registrationAddress: String? = nil

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

    var displayName: String {
        [firstName, lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}
