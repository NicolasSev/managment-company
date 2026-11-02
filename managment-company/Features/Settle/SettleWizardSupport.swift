import Foundation

// Pure types of the move-in wizard (task L14): steps, tenant fields and the form, the review
// reasons of the recognition and the context the entry points open the wizard with. No UI and
// no network here, so every rule is unit tested.

// MARK: - Steps

/// Steps of the wizard, as on the web (L11): Объект → Арендатор → Условия → Договор → Готово.
enum SettleStep: Int, CaseIterable, Identifiable {
    case property
    case tenant
    case terms
    case contract
    case done

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .property: return "Объект"
        case .tenant: return "Арендатор"
        case .terms: return "Условия"
        case .contract: return "Договор"
        case .done: return "Готово"
        }
    }

    /// Part of `settle.step.<identifier>`.
    var identifier: String {
        switch self {
        case .property: return "property"
        case .tenant: return "tenant"
        case .terms: return "terms"
        case .contract: return "contract"
        case .done: return "done"
        }
    }

    var next: SettleStep? { SettleStep(rawValue: rawValue + 1) }
    var previous: SettleStep? { SettleStep(rawValue: rawValue - 1) }
}

// MARK: - Tenant fields

/// Fields of the tenant form (T1 identity fields plus contacts). The raw value is the wire name
/// of the API (`tenant.<name>` in the settle body, `fields.<name>` in the recognition).
enum SettleTenantField: String, CaseIterable, Identifiable, Hashable {
    case lastName = "last_name"
    case firstName = "first_name"
    case middleName = "middle_name"
    case iin
    case documentNumber = "document_number"
    case documentIssuedBy = "document_issued_by"
    case documentIssuedAt = "document_issued_at"
    case birthDate = "birth_date"
    case registrationAddress = "registration_address"
    case phone
    case email

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lastName: return "Фамилия"
        case .firstName: return "Имя"
        case .middleName: return "Отчество"
        case .iin: return "ИИН"
        case .documentNumber: return "Номер документа"
        case .documentIssuedBy: return "Кем выдан"
        case .documentIssuedAt: return "Дата выдачи"
        case .birthDate: return "Дата рождения"
        case .registrationAddress: return "Адрес регистрации"
        case .phone: return "Телефон"
        case .email: return "Эл. почта"
        }
    }

    /// The contract needs these (brief `_recognition-contract.md`: the `missing:` fields); phone,
    /// email and the middle name do not.
    var requiredForContract: Bool {
        switch self {
        case .lastName, .firstName, .iin, .documentNumber, .documentIssuedBy,
             .documentIssuedAt, .birthDate, .registrationAddress:
            return true
        case .middleName, .phone, .email:
            return false
        }
    }

    var isDate: Bool { self == .documentIssuedAt || self == .birthDate }

    /// Wire name from an API error (`last_name`, `tenant.iin`) or a review reason.
    init?(wire: String) {
        let name = wire.hasPrefix("tenant.") ? String(wire.dropFirst("tenant.".count)) : wire
        self.init(rawValue: name)
    }

    /// Russian name of any recognition field, also those the form does not have.
    static func title(forWire wire: String) -> String {
        if let field = SettleTenantField(wire: wire) { return field.title }
        switch wire {
        case "expires_at": return "Срок действия"
        case "document_type": return "Тип документа"
        case "sex": return "Пол"
        case "nationality": return "Гражданство"
        default: return wire
        }
    }
}

/// Text state of the tenant step. Dates are `YYYY-MM-DD` or empty.
struct SettleTenantForm: Equatable {
    var lastName = ""
    var firstName = ""
    var middleName = ""
    var iin = ""
    var documentType: TenantDocumentType = .idCard
    var documentNumber = ""
    var documentIssuedBy = ""
    var documentIssuedAt = ""
    var birthDate = ""
    var registrationAddress = ""
    var phone = ""
    var email = ""
    var cohabitants = ""
    var notes = ""

