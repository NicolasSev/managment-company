import Foundation

struct UtilityReceiptPayload: Codable {
    let id: String
    let status: String
    let fileId: String
    var propertyId: String?
    var provider: String?
    var accountNumber: String?
    var periodYear: Int?
    var periodMonth: Int?
    var currency: String?
    var totalAmount: Double?
    var extractionConfidence: Double?
    var failureReason: String?
    var items: [UtilityReceiptItemPayload]?

    enum CodingKeys: String, CodingKey {
        case id, status, items, currency, provider
        case fileId = "file_id"
        case propertyId = "property_id"
        case accountNumber = "account_number"
        case periodYear = "period_year"
        case periodMonth = "period_month"
        case totalAmount = "total_amount"
        case extractionConfidence = "extraction_confidence"
        case failureReason = "failure_reason"
    }
}

struct UtilityReceiptItemPayload: Codable, Identifiable {
    let id: String
    let utilityType: String
    let amount: Double
    var labelRaw: String?

    enum CodingKeys: String, CodingKey {
        case id, amount
        case utilityType = "utility_type"
        case labelRaw = "label_raw"
    }
}

struct ReceiptItemAmountEdit: Encodable {
    let itemId: String
    let amount: Double?

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case amount
    }
}

struct UtilityReceiptConfirmBody: Encodable {
    var propertyId: String?
    var edits: [ReceiptItemAmountEdit]?

    enum CodingKeys: String, CodingKey {
        case propertyId = "property_id"
        case edits
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(propertyId, forKey: .propertyId)
        try c.encodeIfPresent(edits, forKey: .edits)
    }
}
