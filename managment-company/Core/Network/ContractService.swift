import Foundation

// Contract printing (task T3c, docs/product/lease-v2-spec.md §9.9): preview and generation of
// the contract of a lease, document templates and the landlord profile. The wire models live in
// `Core/Models/LeaseV2/ContractModels.swift`; this file holds the service seam, the request
// types and the failures the screens react to.

/// A file the preview endpoints return: the bytes and the name the server suggests.
struct ContractFile: Equatable {
    var data: Data
    var filename: String
    var mimeType: String
}

enum ContractFormat: String, Codable, CaseIterable {
    case pdf
    case docx

    var fileExtension: String { rawValue }

    var mimeType: String {
        switch self {
        case .pdf: return "application/pdf"
        case .docx: return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        }
    }
}

/// Optional data of the hand-over act. What is left blank stays a line to fill in by hand.
struct ContractAct: Equatable, Encodable {
    var meterElectricity: String = ""
    var meterWater: String = ""
    var inventory: [String] = []
    var keysCount: Int?

    /// Limits of the API (`internal/service/contract_service.go`).
    static let maxKeys = 50

    var isEmpty: Bool {
        normalized.meterElectricity.isEmpty
            && normalized.meterWater.isEmpty
            && normalized.inventory.isEmpty
            && normalized.keysCount == nil
    }

    /// Trimmed, empty inventory lines dropped, commas removed from the items: the preview
    /// sends the inventory comma separated, and an item must stay one item there.
    var normalized: ContractAct {
        ContractAct(
            meterElectricity: meterElectricity.trimmingCharacters(in: .whitespacesAndNewlines),
            meterWater: meterWater.trimmingCharacters(in: .whitespacesAndNewlines),
            inventory: inventory
                .map { $0.replacingOccurrences(of: ",", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            keysCount: keysCount
        )
    }

    /// Message in Russian when a value would be refused by the API, else nil.
    var validationMessage: String? {
        let act = normalized
        for (label, value) in [("электричества", act.meterElectricity), ("воды", act.meterWater)] {
            if !value.isEmpty, value.count > 16 || value.contains(where: { !"0123456789.,".contains($0) }) {
                return "Показания \(label): только число, например 16968 или 412,5."
            }
        }
        if let keys = act.keysCount, keys < 0 || keys > Self.maxKeys {
            return "Количество ключей: от 0 до \(Self.maxKeys)."
        }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case inventory
        case meterElectricity = "meter_electricity"
        case meterWater = "meter_water"
        case keysCount = "keys_count"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(meterElectricity, forKey: .meterElectricity)
        try c.encode(meterWater, forKey: .meterWater)
        try c.encode(inventory, forKey: .inventory)
        try c.encode(keysCount, forKey: .keysCount)
    }
}

/// What the preview and the generation share: template, printed date and the act.
struct ContractRequest: Equatable {
    var templateId: String?
    /// `YYYY-MM-DD`; nil: the server takes `signed_on`, else `start_date`.
    var contractDate: String?
    var act: ContractAct = ContractAct()
}

/// Body of `POST /v1/leases/:id/contract`.
struct ContractGenerateBody: Encodable {
    var templateId: String?
    var contractDate: String?
    var formats: [ContractFormat]
    var act: ContractAct?

    enum CodingKeys: String, CodingKey {
        case formats, act
        case templateId = "template_id"
        case contractDate = "contract_date"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(templateId, forKey: .templateId)
        try c.encode(contractDate, forKey: .contractDate)
        try c.encode(formats, forKey: .formats)
        try c.encodeIfPresent(act, forKey: .act)
    }
}

/// Body of `PUT /v1/landlord-profile` (replaces the profile).
struct LandlordProfileInput: Encodable, Equatable {
    var fullName = ""
    var fullNameShortGen = ""
    var iin = ""
    var document = ""
    var address = ""
    var phone = ""
    var phone2 = ""
    var bankDetails = ""
    /// nil: derived from the patronymic.
    var gender: LandlordGender?

    init() {}

    init(_ profile: LandlordProfile) {
        fullName = profile.fullName
        fullNameShortGen = profile.fullNameShortGen
        iin = profile.iin
        document = profile.document
        address = profile.address
        phone = profile.phone
        phone2 = profile.phone2
        bankDetails = profile.bankDetails
        gender = profile.gender
    }

    enum CodingKeys: String, CodingKey {
        case iin, document, address, phone, phone2, gender
        case fullName = "full_name"
        case fullNameShortGen = "full_name_short_gen"
        case bankDetails = "bank_details"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fullName, forKey: .fullName)
        try c.encode(fullNameShortGen, forKey: .fullNameShortGen)
        try c.encode(iin, forKey: .iin)
        try c.encode(document, forKey: .document)
        try c.encode(address, forKey: .address)
        try c.encode(phone, forKey: .phone)
        try c.encode(phone2, forKey: .phone2)
        try c.encode(bankDetails, forKey: .bankDetails)
        try c.encode(gender?.rawValue, forKey: .gender)
    }
}

/// Failures of the contract endpoints. `Live` maps the HTTP answer here (error `code`, status).
enum ContractServiceError: Error, Equatable {
    /// `422 CONTRACT_DATA_INCOMPLETE`: every missing value at once.
    case incomplete([ContractMissingField])
    /// `422 TEMPLATE_INVALID`.
    case templateInvalid(reason: String?, unknownPlaceholders: [String], splitPlaceholders: [String])
    /// `501 PDF_CONVERSION_UNAVAILABLE`: no converter on the server, the DOCX still works.
    case pdfUnavailable
    /// `502 PDF_CONVERSION_FAILED`: the converter did not answer; try again or take the DOCX.
    case pdfFailed
    /// `422 INVALID_STATE_TRANSITION`: an ended, terminated or cancelled lease cannot save a contract.
    case invalidState
    case notFound
    /// `412 VERSION_MISMATCH`, `409` and other conflicts.
    case conflict(message: String)
    /// `400/422` field validation. `message` is ready for the UI.
    case validation(message: String)
    case unauthorized
    case transport
    case unknown