    subscript(field: SettleTenantField) -> String {
        get {
            switch field {
            case .lastName: return lastName
            case .firstName: return firstName
            case .middleName: return middleName
            case .iin: return iin
            case .documentNumber: return documentNumber
            case .documentIssuedBy: return documentIssuedBy
            case .documentIssuedAt: return documentIssuedAt
            case .birthDate: return birthDate
            case .registrationAddress: return registrationAddress
            case .phone: return phone
            case .email: return email
            }
        }
        set {
            switch field {
            case .lastName: lastName = newValue
            case .firstName: firstName = newValue
            case .middleName: middleName = newValue
            case .iin: iin = newValue
            case .documentNumber: documentNumber = newValue
            case .documentIssuedBy: documentIssuedBy = newValue
            case .documentIssuedAt: documentIssuedAt = newValue
            case .birthDate: birthDate = newValue
            case .registrationAddress: registrationAddress = newValue
            case .phone: phone = newValue
            case .email: email = newValue
            }
        }
    }

    var trimmedIIN: String { iin.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The IIN is 12 digits (the checksum is the server's and the recognition's business).
    var hasValidIINFormat: Bool {
        trimmedIIN.count == 12 && trimmedIIN.allSatisfy(\.isASCII) && trimmedIIN.allSatisfy(\.isNumber)
    }

    var fullName: String {
        [lastName, firstName, middleName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// `tenant` of the settle body: trimmed, blank values left out.
    var input: SettleTenantInput {
        SettleTenantInput(
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: Self.optional(lastName),
            middleName: Self.optional(middleName),
            phone: Self.optional(phone),
            email: Self.optional(email),
            iin: Self.optional(iin),
            documentType: documentType.rawValue,
            documentNumber: Self.optional(documentNumber),
            documentIssuedBy: Self.optional(documentIssuedBy),
            documentIssuedAt: Self.optional(documentIssuedAt),
            birthDate: Self.optional(birthDate),
            registrationAddress: Self.optional(registrationAddress),
            cohabitants: Self.optional(cohabitants),
            notes: Self.optional(notes)
        )
    }

    private static func optional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// What the badge under a field says.
enum SettleFieldBadge: Equatable {
    case none
    /// Empty and needed for the contract.
    case missing
    /// Recognised with confidence under 0.7; `percent` is 0...100.
    case lowConfidence(percent: Int)

    var text: String? {
        switch self {
        case .none: return nil
        case .missing: return "Нужно для договора"
        case .lowConfidence(let percent): return "Проверьте, уверенность \(percent)%"
        }
    }
}

// MARK: - Recognition review reasons

/// `review_reasons` codes of the recognition, localised here (the server sends codes only).
enum RecognitionReviewReason: Equatable, Identifiable {
    case notIdentityDocument
    case iinChecksumFailed
    case iinBirthDateMismatch
    case documentExpired
    case lowConfidence(field: String)
    case missing(field: String)
    case unknown(code: String)

    /// Confidence under this is shown as «Проверьте» (contract: `low_confidence:<field>` < 0.7).
    static let lowConfidenceThreshold = 0.7

    init(code: String) {
        switch code {
        case "not_identity_document": self = .notIdentityDocument
        case "iin_checksum_failed": self = .iinChecksumFailed
        case "iin_birth_date_mismatch": self = .iinBirthDateMismatch
        case "document_expired": self = .documentExpired
        default:
            if code.hasPrefix("low_confidence:") {
                self = .lowConfidence(field: String(code.dropFirst("low_confidence:".count)))
            } else if code.hasPrefix("missing:") {
                self = .missing(field: String(code.dropFirst("missing:".count)))
            } else {
                self = .unknown(code: code)
            }
        }
    }

    var id: String {
        switch self {
        case .notIdentityDocument: return "not_identity_document"
        case .iinChecksumFailed: return "iin_checksum_failed"
        case .iinBirthDateMismatch: return "iin_birth_date_mismatch"
        case .documentExpired: return "document_expired"
        case .lowConfidence(let field): return "low_confidence:\(field)"
        case .missing(let field): return "missing:\(field)"
        case .unknown(let code): return code
        }
    }

    var text: String {
        switch self {
        case .notIdentityDocument:
            return "На фото не удостоверение личности. Загрузите другое фото или заполните данные вручную."
        case .iinChecksumFailed:
            return "Контрольная сумма ИИН не сходится. Проверьте цифры."
        case .iinBirthDateMismatch:
            return "Дата рождения не совпадает с ИИН. Проверьте оба поля."
        case .documentExpired:
            return "Срок действия документа истёк."
        case .lowConfidence(let field):
            return "Плохо читается: \(SettleTenantField.title(forWire: field).lowercasedFirst). Проверьте значение."
        case .missing(let field):
            return "Не найдено: \(SettleTenantField.title(forWire: field).lowercasedFirst)."
        case .unknown(let code):
            return "Проверьте данные (\(code))."
        }
    }

    /// The form field this reason points at, if any.
    var field: SettleTenantField? {
        switch self {
        case .lowConfidence(let field), .missing(let field): return SettleTenantField(wire: field)
        case .iinChecksumFailed: return .iin
        case .iinBirthDateMismatch: return .iin
        default: return nil
        }
    }
}

private extension String {
    /// «Адрес регистрации» → «адрес регистрации»; an acronym like «ИИН» stays as it is.
    var lowercasedFirst: String {
        guard let head = first else { return self }
        let rest = dropFirst()
        if let second = rest.first, second.isUppercase { return self }
        return head.lowercased() + rest
    }
}

// MARK: - Entry context

/// How an entry point opens the wizard: what is already known and what stays fixed.
struct SettleWizardContext: Equatable, Identifiable {
    var id = UUID()
    var propertyId: String?
    var tenantId: String?
    /// The lease the new one replaces (spec §3.10): property and tenant are fixed.
    var replacesLeaseId: String?
    /// Terms taken from the replaced lease.
    var startDate: String?
    var rentAmount: Decimal?
    var currency: String?
    var depositAmount: Decimal?
    var dueDay: Int?

    var locksProperty: Bool { replacesLeaseId != nil }
    var locksTenant: Bool { replacesLeaseId != nil }

    /// First step to show: the ones the entry point already answered are skipped (Back returns).
    var initialStep: SettleStep {
        if replacesLeaseId != nil { return .terms }
        if propertyId != nil { return .tenant }
        return .property
    }

    static func property(_ id: String) -> SettleWizardContext {
        SettleWizardContext(propertyId: id)
    }

    static func tenant(_ id: String) -> SettleWizardContext {
        SettleWizardContext(tenantId: id)
    }

    /// «Заменить новым договором»: property and tenant of `lease`, the new lease starts where the
    /// replaced one's period ends (`next_period_start`, else today).
    static func replacing(_ lease: LeaseAggregate) -> SettleWizardContext {
        SettleWizardContext(
            propertyId: lease.propertyId,
            tenantId: lease.tenantId,
            replacesLeaseId: lease.id,
            startDate: lease.nextPeriodStart,
            rentAmount: lease.currentRentAmount.major,
            currency: lease.currency,
            depositAmount: lease.depositAmount?.major,
            dueDay: lease.dueDay
        )
    }
}

// MARK: - Lease terms helpers

enum SettleTerms {
    static let defaultTermMonths = 12
    static let maxTermMonths = 120
    static let defaultRemindDays = 2
    static let defaultRenewalReminderDays = 30
    static let currencies = ["KZT", "USD", "EUR", "RUB"]

    /// `start + months - 1 day`, the server's rule for `term_months` (spec §9.7).
    static func endDate(start: String, months: Int) -> String? {
        guard let startDate = LeaseDay.date(start) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let plus = calendar.date(byAdding: .month, value: months, to: startDate) else { return nil }
        return LeaseDay.addingDays(-1, to: LeaseDay.string(plus))
    }

    /// Day of month of a wire day (`due_day` default).
    static func dayOfMonth(_ day: String) -> Int? {
        let parts = day.prefix(10).split(separator: "-")
        guard parts.count == 3 else { return nil }
        return Int(parts[2])
    }
}
