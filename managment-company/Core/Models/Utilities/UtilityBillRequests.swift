import Foundation

// Request bodies of the bill commands. Amounts are `Decimal`s built from user input through
// `Money.parse` / `Decimal(string:)`, so a JSON number never carries binary noise (`1092.68`).

/// A line of the items replace-set (`PATCH` and `POST` of a bill).
nonisolated struct UtilityBillItemInput: Codable, Hashable {
    var serviceType: String
    var labelRaw: String?
    var amount: Decimal
    var tariff: Decimal?
    var consumption: Decimal?
    var unit: String?
    var readingPrev: Decimal?
    var readingCurr: Decimal?
    var meterNo: String?

    enum CodingKeys: String, CodingKey {
        case amount, tariff, consumption, unit
        case serviceType = "service_type"
        case labelRaw = "label_raw"
        case readingPrev = "reading_prev"
        case readingCurr = "reading_curr"
        case meterNo = "meter_no"
    }

    /// Carries a recognised line over unchanged, so a replace-set keeps what the owner did not touch.
    init(_ item: UtilityBillItem) {
        serviceType = item.serviceType
        labelRaw = item.labelRaw
        amount = item.amount
        tariff = item.tariff
        consumption = item.consumption
        unit = item.unit
        readingPrev = item.readingPrev
        readingCurr = item.readingCurr
        meterNo = item.meterNo
    }

    init(serviceType: String, labelRaw: String? = nil, amount: Decimal) {
        self.serviceType = serviceType
        self.labelRaw = labelRaw
        self.amount = amount
    }

    // The optional fields are sent as `null` when empty: a replace-set clears what is not given.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(serviceType, forKey: .serviceType)
        try c.encode(amount, forKey: .amount)
        try c.encode(labelRaw, forKey: .labelRaw)
        try c.encode(tariff, forKey: .tariff)
        try c.encode(consumption, forKey: .consumption)
        try c.encode(unit, forKey: .unit)
        try c.encode(readingPrev, forKey: .readingPrev)
        try c.encode(readingCurr, forKey: .readingCurr)
        try c.encode(meterNo, forKey: .meterNo)
    }
}

/// How a field of a `PATCH` is sent: left out (unchanged), a value, or `null` (cleared).
enum UtilityPatchField<Value: Hashable>: Hashable {
    case unchanged
    case set(Value)
    case clear

    var isUnchanged: Bool {
        if case .unchanged = self { return true }
        return false
    }
}

/// `PATCH /v1/utility-bills/:id`. Absent = unchanged, `null` = cleared, `items` replaces the whole set.
struct UtilityBillPatch: Encodable, Equatable {
    var propertyId: UtilityPatchField<String> = .unchanged
    var period: UtilityPatchField<String> = .unchanged
    var providerName: UtilityPatchField<String> = .unchanged
    var accountNumber: UtilityPatchField<String> = .unchanged
    var issuedAt: UtilityPatchField<String> = .unchanged
    var totalDue: UtilityPatchField<Decimal> = .unchanged
    var totalPaid: UtilityPatchField<Decimal> = .unchanged
    var currency: UtilityPatchField<String> = .unchanged
    var notes: UtilityPatchField<String> = .unchanged
    var items: [UtilityBillItemInput]?

    enum CodingKeys: String, CodingKey {
        case period, currency, notes, items
        case propertyId = "property_id"
        case providerName = "provider_name"
        case accountNumber = "account_number"
        case issuedAt = "issued_at"
        case totalDue = "total_due"
        case totalPaid = "total_paid"
    }

