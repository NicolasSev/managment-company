import Foundation

// `POST /v1/utility-bills/uploads`, `GET /v1/utility-bills/uploads/:id`.

/// Answer of the upload: `202 {upload_id, bill?}` or, for a file the owner already has,
/// `200 {bill, duplicate_of}`.
struct UtilityUploadResult: Codable, Hashable {
    let uploadId: String?
    let bill: UtilityBillBrief?
    let duplicateOf: String?

    enum CodingKeys: String, CodingKey {
        case bill
        case uploadId = "upload_id"
        case duplicateOf = "duplicate_of"
    }
}

/// The result of an upload that is not a utility document.
struct UtilityOtherResult: Codable, Hashable {
    let amount: Decimal?
    let currency: String?
    let paymentDate: String?
    let actions: [UtilityUploadAction]

    enum CodingKeys: String, CodingKey {
        case amount, currency, actions
        case paymentDate = "payment_date"
    }
}

struct UtilityUploadState: Codable, Hashable {
    let uploadId: String
    let fileId: String?
    let status: UtilityUploadStatus
    let documentKind: UtilityUploadDocumentKind?
    let bill: UtilityBillBrief?
    let other: UtilityOtherResult?
    let reviewStatus: String
    let reviewReasons: [String]
    let overallConfidence: Double?
    let attempts: Int
    let nextAttemptAt: String?
    let errorCode: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case status, bill, other, attempts
        case uploadId = "upload_id"
        case fileId = "file_id"
        case documentKind = "document_kind"
        case reviewStatus = "review_status"
        case reviewReasons = "review_reasons"
        case overallConfidence = "overall_confidence"
        case nextAttemptAt = "next_attempt_at"
        case errorCode = "error_code"
        case createdAt = "created_at"
    }
}
