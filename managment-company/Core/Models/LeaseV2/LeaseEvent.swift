import Foundation

/// Free-form JSON (`events[].payload` differs per event type).
enum JSONValue: Codable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let value = try? c.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? c.decode(Double.self) {
            self = .number(value)
        } else if let value = try? c.decode(String.self) {
            self = .string(value)
        } else if let value = try? c.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? c.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let value): try c.encode(value)
        case .number(let value): try c.encode(value)
        case .string(let value): try c.encode(value)
        case .array(let value): try c.encode(value)
        case .object(let value): try c.encode(value)
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let dict) = self { return dict[key] }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var doubleValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }
}

/// Event type from the vocabulary of spec §2.3 (`lease.activated`, `payment.recorded`, ...).
/// New server-side types survive as `.unknown`.
enum LeaseEventType: FallbackStringEnum {
    case created
    case termsChanged
    case returnedToDraft
    case sentForSignature
    case contractGenerated
    case signedScanUploaded
    case signed
    case activated
    case amended
    case prolonged
    case endingSoon
    case replaced
    case terminated
    case ended
    case reopened
    case cancelled
    case chargesGenerated
    case chargeAdded
    case chargeVoided
    case chargeWaived
    case chargeUnwaived
    case paymentRecorded
    case paymentReversed
    case allocationsMoved
    case creditApplied
    case creditRefunded
    case depositReceived
    case depositReturned
    case depositForfeited
    case depositAppliedToDebt
    case depositEntryReversed
    case checklistStarted
    case checklistCompleted
    case unknown(String)

    static var knownMapping: [(LeaseEventType, String)] {
        [
            (.created, "lease.created"),
            (.termsChanged, "lease.terms_changed"),
            (.returnedToDraft, "lease.returned_to_draft"),
            (.sentForSignature, "lease.sent_for_signature"),
            (.contractGenerated, "contract.generated"),
            (.signedScanUploaded, "contract.signed_scan_uploaded"),
            (.signed, "lease.signed"),
            (.activated, "lease.activated"),
            (.amended, "lease.amended"),
            (.prolonged, "lease.prolonged"),
            (.endingSoon, "lease.ending_soon"),
            (.replaced, "lease.replaced"),
            (.terminated, "lease.terminated"),
            (.ended, "lease.ended"),
            (.reopened, "lease.reopened"),
            (.cancelled, "lease.cancelled"),
            (.chargesGenerated, "charges.generated"),
            (.chargeAdded, "charge.added"),
            (.chargeVoided, "charge.voided"),
            (.chargeWaived, "charge.waived"),
            (.chargeUnwaived, "charge.unwaived"),
            (.paymentRecorded, "payment.recorded"),
            (.paymentReversed, "payment.reversed"),
            (.allocationsMoved, "payment.allocations_moved"),
            (.creditApplied, "credit.applied"),
            (.creditRefunded, "credit.refunded"),
            (.depositReceived, "deposit.received"),
            (.depositReturned, "deposit.returned"),
            (.depositForfeited, "deposit.forfeited"),
            (.depositAppliedToDebt, "deposit.applied_to_debt"),
            (.depositEntryReversed, "deposit.entry_reversed"),
            (.checklistStarted, "checklist.started"),
            (.checklistCompleted, "checklist.completed"),
        ]
    }

    static func makeUnknown(_ raw: String) -> LeaseEventType { .unknown(raw) }

    var unknownRaw: String? {
        if case .unknown(let raw) = self { return raw }
        return nil
    }

    var rawValue: String {
        switch self {
        case .created: return "lease.created"
        case .termsChanged: return "lease.terms_changed"
        case .returnedToDraft: return "lease.returned_to_draft"
        case .sentForSignature: return "lease.sent_for_signature"
        case .contractGenerated: return "contract.generated"
        case .signedScanUploaded: return "contract.signed_scan_uploaded"
        case .signed: return "lease.signed"
        case .activated: return "lease.activated"
        case .amended: return "lease.amended"
        case .prolonged: return "lease.prolonged"
        case .endingSoon: return "lease.ending_soon"
        case .replaced: return "lease.replaced"
        case .terminated: return "lease.terminated"
        case .ended: return "lease.ended"
        case .reopened: return "lease.reopened"
        case .cancelled: return "lease.cancelled"
        case .chargesGenerated: return "charges.generated"
        case .chargeAdded: return "charge.added"
        case .chargeVoided: return "charge.voided"
        case .chargeWaived: return "charge.waived"
        case .chargeUnwaived: return "charge.unwaived"
        case .paymentRecorded: return "payment.recorded"
        case .paymentReversed: return "payment.reversed"
        case .allocationsMoved: return "payment.allocations_moved"
        case .creditApplied: return "credit.applied"
        case .creditRefunded: return "credit.refunded"
        case .depositReceived: return "deposit.received"
        case .depositReturned: return "deposit.returned"
        case .depositForfeited: return "deposit.forfeited"
        case .depositAppliedToDebt: return "deposit.applied_to_debt"
        case .depositEntryReversed: return "deposit.entry_reversed"
        case .checklistStarted: return "checklist.started"
        case .checklistCompleted: return "checklist.completed"
        case .unknown(let raw): return raw
        }
    }

    /// Russian timeline label.
    var title: String {
        switch self {
        case .created: return "Договор создан"
        case .termsChanged: return "Условия изменены"
        case .returnedToDraft: return "Возврат в черновик"
        case .sentForSignature: return "Отправлен на подпись"
        case .contractGenerated: return "Документ сформирован"
        case .signedScanUploaded: return "Загружен скан подписанного договора"
        case .signed: return "Договор подписан"
        case .activated: return "Договор активирован"
        case .amended: return "Изменение условий"
        case .prolonged: return "Договор продлён"
        case .endingSoon: return "Скоро окончание договора"
        case .replaced: return "Заменён новым договором"
        case .terminated: return "Договор расторгнут"
        case .ended: return "Договор завершён"
        case .reopened: return "Договор возобновлён"
        case .cancelled: return "Договор отменён"
        case .chargesGenerated: return "Начисления созданы"
        case .chargeAdded: return "Добавлено начисление"
        case .chargeVoided: return "Начисление аннулировано"
        case .chargeWaived: return "Начисление прощено"
        case .chargeUnwaived: return "Прощение отменено"
        case .paymentRecorded: return "Платёж принят"
        case .paymentReversed: return "Платёж отменён"
        case .allocationsMoved: return "Платёж перераспределён"
        case .creditApplied: return "Кредит засчитан"
        case .creditRefunded: return "Кредит возвращён"
        case .depositReceived: return "Депозит получен"
        case .depositReturned: return "Депозит возвращён"
        case .depositForfeited: return "Депозит удержан"
        case .depositAppliedToDebt: return "Депозит зачтён в долг"
        case .depositEntryReversed: return "Запись депозита отменена"
        case .checklistStarted: return "Чек-лист начат"
        case .checklistCompleted: return "Чек-лист завершён"
        case .unknown(let raw): return raw
        }
    }
}

struct LeaseEventActor: Codable, Hashable {
    var id: String
    var name: String
}

/// `events[]`: latest 50, newest first.
struct LeaseEvent: Codable, Hashable, Identifiable {
    var id: String
    var at: String
    var type: LeaseEventType
    var actor: LeaseEventActor?
    var payload: JSONValue
}
