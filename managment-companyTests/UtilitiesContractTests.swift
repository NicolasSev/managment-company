//
//  UtilitiesContractTests.swift
//  managment-companyTests
//
//  Utility bills v2 (task U9): the models decode exactly the contract fixtures of
//  packages/api-contracts/fixtures/{utilities,notifications} (copied by `make ios-contract-fixtures`),
//  every field of a fixture is read by a model (found by mutating each leaf), the enums know exactly
//  the codes of `GET /utility-bills/meta`, and the request bodies keep the wire semantics of the API
//  (absent = unchanged, null = cleared, money without binary noise).
//

import Foundation
import Testing
@testable import managment_company

// MARK: - Fixture access

private func fixtureData(_ name: String) throws -> Data {
    try UtilityFixtures.data(named: name)
}

private func fixtureJSON(_ name: String) throws -> Any {
    try JSONSerialization.jsonObject(with: try fixtureData(name))
}

private func leafPaths(_ value: Any, prefix: [Any] = []) -> [[Any]] {
    if let object = value as? [String: Any] {
        return object.keys.sorted().flatMap { leafPaths(object[$0]!, prefix: prefix + [$0]) }
    }
    if let array = value as? [Any] {
        return array.enumerated().flatMap { leafPaths($0.element, prefix: prefix + [$0.offset]) }
    }
    return [prefix]
}

private func normalized(_ path: [Any]) -> String {
    var text = ""
    for component in path {
        if let key = component as? String {
            text += text.isEmpty ? key : ".\(key)"
        } else {
            text += "[]"
        }
    }
    return text
}

private func isBool(_ value: Any) -> Bool {
    guard let number = value as? NSNumber else { return false }
    return CFGetTypeID(number) == CFBooleanGetTypeID()
}

private func mutated(_ root: Any, at path: ArraySlice<Any>) -> Any {
    guard let head = path.first else {
        if root is NSNull { return "~" }
        if isBool(root) { return !(root as! Bool) }
        if let number = root as? NSNumber { return number.doubleValue + 7 }
        if let text = root as? String { return text + "~" }
        return root
    }
    if let key = head as? String, var object = root as? [String: Any] {
        object[key] = mutated(object[key] as Any, at: path.dropFirst())
        return object
    }
    if let index = head as? Int, var array = root as? [Any] {
        array[index] = mutated(array[index], at: path.dropFirst())
        return array
    }
    return root
}

private func isCovered(_ path: String, by ignored: Set<String>) -> Bool {
    ignored.contains { entry in
        entry.hasSuffix(".*") ? path.hasPrefix(entry.dropLast(1)) : path == entry
    }
}

@MainActor
private struct FixtureCase {
    let fixture: String
    let decode: (Data) throws -> AnyHashable
    var ignored: Set<String> = []
}

@MainActor
private func envelope<T: Decodable & Hashable>(_ type: T.Type) -> (Data) throws -> AnyHashable {
    { AnyHashable(try JSONDecoder().decode(APIResponse<T>.self, from: $0).data) }
}

@MainActor
private func page<T: Decodable & Hashable>(_ type: T.Type) -> (Data) throws -> AnyHashable {
    {
        let page = try JSONDecoder().decode(APIListEnvelope<T>.self, from: $0)
        return AnyHashable([AnyHashable(page.data), AnyHashable(page.page), AnyHashable(page.perPage), AnyHashable(page.total)])
    }
}

