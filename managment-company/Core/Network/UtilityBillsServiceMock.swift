import Foundation

private final class UtilityFixtureBundleToken {}

/// The contract fixtures of the utility screens (`packages/api-contracts/fixtures/{utilities,notifications}`),
/// bundled into the app as `Core/Resources/UtilityFixtures/` by `make ios-contract-fixtures`; the unit
/// tests find the same files in the test bundle (`Fixtures/`).
enum UtilityFixtures {
    static func data(named name: String, bundle: Bundle? = nil) throws -> Data {
        let bundles = bundle.map { [$0] } ?? [Bundle(for: UtilityFixtureBundleToken.self), Bundle.main] + Bundle.allBundles
        for bundle in bundles {
            for subdirectory in ["UtilityFixtures", "Fixtures", nil] as [String?] {
                if let url = bundle.url(forResource: name, withExtension: "json", subdirectory: subdirectory) {
                    return try Data(contentsOf: url)
                }
            }
        }
        throw UtilityBillsError.notFound
    }

    /// The `data` of an answer as a JSON object (money kept exact, see `exactNumbers`).
    static func object(named name: String) throws -> [String: Any] {
        let root = try JSONSerialization.jsonObject(with: data(named: name)) as? [String: Any]
        guard let object = root?["data"].map(exactNumbers) as? [String: Any] else { throw UtilityBillsError.notFound }
        return object
    }

    /// `JSONSerialization` reads `1092.68` as a binary double and writes it back with seventeen digits
    /// (`1092.6800000000001`). Amounts of the mock state are decimals, so the wire value survives the trip.
    static func exactNumbers(_ value: Any) -> Any {
        if let object = value as? [String: Any] { return object.mapValues(exactNumbers) }
        if let array = value as? [Any] { return array.map(exactNumbers) }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), !(number is NSDecimalNumber) {
            let double = number.doubleValue
            if double != double.rounded() { return NSDecimalNumber(string: "\(double)") }
        }
        return value
    }

    static func decode<T: Decodable>(_ type: T.Type, named name: String) throws -> T {
        try JSONDecoder().decode(APIResponse<T>.self, from: data(named: name)).data
    }
}

/// How a mock upload ends once the owner has waited for it.
enum MockUtilityUploadOutcome: Equatable {
    /// `upload-state-succeeded-bill`: a bill in `needs_review` for the month.
    case bill
    /// `upload-state-succeeded-proof`: the file is a payment proof.
    case proof
    /// `upload-state-other`: a transfer, not a utility bill.
    case other
    /// `upload-state-failed`: the bill is left for manual entry.
    case failed
    /// The worker never finishes: the poll limit has to end the wait.
    case stalled
}

/// `UtilityBillsService` on the fixtures of the contract, with the status machine of §2 imitated in
/// memory: a bill can be uploaded, checked, confirmed, marked paid and unmarked on a phone with no
/// server. The state is kept as the JSON of the wire, so the models decode exactly what the API sends.
final class MockUtilityBillsService: UtilityBillsService {
    static let referenceNow = "2026-11-02"

    var latency: Duration
    /// What the next uploads turn into.
    var uploadOutcome: MockUtilityUploadOutcome = .bill
    /// Polls of `uploadState` that answer `queued`/`running` before the outcome.
    var pollsBeforeResult = 2
    /// Latency of `uploadState` alone (a test makes the poll hang).
    var stateLatency: Duration = .zero
    /// Scripted failure for the next call of any command.
    var failure: UtilityBillsError?

    private(set) var uploads: [(upload: RecognitionUpload, target: UtilityUploadTarget)] = []
    private(set) var stateCalls = 0
    private(set) var confirmCalls = 0
    private(set) var tenantMessageCalls = 0

    private struct MockProperty {
        var id: String
        var name: String
        var payer: UtilityPayer
        var account: UtilityAccount?
        var expectations: [UtilityExpectation]
    }

    private struct PendingUpload {
        var id: String
        var target: UtilityUploadTarget
        var role: UtilityFileRole
        var fileId: String
        var data = Data()
        var polls = 0
        var billId: String?
        var outcome: MockUtilityUploadOutcome
    }

    private var metaValue: UtilityMeta
    private var billsJSON: [String: [String: Any]] = [:]
    private var properties: [MockProperty] = []
    private var otherUploads: [UtilityOtherUpload]
    private var pending: [String: PendingUpload] = [:]
    private var seenFiles: [Data: String] = [:]
    private let comparisonValue: UtilityComparison?
    private let templates: [String: [String: Any]]
    private let messageTemplate: UtilityTenantMessage?
    private let now: String

