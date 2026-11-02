import Foundation

// `GET /v1/utility-bills/grid` and `GET /v1/utility-bills/review-inbox`.

/// The default account of a property as the grid shows it.
struct UtilityGridAccount: Codable, Hashable {
    let utilityAccountId: String
    let providerName: String?
    let accountNumber: String

    enum CodingKeys: String, CodingKey {
        case utilityAccountId = "utility_account_id"
        case providerName = "provider_name"
        case accountNumber = "account_number"
    }
}

/// One month of a property. `status == nil` means no bill and no expectation for the month.
struct UtilityGridMonth: Codable, Hashable, Identifiable {
    let period: String
    let status: UtilityBillStatus?
    let billId: String?
    let total: Decimal?
    let currency: String?
    let hasPaymentProof: Bool?
    let noReceipt: Bool?
    let confidence: Double?
    let reviewReasons: [String]?
    let remindersSent: Int?
    let nextReminderAt: String?

    var id: String { period }

    enum CodingKeys: String, CodingKey {
        case period, status, total, currency, confidence
        case billId = "bill_id"
        case hasPaymentProof = "has_payment_proof"
        case noReceipt = "no_receipt"
        case reviewReasons = "review_reasons"
        case remindersSent = "reminders_sent"
        case nextReminderAt = "next_reminder_at"
    }

    /// «Оплачено без квитанции» is a chip of its own.
    var isPaidWithoutReceipt: Bool { status == .paid && noReceipt == true }
}

struct UtilityGridProperty: Codable, Hashable, Identifiable {
    let propertyId: String
    let propertyName: String
    let utilityPayer: UtilityPayer
    let account: UtilityGridAccount?
    let months: [UtilityGridMonth]
    let yearTotalBase: Decimal

    var id: String { propertyId }

    enum CodingKeys: String, CodingKey {
        case account, months
        case propertyId = "property_id"
        case propertyName = "property_name"
        case utilityPayer = "utility_payer"
        case yearTotalBase = "year_total_base"
    }
}

/// Badges of the whole portfolio (all years).
struct UtilityCounters: Codable, Hashable {
    let missing: Int
    let needsReview: Int
    let unassigned: Int
    let otherUploads: Int

    enum CodingKeys: String, CodingKey {
        case missing, unassigned
        case needsReview = "needs_review"
        case otherUploads = "other_uploads"
    }

    /// What waits for the owner in the inbox.
    var inboxCount: Int { needsReview + otherUploads }
}

struct UtilityGrid: Codable, Hashable {
    let year: Int
    let baseCurrency: String
    let properties: [UtilityGridProperty]
    let counters: UtilityCounters

    enum CodingKeys: String, CodingKey {
        case year, properties, counters
        case baseCurrency = "base_currency"
    }
}

/// A document the extraction classified as `other`: it never creates a bill.
struct UtilityOtherUpload: Codable, Hashable, Identifiable {
    let extractionId: String
    let fileId: String?
    let downloadUrl: String?
    let downloadExpiresAt: String?
    let currency: String?
    let totalPaid: Decimal?
    let paymentDate: String?
    let actions: [UtilityUploadAction]
    let createdAt: String

    var id: String { extractionId }

    enum CodingKeys: String, CodingKey {
        case currency, actions
        case extractionId = "extraction_id"
        case fileId = "file_id"
        case downloadUrl = "download_url"
        case downloadExpiresAt = "download_expires_at"
        case totalPaid = "total_paid"
        case paymentDate = "payment_date"
        case createdAt = "created_at"
    }
}

/// An entry of the review inbox: a bill that waits for a check or an `other` document.
struct UtilityInboxEntry: Codable, Hashable, Identifiable {
    let id: String
    let kind: UtilityInboxKind
    let at: String
    let bill: UtilityBillSummary?
    let upload: UtilityOtherUpload?
}