    var isEmpty: Bool {
        propertyId.isUnchanged && period.isUnchanged && providerName.isUnchanged && accountNumber.isUnchanged
            && issuedAt.isUnchanged && totalDue.isUnchanged && totalPaid.isUnchanged && currency.isUnchanged
            && notes.isUnchanged && items == nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try Self.put(propertyId, .propertyId, in: &c)
        try Self.put(period, .period, in: &c)
        try Self.put(providerName, .providerName, in: &c)
        try Self.put(accountNumber, .accountNumber, in: &c)
        try Self.put(issuedAt, .issuedAt, in: &c)
        try Self.put(totalDue, .totalDue, in: &c)
        try Self.put(totalPaid, .totalPaid, in: &c)
        try Self.put(currency, .currency, in: &c)
        try Self.put(notes, .notes, in: &c)
        try c.encodeIfPresent(items, forKey: .items)
    }

    private static func put<Value: Hashable & Encodable>(
        _ field: UtilityPatchField<Value>,
        _ key: CodingKeys,
        in container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        switch field {
        case .unchanged: break
        case .set(let value): try container.encode(value, forKey: key)
        case .clear: try container.encodeNil(forKey: key)
        }
    }
}

/// `POST /v1/utility-bills`: a bill entered by hand (`total` alone becomes one `other` line).
struct UtilityBillCreate: Encodable, Equatable {
    var propertyId: String
    var period: String
    var currency: String?
    var providerName: String?
    var accountNumber: String?
    var issuedAt: String?
    var notes: String?
    var total: Decimal?
    var items: [UtilityBillItemInput]?

    enum CodingKeys: String, CodingKey {
        case period, currency, notes, total, items
        case propertyId = "property_id"
        case providerName = "provider_name"
        case accountNumber = "account_number"
        case issuedAt = "issued_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(propertyId, forKey: .propertyId)
        try c.encode(period, forKey: .period)
        try c.encodeIfPresent(currency, forKey: .currency)
        try c.encodeIfPresent(providerName, forKey: .providerName)
        try c.encodeIfPresent(accountNumber, forKey: .accountNumber)
        try c.encodeIfPresent(issuedAt, forKey: .issuedAt)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(total, forKey: .total)
        try c.encodeIfPresent(items, forKey: .items)
    }
}

/// `POST /v1/utility-bills/:id/mark-paid`: with the proof file or «без квитанции» (never both).
struct UtilityMarkPaid: Encodable, Equatable {
    var paidAt: String
    var paymentProofFileId: String?
    var noReceipt: Bool
    var currency: String?

    enum CodingKeys: String, CodingKey {
        case currency
        case paidAt = "paid_at"
        case paymentProofFileId = "payment_proof_file_id"
        case noReceipt = "no_receipt"
    }

    static func proof(fileId: String, paidAt: String) -> UtilityMarkPaid {
        UtilityMarkPaid(paidAt: paidAt, paymentProofFileId: fileId, noReceipt: false, currency: nil)
    }

    static func noReceipt(paidAt: String, currency: String? = nil) -> UtilityMarkPaid {
        UtilityMarkPaid(paidAt: paidAt, paymentProofFileId: nil, noReceipt: true, currency: currency)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(paidAt, forKey: .paidAt)
        try c.encodeIfPresent(paymentProofFileId, forKey: .paymentProofFileId)
        if noReceipt { try c.encode(true, forKey: .noReceipt) }
        try c.encodeIfPresent(currency, forKey: .currency)
    }
}

/// `POST/PATCH /v1/properties/:id/utility-accounts`.
struct UtilityAccountInput: Encodable, Equatable {
    var providerName: String?
    var accountNumber: String

    enum CodingKeys: String, CodingKey {
        case providerName = "provider_name"
        case accountNumber = "account_number"
    }
}

/// `POST/PATCH /v1/properties/:id/utility-expectations`.
struct UtilityExpectationInput: Encodable, Equatable {
    var months: [Int]
    var activeFrom: String
    var activeTo: String?

    enum CodingKeys: String, CodingKey {
        case months
        case activeFrom = "active_from"
        case activeTo = "active_to"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(months, forKey: .months)
        try c.encode(activeFrom, forKey: .activeFrom)
        try c.encode(activeTo, forKey: .activeTo)
    }
}
