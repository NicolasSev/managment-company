import Foundation

// Utility bills v2 (docs/architecture/utilities-v2.md, ai/context/utility-bills-api.md). The enums keep
// the wire spelling and never fail to decode: a value the app does not know yet becomes `.unknown`.
// Display labels are not here on purpose: statuses, service types, hint codes and payers come from
// `GET /v1/utility-bills/meta` (`UtilityMeta`).

/// `status` of a bill (state machine of §2).
enum UtilityBillStatus: FallbackStringEnum {
    case expected
    case missing
    case uploaded
    case needsReview
    case confirmed
    case paid
    case unknown(String)

    static var knownMapping: [(UtilityBillStatus, String)] {
        [
            (.expected, "expected"), (.missing, "missing"), (.uploaded, "uploaded"),
            (.needsReview, "needs_review"), (.confirmed, "confirmed"), (.paid, "paid"),
        ]
    }

    var rawValue: String {
        switch self {
        case .expected: return "expected"
        case .missing: return "missing"
        case .uploaded: return "uploaded"
        case .needsReview: return "needs_review"
        case .confirmed: return "confirmed"
        case .paid: return "paid"
        case .unknown(let raw): return raw
        }
    }

    static func makeUnknown(_ raw: String) -> UtilityBillStatus { .unknown(raw) }

    var unknownRaw: String? {
        if case .unknown(let raw) = self { return raw }
        return nil
    }

    /// The bill is still being read by the pipeline: nothing to edit yet.
    var isProcessing: Bool { self == .uploaded }
}

/// One entry of `available_actions`: the list of buttons the server offers for the bill.
enum UtilityBillAction: FallbackStringEnum {
    case edit
    case confirm
    case markPaid
    case unmarkPaid
    case reextract
    case tenantMessage
    case delete
    case unknown(String)

    static var knownMapping: [(UtilityBillAction, String)] {
        [
            (.edit, "edit"), (.confirm, "confirm"), (.markPaid, "mark_paid"), (.unmarkPaid, "unmark_paid"),
            (.reextract, "reextract"), (.tenantMessage, "tenant_message"), (.delete, "delete"),
        ]
    }

    var rawValue: String {
        switch self {
        case .edit: return "edit"
        case .confirm: return "confirm"
        case .markPaid: return "mark_paid"
        case .unmarkPaid: return "unmark_paid"
        case .reextract: return "reextract"
        case .tenantMessage: return "tenant_message"
        case .delete: return "delete"
        case .unknown(let raw): return raw
        }
    }

    static func makeUnknown(_ raw: String) -> UtilityBillAction { .unknown(raw) }

    var unknownRaw: String? {
        if case .unknown(let raw) = self { return raw }
        return nil
    }
}

/// `utility_payer` of a property.
enum UtilityPayer: FallbackStringEnum {
    case tenant
    case owner
    case unknown(String)

    static var knownMapping: [(UtilityPayer, String)] { [(.tenant, "tenant"), (.owner, "owner")] }

    var rawValue: String {
        switch self {
        case .tenant: return "tenant"
        case .owner: return "owner"
        case .unknown(let raw): return raw
        }
    }

    static func makeUnknown(_ raw: String) -> UtilityPayer { .unknown(raw) }

    var unknownRaw: String? {
        if case .unknown(let raw) = self { return raw }
        return nil
    }
}

/// `role` of a file on a bill, and the `role` field of an upload.
enum UtilityFileRole: FallbackStringEnum {
    case invoice
    case paymentProof
    case unknown(String)

    static var knownMapping: [(UtilityFileRole, String)] { [(.invoice, "invoice"), (.paymentProof, "payment_proof")] }

    var rawValue: String {
        switch self {
        case .invoice: return "invoice"
        case .paymentProof: return "payment_proof"
        case .unknown(let raw): return raw
        }
    }

    static func makeUnknown(_ raw: String) -> UtilityFileRole { .unknown(raw) }

    var unknownRaw: String? {
        if case .unknown(let raw) = self { return raw }
        return nil
    }
}

/// `status` of an upload (extraction).
enum UtilityUploadStatus: FallbackStringEnum {
    case queued
    case running
    case succeeded
    case failed
    case unknown(String)

    static var knownMapping: [(UtilityUploadStatus, String)] {
        [(.queued, "queued"), (.running, "running"), (.succeeded, "succeeded"), (.failed, "failed")]
    }

    var rawValue: String {
        switch self {
        case .queued: return "queued"
        case .running: return "running"
        case .succeeded: return "succeeded"
        case .failed: return "failed"
        case .unknown(let raw): return raw
        }
    }

    static func makeUnknown(_ raw: String) -> UtilityUploadStatus { .unknown(raw) }

    var unknownRaw: String? {
        if case .unknown(let raw) = self { return raw }
        return nil
    }

    /// Still waiting for the worker: poll again.
    var isPending: Bool { self == .queued || self == .running }
}

/// `document_kind` of an upload result.
enum UtilityUploadDocumentKind: FallbackStringEnum {
    case utilityBill
    case paymentProof
    case other
    case unknown(String)

    static var knownMapping: [(UtilityUploadDocumentKind, String)] {
        [(.utilityBill, "utility_bill"), (.paymentProof, "payment_proof"), (.other, "other")]
    }

    var rawValue: String {
        switch self {
        case .utilityBill: return "utility_bill"
        case .paymentProof: return "payment_proof"
        case .other: return "other"
        case .unknown(let raw): return raw
        }
    }

    static func makeUnknown(_ raw: String) -> UtilityUploadDocumentKind { .unknown(raw) }

    var unknownRaw: String? {
        if case .unknown(let raw) = self { return raw }
        return nil
    }
}

/// `kind` of a review inbox entry.
enum UtilityInboxKind: FallbackStringEnum {
    case bill
    case upload
    case unknown(String)

    static var knownMapping: [(UtilityInboxKind, String)] { [(.bill, "bill"), (.upload, "upload")] }

    var rawValue: String {
        switch self {
        case .bill: return "bill"
        case .upload: return "upload"
        case .unknown(let raw): return raw
        }
    }

    static func makeUnknown(_ raw: String) -> UtilityInboxKind { .unknown(raw) }

    var unknownRaw: String? {
        if case .unknown(let raw) = self { return raw }
        return nil
    }
}

/// Action of an `other` upload.
enum UtilityUploadAction: FallbackStringEnum {
    case attachToRent
    case reject
    case unknown(String)

    static var knownMapping: [(UtilityUploadAction, String)] { [(.attachToRent, "attach_to_rent"), (.reject, "reject")] }

    var rawValue: String {
        switch self {
        case .attachToRent: return "attach_to_rent"
        case .reject: return "reject"
        case .unknown(let raw): return raw
        }
    }

    static func makeUnknown(_ raw: String) -> UtilityUploadAction { .unknown(raw) }

    var unknownRaw: String? {
        if case .unknown(let raw) = self { return raw }
        return nil
    }
}

/// `{ru, kk, en}` labels of the meta catalogue.
struct UtilityLabels: Codable, Hashable {
    let ru: String
    let kk: String
    let en: String
}