    init(latency: Duration = .zero, now: String = MockUtilityBillsService.referenceNow) throws {
        self.latency = latency
        self.now = now
        metaValue = try UtilityFixtures.decode(UtilityMeta.self, named: "meta")
        comparisonValue = try? UtilityFixtures.decode(UtilityComparison.self, named: "analytics-comparison")
        messageTemplate = try? UtilityFixtures.decode(UtilityTenantMessage.self, named: "tenant-message")
        let inbox = try JSONDecoder().decode(APIListEnvelope<UtilityInboxEntry>.self, from: UtilityFixtures.data(named: "inbox"))
        otherUploads = inbox.data.compactMap(\.upload)

        var templates: [String: [String: Any]] = [:]
        for name in ["bill-needs-review", "bill-paid", "bill-paid-no-receipt", "bill-missing"] {
            templates[name] = try UtilityFixtures.object(named: name)
        }
        self.templates = templates

        let gridDecoded = try UtilityFixtures.decode(UtilityGrid.self, named: "grid")
        let accounts = try? UtilityFixtures.decode(UtilityAccount.self, named: "accounts-item")
        let expectation = try? UtilityFixtures.decode(UtilityExpectation.self, named: "expectations-item")
        for item in gridDecoded.properties {
            let isFirst = properties.isEmpty
            properties.append(MockProperty(
                id: item.propertyId,
                name: item.propertyName,
                payer: item.utilityPayer,
                account: isFirst ? accounts : nil,
                expectations: isFirst ? (expectation.map { [$0] } ?? []) : []
            ))
        }
        seedBills(from: gridDecoded)
    }

    /// The mock the app runs on; an app without the bundled fixtures gets an empty one.
    static func fromFixtures(latency: Duration = .zero) -> MockUtilityBillsService {
        if let mock = try? MockUtilityBillsService(latency: latency) { return mock }
        return MockUtilityBillsService(empty: latency)
    }

    private init(empty latency: Duration) {
        self.latency = latency
        now = Self.referenceNow
        metaValue = UtilityMeta(
            serviceTypes: [], statuses: [], reviewReasons: [], documentKinds: [], fileRoles: [], payers: [],
            currencies: ["KZT"],
            limits: UtilityLimits(
                maxFileBytes: 10_485_760, maxPdfPages: 5, mimeTypes: [], maxItems: 60, maxNotesLen: 2000,
                periodMin: "2015-01", reminderDayMin: 1, reminderDayMax: 28
            )
        )
        comparisonValue = nil
        messageTemplate = nil
        otherUploads = []
        templates = [:]
    }

    // MARK: Seeds

    /// One bill per month the grid fixture shows a bill id for, built from the matching bill fixture.
    private func seedBills(from grid: UtilityGrid) {
        guard let first = grid.properties.first else { return }
        let names: [UtilityBillStatus: String] = [
            .paid: "bill-paid", .needsReview: "bill-needs-review", .missing: "bill-missing", .expected: "bill-missing",
        ]
        for month in first.months {
            guard let status = month.status, let id = month.billId else { continue }
            var template = month.isPaidWithoutReceipt ? "bill-paid-no-receipt" : (names[status] ?? "bill-missing")
            if status == .paid, month.hasPaymentProof != true, month.noReceipt != true { template = "bill-paid" }
            guard var json = freshBill(template: template, id: id, property: first.propertyId, period: month.period) else { continue }
            json["status"] = status.rawValue
            if status == .expected { json["source"] = "expected" }
            if status == .needsReview {
                // The sample invoice carries a payment date; the grid sample is a plain bill to check.
                json["paid_at"] = NSNull()
                json["paid_on_confirm"] = false
            }
            json["available_actions"] = actions(for: json).map(\.rawValue)
            billsJSON[id] = json
        }
    }

    private func freshBill(template: String, id: String, property propertyId: String, period: String) -> [String: Any]? {
        guard var json = templates[template] else { return nil }
        let property = properties.first(where: { $0.id == propertyId })
        json["id"] = id
        json["property_id"] = propertyId
        json["property_name"] = property?.name
        json["period"] = period
        if let items = json["items"] as? [[String: Any]] {
            json["items"] = items.enumerated().map { index, item in
                var copy = item
                copy["id"] = "\(id.prefix(24))\(String(format: "%012d", index + 1))"
                return copy
            }
        }
        return json
    }

