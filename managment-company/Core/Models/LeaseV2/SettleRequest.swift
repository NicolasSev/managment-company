import Foundation

// Body of `POST /v1/workflows/settle` (spec §9.7, fixture `settle-request.json`). Optional values
// that are `nil` are left out of the JSON. The answer is `SettleResponse`.

/// `tenant` of a settle request: a new tenant, or an existing one found by IIN.
struct SettleTenantInput: Encodable, Equatable {
    var firstName: String
    var lastName: String?
    var middleName: String?
    var phone: String?
    var email: String?
    var iin: String?
    var documentType: String?
    var documentNumber: String?
    var documentIssuedBy: String?
    var documentIssuedAt: String?
    var birthDate: String?
    var registrationAddress: String?
    var cohabitants: String?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case phone, email, iin, cohabitants, notes
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

/// `lease` of a settle request. `termMonths` and `endDate` are mutually exclusive on the server.
struct SettleLeaseInput: Encodable, Equatable {
    var startDate: String
    var endDate: String?
    var termMonths: Int?
    var rentAmount: Decimal
    var rentCurrency: String
    var depositAmount: Decimal?
    var dueDay: Int?
    var remindDaysBefore: Int?
    var utilitiesPaidBy: UtilitiesPaidBy
    var renewalReminderDays: Int?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case notes
        case startDate = "start_date"
        case endDate = "end_date"
        case termMonths = "term_months"
        case rentAmount = "rent_amount"
        case rentCurrency = "rent_currency"
        case depositAmount = "deposit_amount"
        case dueDay = "due_day"
        case remindDaysBefore = "remind_days_before"
        case utilitiesPaidBy = "utilities_paid_by"
        case renewalReminderDays = "renewal_reminder_days"
    }
}

struct SettleRequest: Encodable, Equatable {
    /// Exactly one of `tenant` and `tenantId`.
    var tenant: SettleTenantInput?
    var tenantId: String?
    var propertyId: String
    var replacesLeaseId: String?
    var lease: SettleLeaseInput
    var templateId: String?
    /// The app renders the document itself afterwards (`POST /v1/leases/:id/contract`); the
    /// server answers `501` to `true`.
    var generateContract = false
    var sendForSignature: Bool?
    var signedOn: String?
    var activate: Bool?
    var activationDate: String?
    var identityDocumentFileId: String?
    /// Which client sent it; the server records it in `workflow.settled`.
    var source = "ios"

    enum CodingKeys: String, CodingKey {
        case tenant, lease, activate, source
        case tenantId = "tenant_id"
        case propertyId = "property_id"
        case replacesLeaseId = "replaces_lease_id"
        case templateId = "template_id"
        case generateContract = "generate_contract"
        case sendForSignature = "send_for_signature"
        case signedOn = "signed_on"
        case activationDate = "activation_date"
        case identityDocumentFileId = "identity_document_file_id"
    }
}