@MainActor
private let cases: [FixtureCase] = [
    FixtureCase(fixture: "meta", decode: envelope(UtilityMeta.self)),
    FixtureCase(fixture: "bill-needs-review", decode: envelope(UtilityBill.self)),
    FixtureCase(fixture: "bill-paid", decode: envelope(UtilityBill.self)),
    FixtureCase(fixture: "bill-paid-no-receipt", decode: envelope(UtilityBill.self)),
    FixtureCase(fixture: "bill-missing", decode: envelope(UtilityBill.self)),
    FixtureCase(fixture: "bill-list", decode: page(UtilityBillSummary.self)),
    FixtureCase(fixture: "grid", decode: envelope(UtilityGrid.self)),
    FixtureCase(fixture: "inbox", decode: page(UtilityInboxEntry.self)),
    FixtureCase(fixture: "tenant-message", decode: envelope(UtilityTenantMessage.self)),
    FixtureCase(fixture: "upload-accepted", decode: envelope(UtilityUploadResult.self)),
    FixtureCase(fixture: "upload-accepted-to-bill", decode: envelope(UtilityUploadResult.self)),
    FixtureCase(fixture: "upload-duplicate", decode: envelope(UtilityUploadResult.self)),
    FixtureCase(fixture: "upload-state-queued", decode: envelope(UtilityUploadState.self)),
    FixtureCase(fixture: "upload-state-succeeded-bill", decode: envelope(UtilityUploadState.self)),
    FixtureCase(fixture: "upload-state-succeeded-proof", decode: envelope(UtilityUploadState.self)),
    FixtureCase(fixture: "upload-state-other", decode: envelope(UtilityUploadState.self)),
    FixtureCase(fixture: "upload-state-failed", decode: envelope(UtilityUploadState.self)),
    FixtureCase(fixture: "analytics-comparison", decode: envelope(UtilityComparison.self)),
    FixtureCase(fixture: "accounts-item", decode: envelope(UtilityAccount.self)),
    FixtureCase(fixture: "accounts-list", decode: page(UtilityAccount.self)),
    FixtureCase(fixture: "expectations-item", decode: envelope(UtilityExpectation.self)),
    FixtureCase(fixture: "expectations-list", decode: page(UtilityExpectation.self)),
    FixtureCase(fixture: "settings", decode: envelope(NotificationSettings.self)),
    FixtureCase(fixture: "settings-no-quiet-no-telegram", decode: envelope(NotificationSettings.self)),
    FixtureCase(fixture: "telegram-link", decode: envelope(TelegramLink.self)),
]

// MARK: - Tests

@MainActor
@Suite(.serialized)
struct UtilitiesContractTests {
    @Test func everyFixtureDecodes() throws {
        for item in cases {
            do {
                _ = try item.decode(try fixtureData(item.fixture))
            } catch {
                Issue.record("\(item.fixture) does not decode: \(error)")
            }
        }
    }