    // MARK: Reads

    func meta() async throws -> UtilityMeta {
        try await pause()
        return metaValue
    }

    func grid(year: Int, propertyId: String?) async throws -> UtilityGrid {
        try await pause()
        let selected = properties.filter { propertyId == nil || $0.id == propertyId }
        var counters = (missing: 0, review: 0, unassigned: 0)
        for json in billsJSON.values {
            switch json["status"] as? String {
            case "missing": counters.missing += 1
            case "needs_review": counters.review += 1
            default: break
            }
            if json["property_id"] is NSNull || json["property_id"] == nil { counters.unassigned += 1 }
        }
        let propertiesJSON: [[String: Any]] = selected.map { property in
            var yearTotal = Decimal(0)
            let months: [[String: Any]] = (1...12).map { month in
                let period = String(format: "%04d-%02d", year, month)
                guard let bill = billsJSON.values.first(where: { ($0["property_id"] as? String) == property.id && ($0["period"] as? String) == period }) else {
                    return ["period": period, "status": NSNull(), "bill_id": NSNull(), "total": NSNull(), "currency": NSNull()]
                }
                let status = bill["status"] as? String ?? "expected"
                var entry: [String: Any] = [
                    "period": period, "status": status, "bill_id": bill["id"] ?? NSNull(),
                    "total": bill["total"] ?? NSNull(), "currency": bill["currency"] ?? NSNull(),
                    "no_receipt": bill["no_receipt"] ?? false,
                    "has_payment_proof": (bill["files"] as? [[String: Any]] ?? []).contains { ($0["role"] as? String) == "payment_proof" },
                ]
                if status == "needs_review" {
                    if let extraction = bill["extraction"] as? [String: Any], let confidence = extraction["overall_confidence"] { entry["confidence"] = confidence }
                    entry["review_reasons"] = bill["review_reasons"] ?? []
                }
                if status == "missing" {
                    entry["reminders_sent"] = 2
                    entry["next_reminder_at"] = "2026-11-05"
                }
                if status == "confirmed" || status == "paid", let total = (bill["total"] as? NSNumber)?.decimalValue {
                    yearTotal += total
                }
                return entry
            }
            var entry: [String: Any] = [
                "property_id": property.id, "property_name": property.name, "utility_payer": property.payer.rawValue,
                "months": months, "year_total_base": NSDecimalNumber(decimal: yearTotal),
            ]
            if let account = property.account {
                let accountJSON: [String: Any] = [
                    "utility_account_id": account.id,
                    "provider_name": nullable(account.providerName),
                    "account_number": account.accountNumber,
                ]
                entry["account"] = accountJSON
            }
            return entry
        }
        let root: [String: Any] = [
            "year": year, "base_currency": "KZT", "properties": propertiesJSON,
            "counters": [
                "missing": counters.missing, "needs_review": counters.review,
                "unassigned": counters.unassigned, "other_uploads": otherUploads.count,
            ],
        ]
        return try decode(root)
    }

    func inbox(page: Int, perPage: Int) async throws -> UtilityInboxPage {
        try await pause()
        var entries: [[String: Any]] = []
        for json in billsJSON.values where (json["status"] as? String) == "needs_review" {
            entries.append([
                "kind": "bill", "id": json["id"] ?? "", "at": json["updated_at"] ?? "",
                "bill": summaryJSON(json), "upload": NSNull(),
            ])
        }
        let bills: [UtilityInboxEntry] = try entries.map { try decode($0) }
        let uploads = otherUploads.map {
            UtilityInboxEntry(id: $0.extractionId, kind: .upload, at: $0.createdAt, bill: nil, upload: $0)
        }
        let all = (bills + uploads).sorted { $0.at > $1.at }
        let start = max(0, (page - 1) * perPage)
        let slice = start < all.count ? Array(all[start..<min(all.count, start + perPage)]) : []
        return UtilityInboxPage(entries: slice, page: page, perPage: perPage, total: all.count)
    }

    func bill(id: String) async throws -> UtilityBill {
        try await pause()
        return try decode(try existing(id))
    }

    func comparison(year: Int, propertyId: String?) async throws -> UtilityComparison {
        try await pause()
        guard let comparisonValue else { throw UtilityBillsError.notFound }
        return comparisonValue
    }

