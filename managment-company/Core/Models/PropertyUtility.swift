import Foundation

struct PropertyUtility: Identifiable, Codable {
    let id: String
    let propertyId: String
    let propertyName: String?
    /// Optional linkage to lease (contract `PropertyUtility.lease_id`).
    let leaseId: String?
    let periodYear: Int
    let periodMonth: Int
    let utilityType: String
    let provider: String?
    let amount: Double
    let currency: String
    let dueDate: String?
    let paidAt: String?
    let status: String
    let notes: String?
    let receiptFileId: String?
    let ocrStatus: String?
    let ocrConfidence: Double?
    let ocrRawText: String?
    let ocrProcessedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, provider, amount, currency, status, notes
        case propertyId = "property_id"
        case propertyName = "property_name"
        case leaseId = "lease_id"
        case periodYear = "period_year"
        case periodMonth = "period_month"
        case utilityType = "utility_type"
        case dueDate = "due_date"
        case paidAt = "paid_at"
        case receiptFileId = "receipt_file_id"
        case ocrStatus = "ocr_status"
        case ocrConfidence = "ocr_confidence"
        case ocrRawText = "ocr_raw_text"
        case ocrProcessedAt = "ocr_processed_at"
    }
}
