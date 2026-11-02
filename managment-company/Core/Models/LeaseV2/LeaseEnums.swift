import Foundation

/// String enum that never fails to decode: a value the app does not know yet becomes
/// `.unknown(raw)` and keeps its wire spelling. Server-side additions (a new status, a new
/// action) therefore degrade to "hidden/neutral" in the UI instead of failing the whole screen.
///
/// Conforming enums write `rawValue` as an explicit `switch` (do not derive it from
/// `knownMapping` with `==`: the stdlib `RawRepresentable` `==` calls `rawValue` and would recurse).
protocol FallbackStringEnum: RawRepresentable, Codable, Hashable where RawValue == String {
    /// Known cases with their wire spelling.
    static var knownMapping: [(Self, String)] { get }
    static func makeUnknown(_ raw: String) -> Self
    /// Wire value when this is the `.unknown` case, else `nil`.
    var unknownRaw: String? { get }
}

extension FallbackStringEnum {
    /// Never fails: unknown spellings map to `.unknown(raw)`.
    static func fromWire(_ raw: String) -> Self {
        knownMapping.first(where: { $0.1 == raw })?.0 ?? makeUnknown(raw)
    }

    init?(rawValue: String) {
        self = Self.fromWire(rawValue)
    }

    var isKnown: Bool { unknownRaw == nil }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Self.fromWire(try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Lease status (spec §2.1)

enum LeaseStatus: FallbackStringEnum {
    case draft
    case pendingSignature
    case active
    case ended
    case terminated
    case cancelled
    case unknown(String)

    static var knownMapping: [(LeaseStatus, String)] {
        [
            (.draft, "draft"),
            (.pendingSignature, "pending_signature"),
            (.active, "active"),
            (.ended, "ended"),
            (.terminated, "terminated"),
            (.cancelled, "cancelled"),
        ]
    }

    var rawValue: String {
        switch self {
        case .draft: return "draft"
        case .pendingSignature: return "pending_signature"
        case .active: return "active"
        case .ended: return "ended"
        case .terminated: return "terminated"
        case .cancelled: return "cancelled"
        case .unknown(let raw): return raw
        }
    }

    static func makeUnknown(_ raw: String) -> LeaseStatus { .unknown(raw) }

    var unknownRaw: String? {
        if case .unknown(let raw) = self { return raw }
        return nil
    }

    /// Russian label for badges.
    var title: String {
        switch self {
        case .draft: return "Черновик"
        case .pendingSignature: return "Ожидает подписи"
        case .active: return "Действует"
        case .ended: return "Завершён"
        case .terminated: return "Расторгнут"
        case .cancelled: return "Отменён"
        case .unknown(let raw): return raw.isEmpty ? "Неизвестно" : raw
        }
    }

    /// Money commands (payments, deposit) are allowed (spec §2.1 last rows).
    var allowsMoneyCommands: Bool {
        switch self {
        case .active, .ended, .terminated: return true
        default: return false
        }
    }
}

// MARK: - Available actions (spec §2.2)

enum LeaseAction: FallbackStringEnum {
    case update
    case sendForSignature
    case markSigned
    case activate
    case cancel
    case delete
    case generateContract
    case uploadSignedScan
    case amendRent
    case addExtraCharge
    case recordPayment
    case terminate
    case prolong
    case replaceWithNew
    case returnDeposit
    case forfeitDeposit
    case refundCredit
    case reopen
    case unknown(String)

    static var knownMapping: [(LeaseAction, String)] {
        [
            (.update, "update"),
            (.sendForSignature, "send_for_signature"),
            (.markSigned, "mark_signed"),
            (.activate, "activate"),
            (.cancel, "cancel"),
            (.delete, "delete"),
            (.generateContract, "generate_contract"),
            (.uploadSignedScan, "upload_signed_scan"),
            (.amendRent, "amend_rent"),
            (.addExtraCharge, "add_extra_charge"),
            (.recordPayment, "record_payment"),
            (.terminate, "terminate"),
            (.prolong, "prolong"),
            (.replaceWithNew, "replace_with_new"),
            (.returnDeposit, "return_deposit"),
            (.forfeitDeposit, "forfeit_deposit"),
            (.refundCredit, "refund_credit"),
            (.reopen, "reopen"),
        ]
    }

    var rawValue: String {
        switch self {
        case .update: return "update"
        case .sendForSignature: return "send_for_signature"
        case .markSigned: return "mark_signed"
        case .activate: return "activate"
        case .cancel: return "cancel"
        case .delete: return "delete"
        case .generateContract: return "generate_contract"
        case .uploadSignedScan: return "upload_signed_scan"
        case .amendRent: return "amend_rent"
        case .addExtraCharge: return "add_extra_charge"
        case .recordPayment: return "record_payment"
        case .terminate: return "terminate"
        case .prolong: return "prolong"
        case .replaceWithNew: return "replace_with_new"
        case .returnDeposit: return "return_deposit"
        case .forfeitDeposit: return "forfeit_deposit"
        case .refundCredit: return "refund_credit"
        case .reopen: return "reopen"
        case .unknown(let raw): return raw
        }
    }

    static func makeUnknown(_ raw: String) -> LeaseAction { .unknown(raw) }

    var unknownRaw: String? {
        if case .unknown(let raw) = self { return raw }
        return nil
    }
}

// MARK: - Charges (spec §1.3, §6)

enum ChargeKind: FallbackStringEnum {
    case rent
    case deposit
    case extra
    case unknown(String)

    static var knownMapping: [(ChargeKind, String)] {
        [(.rent, "rent"), (.deposit, "deposit"), (.extra, "extra")]
    }

    var rawValue: String {
        switch self {
        case .rent: return "rent"
        case .deposit: return "deposit"
        case .extra: return "extra"
        case .unknown(let raw): return raw
        }
    }

    static func makeUnknown(_ raw: String) -> ChargeKind { .unknown(raw) }

    var unknownRaw: String? {
        if case .unknown(let raw) = self { return raw }
        return nil
    }

    var title: String {
        switch self {
        case .rent: return "Аренда"
        case .deposit: return "Депозит"
        case .extra: return "Доп. начисление"
        case .unknown(let raw): return raw
        }
    }

    /// FIFO tie-break order inside one due date: deposit < rent < extra (spec §4.2).
    var rank: Int {
        switch self {
        case .deposit: return 0
        case .rent: return 1
        case .extra: return 2
        case .unknown: return 3
        }
    }
}

enum ChargeState: FallbackStringEnum {
    case open
    case void
    case waived
    case unknown(String)

    static var knownMapping: [(ChargeState, String)] {
        [(.open, "open"), (.void, "void"), (.waived, "waived")]
    }

    var rawValue: String {
        switch self {
        case .open: return "open"
        case .void: return "void"
        case .waived: return "waived"
        case .unknown(let raw): return raw
        }
    }

    static func makeUnknown(_ raw: String) -> ChargeState { .unknown(raw) }

    var unknownRaw: String? {
        if case .unknown(let raw) = self { return raw }
        return nil
    }
}

enum ChargePaymentStatus: FallbackStringEnum {
    case unpaid
    case partial
    case paid
    case waived
    case void
    case unknown(String)

    static var knownMapping: [(ChargePaymentStatus, String)] {
        [(.unpaid, "unpaid"), (.partial, "partial"), (.paid, "paid"), (.waived, "waived"), (.void, "void")]
    }

    var rawValue: String {
        switch self {
        case .unpaid: return "unpaid"
        case .partial: return "partial"
        case .paid: return "paid"
        case .waived: return "waived"
        case .void: return "void"
        case .unknown(let raw): return raw
        }
    }

    static func makeUnknown(_ raw: String) -> ChargePaymentStatus { .unknown(raw) }

    var unknownRaw: String? {
        if case .unknown(let raw) = self { return raw }
        return nil
    }

    var title: String {
        switch self {
        case .unpaid: return "Не оплачено"
        case .partial: return "Частично"
        case .paid: return "Оплачено"
        case .waived: return "Прощено"
        case .void: return "Аннулировано"
        case .unknown(let raw): return raw
        }
    }
}

// MARK: - Payments (spec §1.4)

enum PaymentDirection: FallbackStringEnum {
    case incoming
    case outgoing
    case unknown(String)

    static var knownMapping: [(PaymentDirection, String)] {
        [(.incoming, "in"), (.outgoing, "out")]
    }

    var rawValue: String {
        switch self {
        case .incoming: return "in"
        case .outgoing: return "out"
        case .unknown(let raw): return raw
        }
    }

    static func makeUnknown(_ raw: String) -> PaymentDirection { .unknown(raw) }

    var unknownRaw: String? {
        if case .unknown(let raw) = self { return raw }
        return nil
    }
}

// MARK: - Deposit (spec §5)

enum DepositStatus: FallbackStringEnum {
    /// A lease without a deposit (contract value `none`).
    case noDeposit
    case expected
    case held
    case partiallyReturned
    case returned
    case forfeited
    case unknown(String)

    static var knownMapping: [(DepositStatus, String)] {
        [
            (.noDeposit, "none"),
            (.expected, "expected"),
            (.held, "held"),
            (.partiallyReturned, "partially_returned"),
            (.returned, "returned"),
            (.forfeited, "forfeited"),
        ]
    }

    var rawValue: String {
        switch self {
        case .noDeposit: return "none"
        case .expected: return "expected"
        case .held: return "held"
        case .partiallyReturned: return "partially_returned"
        case .returned: return "returned"
        case .forfeited: return "forfeited"
        case .unknown(let raw): return raw
        }
    }

    static func makeUnknown(_ raw: String) -> DepositStatus { .unknown(raw) }

    var unknownRaw: String? {
        if case .unknown(let raw) = self { return raw }
        return nil
    }

    var title: String {
        switch self {
        case .noDeposit: return "Депозита нет"
        case .expected: return "Ожидается"
        case .held: return "Удерживается"
        case .partiallyReturned: return "Возвращён частично"
        case .returned: return "Возвращён"
        case .forfeited: return "Удержан владельцем"
        case .unknown(let raw): return raw
        }
    }
}

enum DepositEntryType: FallbackStringEnum {
    case received
    case returned
    case forfeited
    case appliedToDebt
    case unknown(String)

    static var knownMapping: [(DepositEntryType, String)] {
        [
            (.received, "received"),
            (.returned, "returned"),
            (.forfeited, "forfeited"),
            (.appliedToDebt, "applied_to_debt"),
        ]
    }

    var rawValue: String {
        switch self {
        case .received: return "received"
        case .returned: return "returned"
        case .forfeited: return "forfeited"
        case .appliedToDebt: return "applied_to_debt"
        case .unknown(let raw): return raw
        }
    }

    static func makeUnknown(_ raw: String) -> DepositEntryType { .unknown(raw) }

    var unknownRaw: String? {
        if case .unknown(let raw) = self { return raw }
        return nil
    }

    var title: String {
        switch self {
        case .received: return "Получен"
        case .returned: return "Возвращён"
        case .forfeited: return "Удержан"
        case .appliedToDebt: return "Зачтён в долг"
        case .unknown(let raw): return raw
        }
    }
}

// MARK: - Misc

enum UtilitiesPaidBy: FallbackStringEnum {
    case owner
    case tenant
    case split
    case unknown(String)

    static var knownMapping: [(UtilitiesPaidBy, String)] {
        [(.owner, "owner"), (.tenant, "tenant"), (.split, "split")]
    }

    var rawValue: String {
        switch self {
        case .owner: return "owner"
        case .tenant: return "tenant"
        case .split: return "split"
        case .unknown(let raw): return raw
        }
    }

    static func makeUnknown(_ raw: String) -> UtilitiesPaidBy { .unknown(raw) }

    var unknownRaw: String? {
        if case .unknown(let raw) = self { return raw }
        return nil
    }

    var title: String {
        switch self {
        case .owner: return "Владелец"
        case .tenant: return "Арендатор"
        case .split: return "Пополам"
        case .unknown(let raw): return raw
        }
    }
}
