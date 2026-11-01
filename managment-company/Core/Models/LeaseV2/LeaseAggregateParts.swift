import Foundation

/// `property` of the aggregate: `{id, name, address}`.
struct LeaseProperty: Codable, Hashable {
    var id: String
    var name: String
    var address: String?
}

/// Current tenant card (`tenant`): `{id, first_name, ..., iin}`.
struct LeaseTenantCard: Codable, Hashable {
    var id: String
    var firstName: String?
    var lastName: String?
    var middleName: String?
    var fullName: String
    var phone: String?
    var email: String?
    var iin: String?

    enum CodingKeys: String, CodingKey {
        case id, phone, email, iin
        case firstName = "first_name"
        case lastName = "last_name"
        case middleName = "middle_name"
        case fullName = "full_name"
    }
}

/// `tenant_snapshot`: identity frozen at send-for-signature / mark-signed (spec §1.1).
struct LeaseTenantSnapshot: Codable, Hashable {
    var firstName: String?
    var lastName: String?
    var middleName: String?
    var fullName: String?
    var iin: String?
    var documentType: String?
    var documentNumber: String?
    var documentIssuedBy: String?
    var documentIssuedAt: String?
    var birthDate: String?
    var registrationAddress: String?
    var phone: String?
    var email: String?
    var capturedAt: String?

    enum CodingKeys: String, CodingKey {
        case iin, phone, email
        case firstName = "first_name"
        case lastName = "last_name"
        case middleName = "middle_name"
        case fullName = "full_name"
        case documentType = "document_type"
        case documentNumber = "document_number"
        case documentIssuedBy = "document_issued_by"
        case documentIssuedAt = "document_issued_at"
        case birthDate = "birth_date"
        case registrationAddress = "registration_address"
        case capturedAt = "captured_at"
    }
}

struct LeasePropertySnapshot: Codable, Hashable {
    var name: String?
    var address: String?
    var capturedAt: String?

    enum CodingKeys: String, CodingKey {
        case name, address
        case capturedAt = "captured_at"
    }
}

/// `lifecycle`: timestamps of the status machine. `terminated_at` here is the timestamp
/// (the top-level legacy alias is a date and is not decoded).
struct LeaseLifecycle: Codable, Hashable {
    var createdAt: String?
    var sentForSignatureAt: String?
    var signedOn: String?
    var activatedAt: String?
    var terminatedAt: String?
    var endedAt: String?
    var cancelledAt: String?
    var cancelReason: String?
    var lastProlongedAt: String?

    enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case sentForSignatureAt = "sent_for_signature_at"
        case signedOn = "signed_on"
        case activatedAt = "activated_at"
        case terminatedAt = "terminated_at"
        case endedAt = "ended_at"
        case cancelledAt = "cancelled_at"
        case cancelReason = "cancel_reason"
        case lastProlongedAt = "last_prolonged_at"
    }
}

struct LeaseFile: Codable, Hashable, Identifiable {
    var id: String
    var filename: String
    var mimeType: String?
    var sizeBytes: Int?
    var uploadedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, filename
        case mimeType = "mime_type"
        case sizeBytes = "size_bytes"
        case uploadedAt = "uploaded_at"
    }
}

struct LeaseDocuments: Codable, Hashable {
    var templateId: String?
    var contractFile: LeaseFile?
    var signedFile: LeaseFile?
    var files: [LeaseFile]

    enum CodingKeys: String, CodingKey {
        case files
        case templateId = "template_id"
        case contractFile = "contract_file"
        case signedFile = "signed_file"
    }
}

struct LeaseChecklistSummary: Codable, Hashable {
    var kind: String
    var status: String
    var done: Int
    var total: Int
}