    @MainActor
    var userMessage: String {
        switch self {
        case .incomplete: return "В договоре не хватает данных."
        case .templateInvalid(let reason, let unknown, let split):
            var parts = ["Шаблон не подходит."]
            if let reason, !reason.isEmpty { parts.append(reason) }
            if !unknown.isEmpty { parts.append("Неизвестные поля: \(unknown.joined(separator: ", ")).") }
            if !split.isEmpty { parts.append("Поля разбиты на части в Word: \(split.joined(separator: ", ")).") }
            return parts.joined(separator: " ")
        case .pdfUnavailable: return "PDF на сервере не настроен. Доступен DOCX."
        case .pdfFailed: return "Сервер не смог собрать PDF. Повторите или возьмите DOCX."
        case .invalidState: return "Для договора с этим статусом файл сохранить нельзя."
        case .notFound: return "Договор или шаблон не найден."
        case .conflict(let message): return message
        case .validation(let message): return message
        case .unauthorized: return "Сессия истекла. Войдите снова."
        case .transport: return "Нет связи с сервером."
        case .unknown: return "Не удалось выполнить действие."
        }
    }
}

/// Everything the contract screens need from the API (spec §9.9).
protocol ContractService {
    /// `GET /v1/leases/:id/contract/preview`: nothing is saved on the server.
    func preview(leaseId: String, format: ContractFormat, request: ContractRequest) async throws -> ContractFile
    /// `POST /v1/leases/:id/contract`: saves the files to the lease. One `idempotencyKey` per intent.
    func generate(
        leaseId: String,
        request: ContractRequest,
        formats: [ContractFormat],
        idempotencyKey: String
    ) async throws -> ContractGenerateResponse

    func listTemplates() async throws -> [DocumentTemplate]
    func templateFile(id: String, format: ContractFormat) async throws -> ContractFile
    func uploadTemplate(name: String, isDefault: Bool, fileData: Data, fileName: String) async throws -> DocumentTemplate

    func landlordProfile() async throws -> LandlordProfile
    func saveLandlordProfile(_ input: LandlordProfileInput) async throws -> LandlordProfile
}

/// Picks the service the contract screens use: the live one when the lease screens run on the
/// real API (`LeaseV2ServiceProvider.useMocks` is off), else the sample-data mock.
@MainActor
enum ContractServiceProvider {
    static func makeService(authManager: AuthManager) -> ContractService {
        if !LeaseV2ServiceProvider.useMocks {
            return LiveContractService(authManager: authManager)
        }
        return MockContractService.shared
    }
}
