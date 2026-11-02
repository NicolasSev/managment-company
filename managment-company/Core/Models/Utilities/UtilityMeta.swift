import Foundation

// `GET /v1/utility-bills/meta`: the catalogue of statuses, service types, hints and payers with
// ru/kk/en labels. The client keeps no label maps of its own (design decision D14): every label
// shown for a status, a service line, a hint or a payer comes through `UtilityMeta`.

struct UtilityCodeLabel: Codable, Hashable {
    let code: String
    let labels: UtilityLabels
}

struct UtilityServiceType: Codable, Hashable {
    let code: String
    let labels: UtilityLabels
    let defaultUnit: String?

    enum CodingKeys: String, CodingKey {
        case code, labels
        case defaultUnit = "default_unit"
    }
}

struct UtilityStatusInfo: Codable, Hashable {
    let code: String
    let labels: UtilityLabels
    let order: Int
}

struct UtilityLimits: Codable, Hashable {
    let maxFileBytes: Int
    let maxPdfPages: Int
    let mimeTypes: [String]
    let maxItems: Int
    let maxNotesLen: Int
    let periodMin: String
    let reminderDayMin: Int
    let reminderDayMax: Int

    enum CodingKeys: String, CodingKey {
        case mimeTypes = "mime_types"
        case maxFileBytes = "max_file_bytes"
        case maxPdfPages = "max_pdf_pages"
        case maxItems = "max_items"
        case maxNotesLen = "max_notes_len"
        case periodMin = "period_min"
        case reminderDayMin = "reminder_day_min"
        case reminderDayMax = "reminder_day_max"
    }
}

struct UtilityMeta: Codable, Hashable {
    let serviceTypes: [UtilityServiceType]
    let statuses: [UtilityStatusInfo]
    let reviewReasons: [UtilityCodeLabel]
    let documentKinds: [String]
    let fileRoles: [String]
    let payers: [UtilityCodeLabel]
    let currencies: [String]
    let limits: UtilityLimits

    enum CodingKeys: String, CodingKey {
        case statuses, payers, currencies, limits
        case serviceTypes = "service_types"
        case reviewReasons = "review_reasons"
        case documentKinds = "document_kinds"
        case fileRoles = "file_roles"
    }
}

/// Reads labels out of the meta (Russian: the app is Russian-language). A code the catalogue
/// does not know comes back unchanged for a status, a service type and a payer; hints have a
/// short generic text instead, because a raw code is no help to the reviewer.
struct UtilityLabelBook: Equatable {
    let meta: UtilityMeta?

    init(_ meta: UtilityMeta?) {
        self.meta = meta
    }

    func statusLabel(_ status: UtilityBillStatus) -> String {
        meta?.statuses.first(where: { $0.code == status.rawValue })?.labels.ru ?? status.rawValue
    }

    func serviceLabel(_ code: String) -> String {
        meta?.serviceTypes.first(where: { $0.code == code })?.labels.ru ?? code
    }

    func defaultUnit(_ code: String) -> String? {
        meta?.serviceTypes.first(where: { $0.code == code })?.defaultUnit
    }

    func payerLabel(_ payer: UtilityPayer) -> String {
        meta?.payers.first(where: { $0.code == payer.rawValue })?.labels.ru ?? payer.rawValue
    }

    var serviceCodes: [String] { meta?.serviceTypes.map(\.code) ?? [] }
    var currencies: [String] { meta?.currencies ?? ["KZT", "RUB", "USD", "EUR"] }

    /// Codes the meta of U5 does not list yet. The server adds them in the apply step
    /// (`period_mismatch`, U4) or in the parser (`not_utility_document`, U3); the catalogue
    /// answers without them, so the only local texts of the screen are these two.
    private static let uncatalogued: [String: String] = [
        "period_mismatch": "Период в документе отличается от выбранного",
        "not_utility_document": "Файл не похож на коммунальную квитанцию",
    ]

    /// Names of the fields behind `low_confidence:<field>` and `missing:<field>`.
    private static let fieldNames: [String: String] = [
        "provider": "поставщик",
        "account_number": "лицевой счёт",
        "period": "период",
        "total_due": "сумма к оплате",
        "total_paid": "сумма оплаты",
        "payment_date": "дата оплаты",
        "issued_at": "дата квитанции",
        "currency": "валюта",
        "items": "строки",
    ]

    /// Text of one `review_reasons` entry. `low_confidence:provider` reads as the label of
    /// `low_confidence` plus the field.
    func reasonText(_ code: String) -> String {
        if let label = catalogue(code) { return label }
        if let colon = code.firstIndex(of: ":") {
            let base = String(code[..<colon])
            let field = String(code[code.index(after: colon)...])
            if let label = catalogue(base) {
                if let name = Self.fieldNames[field] { return "\(label): \(name)" }
                return label
            }
        }
        return Self.uncatalogued[code] ?? "Проверьте данные документа"
    }

    private func catalogue(_ code: String) -> String? {
        if let label = meta?.reviewReasons.first(where: { $0.code == code })?.labels.ru { return label }
        return Self.uncatalogued[code]
    }

    /// Texts of all hints, in order and without repeats.
    func reasonTexts(_ codes: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for code in codes {
            let text = reasonText(code)
            if seen.insert(text).inserted { out.append(text) }
        }
        return out
    }
}