/// `balance` (spec §6): every figure in `currency`, void charges excluded, all kinds counted.
struct LeaseBalance: Codable, Hashable {
    var currency: String
    var asOf: String
    var chargedToDate: Money
    var waivedToDate: Money
    var paidToDate: Money
    var outstanding: Money
    var overdue: Money
    var overdueCharges: Int
    var upcoming: Money
    var prepaid: Money
    var tenantCredit: Money
    var receivedTotal: Money
    var nextCharge: LeaseNextCharge?

    enum CodingKeys: String, CodingKey {
        case currency, outstanding, overdue, upcoming, prepaid
        case asOf = "as_of"
        case chargedToDate = "charged_to_date"
        case waivedToDate = "waived_to_date"
        case paidToDate = "paid_to_date"
        case overdueCharges = "overdue_charges"
        case tenantCredit = "tenant_credit"
        case receivedTotal = "received_total"
        case nextCharge = "next_charge"
    }

    init(
        currency: String,
        asOf: String,
        chargedToDate: Money? = nil,
        waivedToDate: Money? = nil,
        paidToDate: Money? = nil,
        outstanding: Money? = nil,
        overdue: Money? = nil,
        overdueCharges: Int = 0,
        upcoming: Money? = nil,
        prepaid: Money? = nil,
        tenantCredit: Money? = nil,
        receivedTotal: Money? = nil,
        nextCharge: LeaseNextCharge? = nil
    ) {
        let zero = Money.zero(currency)
        self.currency = currency
        self.asOf = asOf
        self.chargedToDate = chargedToDate ?? zero
        self.waivedToDate = waivedToDate ?? zero
        self.paidToDate = paidToDate ?? zero
        self.outstanding = outstanding ?? zero
        self.overdue = overdue ?? zero
        self.overdueCharges = overdueCharges
        self.upcoming = upcoming ?? zero
        self.prepaid = prepaid ?? zero
        self.tenantCredit = tenantCredit ?? zero
        self.receivedTotal = receivedTotal ?? zero
        self.nextCharge = nextCharge
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let currency = try c.decode(String.self, forKey: .currency)
        self.currency = currency
        asOf = try c.decode(String.self, forKey: .asOf)
        chargedToDate = try c.decodeMoney(.chargedToDate, currency: currency)
        waivedToDate = try c.decodeMoney(.waivedToDate, currency: currency)
        paidToDate = try c.decodeMoney(.paidToDate, currency: currency)
        outstanding = try c.decodeMoney(.outstanding, currency: currency)
        overdue = try c.decodeMoney(.overdue, currency: currency)
        overdueCharges = try c.decode(Int.self, forKey: .overdueCharges)
        upcoming = try c.decodeMoney(.upcoming, currency: currency)
        prepaid = try c.decodeMoney(.prepaid, currency: currency)
        tenantCredit = try c.decodeMoney(.tenantCredit, currency: currency)
        receivedTotal = try c.decodeMoney(.receivedTotal, currency: currency)
        if c.contains(.nextCharge), try !c.decodeNil(forKey: .nextCharge) {
            nextCharge = try LeaseNextCharge(from: c.superDecoder(forKey: .nextCharge), currency: currency)
        } else {
            nextCharge = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(currency, forKey: .currency)
        try c.encode(asOf, forKey: .asOf)
        try c.encodeMoney(chargedToDate, forKey: .chargedToDate)
        try c.encodeMoney(waivedToDate, forKey: .waivedToDate)
        try c.encodeMoney(paidToDate, forKey: .paidToDate)
        try c.encodeMoney(outstanding, forKey: .outstanding)
        try c.encodeMoney(overdue, forKey: .overdue)
        try c.encode(overdueCharges, forKey: .overdueCharges)
        try c.encodeMoney(upcoming, forKey: .upcoming)
        try c.encodeMoney(prepaid, forKey: .prepaid)
        try c.encodeMoney(tenantCredit, forKey: .tenantCredit)
        try c.encodeMoney(receivedTotal, forKey: .receivedTotal)
        try c.encode(nextCharge, forKey: .nextCharge)
    }
}