    func propertyPayer(propertyId: String) async throws -> UtilityPayer? {
        try await pause()
        return properties.first(where: { $0.id == propertyId })?.payer
    }

    // MARK: Bill commands

    func createBill(_ body: UtilityBillCreate) async throws -> UtilityBill {
        try await pause()
        guard properties.contains(where: { $0.id == body.propertyId }) else { throw UtilityBillsError.notFound }
        if let taken = billsJSON.values.first(where: { ($0["property_id"] as? String) == body.propertyId && ($0["period"] as? String) == body.period }) {
            let status = taken["status"] as? String
            if status != "expected" && status != "missing" { throw UtilityBillsError.billExists(billId: taken["id"] as? String) }
            billsJSON[taken["id"] as? String ?? ""] = nil
        }
        let id = UUID().uuidString.lowercased()
        guard var json = freshBill(template: "bill-missing", id: id, property: body.propertyId, period: body.period) else { throw UtilityBillsError.unknown }
        json["status"] = "needs_review"
        json["source"] = "manual"
        json["currency"] = body.currency ?? "KZT"
        json["provider_name"] = body.providerName ?? NSNull()
        json["account_number"] = body.accountNumber ?? NSNull()
        json["issued_at"] = body.issuedAt ?? NSNull()
        json["notes"] = body.notes ?? NSNull()
        var items = body.items ?? []
        if items.isEmpty, let total = body.total { items = [UtilityBillItemInput(serviceType: "other", amount: total)] }
        json["items"] = try itemsJSON(items, billId: id)
        json["total"] = total(of: json)
        json["available_actions"] = actions(for: json).map(\.rawValue)
        billsJSON[id] = json
        return try decode(json)
    }

