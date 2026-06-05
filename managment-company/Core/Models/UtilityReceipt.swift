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
    var paymentDate: String?
    var extractionConfidence: Double?
    var failureReason: String?
    var confirmedAt: String?
    var items: [UtilityReceiptItemPayload]?
    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status, items, currency, provider
        case fileId = "file_id"
        case propertyId = "property_id"
        case accountNumber = "account_number"
        case periodYear = "period_year"
        case periodMonth = "period_month"
        case totalAmount = "total_amount"
        case paymentDate = "payment_date"
        case extractionConfidence = "extraction_confidence"
        case failureReason = "failure_reason"
        case confirmedAt = "confirmed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct UtilityReceiptItemPayload: Codable, Identifiable {
    let id: String
    let utilityType: String
    let amount: Double
    var labelRaw: String?
    var tariff: Double?
    var consumption: Double?
    var unit: String?
    var previousReading: Double?
    var currentReading: Double?
    var materializedUtilityId: String?

    enum CodingKeys: String, CodingKey {
        case id, amount, tariff, consumption, unit
        case utilityType = "utility_type"
        case labelRaw = "label_raw"
        case previousReading = "previous_reading"
        case currentReading = "current_reading"
        case materializedUtilityId = "materialized_utility_id"
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
    var conflictStrategy: String?
    var paymentDate: String?

    enum CodingKeys: String, CodingKey {
        case propertyId = "property_id"
        case edits
        case conflictStrategy = "conflict_strategy"
        case paymentDate = "payment_date"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(propertyId, forKey: .propertyId)
        try c.encodeIfPresent(edits, forKey: .edits)
        try c.encodeIfPresent(conflictStrategy, forKey: .conflictStrategy)
        try c.encodeIfPresent(paymentDate, forKey: .paymentDate)
    }
}
