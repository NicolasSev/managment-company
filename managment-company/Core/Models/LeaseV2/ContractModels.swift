import Foundation

// Contract generation (task T3a): templates, landlord profile, generate answer and the 422
// CONTRACT_DATA_INCOMPLETE details. Wire shapes of `packages/api-contracts` (`make contracts`);
// `LeaseV2ContractTests` checks them against the generated schemas. Models only: the screens
// that use them come with T3c / L14.

// MARK: - Enums

enum DocumentTemplateKind: FallbackStringEnum {
    case rentContract
    case unknown(String)

    static var knownMapping: [(DocumentTemplateKind, String)] { [(.rentContract, "rent_contract")] }

    var rawValue: String {
        switch self {
        case .rentContract: return "rent_contract"
        case .unknown(let raw): return raw
        }
    }

    static func makeUnknown(_ raw: String) -> DocumentTemplateKind { .unknown(raw) }

    var unknownRaw: String? {
        if case .unknown(let raw) = self { return raw }
        return nil
    }
}

/// `file_type` of a generated contract file.
enum ContractFileType: FallbackStringEnum {
    case pdf
    case docx
    case unknown(String)

    static var knownMapping: [(ContractFileType, String)] {
        [(.pdf, "contract_pdf"), (.docx, "contract_docx")]
    }

    var rawValue: String {
        switch self {
        case .pdf: return "contract_pdf"
        case .docx: return "contract_docx"
        case .unknown(let raw): return raw
        }
    }

    static func makeUnknown(_ raw: String) -> ContractFileType { .unknown(raw) }

    var unknownRaw: String? {
        if case .unknown(let raw) = self { return raw }
        return nil
    }
}

enum LandlordGender: FallbackStringEnum {
    case female
    case male
    case unknown(String)

    static var knownMapping: [(LandlordGender, String)] { [(.female, "female"), (.male, "male")] }

    var rawValue: String {
        switch self {
        case .female: return "female"
        case .male: return "male"
        case .unknown(let raw): return raw
        }
    }

    static func makeUnknown(_ raw: String) -> LandlordGender { .unknown(raw) }

    var unknownRaw: String? {
        if case .unknown(let raw) = self { return raw }
        return nil
    }
}

/// Whose record a missing contract value belongs to.
enum ContractMissingEntity: FallbackStringEnum {
    case landlordProfile
    case property
    case tenant
    case lease
    case unknown(String)

    static var knownMapping: [(ContractMissingEntity, String)] {
        [(.landlordProfile, "landlord_profile"), (.property, "property"), (.tenant, "tenant"), (.lease, "lease")]
    }

    var rawValue: String {
        switch self {
        case .landlordProfile: return "landlord_profile"
        case .property: return "property"
        case .tenant: return "tenant"
        case .lease: return "lease"
        case .unknown(let raw): return raw
        }
    }

    static func makeUnknown(_ raw: String) -> ContractMissingEntity { .unknown(raw) }

    var unknownRaw: String? {
        if case .unknown(let raw) = self { return raw }
        return nil
    }
}

// MARK: - Templates and landlord profile

/// One entry of `GET /v1/document-templates` (contract schema `DocumentTemplate`).
struct DocumentTemplate: Codable, Hashable, Identifiable {
    var id: String
    var kind: DocumentTemplateKind
    var name: String
    var version: Int
    /// The built-in template; it cannot be changed.
    var isSystem: Bool
    /// The one used when a request names no template.
    var isDefault: Bool
    var sizeBytes: Int64?
    var createdAt: String
    var sha256: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, name, version, sha256
        case isSystem = "is_system"
        case isDefault = "is_default"
        case sizeBytes = "size_bytes"
        case createdAt = "created_at"
    }
}

/// `GET|PUT /v1/landlord-profile` (contract schema `LandlordProfile`).
struct LandlordProfile: Codable, Hashable {
    var fullName: String
    var fullNameShortGen: String
    var iin: String
    var document: String
    var address: String
    var phone: String
    var phone2: String
    var bankDetails: String
    /// `nil`: derived from the patronymic.
    var gender: LandlordGender?
    var updatedAt: String?
    /// What the contract still needs from the profile; empty when it is complete.
    var missingFields: [String]

    enum CodingKeys: String, CodingKey {
        case iin, document, address, phone, phone2, gender
        case fullName = "full_name"
        case fullNameShortGen = "full_name_short_gen"
        case bankDetails = "bank_details"
        case updatedAt = "updated_at"
        case missingFields = "missing_fields"
    }
}

// MARK: - Generate answer

/// A saved contract file (contract schema `ContractGeneratedFile`).
struct GeneratedContractFile: Codable, Hashable, Identifiable {
    var id: String
    var fileType: ContractFileType
    var filename: String
    var mimeType: String
    var sizeBytes: Int64
    /// Signed link valid for 15 minutes; absent when the server could not sign one.
    var downloadUrl: String?
    var downloadUrlExpiresAt: String?

    enum CodingKeys: String, CodingKey {
        case id, filename
        case fileType = "file_type"
        case mimeType = "mime_type"
        case sizeBytes = "size_bytes"
        case downloadUrl = "download_url"
        case downloadUrlExpiresAt = "download_url_expires_at"
    }
}

/// `data` of the 201 answer of `POST /v1/leases/{id}/contract`.
struct ContractGenerateResponse: Codable, Hashable {
    var files: [GeneratedContractFile]
    var lease: LeaseAggregate
}

// MARK: - 422 errors

/// A value the contract needs that is not filled in yet.
struct ContractMissingField: Codable, Hashable {
    var entity: ContractMissingEntity
    /// The property, tenant or lease to open; absent for the landlord profile.
    var entityId: String?
    var field: String
    var placeholder: String
    var message: String

    enum CodingKeys: String, CodingKey {
        case entity, field, placeholder, message
        case entityId = "entity_id"
    }
}

/// `error.details` of the 422 errors of the contract endpoints: `fields` for
/// CONTRACT_DATA_INCOMPLETE, `reason` and the placeholder lists for TEMPLATE_INVALID.
struct ContractErrorDetails: Codable, Hashable {
    var fields: [ContractMissingField]?
    var reason: String?
    var unknownPlaceholders: [String]?
    var splitPlaceholders: [String]?

    enum CodingKeys: String, CodingKey {
        case fields, reason
        case unknownPlaceholders = "unknown_placeholders"
        case splitPlaceholders = "split_placeholders"
    }
}

struct ContractError: Codable, Hashable {
    var code: String
    var message: String
    var details: ContractErrorDetails?
}

/// The 422 body of the contract endpoints: `{"error": {code, message, details}}`.
struct ContractErrorEnvelope: Codable, Hashable {
    var error: ContractError
}
