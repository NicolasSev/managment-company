import Foundation

// `GET /v1/utility-bills/:id` and the short forms of the same bill (list, inbox, upload result).
// Money is `Decimal` (a JSON number in major units, at most two decimals); the server computes
// `total`, clients never sum. Field names follow `packages/api-contracts/fixtures/utilities/*.json`.

/// One service line of a bill.
struct UtilityBillItem: Codable, Hashable, Identifiable {
    let id: String
    let position: Int
    let serviceType: String
    let labelRaw: String?
    let amount: Decimal
    let tariff: Decimal?
    let consumption: Decimal?
    let unit: String?
    let readingPrev: Decimal?
    let readingCurr: Decimal?
    let meterNo: String?
    let extractionId: String?

    enum CodingKeys: String, CodingKey {
        case id, position, amount, tariff, consumption, unit
        case serviceType = "service_type"
        case labelRaw = "label_raw"
        case readingPrev = "reading_prev"
        case readingCurr = "reading_curr"
        case meterNo = "meter_no"
        case extractionId = "extraction_id"
    }
}

/// A file attached to a bill: the invoice or the payment proof. `downloadUrl` is a signed path.
struct UtilityBillFile: Codable, Hashable, Identifiable {
    let id: String
    let fileId: String
    let role: UtilityFileRole
    let originalName: String?
    let mimeType: String?
    let sizeBytes: Int?
    let downloadUrl: String?
    let downloadExpiresAt: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, role
        case fileId = "file_id"
        case originalName = "original_name"
        case mimeType = "mime_type"
        case sizeBytes = "size_bytes"
        case downloadUrl = "download_url"
        case downloadExpiresAt = "download_expires_at"
        case createdAt = "created_at"
    }

    var isPDF: Bool {
        if let mimeType { return mimeType.lowercased() == "application/pdf" }
        return originalName?.lowercased().hasSuffix(".pdf") == true
    }
}

/// Summary of the current extraction of a bill.
struct UtilityExtractionSummary: Codable, Hashable {
    let id: String
    let status: UtilityUploadStatus
    let documentKind: String?
    let source: String
    let provider: String?
    let model: String?
    let overallConfidence: Double?
    let fieldConfidence: [String: Double]?
    let reviewStatus: String
    let errorCode: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, status, source, provider, model
        case documentKind = "document_kind"
        case overallConfidence = "overall_confidence"
        case fieldConfidence = "field_confidence"
        case reviewStatus = "review_status"
        case errorCode = "error_code"
        case createdAt = "created_at"
    }
}

/// The full bill (`GET /v1/utility-bills/:id` and every command answer).
struct UtilityBill: Codable, Hashable, Identifiable {
    let id: String
    let propertyId: String?
    let propertyName: String?
    let leaseId: String?
    let utilityAccountId: String?
    let period: String
    let providerName: String?
    let accountNumber: String?
    let documentKind: String?
    let issuedAt: String?
    let totalDue: Decimal?
    let totalPaid: Decimal?
    let balanceCarry: Decimal?
    let total: Decimal?
    let currency: String?
    let amountBase: Decimal?
    let baseCurrency: String?
    let fxRate: Decimal?
    let status: UtilityBillStatus
    let reviewReasons: [String]
    let paidAt: String?
    let paidBy: UtilityPayer?
    let noReceipt: Bool
    let paidOnConfirm: Bool
    let source: String
    let currentExtractionId: String?
    let confirmedAt: String?
    let notes: String?
    let items: [UtilityBillItem]
    let files: [UtilityBillFile]
    let extraction: UtilityExtractionSummary?
    let availableActions: [UtilityBillAction]
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, period, currency, status, source, notes, items, files, extraction, total
        case propertyId = "property_id"
        case propertyName = "property_name"
        case leaseId = "lease_id"
        case utilityAccountId = "utility_account_id"
        case providerName = "provider_name"
        case accountNumber = "account_number"
        case documentKind = "document_kind"
        case issuedAt = "issued_at"
        case totalDue = "total_due"
        case totalPaid = "total_paid"
        case balanceCarry = "balance_carry"
        case amountBase = "amount_base"
        case baseCurrency = "base_currency"
        case fxRate = "fx_rate"
        case reviewReasons = "review_reasons"
        case paidAt = "paid_at"
        case paidBy = "paid_by"
        case noReceipt = "no_receipt"
        case paidOnConfirm = "paid_on_confirm"
        case currentExtractionId = "current_extraction_id"
        case confirmedAt = "confirmed_at"
        case availableActions = "available_actions"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// The file that is shown as the document: the invoice first, else the proof.
    var primaryFile: UtilityBillFile? {
        files.first(where: { $0.role == .invoice }) ?? files.first
    }

    var paymentProofFile: UtilityBillFile? {
        files.first(where: { $0.role == .paymentProof })
    }

    func offers(_ action: UtilityBillAction) -> Bool {
        availableActions.contains(action)
    }
}

/// Short bill (`GET /properties/:id/utility-bills`, the inbox).
struct UtilityBillSummary: Codable, Hashable, Identifiable {
    let id: String
    let propertyId: String?
    let propertyName: String?
    let period: String
    let status: UtilityBillStatus
    let total: Decimal?
    let currency: String?
    let providerName: String?
    let reviewReasons: [String]
    let paidAt: String?
    let noReceipt: Bool
    let hasFile: Bool
    let source: String
    let confidence: Double?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, period, status, total, currency, source, confidence
        case propertyId = "property_id"
        case propertyName = "property_name"
        case providerName = "provider_name"
        case reviewReasons = "review_reasons"
        case paidAt = "paid_at"
        case noReceipt = "no_receipt"
        case hasFile = "has_file"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// The bill an upload landed on (`bill` of the upload answers).
struct UtilityBillBrief: Codable, Hashable, Identifiable {
    let id: String
    let propertyId: String?
    let period: String
    let status: UtilityBillStatus
    let documentKind: String?
    let currency: String?
    let totalDue: Decimal?
    let totalPaid: Decimal?
    let paidAt: String?
    let reviewReasons: [String]

    enum CodingKeys: String, CodingKey {
        case id, period, status, currency
        case propertyId = "property_id"
        case documentKind = "document_kind"
        case totalDue = "total_due"
        case totalPaid = "total_paid"
        case paidAt = "paid_at"
        case reviewReasons = "review_reasons"
    }
}

/// `GET /v1/utility-bills/:id/tenant-message`.
struct UtilityTenantMessage: Codable, Hashable {
    let text: String
    let lang: String
    let period: String
    let propertyId: String
    let utilityPayer: UtilityPayer

    enum CodingKeys: String, CodingKey {
        case text, lang, period
        case propertyId = "property_id"
        case utilityPayer = "utility_payer"
    }
}
