import Foundation

// Identity-document recognition (task T4, briefs/_recognition-contract.md):
// `POST /v1/recognition/identity-document` answers `{"data": IdentityRecognitionResult}`.
//
// Everything the server may leave out is optional, so a field added or dropped on the API side
// never breaks decoding. Dates stay `YYYY-MM-DD` strings (the form of every other lease-v2 wire
// date); `Date` accessors go through `LeaseDay`. Nothing here is a decision: the result is a
// proposal that the owner reviews (`status` is always `needs_review`).

/// `document_kind`: what the photo shows. An unknown spelling is `.other`.
enum IdentityDocumentKind: String, Codable, Hashable {
    case idCard = "id_card"
    case passport
    case other

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = IdentityDocumentKind(rawValue: raw) ?? .other
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// `document_type` of the tenant record that matches this kind.
    var tenantDocumentType: String { rawValue }
}

/// `fields`: always present on the wire, `null` for what was not recognised.
struct IdentityRecognitionFields: Codable, Hashable {
    var lastName: String?
    var firstName: String?
    var middleName: String?
    var iin: String?
    var documentType: String?
    var documentNumber: String?
    var documentIssuedBy: String?
    var documentIssuedAt: String?
    var expiresAt: String?
    var birthDate: String?
    var sex: String?
    var nationality: String?
    var registrationAddress: String?

    init(
        lastName: String? = nil,
        firstName: String? = nil,
        middleName: String? = nil,
        iin: String? = nil,
        documentType: String? = nil,
        documentNumber: String? = nil,
        documentIssuedBy: String? = nil,
        documentIssuedAt: String? = nil,
        expiresAt: String? = nil,
        birthDate: String? = nil,
        sex: String? = nil,
        nationality: String? = nil,
        registrationAddress: String? = nil
    ) {
        self.lastName = lastName
        self.firstName = firstName
        self.middleName = middleName
        self.iin = iin
        self.documentType = documentType
        self.documentNumber = documentNumber
        self.documentIssuedBy = documentIssuedBy
        self.documentIssuedAt = documentIssuedAt
        self.expiresAt = expiresAt
        self.birthDate = birthDate
        self.sex = sex
        self.nationality = nationality
        self.registrationAddress = registrationAddress
    }

    enum CodingKeys: String, CodingKey {
        case iin, sex, nationality
        case lastName = "last_name"
        case firstName = "first_name"
        case middleName = "middle_name"
        case documentType = "document_type"
        case documentNumber = "document_number"
        case documentIssuedBy = "document_issued_by"
        case documentIssuedAt = "document_issued_at"
        case expiresAt = "expires_at"
        case birthDate = "birth_date"
        case registrationAddress = "registration_address"
    }

    /// Picker `Date` of a wire day (local midnight), nil when absent or not a date.
    static func date(_ day: String?) -> Date? {
        guard let day, !day.isEmpty else { return nil }
        return LeaseDay.pickerDate(day)
    }

    var documentIssuedAtDate: Date? { Self.date(documentIssuedAt) }
    var expiresAtDate: Date? { Self.date(expiresAt) }
    var birthDateValue: Date? { Self.date(birthDate) }
}

/// Body of `data` of the 200 answer.
struct IdentityRecognitionResult: Codable, Hashable {
    var extractionId: String?
    /// The saved photo; goes to settle as `identity_document_file_id`.
    var fileId: String?
    var status: String?
    var documentKind: IdentityDocumentKind
    var fields: IdentityRecognitionFields
    /// 0...1 per field name (`last_name`, `iin`, ...); a field may be missing from the map.
    var fieldConfidence: [String: Double]
    var overallConfidence: Double?
    /// Codes such as `missing:registration_address`; localised by `RecognitionReviewReason`.
    var reviewReasons: [String]
    var provider: String?
    var model: String?
    var durationMs: Int?

    init(
        extractionId: String? = nil,
        fileId: String? = nil,
        status: String? = "needs_review",
        documentKind: IdentityDocumentKind = .other,
        fields: IdentityRecognitionFields = IdentityRecognitionFields(),
        fieldConfidence: [String: Double] = [:],
        overallConfidence: Double? = nil,
        reviewReasons: [String] = [],
        provider: String? = nil,
        model: String? = nil,
        durationMs: Int? = nil
    ) {
        self.extractionId = extractionId
        self.fileId = fileId
        self.status = status
        self.documentKind = documentKind
        self.fields = fields
        self.fieldConfidence = fieldConfidence
        self.overallConfidence = overallConfidence
        self.reviewReasons = reviewReasons
        self.provider = provider
        self.model = model
        self.durationMs = durationMs
    }

    enum CodingKeys: String, CodingKey {
        case status, fields, provider, model
        case extractionId = "extraction_id"
        case fileId = "file_id"
        case documentKind = "document_kind"
        case fieldConfidence = "field_confidence"
        case overallConfidence = "overall_confidence"
        case reviewReasons = "review_reasons"
        case durationMs = "duration_ms"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        extractionId = try c.decodeIfPresent(String.self, forKey: .extractionId)
        fileId = try c.decodeIfPresent(String.self, forKey: .fileId)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        documentKind = try c.decodeIfPresent(IdentityDocumentKind.self, forKey: .documentKind) ?? .other
        fields = try c.decodeIfPresent(IdentityRecognitionFields.self, forKey: .fields) ?? IdentityRecognitionFields()
        fieldConfidence = try c.decodeIfPresent([String: Double].self, forKey: .fieldConfidence) ?? [:]
        overallConfidence = try c.decodeIfPresent(Double.self, forKey: .overallConfidence)
        reviewReasons = try c.decodeIfPresent([String].self, forKey: .reviewReasons) ?? []
        provider = try c.decodeIfPresent(String.self, forKey: .provider)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        durationMs = try c.decodeIfPresent(Int.self, forKey: .durationMs)
    }

    /// `other` is not an identity document: the fields are empty and the file is not used.
    var isIdentityDocument: Bool {
        documentKind != .other && !reviewReasons.contains("not_identity_document")
    }
}