    func patchBill(id: String, _ patch: UtilityBillPatch) async throws -> UtilityBill {
        try await pause()
        var json = try existing(id)
        if (json["status"] as? String) == "uploaded" { throw UtilityBillsError.invalidTransition }
        let encoded = UtilityFixtures.exactNumbers(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(patch))
        ) as? [String: Any] ?? [:]
        for (key, value) in encoded where key != "items" { json[key] = value }
        if let items = patch.items {
            json["items"] = try itemsJSON(items, billId: id)
            json["total"] = total(of: json)
            if (json["status"] as? String) == "expected" || (json["status"] as? String) == "missing" {
                json["status"] = "needs_review"
            }
        }
        json["review_reasons"] = (json["review_reasons"] as? [String] ?? []).filter { !["property_unresolved", "currency_missing", "period_missing", "period_inferred", "sum_mismatch"].contains($0) }
        json["available_actions"] = actions(for: json).map(\.rawValue)
        billsJSON[id] = json
        return try decode(json)
    }

    func confirm(id: String) async throws -> UtilityBill {
        try await pause()
        confirmCalls += 1
        var json = try existing(id)
        guard (json["status"] as? String) == "needs_review" else { throw UtilityBillsError.invalidTransition }
        var missing: [String] = []
        if json["property_id"] == nil || json["property_id"] is NSNull { missing.append("property") }
        if json["currency"] == nil || json["currency"] is NSNull { missing.append("currency") }
        if (json["items"] as? [Any] ?? []).isEmpty { missing.append("items") }
        guard missing.isEmpty else { throw UtilityBillsError.incomplete(missing: missing) }
        let paid = !(json["paid_at"] is NSNull) && json["paid_at"] != nil
        json["status"] = paid ? "paid" : "confirmed"
        json["confirmed_at"] = "\(now)T10:00:00Z"
        json["paid_on_confirm"] = false
        if paid, let payer = properties.first(where: { $0.id == (json["property_id"] as? String) })?.payer { json["paid_by"] = payer.rawValue }
        json["available_actions"] = actions(for: json).map(\.rawValue)
        billsJSON[id] = json
        return try decode(json)
    }

    func markPaid(id: String, _ body: UtilityMarkPaid) async throws -> UtilityBill {
        try await pause()
        var json = try existing(id)
        let status = json["status"] as? String
        if body.noReceipt {
            guard ["confirmed", "expected", "missing"].contains(status ?? "") else { throw UtilityBillsError.invalidTransition }
        } else {
            guard status == "confirmed" else { throw UtilityBillsError.invalidTransition }
        }
        json["status"] = "paid"
        json["paid_at"] = body.paidAt
        json["no_receipt"] = body.noReceipt
        if json["currency"] == nil || json["currency"] is NSNull { json["currency"] = body.currency ?? "KZT" }
        if let payer = properties.first(where: { $0.id == (json["property_id"] as? String) })?.payer { json["paid_by"] = payer.rawValue }
        if let fileId = body.paymentProofFileId {
            var files = json["files"] as? [[String: Any]] ?? []
            if !files.contains(where: { ($0["file_id"] as? String) == fileId }) {
                files.append([
                    "id": UUID().uuidString.lowercased(), "file_id": fileId, "role": "payment_proof",
                    "original_name": "payment-proof.jpg", "mime_type": "image/jpeg", "size_bytes": 0,
                    "download_url": NSNull(), "download_expires_at": NSNull(), "created_at": "\(now)T10:00:00Z",
                ])
            }
            json["files"] = files
        }
        json["available_actions"] = actions(for: json).map(\.rawValue)
        billsJSON[id] = json
        return try decode(json)
    }

    func unmarkPaid(id: String) async throws -> UtilityBill {
        try await pause()
        var json = try existing(id)
        guard (json["status"] as? String) == "paid", (json["no_receipt"] as? Bool) == true else { throw UtilityBillsError.invalidTransition }
        json["status"] = (json["items"] as? [Any] ?? []).isEmpty ? "expected" : "confirmed"
        json["paid_at"] = NSNull()
        json["paid_by"] = NSNull()
        json["no_receipt"] = false
        json["available_actions"] = actions(for: json).map(\.rawValue)
        billsJSON[id] = json
        return try decode(json)
    }

    func deleteBill(id: String) async throws {
        try await pause()
        let json = try existing(id)
        guard (json["status"] as? String) != "paid" else { throw UtilityBillsError.invalidTransition }
        billsJSON[id] = nil
    }

    func tenantMessage(id: String) async throws -> UtilityTenantMessage {
        try await pause()
        tenantMessageCalls += 1
        let json = try existing(id)
        guard let propertyId = json["property_id"] as? String, let property = properties.first(where: { $0.id == propertyId }) else {
            throw UtilityBillsError.notFound
        }
        let period = json["period"] as? String ?? ""
        let text = (messageTemplate?.text ?? "Пришлите, пожалуйста, квитанцию.")
            .replacingOccurrences(of: "апрель 2026", with: UtilityFormat.periodTitle(period).lowercased())
            .replacingOccurrences(of: "Примерная 1, кв. 1", with: property.name)
        return UtilityTenantMessage(text: text, lang: "ru", period: period, propertyId: propertyId, utilityPayer: property.payer)
    }

    func reextract(id: String) async throws -> UtilityUploadResult {
        try await pause()
        var json = try existing(id)
        guard (json["files"] as? [Any] ?? []).isEmpty == false else { throw UtilityBillsError.invalidTransition }
        json["status"] = "uploaded"
        json["available_actions"] = actions(for: json).map(\.rawValue)
        billsJSON[id] = json
        let uploadId = UUID().uuidString.lowercased()
        pending[uploadId] = PendingUpload(
            id: uploadId, target: UtilityUploadTarget(billId: id), role: .invoice,
            fileId: UUID().uuidString.lowercased(), billId: id, outcome: uploadOutcome == .stalled ? .stalled : .bill
        )
        return UtilityUploadResult(uploadId: uploadId, bill: brief(json), duplicateOf: nil)
    }

    // MARK: Uploads

    func upload(_ upload: RecognitionUpload, target: UtilityUploadTarget) async throws -> UtilityUploadResult {
        try await pause()
        uploads.append((upload, target))
        if let known = seenFiles[upload.data], let json = billsJSON[known] {
            return UtilityUploadResult(uploadId: nil, bill: brief(json), duplicateOf: known)
        }
        let uploadId = UUID().uuidString.lowercased()
        var attached: [String: Any]?
        if let billId = target.billId {
            var json = try existing(billId)
            if let status = json["status"] as? String, status == "expected" || status == "missing" { json["status"] = "uploaded" }
            json["available_actions"] = actions(for: json).map(\.rawValue)
            billsJSON[billId] = json
            attached = json
            seenFiles[upload.data] = billId
        }
        pending[uploadId] = PendingUpload(
            id: uploadId, target: target, role: target.role ?? .invoice,
            fileId: UUID().uuidString.lowercased(), data: upload.data, billId: target.billId, outcome: uploadOutcome
        )
        return UtilityUploadResult(uploadId: uploadId, bill: attached.flatMap(brief), duplicateOf: nil)
    }

    func uploadState(id: String) async throws -> UtilityUploadState {
        try await pause()
        if stateLatency > .zero { try await Task.sleep(for: stateLatency) }
        stateCalls += 1
        guard var upload = pending[id] else { throw UtilityBillsError.notFound }
        upload.polls += 1
        defer { pending[id] = upload }
        let base: [String: Any] = [
            "upload_id": id, "file_id": upload.fileId, "review_status": "needs_review", "attempts": 0,
            "next_attempt_at": NSNull(), "error_code": NSNull(), "created_at": "\(now)T09:00:00Z",
            "other": NSNull(), "document_kind": NSNull(), "bill": NSNull(), "review_reasons": [], "overall_confidence": NSNull(),
        ]
        func state(_ patch: [String: Any]) throws -> UtilityUploadState {
            try decode(base.merging(patch) { $1 })
        }
        if upload.outcome == .stalled || upload.polls <= pollsBeforeResult {
            return try state(["status": upload.polls == 1 ? "queued" : "running"])
        }
        switch upload.outcome {
        case .other:
            return try state([
                "status": "succeeded", "document_kind": "other", "review_reasons": ["not_utility_document"], "overall_confidence": 0.8,
                "other": ["amount": 25000, "currency": "KZT", "payment_date": "2026-10-30", "actions": ["attach_to_rent", "reject"]],
            ])
        case .failed:
            let json = try landBill(&upload, reasons: ["extraction_failed"], items: false)
            return try state(["status": "failed", "error_code": "provider_timeout", "attempts": 4, "bill": briefJSON(json)])
        case .proof:
            let json = try landBill(&upload, reasons: ["period_inferred", "payment_proof_pending"], items: false)
            return try state([
                "status": "succeeded", "document_kind": "payment_proof", "bill": briefJSON(json),
                "review_reasons": ["period_inferred", "payment_proof_pending"], "overall_confidence": 0.9,
            ])
        case .bill, .stalled:
            let json = try landBill(&upload, reasons: ["low_confidence:provider"], items: true)
            return try state([
                "status": "succeeded", "document_kind": "utility_bill", "bill": briefJSON(json),
                "review_reasons": ["low_confidence:provider"], "overall_confidence": 0.93,
            ])
        }
    }

    func rejectUpload(id: String) async throws -> UtilityUploadState {
        try await pause()
        guard let index = otherUploads.firstIndex(where: { $0.extractionId == id }) else {
            // An upload of this session that ended as an `other` document can be rejected too.
            if let waiting = pending[id], waiting.outcome == .other, waiting.polls > pollsBeforeResult {
                pending[id] = nil
                return try decode([
                    "upload_id": id, "file_id": waiting.fileId, "review_status": "rejected", "attempts": 1,
                    "next_attempt_at": NSNull(), "error_code": NSNull(), "created_at": "\(now)T09:00:00Z", "other": NSNull(),
                    "status": "succeeded", "document_kind": "other", "bill": NSNull(), "review_reasons": [], "overall_confidence": 0.8,
                ] as [String: Any])
            }
            if pending[id] != nil { throw UtilityBillsError.invalidTransition }
            throw UtilityBillsError.notFound
        }
        let upload = otherUploads.remove(at: index)
        let json: [String: Any] = [
            "upload_id": id, "file_id": nullable(upload.fileId), "review_status": "rejected", "attempts": 1,
            "next_attempt_at": NSNull(), "error_code": NSNull(), "created_at": upload.createdAt, "other": NSNull(),
            "status": "succeeded", "document_kind": "other", "bill": NSNull(), "review_reasons": [], "overall_confidence": 0.8,
        ]
        return try decode(json)
    }

    /// Creates the bill an upload lands on (once) or finds the bill it was attached to.
    private func landBill(_ upload: inout PendingUpload, reasons: [String], items: Bool) throws -> [String: Any] {
        if let billId = upload.billId, var json = billsJSON[billId] {
            if upload.role == .invoice || items {
                json["status"] = (json["status"] as? String) == "paid" ? "paid" : "needs_review"
            }
            json["review_reasons"] = reasons
            json["available_actions"] = actions(for: json).map(\.rawValue)
            billsJSON[billId] = json
            return json
        }
        let propertyId = upload.target.propertyId ?? properties.first?.id ?? ""
        let period = upload.target.period ?? Self.previousPeriod(of: now)
        let id = UUID().uuidString.lowercased()
        guard var json = freshBill(template: items ? "bill-needs-review" : "bill-missing", id: id, property: propertyId, period: period) else {
            throw UtilityBillsError.unknown
        }
        // The month may already hold an expected or missing bill: the upload fills it in.
        if let slot = billsJSON.values.first(where: { ($0["property_id"] as? String) == propertyId && ($0["period"] as? String) == period }) {
            billsJSON[slot["id"] as? String ?? ""] = nil
        }
        json["status"] = "needs_review"
        json["source"] = "upload"
        json["review_reasons"] = reasons
        json["paid_at"] = NSNull()
        json["paid_on_confirm"] = false
        json["available_actions"] = actions(for: json).map(\.rawValue)
        billsJSON[id] = json
        upload.billId = id
        // The file is on the bill now: the same file again is a duplicate of it.
        seenFiles[upload.data] = id
        return json
    }

    static func previousPeriod(of day: String) -> String {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count >= 2 else { return String(day.prefix(7)) }
        let year = parts[1] == 1 ? parts[0] - 1 : parts[0]
        let month = parts[1] == 1 ? 12 : parts[1] - 1
        return String(format: "%04d-%02d", year, month)
    }

    // MARK: Account and expectations

    func account(propertyId: String) async throws -> UtilityAccount? {
        try await pause()
        return properties.first(where: { $0.id == propertyId })?.account
    }

    func saveAccount(propertyId: String, existing: UtilityAccount?, input: UtilityAccountInput) async throws -> UtilityAccount {
        try await pause()
        guard let index = properties.firstIndex(where: { $0.id == propertyId }) else { throw UtilityBillsError.notFound }
        let json: [String: Any] = [
            "id": existing?.id ?? UUID().uuidString.lowercased(), "property_id": propertyId,
            "provider_name": input.providerName ?? NSNull(), "provider_code": NSNull(),
            "account_number": input.accountNumber, "is_default": true, "is_active": true,
            "created_at": existing?.createdAt ?? "\(now)T09:00:00Z", "updated_at": "\(now)T09:00:00Z",
        ]
        let account: UtilityAccount = try decode(json)
        properties[index].account = account
        return account
    }

    func deleteAccount(propertyId: String, id: String) async throws {
        try await pause()
        guard let index = properties.firstIndex(where: { $0.id == propertyId }) else { throw UtilityBillsError.notFound }
        properties[index].account = nil
    }

    func expectations(propertyId: String) async throws -> [UtilityExpectation] {
        try await pause()
        return properties.first(where: { $0.id == propertyId })?.expectations ?? []
    }

    func saveExpectation(propertyId: String, existing: UtilityExpectation?, input: UtilityExpectationInput) async throws -> UtilityExpectation {
        try await pause()
        guard let index = properties.firstIndex(where: { $0.id == propertyId }) else { throw UtilityBillsError.notFound }
        let json: [String: Any] = [
            "id": existing?.id ?? UUID().uuidString.lowercased(), "property_id": propertyId,
            "lease_id": existing?.leaseId ?? NSNull(), "months": input.months, "active_from": input.activeFrom,
            "active_to": input.activeTo ?? NSNull(),
            "created_at": existing?.createdAt ?? "\(now)T09:00:00Z", "updated_at": "\(now)T09:00:00Z",
        ]
        let expectation: UtilityExpectation = try decode(json)
        properties[index].expectations.removeAll { $0.id == expectation.id }
        properties[index].expectations.append(expectation)
        return expectation
    }

    func deleteExpectation(propertyId: String, id: String) async throws {
        try await pause()
        guard let index = properties.firstIndex(where: { $0.id == propertyId }) else { throw UtilityBillsError.notFound }
        properties[index].expectations.removeAll { $0.id == id }
    }

    /// Changes the stored bill (tests and previews: a bill with a payment date, without a file, ...).
    func mutateBill(id: String, _ change: (inout [String: Any]) -> Void) {
        guard var json = billsJSON[id] else { return }
        change(&json)
        json["available_actions"] = actions(for: json).map(\.rawValue)
        billsJSON[id] = json
    }

    /// Ids of the stored bills of a status, oldest period first (tests and previews).
    func billIds(status: UtilityBillStatus) -> [String] {
        billsJSON.values.filter { ($0["status"] as? String) == status.rawValue }
            .sorted { ($0["period"] as? String ?? "") < ($1["period"] as? String ?? "") }
            .compactMap { $0["id"] as? String }
    }

    // MARK: Helpers

    private func nullable(_ value: Any?) -> Any {
        value ?? NSNull()
    }

    private func pause() async throws {
        if latency > .zero { try await Task.sleep(for: latency) }
        if let failure {
            self.failure = nil
            throw failure
        }
    }

    private func existing(_ id: String) throws -> [String: Any] {
        guard let json = billsJSON[id] else { throw UtilityBillsError.notFound }
        return json
    }

    private func decode<T: Decodable>(_ json: Any) throws -> T {
        guard JSONSerialization.isValidJSONObject(json) else { throw UtilityBillsError.unknown }
        do {
            return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: json))
        } catch {
            throw UtilityBillsError.unknown
        }
    }

    private func brief(_ json: [String: Any]) -> UtilityBillBrief? {
        try? decode(briefJSON(json)) as UtilityBillBrief
    }

    private func briefJSON(_ json: [String: Any]) -> [String: Any] {
        [
            "id": json["id"] ?? "", "property_id": json["property_id"] ?? NSNull(), "period": json["period"] ?? "",
            "status": json["status"] ?? "expected", "document_kind": json["document_kind"] ?? NSNull(),
            "currency": json["currency"] ?? NSNull(), "total_due": json["total_due"] ?? NSNull(),
            "total_paid": json["total_paid"] ?? NSNull(), "paid_at": json["paid_at"] ?? NSNull(),
            "review_reasons": json["review_reasons"] ?? [],
        ]
    }

    private func summaryJSON(_ json: [String: Any]) -> [String: Any] {
        let files = json["files"] as? [Any] ?? []
        return [
            "id": json["id"] ?? "", "property_id": json["property_id"] ?? NSNull(), "property_name": json["property_name"] ?? NSNull(),
            "period": json["period"] ?? "", "status": json["status"] ?? "", "total": json["total"] ?? NSNull(),
            "currency": json["currency"] ?? NSNull(), "provider_name": json["provider_name"] ?? NSNull(),
            "review_reasons": json["review_reasons"] ?? [], "paid_at": json["paid_at"] ?? NSNull(),
            "no_receipt": json["no_receipt"] ?? false, "has_file": !files.isEmpty, "source": json["source"] ?? "upload",
            "confidence": (json["extraction"] as? [String: Any])?["overall_confidence"] ?? NSNull(),
            "created_at": json["created_at"] ?? "", "updated_at": json["updated_at"] ?? "",
        ]
    }

    private func itemsJSON(_ items: [UtilityBillItemInput], billId: String) throws -> [[String: Any]] {
        let encoder = JSONEncoder()
        return try items.enumerated().map { index, item in
            var json = UtilityFixtures.exactNumbers(
                try JSONSerialization.jsonObject(with: encoder.encode(item))
            ) as? [String: Any] ?? [:]
            json["id"] = "\(billId.prefix(24))\(String(format: "%012d", index + 1))"
            json["position"] = index
            json["extraction_id"] = NSNull()
            return json
        }
    }

    /// The server sums the lines; the mock does the same, so «Итого» stays right after an edit.
    private func total(of json: [String: Any]) -> Any {
        let items = json["items"] as? [[String: Any]] ?? []
        guard !items.isEmpty else { return json["total_due"] ?? NSNull() }
        let sum = items.reduce(Decimal(0)) { $0 + ((($1["amount"] as? NSNumber)?.decimalValue) ?? 0) }
        return NSDecimalNumber(decimal: sum)
    }

    /// `available_actions` of the status machine of §2 (the buttons the server offers).
    private func actions(for json: [String: Any]) -> [UtilityBillAction] {
        let status = UtilityBillStatus.fromWire(json["status"] as? String ?? "")
        let hasFile = !(json["files"] as? [Any] ?? []).isEmpty
        let noReceipt = (json["no_receipt"] as? Bool) == true
        switch status {
        case .expected, .missing: return [.edit, .markPaid, .tenantMessage, .delete]
        case .uploaded: return []
        case .needsReview: return [.edit, .confirm] + (hasFile ? [.reextract] : []) + [.tenantMessage, .delete]
        case .confirmed: return [.edit, .markPaid] + (hasFile ? [.reextract] : []) + [.tenantMessage, .delete]
        case .paid: return [.edit] + (noReceipt ? [.unmarkPaid] : []) + [.tenantMessage]
        case .unknown: return []
        }
    }
}