    @Test func modelsReadEveryContractField() throws {
        for item in cases {
            let json = try fixtureJSON(item.fixture)
            let original = try item.decode(try JSONSerialization.data(withJSONObject: json))
            var ignoredByModel = Set<String>()
            for path in leafPaths(json) {
                let changed = mutated(json, at: path[...])
                let data = try JSONSerialization.data(withJSONObject: changed)
                // A decode failure after the change also means the model reads the field.
                if let result = try? item.decode(data), result == original {
                    ignoredByModel.insert(normalized(path))
                }
            }
            let unexpected = ignoredByModel.filter { !isCovered($0, by: item.ignored) }.sorted()
            #expect(
                unexpected.isEmpty,
                "\(item.fixture): the model does not read these contract fields:\n\(unexpected.joined(separator: "\n"))"
            )
            let stale = item.ignored.filter { !$0.hasSuffix(".*") && !ignoredByModel.contains($0) }.sorted()
            #expect(stale.isEmpty, "\(item.fixture): stale exceptions:\n\(stale.joined(separator: "\n"))")
        }
    }

    // MARK: Wire values

    @Test func billFixtureMapsToTheModel() throws {
        let bill = try UtilityFixtures.decode(UtilityBill.self, named: "bill-needs-review")
        #expect(bill.status == .needsReview)
        #expect(bill.period == "2025-11")
        #expect(bill.total == Decimal(string: "12057.5"))
        #expect(bill.items.count == 10)
        #expect(bill.items[0].amount == Decimal(string: "1092.68"))
        #expect(bill.items[0].readingCurr == Decimal(string: "17096.55"))
        #expect(bill.reviewReasons == ["period_inferred"])
        #expect(bill.paidOnConfirm)
        #expect(bill.paidAt == "2025-11-22")
        #expect(bill.primaryFile?.isPDF == true)
        #expect(bill.extraction?.overallConfidence == 0.93)
        #expect(bill.availableActions == [.edit, .confirm, .reextract, .tenantMessage, .delete])
    }

    @Test func paidWithoutReceiptHasNoFileAndCanBeUnmarked() throws {
        let bill = try UtilityFixtures.decode(UtilityBill.self, named: "bill-paid-no-receipt")
        #expect(bill.status == .paid && bill.noReceipt)
        #expect(bill.files.isEmpty && bill.primaryFile == nil)
        #expect(bill.paidBy == .tenant)
        #expect(bill.offers(.unmarkPaid) && !bill.offers(.confirm))
    }

    @Test func gridMonthWithoutStatusDecodes() throws {
        let grid = try UtilityFixtures.decode(UtilityGrid.self, named: "grid")
        let first = try #require(grid.properties.first)
        #expect(first.months.count == 12)
        #expect(first.months[5].status == nil && first.months[5].billId == nil)
        #expect(first.months[1].isPaidWithoutReceipt)
        #expect(first.months[3].remindersSent == 2)
        #expect(grid.counters.inboxCount == 1)
        #expect(grid.properties[1].utilityPayer == .owner && grid.properties[1].account == nil)
    }

    @Test func inboxEntriesCarryABillOrAnUpload() throws {
        let data = try fixtureData("inbox")
        let entries = try JSONDecoder().decode(APIListEnvelope<UtilityInboxEntry>.self, from: data).data
        #expect(entries.map(\.kind) == [.bill, .upload])
        #expect(entries[0].bill?.id == entries[0].id && entries[0].upload == nil)
        #expect(entries[1].upload?.actions == [.attachToRent, .reject])
        #expect(entries[1].upload?.totalPaid == Decimal(25000))
    }

    @Test func uploadAnswersDistinguishAcceptedFromDuplicate() throws {
        let accepted = try UtilityFixtures.decode(UtilityUploadResult.self, named: "upload-accepted")
        #expect(accepted.uploadId != nil && accepted.bill == nil && accepted.duplicateOf == nil)
        let duplicate = try UtilityFixtures.decode(UtilityUploadResult.self, named: "upload-duplicate")
        #expect(duplicate.uploadId == nil && duplicate.duplicateOf == duplicate.bill?.id)
        let toBill = try UtilityFixtures.decode(UtilityUploadResult.self, named: "upload-accepted-to-bill")
        #expect(toBill.uploadId != nil && toBill.bill?.status == .uploaded)
    }

    @Test func uploadStatesMapToPhases() throws {
        func phase(_ name: String) throws -> UtilityUploadPhase? {
            UtilityUploadFlowModel.phase(for: try UtilityFixtures.decode(UtilityUploadState.self, named: name))
        }
        #expect(try phase("upload-state-queued") == nil)
        if case .bill(let bill)? = try phase("upload-state-succeeded-bill") { #expect(bill.status == .needsReview) } else { Issue.record("bill") }
        if case .bill(let bill)? = try phase("upload-state-succeeded-proof") {
            #expect(bill.reviewReasons.contains("payment_proof_pending"))
        } else { Issue.record("proof") }
        if case .other(_, let other)? = try phase("upload-state-other") {
            #expect(other.amount == Decimal(25000) && other.actions == [.attachToRent, .reject])
        } else { Issue.record("other") }
        if case .failed(_, let bill)? = try phase("upload-state-failed") {
            #expect(bill?.reviewReasons == ["extraction_failed"])
        } else { Issue.record("failed") }
    }

    @Test func notificationSettingsFixtures() throws {
        let settings = try UtilityFixtures.decode(NotificationSettings.self, named: "settings")
        #expect(settings.quietFrom == "22:00" && settings.hasQuietHours)
        #expect(settings.telegram.linked)
        #expect(settings.isEnabled(.utilityBillMissing, .telegram))
        #expect(!settings.isEnabled(.utilityBillNeedsReview, .telegram))
        let bare = try UtilityFixtures.decode(NotificationSettings.self, named: "settings-no-quiet-no-telegram")
        #expect(!bare.hasQuietHours && !bare.telegram.linked && bare.telegram.verifiedAt == nil)
        let link = try UtilityFixtures.decode(TelegramLink.self, named: "telegram-link")
        #expect(link.deepLink == "https://t.me/RentfolioBot?start=K7M2Q9XW4HPD")
        #expect(link.groupDeepLink?.contains("startgroup=") == true)
    }

    // MARK: Enums against the meta

    @Test func knownEnumCasesAreExactlyTheMetaCodes() throws {
        let meta = try UtilityFixtures.decode(UtilityMeta.self, named: "meta")
        func known<E: FallbackStringEnum>(_: E.Type) -> Set<String> { Set(E.knownMapping.map { $0.1 }) }
        #expect(known(UtilityBillStatus.self) == Set(meta.statuses.map(\.code)))
        #expect(known(UtilityPayer.self) == Set(meta.payers.map(\.code)))
        #expect(known(UtilityFileRole.self) == Set(meta.fileRoles))
        #expect(meta.limits.maxFileBytes == RecognitionUpload.maxBytes)
        #expect(meta.limits.maxPdfPages == UtilityDocumentBuilder.maxPages)
    }

    @Test func unknownValuesDegradeInsteadOfFailing() throws {
        let data = Data(#"{"data":{"id":"b","period":"2026-01","status":"archived","total":null,"currency":null,"provider_name":null,"review_reasons":[],"paid_at":null,"no_receipt":false,"has_file":false,"source":"x","confidence":null,"created_at":"a","updated_at":"a","property_id":null,"property_name":null}}"#.utf8)
        let summary = try JSONDecoder().decode(APIResponse<UtilityBillSummary>.self, from: data).data
        #expect(summary.status == .unknown("archived"))
        #expect(summary.status.tone == .neutral)
        #expect(UtilityBillAction.fromWire("sign") == .unknown("sign"))
    }

    // MARK: Requests

    private func object(_ value: some Encodable) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any] ?? [:]
    }

    @Test func patchSendsOnlyWhatChangedAndNullClears() throws {
        var patch = UtilityBillPatch()
        patch.providerName = .set("АлСеКо")
        patch.notes = .clear
        let json = try object(patch)
        #expect(Set(json.keys) == ["provider_name", "notes"])
        #expect(json["provider_name"] as? String == "АлСеКо")
        #expect(json["notes"] is NSNull)
        #expect(UtilityBillPatch().isEmpty)
    }

    @Test func moneyInRequestsHasNoBinaryNoise() throws {
        let money = try #require(Money.parse("1 092,68", currency: "KZT"))
        var patch = UtilityBillPatch()
        patch.items = [UtilityBillItemInput(serviceType: "electricity", labelRaw: "Электроэнергия", amount: money.major)]
        patch.totalDue = .set(try #require(UtilityFormat.parseDecimal("12057.5")))
        let text = String(data: try JSONEncoder().encode(patch), encoding: .utf8) ?? ""
        #expect(text.contains("\"amount\":1092.68"))
        #expect(text.contains("\"total_due\":12057.5"))
        #expect(!text.contains("1092.6800"))
    }

    @Test func itemReplaceSetClearsEmptyOptionals() throws {
        let item = UtilityBillItemInput(serviceType: "gas", amount: Decimal(string: "439.93")!)
        let json = try object(item)
        #expect(json["tariff"] is NSNull && json["unit"] is NSNull && json["meter_no"] is NSNull)
        #expect(json["service_type"] as? String == "gas")
    }

    @Test func markPaidBodiesMatchTheContractRequests() throws {
        let noReceipt = try object(UtilityMarkPaid.noReceipt(paidAt: "2026-03-10"))
        #expect(noReceipt["paid_at"] as? String == "2026-03-10")
        #expect(noReceipt["no_receipt"] as? Bool == true)
        #expect(noReceipt["payment_proof_file_id"] == nil)
        let proof = try object(UtilityMarkPaid.proof(fileId: "f0000000-0000-4000-8000-000000000002", paidAt: "2026-03-10"))
        #expect(proof["payment_proof_file_id"] as? String == "f0000000-0000-4000-8000-000000000002")
        #expect(proof["no_receipt"] == nil)
        // The same keys as the contract request fixtures.
        let proofFixture = try #require(try fixtureJSON("bill-mark-paid-proof-request") as? [String: Any])
        let noReceiptFixture = try #require(try fixtureJSON("bill-mark-paid-request") as? [String: Any])
        #expect(Set(proof.keys) == Set(proofFixture.keys))
        #expect(Set(noReceipt.keys) == Set(noReceiptFixture.keys))
    }

    @Test func createBodyMatchesTheContractRequest() throws {
        let item = UtilityBillItemInput(serviceType: "heating", amount: Decimal(string: "821.96")!)
        let body = UtilityBillCreate(
            propertyId: "7c1e4a52-3b1f-4d1c-9a55-0a1f6c1d2b01", period: "2026-03", currency: "KZT",
            providerName: "АлСеКо", accountNumber: "1100000", issuedAt: "2026-04-02", items: [item]
        )
        let json = try object(body)
        let fixture = try #require(try fixtureJSON("bill-create-request") as? [String: Any])
        #expect(Set(json.keys) == Set(fixture.keys).subtracting(["notes"]))
        // A total alone becomes one `other` line on the server.
        let totalOnly = try object(UtilityBillCreate(propertyId: "p", period: "2026-03", total: Decimal(string: "34959.57")))
        #expect(totalOnly["total"] != nil && totalOnly["items"] == nil && totalOnly["currency"] == nil)
    }

    @Test func expectationAndAccountBodiesMatchTheContractRequests() throws {
        let rule = try object(UtilityExpectationInput(months: Array(1...12), activeFrom: "2025-11-01", activeTo: nil))
        let ruleFixture = try #require(try fixtureJSON("expectation-create-request") as? [String: Any])
        #expect(Set(rule.keys) == Set(ruleFixture.keys))
        #expect(rule["active_to"] is NSNull)
        let account = try object(UtilityAccountInput(providerName: "АлСеКо", accountNumber: "11-00 000"))
        let accountFixture = try #require(try fixtureJSON("account-create-request") as? [String: Any])
        #expect(Set(account.keys) == Set(accountFixture.keys))
    }

    @Test func notificationUpdateEncodesQuietHoursAsAPair() throws {
        var update = NotificationSettingsUpdate()
        update.quiet = .init(from: nil, to: nil)
        let cleared = try object(update)
        #expect(cleared["quiet_from"] is NSNull && cleared["quiet_to"] is NSNull)
        #expect(cleared["channels"] == nil && cleared["utility_reminder_day"] == nil)

        var change = NotificationSettingsUpdate()
        change.quiet = .init(from: "21:30", to: "07:00")
        change.utilityReminderDay = 15
        change.channels = [NotificationChannelSetting(eventType: .utilityBillMissing, channel: .telegram, enabled: false)]
        let json = try object(change)
        let fixture = try #require(try fixtureJSON("settings-request") as? [String: Any])
        #expect(Set(json.keys).isSubset(of: Set(fixture.keys)))
        #expect(json["quiet_from"] as? String == "21:30")
        let channel = (json["channels"] as? [[String: Any]])?.first
        #expect(channel?["event_type"] as? String == "utility_bill_missing" && channel?["channel"] as? String == "telegram")
    }

    // MARK: Errors

    @Test func apiErrorsMapByCode() {
        func body(_ code: String, _ details: JSONValue? = nil) -> APIError {
            .server(status: 409, error: APIErrorBody(code: code, message: nil, details: details))
        }
        #expect(LiveUtilityBillsService.map(body("BILL_EXISTS", .object(["bill_id": .string("b1")]))) == .billExists(billId: "b1"))
        #expect(LiveUtilityBillsService.map(body("INVALID_STATE_TRANSITION")) == .invalidTransition)
        #expect(LiveUtilityBillsService.map(body("FILE_ALREADY_ATTACHED")) == .fileAlreadyAttached)
        #expect(LiveUtilityBillsService.map(body("ACCOUNT_NUMBER_IN_USE")) == .conflict(code: "ACCOUNT_NUMBER_IN_USE"))
        #expect(LiveUtilityBillsService.map(
            APIError.server(status: 422, error: APIErrorBody(code: "BILL_INCOMPLETE", message: nil, details: .object(["missing": .array([.string("items")])])))
        ) == .incomplete(missing: ["items"]))
        #expect(LiveUtilityBillsService.map(
            APIError.server(status: 429, error: APIErrorBody(code: "RECOGNITION_QUOTA_EXCEEDED", message: nil, details: .object(["limit": .number(50)])))
        ) == .quotaExceeded(limit: 50))
        #expect(LiveUtilityBillsService.map(APIError.server(status: 410, error: APIErrorBody(code: "GONE", message: nil, details: nil))) == .gone)
        #expect(LiveUtilityBillsService.map(APIError.httpStatus(404)) == .notFound)
        #expect(LiveUtilityBillsService.map(APIError.unauthorized) == .unauthorized)
    }

    @Test func validationErrorsKeepTheFieldAndReadInRussian() {
        let details = JSONValue.array([.object(["field": .string("items[1].service_type"), "message": .string("must be one of")])])
        let error = LiveUtilityBillsService.map(APIError.server(status: 400, error: APIErrorBody(code: "VALIDATION_ERROR", message: nil, details: details)))
        #expect(error == .validation(fields: [UtilityFieldError(field: "items[1].service_type", message: "must be one of")]))
        #expect(error.userMessage.contains("строки"))
        let incomplete = UtilityBillsError.incomplete(missing: ["property", "items"])
        #expect(incomplete.userMessage.contains("объект") && incomplete.userMessage.contains("строку"))
    }
}
