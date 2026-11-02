//
//  SettleWizardTests.swift
//  managment-companyTests
//
//  Move-in wizard (task L14): the recognition contract decodes, its fields land in the form, the
//  review reasons are localised, the settle body matches the contract, the Idempotency-Key stays
//  the same across retries, and every error branch (409 IIN, 409 overlap, 422 identity, 429/502/503
//  recognition, offline) leads where the brief says. Services are the project's mocks.
//

import Foundation
import Testing
import UIKit
@testable import managment_company

private let propertyId = "5b8e0f37-2c19-4d7a-b6e4-1f3a9c7d2e50"
private let existingTenantId = "a52d7e19-0c64-4f1b-8e3a-9b7f2c6d4e21"
private let activeLeaseId = "7c1e2a40-5b3d-4f8e-9a61-2d4c8b1f0a01"

/// 2026-11-02 12:00 in the device calendar: the clock of the wizard in these tests.
private let testNow: Date = {
    Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12)) ?? Date()
}()

@MainActor
private struct Harness {
    let viewModel: SettleWizardViewModel
    let lease: MockLeaseV2Service
    let recognition: MockRecognitionService
    let contracts: MockContractService
    let network: StaticNetworkMonitor
}

@MainActor
private func makeHarness(
    context: SettleWizardContext = SettleWizardContext(),
    online: Bool = true,
    key: String = "fixed-key-1"
) throws -> Harness {
    let lease = try MockLeaseV2Service.fromFixtures()
    let recognition = MockRecognitionService()
    let contracts = MockContractService()
    let network = StaticNetworkMonitor(isOnline: online)
    let viewModel = SettleWizardViewModel(
        context: context,
        leaseService: lease,
        recognition: recognition,
        contracts: contracts,
        directory: MockSettleDirectory(),
        network: network,
        idempotencyKey: key,
        now: { testNow }
    )
    return Harness(viewModel: viewModel, lease: lease, recognition: recognition, contracts: contracts, network: network)
}

private final class FixedRecognition: RecognitionService {
    let result: IdentityRecognitionResult
    init(_ result: IdentityRecognitionResult) { self.result = result }
    func recognizeIdentityDocument(_ upload: RecognitionUpload, tenantId: String?) async throws -> IdentityRecognitionResult { result }
}

private let sampleUpload = RecognitionUpload(data: Data([0xFF, 0xD8, 0xFF, 0xD9]), fileName: "id.jpg", mimeType: "image/jpeg")

/// Fills what the steps need and walks to the contract step, ready to press «Заселить».
@MainActor
private func fillThroughContract(_ viewModel: SettleWizardViewModel) async {
    await viewModel.start()
    viewModel.selectedPropertyId = propertyId
    viewModel.go(to: .tenant)
    viewModel.setValue("Ерлан", for: .firstName)
    viewModel.setValue("Ахметов", for: .lastName)
    viewModel.setValue("900722304561", for: .iin)
    viewModel.rentText = "280000"
    viewModel.go(to: .contract)
}

private func jsonObject(_ request: SettleRequest) throws -> [String: Any] {
    let data = try JSONEncoder().encode(request)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    return try #require(object)
}

// MARK: - Contract decoding

@Suite struct RecognitionContractDecodingTests {
    @Test func contractAnswerDecodesEveryField() throws {
        let result = try MockRecognitionService.decode(MockRecognitionService.identityJSON)
        #expect(result.documentKind == .idCard)
        #expect(result.fileId == "2a6e9c1d-7f3b-4d8a-b5e0-4c1f8a3d9e67")
        #expect(result.status == "needs_review")
        #expect(result.fields.lastName == "Ахметов")
        #expect(result.fields.iin == "900722304561")
        #expect(result.fields.documentIssuedAt == "2019-08-14")
        #expect(result.fields.expiresAt == "2029-08-13")
        #expect(result.fields.sex == "male")
        #expect(result.fields.registrationAddress == nil)
        #expect(result.fieldConfidence["iin"] == 0.98)
        #expect(result.fieldConfidence["registration_address"] == 0.0)
        #expect(result.overallConfidence == 0.94)
        #expect(result.reviewReasons == ["missing:registration_address"])
        #expect(result.provider == "gemini")
        #expect(result.durationMs == 6400)
        #expect(result.isIdentityDocument)
    }

    @Test func datesAreAvailableAsDates() throws {
        let result = try MockRecognitionService.decode(MockRecognitionService.identityJSON)
        let issued = try #require(result.fields.documentIssuedAtDate)
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: issued)
        #expect(parts.year == 2019 && parts.month == 8 && parts.day == 14)
        #expect(result.fields.birthDateValue != nil)
        #expect(IdentityRecognitionFields().expiresAtDate == nil)
    }

    @Test func otherDocumentKindIsNotAnIdentityDocument() throws {
        let result = try MockRecognitionService.decode(MockRecognitionService.otherJSON)
        #expect(result.documentKind == .other)
        #expect(!result.isIdentityDocument)
        #expect(result.fields.firstName == nil)
        #expect(result.reviewReasons == ["not_identity_document"])
    }

    @Test func unknownKindFallsBackToOther() throws {
        let json = #"{"data":{"document_kind":"driver_license","fields":{}}}"#
        let result = try JSONDecoder().decode(APIResponse<IdentityRecognitionResult>.self, from: Data(json.utf8)).data
        #expect(result.documentKind == .other)
        #expect(result.fieldConfidence.isEmpty)
        #expect(result.reviewReasons.isEmpty)
    }

    @Test func anEmptyObjectDecodes() throws {
        let result = try JSONDecoder().decode(IdentityRecognitionResult.self, from: Data("{}".utf8))
        #expect(result.fileId == nil)
        #expect(result.fields == IdentityRecognitionFields())
    }
}

// MARK: - Review reasons and badges

@Suite struct ReviewReasonTests {
    @Test func codesAreLocalised() {
        #expect(RecognitionReviewReason(code: "not_identity_document") == .notIdentityDocument)
        #expect(RecognitionReviewReason(code: "iin_checksum_failed").text.contains("Контрольная сумма ИИН"))
        #expect(RecognitionReviewReason(code: "iin_birth_date_mismatch").text.contains("ИИН"))
        #expect(RecognitionReviewReason(code: "document_expired").text == "Срок действия документа истёк.")
        #expect(RecognitionReviewReason(code: "missing:registration_address").text == "Не найдено: адрес регистрации.")
        #expect(RecognitionReviewReason(code: "low_confidence:iin").text == "Плохо читается: ИИН. Проверьте значение.")
        #expect(RecognitionReviewReason(code: "low_confidence:document_issued_at") == .lowConfidence(field: "document_issued_at"))
        #expect(RecognitionReviewReason(code: "something_new") == .unknown(code: "something_new"))
    }

    @Test func reasonsPointAtFormFields() {
        #expect(RecognitionReviewReason(code: "missing:birth_date").field == .birthDate)
        #expect(RecognitionReviewReason(code: "iin_checksum_failed").field == .iin)
        #expect(RecognitionReviewReason(code: "document_expired").field == nil)
    }
}

// MARK: - Recognition to form

@MainActor
@Suite(.serialized) struct SettleRecognitionTests {
    @Test func recognitionFillsTheForm() async throws {
        let h = try makeHarness()
        await h.viewModel.recognize(sampleUpload)

        let vm = h.viewModel
        #expect(vm.recognitionState == .recognized)
        #expect(vm.form.lastName == "Ахметов")
        #expect(vm.form.firstName == "Ерлан")
        #expect(vm.form.middleName == "Серикович")
        #expect(vm.form.iin == "900722304561")
        #expect(vm.form.documentType == .idCard)
        #expect(vm.form.documentNumber == "052318774")
        #expect(vm.form.documentIssuedBy == "МВД РК")
        #expect(vm.form.documentIssuedAt == "2019-08-14")
        #expect(vm.form.birthDate == "1990-07-22")
        #expect(vm.form.registrationAddress.isEmpty)
        #expect(vm.identityFileId == "2a6e9c1d-7f3b-4d8a-b5e0-4c1f8a3d9e67")
        #expect(vm.reviewReasons == [.missing(field: "registration_address")])
        #expect(vm.overallConfidence == 0.94)
        #expect(h.recognition.calls.count == 1)
        #expect(h.recognition.calls[0].tenantId == nil)
    }

    @Test func emptyRequiredFieldIsMissingAfterRecognition() async throws {
        let h = try makeHarness()
        #expect(h.viewModel.badge(for: .registrationAddress) == .none)  // nothing recognised yet: no noise
        await h.viewModel.recognize(sampleUpload)
        #expect(h.viewModel.badge(for: .registrationAddress) == .missing)
        #expect(h.viewModel.badge(for: .phone) == .none)
        #expect(h.viewModel.badge(for: .iin) == .none)
    }

    @Test func lowConfidenceFieldIsFlaggedUntilTheOwnerEditsIt() async throws {
        // A poor photo: the contract sample with the IIN read at 0.55.
        let low = try MockRecognitionService.decode(
            MockRecognitionService.identityJSON.replacingOccurrences(of: "\"iin\":0.98", with: "\"iin\":0.55")
        )
        let vm = SettleWizardViewModel(
            leaseService: try MockLeaseV2Service.fromFixtures(),
            recognition: FixedRecognition(low),
            contracts: MockContractService(),
            directory: MockSettleDirectory(),
            network: StaticNetworkMonitor(),
            now: { testNow }
        )
        await vm.recognize(sampleUpload)
        #expect(vm.badge(for: .iin) == .lowConfidence(percent: 55))
        #expect(vm.badge(for: .lastName) == .none)
        vm.setValue("900722304561", for: .iin)
        #expect(vm.badge(for: .iin) == .none)
    }

    @Test func notAnIdentityDocumentFillsNothing() async throws {
        let h = try makeHarness()
        h.recognition.outcome = .notIdentityDocument
        await h.viewModel.recognize(sampleUpload)

        #expect(h.viewModel.recognitionState == .notIdentityDocument)
        #expect(h.viewModel.form.firstName.isEmpty)
        #expect(h.viewModel.identityFileId == nil)
        #expect(h.viewModel.reviewReasons == [.notIdentityDocument])
    }

    @Test func unavailableKeepsTheSavedFileForSettle() async throws {
        let h = try makeHarness()
        h.recognition.outcome = .failure(.unavailable(fileId: "saved-file-id", extractionId: "x"))
        await h.viewModel.recognize(sampleUpload)

        #expect(h.viewModel.recognitionState == .failed(.unavailable(fileId: "saved-file-id", extractionId: "x")))
        #expect(h.viewModel.identityFileId == "saved-file-id")
        h.viewModel.continueManually()
        #expect(h.viewModel.recognitionState == .idle)
        #expect(h.viewModel.identityFileId == "saved-file-id")

        await fillThroughContract(h.viewModel)
        #expect(h.viewModel.buildRequest()?.identityDocumentFileId == "saved-file-id")
    }

    @Test func quotaAndDisabledOfferManualEntry() {
        #expect(RecognitionError.quotaExceeded.offersManualEntry)
        #expect(RecognitionError.disabled.offersManualEntry)
        #expect(RecognitionError.unavailable(fileId: nil, extractionId: nil).offersManualEntry)
        #expect(!RecognitionError.validation(message: "x").offersManualEntry)
        #expect(RecognitionError.quotaExceeded.userMessage.contains("лимит"))
    }

    @Test func oversizedFileIsRejectedBeforeTheUpload() async throws {
        let h = try makeHarness()
        let big = RecognitionUpload(data: Data(count: RecognitionUpload.maxBytes + 1), fileName: "big.jpg", mimeType: "image/jpeg")
        await h.viewModel.recognize(big)
        guard case .failed(.validation(let message)) = h.viewModel.recognitionState else {
            Issue.record("expected a validation failure")
            return
        }
        #expect(message.contains("10 МБ"))
        #expect(h.recognition.calls.isEmpty)
    }

    @Test func offlineStopsTheRecognition() async throws {
        let h = try makeHarness(online: false)
        await h.viewModel.start()
        await h.viewModel.recognize(sampleUpload)
        #expect(h.viewModel.recognitionState == .failed(.transport))
        #expect(h.recognition.calls.isEmpty)
    }
}

// MARK: - Settle body

@MainActor
@Suite(.serialized) struct SettleRequestTests {
    @Test func bodyMatchesTheContractForANewTenantSignedOnPaper() async throws {
        let h = try makeHarness()
        await h.viewModel.recognize(sampleUpload)
        await fillThroughContract(h.viewModel)
        h.viewModel.setValue("г. Алматы, ул. Розыбакиева, 247, кв. 15", for: .registrationAddress)
        let request = try #require(h.viewModel.buildRequest())
        let json = try jsonObject(request)

        #expect(json["property_id"] as? String == propertyId)
        #expect(json["generate_contract"] as? Bool == false)
        #expect(json["source"] as? String == "ios")
        #expect(json["signed_on"] as? String == LeaseDay.string(fromPicker: testNow))
        #expect(json["activate"] as? Bool == true)
        #expect(json["send_for_signature"] == nil)
        #expect(json["tenant_id"] == nil)
        #expect(json["replaces_lease_id"] == nil)
        #expect(json["identity_document_file_id"] as? String == "2a6e9c1d-7f3b-4d8a-b5e0-4c1f8a3d9e67")

        let tenant = try #require(json["tenant"] as? [String: Any])
        #expect(tenant["first_name"] as? String == "Ерлан")
        #expect(tenant["document_type"] as? String == "id_card")
        #expect(tenant["registration_address"] as? String == "г. Алматы, ул. Розыбакиева, 247, кв. 15")
        #expect(tenant["phone"] == nil)

        let lease = try #require(json["lease"] as? [String: Any])
        #expect(lease["start_date"] as? String == "2026-11-02")
        #expect(lease["term_months"] as? Int == 12)
        #expect(lease["end_date"] == nil)
        #expect(lease["rent_amount"] as? Int == 280000)
        #expect(lease["rent_currency"] as? String == "KZT")
        #expect(lease["deposit_amount"] as? Int == 280000)
        #expect(lease["due_day"] as? Int == 2)
        #expect(lease["utilities_paid_by"] as? String == "tenant")
    }

    @Test func bodyKeysExistInTheContractFixture() async throws {
        let h = try makeHarness()
        await fillThroughContract(h.viewModel)
        h.viewModel.notes = "Без животных"
        let request = try #require(h.viewModel.buildRequest())
        let json = try jsonObject(request)
        let fixtureObject = try JSONSerialization.jsonObject(with: LeaseV2Fixtures.data(named: "settle-request")) as? [String: Any]
        let fixture = try #require(fixtureObject)
        // Spec §9.7 adds `signed_on`, `activate`, `activation_date`, `confirm` and `source` to the fixture's keys.
        let documented = Set(fixture.keys).union(["signed_on", "activate", "activation_date", "confirm", "source"])
        #expect(Set(json.keys).isSubset(of: documented))
        let lease = try #require(json["lease"] as? [String: Any])
        let fixtureLease = try #require(fixture["lease"] as? [String: Any])
        // `term_months` is the documented alternative to the fixture's `end_date`.
        #expect(Set(lease.keys).subtracting(["term_months"]).isSubset(of: Set(fixtureLease.keys)))
        let tenant = try #require(json["tenant"] as? [String: Any])
        let fixtureTenant = try #require(fixture["tenant"] as? [String: Any])
        #expect(Set(tenant.keys).isSubset(of: Set(fixtureTenant.keys)))
    }

    @Test func existingTenantGoesByIdOnly() async throws {
        let h = try makeHarness(context: .tenant(existingTenantId))
        await h.viewModel.start()
        h.viewModel.selectedPropertyId = propertyId
        h.viewModel.rentText = "250000"
        let json = try jsonObject(try #require(h.viewModel.buildRequest()))
        #expect(json["tenant_id"] as? String == existingTenantId)
        #expect(json["tenant"] == nil)
        #expect(json["identity_document_file_id"] == nil)
    }

    @Test func sendForSignatureAndDraftVariants() async throws {
        let h = try makeHarness()
        await fillThroughContract(h.viewModel)
        h.viewModel.signedOnPaper = false
        var json = try jsonObject(try #require(h.viewModel.buildRequest()))
        #expect(json["send_for_signature"] as? Bool == true)
        #expect(json["signed_on"] == nil)
        #expect(json["activate"] == nil)

        h.viewModel.sendForSignature = false
        json = try jsonObject(try #require(h.viewModel.buildRequest()))
        #expect(json["send_for_signature"] == nil)
        #expect(h.viewModel.outcomeSummary == "Договор останется черновиком.")

        h.viewModel.signedOnPaper = true
        h.viewModel.activateFromStart = false
        json = try jsonObject(try #require(h.viewModel.buildRequest()))
        #expect(json["signed_on"] != nil)
        #expect(json["activate"] == nil)
    }

    @Test func endDateModeSendsEndDateInsteadOfTermMonths() async throws {
        let h = try makeHarness()
        await fillThroughContract(h.viewModel)
        h.viewModel.termMode = .endDate
        // Switching carries the 12 months over: 2026-11-02 + 12 months - 1 day.
        #expect(LeaseDay.string(fromPicker: h.viewModel.endDate) == "2027-11-01")
        let body = try jsonObject(try #require(h.viewModel.buildRequest()))
        let lease = try #require(body["lease"] as? [String: Any])
        #expect(lease["end_date"] as? String == "2027-11-01")
        #expect(lease["term_months"] == nil)
    }

    @Test func replacementCarriesTheReplacedLease() async throws {
        let aggregate = try LeaseV2Fixtures.aggregate(named: LeaseV2Fixtures.activeName)
        let context = SettleWizardContext.replacing(aggregate)
        #expect(context.replacesLeaseId == aggregate.id)
        #expect(context.propertyId == aggregate.propertyId)
        #expect(context.tenantId == aggregate.tenantId)
        #expect(context.locksProperty && context.locksTenant)
        #expect(context.initialStep == .terms)

        let h = try makeHarness(context: context)
        let vm = h.viewModel
        #expect(vm.step == .terms)
        #expect(vm.tenantMode == .existing)
        #expect(vm.rentAmount == aggregate.currentRentAmount.major)
        #expect(!vm.canGoBack || vm.step.previous != .property)
        let json = try jsonObject(try #require(vm.buildRequest()))
        #expect(json["replaces_lease_id"] as? String == aggregate.id)
        #expect(json["tenant_id"] as? String == aggregate.tenantId)
    }

    @Test func initialStepFollowsTheEntryPoint() {
        #expect(SettleWizardContext().initialStep == .property)
        #expect(SettleWizardContext.property("p").initialStep == .tenant)
        #expect(SettleWizardContext.tenant("t").initialStep == .property)
    }
}

// MARK: - Terms and steps

@MainActor
@Suite(.serialized) struct SettleStepsTests {
    @Test func depositFollowsRentUntilEdited() throws {
        let vm = try makeHarness().viewModel
        vm.rentText = "300000"
        #expect(vm.depositText == "300000")
        vm.editDeposit("150000")
        vm.rentText = "320000"
        #expect(vm.depositText == "150000")
        #expect(vm.depositAmount == 150000)
    }

    @Test func dueDayFollowsStartDateUntilEdited() throws {
        let vm = try makeHarness().viewModel
        #expect(vm.dueDay == 2)
        vm.startDate = LeaseDay.pickerDate("2026-11-17") ?? testNow
        #expect(vm.dueDay == 17)
        vm.editDueDay(5)
        vm.startDate = LeaseDay.pickerDate("2026-11-20") ?? testNow
        #expect(vm.dueDay == 5)
    }

    @Test func termsValidation() throws {
        let vm = try makeHarness().viewModel
        #expect(vm.termsError == "Укажите сумму аренды.")
        vm.rentText = "280 000"
        #expect(vm.termsError == nil)
        #expect(vm.rentAmount == 280000)
        vm.termMonthsText = "0"
        #expect(vm.termsError != nil)
        vm.termMonthsText = "121"
        #expect(vm.termsError != nil)
        vm.termMonthsText = "6"
        #expect(vm.termsError == nil)
        #expect(vm.endDay == "2027-05-01")
        vm.editDeposit("abc")
        #expect(vm.termsError?.hasPrefix("Депозит") == true)
        vm.editDeposit("")
        #expect(vm.depositAmount == nil && vm.termsError == nil)
        vm.termMode = .endDate
        vm.endDate = vm.startDate
        #expect(vm.termsError == "Дата окончания должна быть позже даты заезда.")
    }

    @Test func contractStepRejectsFutureSignatureAndFarActivation() throws {
        let vm = try makeHarness().viewModel
        #expect(vm.contractError == nil)
        vm.signedOnDate = LeaseDay.pickerDate("2026-11-05") ?? testNow
        #expect(vm.contractError == "Дата подписания не может быть в будущем.")
        vm.signedOnDate = testNow
        vm.startDate = LeaseDay.pickerDate("2027-02-01") ?? testNow
        #expect(vm.contractError?.contains("30 дней") == true)
        vm.activateFromStart = false
        #expect(vm.contractError == nil)
    }

    @Test func tenantStepNeedsAFirstNameAndAWellFormedIIN() async throws {
        let vm = try makeHarness().viewModel
        await vm.start()
        vm.go(to: .tenant)
        #expect(!vm.canAdvance)
        vm.setValue("Ерлан", for: .firstName)
        #expect(vm.canAdvance)
        vm.setValue("12345", for: .iin)
        #expect(!vm.canAdvance)
        #expect(vm.iinFormatWarning == "ИИН состоит из 12 цифр.")
        vm.setValue("900722304561", for: .iin)
        #expect(vm.canAdvance)
        vm.tenantMode = .existing
        #expect(!vm.canAdvance)
        vm.selectedTenantId = existingTenantId
        #expect(vm.canAdvance)
    }

    @Test func freePropertiesFirstOccupiedOnRequest() async throws {
        let vm = try makeHarness().viewModel
        await vm.start()
        #expect(vm.directoryState == .loaded)
        #expect(vm.selectableProperties.map(\.name) == ["Студия на Абая, 15", "ул. Байзакова, 280, кв. 12"])
        #expect(vm.hiddenOccupiedCount == 1)
        vm.showOccupied = true
        #expect(vm.selectableProperties.count == 3)
        #expect(vm.selectableProperties.last?.status == "occupied")
    }

    @Test func existingTenantSearchByNameIINAndPhone() async throws {
        let vm = try makeHarness().viewModel
        await vm.start()
        vm.tenantQuery = "касым"
        #expect(vm.filteredTenants.map(\.id) == [existingTenantId])
        vm.tenantQuery = "880114"
        #expect(vm.filteredTenants.map(\.firstName) == ["Данияр"])
        vm.tenantQuery = "+7 701 555"
        #expect(vm.filteredTenants.map(\.id) == [existingTenantId])
        vm.tenantQuery = "нет такого"
        #expect(vm.filteredTenants.isEmpty)
    }

    @Test func advanceAndBackWalkTheSteps() async throws {
        let vm = try makeHarness().viewModel
        await vm.start()
        #expect(vm.step == .property)
        #expect(!vm.canAdvance)
        vm.selectedPropertyId = propertyId
        vm.advance()
        #expect(vm.step == .tenant)
        vm.back()
        #expect(vm.step == .property)
        #expect(!vm.canGoBack)
    }

    @Test func offlineBlocksAdvance() async throws {
        let h = try makeHarness(online: false)
        await h.viewModel.start()
        h.viewModel.selectedPropertyId = propertyId
        #expect(!h.viewModel.isOnline)
        #expect(!h.viewModel.canAdvance)
        h.network.set(online: true)
        #expect(h.viewModel.isOnline && h.viewModel.canAdvance)
    }
}

// MARK: - Settle, idempotency, errors

@MainActor
@Suite(.serialized) struct SettleSubmitTests {
    @Test func successSettlesThenBuildsTheContract() async throws {
        let h = try makeHarness()
        await fillThroughContract(h.viewModel)
        var settled: SettleResponse?
        h.viewModel.onSettled = { settled = $0 }

        h.viewModel.advance()
        await h.viewModel.submitTask?.value

        #expect(h.viewModel.step == .done)
        #expect(h.viewModel.submitState == .settled)
        #expect(h.viewModel.contractState == .ready)
        #expect(h.viewModel.successSignal == 1)
        #expect(settled?.lease.status == .active)
        #expect(settled?.lease.rentAmount.major == 280000)
        #expect(settled?.tenantCreated == true)
        #expect(h.lease.settleCalls.count == 1)
        #expect(h.contracts.generateCalls.count == 1)
        #expect(h.contracts.generateCalls[0].formats == [.pdf, .docx])
        let context = try #require(h.viewModel.contractContext)
        #expect(context.leaseId == settled?.lease.id)
        #expect(!h.viewModel.canGoBack)
        // The new lease is reachable on the same mock service the lease screen uses.
        _ = try await h.lease.fetchLease(id: context.leaseId)
    }

    @Test func idempotencyKeyIsFixedAndSurvivesARetryAfterANetworkFailure() async throws {
        let h = try makeHarness(key: "wizard-key")
        await fillThroughContract(h.viewModel)
        #expect(h.viewModel.idempotencyKey == "wizard-key")

        h.lease.failNextSettle = .other(.transport)
        h.viewModel.advance()
        await h.viewModel.submitTask?.value
        #expect(h.viewModel.submitState == .failed(LeaseV2Error.transport.userMessage))
        #expect(h.viewModel.settleResponse == nil)

        await h.viewModel.submit()
        #expect(h.viewModel.submitState == .settled)
        #expect(h.lease.settleCalls.map(\.idempotencyKey) == ["wizard-key", "wizard-key"])
        #expect(h.lease.settleCalls[0].request == h.lease.settleCalls[1].request)
    }

    @Test func eachWizardOpeningGetsItsOwnKey() throws {
        func make() throws -> SettleWizardViewModel {
            SettleWizardViewModel(
                leaseService: try MockLeaseV2Service.fromFixtures(),
                recognition: MockRecognitionService(),
                contracts: MockContractService(),
                directory: MockSettleDirectory(),
                network: StaticNetworkMonitor()
            )
        }
        let first = try make()
        let second = try make()
        #expect(!first.idempotencyKey.isEmpty)
        #expect(first.idempotencyKey != second.idempotencyKey)
    }

    @Test func aFailedContractDoesNotSettleTwice() async throws {
        let h = try makeHarness()
        h.contracts.generateOutcome = .failure(.pdfFailed)
        await fillThroughContract(h.viewModel)
        h.viewModel.advance()
        await h.viewModel.submitTask?.value

        #expect(h.viewModel.submitState == .settled)
        #expect(h.viewModel.contractState == .failed(ContractServiceError.pdfFailed.userMessage))

        h.contracts.generateOutcome = .success
        await h.viewModel.retryContract()
        #expect(h.viewModel.contractState == .ready)
        #expect(h.lease.settleCalls.count == 1)
        #expect(h.contracts.generateCalls.count == 2)
        #expect(h.contracts.generateCalls[0].idempotencyKey == h.contracts.generateCalls[1].idempotencyKey)
    }

    @Test func incompleteContractDataIsExplainedNotFatal() async throws {
        let h = try makeHarness()
        h.contracts.generateOutcome = .failure(.incomplete([]))
        await fillThroughContract(h.viewModel)
        h.viewModel.advance()
        await h.viewModel.submitTask?.value
        guard case .failed(let message) = h.viewModel.contractState else {
            Issue.record("expected a contract failure")
            return
        }
        #expect(message.contains("не хватает данных"))
        #expect(h.viewModel.submitState == .settled)
    }

    @Test func offlineNeverCallsSettle() async throws {
        let h = try makeHarness(online: false)
        await fillThroughContract(h.viewModel)
        await h.viewModel.submit()
        #expect(h.lease.settleCalls.isEmpty)
        guard case .failed(let message) = h.viewModel.submitState else {
            Issue.record("expected an offline failure")
            return
        }
        #expect(message.contains("Нет сети"))
    }

    @Test func iinConflictOffersTheStoredTenantOrAFix() async throws {
        let h = try makeHarness()
        await fillThroughContract(h.viewModel)
        let stored = try #require(MockSettleDirectory.sampleTenants.first)
        let storedTenant = SettleTenant(
            id: stored.id, firstName: stored.firstName, lastName: stored.lastName, middleName: stored.middleName,
            phone: stored.phone, email: nil, cohabitants: nil, notes: nil, iin: stored.iin,
            documentType: nil, documentNumber: nil, documentIssuedBy: nil, documentIssuedAt: nil,
            birthDate: nil, registrationAddress: nil
        )
        h.lease.failNextSettle = .tenantIINConflict(stored: storedTenant, provided: SettleProvidedName(firstName: "Ерлан", lastName: "Ахметов", middleName: nil))
        h.viewModel.advance()
        await h.viewModel.submitTask?.value

        #expect(h.viewModel.step == .tenant)
        #expect(h.viewModel.highlightedFields == [.iin])
        #expect(h.viewModel.alert == .iinConflict(stored: storedTenant, providedName: "Ахметов Ерлан"))
        #expect(h.viewModel.settleResponse == nil)

        // «Исправить»: back to the IIN, nothing else changes.
        h.viewModel.fixIIN()
        #expect(h.viewModel.alert == nil && h.viewModel.step == .tenant && h.viewModel.tenantMode == .new)

        // «Использовать существующего»: the stored tenant replaces the form, wizard returns to the contract step.
        h.lease.failNextSettle = .tenantIINConflict(stored: storedTenant, provided: nil)
        h.viewModel.go(to: .contract)
        h.viewModel.advance()
        await h.viewModel.submitTask?.value
        h.viewModel.useStoredTenant()
        #expect(h.viewModel.tenantMode == .existing)
        #expect(h.viewModel.selectedTenantId == stored.id)
        #expect(h.viewModel.step == .contract)
        #expect(h.viewModel.highlightedFields.isEmpty)

        h.viewModel.advance()
        await h.viewModel.submitTask?.value
        #expect(h.viewModel.submitState == .settled)
        let sent = try #require(h.lease.settleCalls.last?.request)
        #expect(sent.tenantId == stored.id && sent.tenant == nil)
        #expect(Set(h.lease.settleCalls.map(\.idempotencyKey)).count == 1)
    }

    @Test func leaseOverlapOffersTheConflictingLease() async throws {
        let h = try makeHarness()
        await fillThroughContract(h.viewModel)
        h.lease.failNextSettle = .leaseOverlap(conflictingLeaseId: activeLeaseId, from: "2026-01-01", to: "2026-12-31")
        h.viewModel.advance()
        await h.viewModel.submitTask?.value

        #expect(h.viewModel.step == .terms)
        guard case .leaseOverlap(let id, let range)? = h.viewModel.alert else {
            Issue.record("expected the overlap alert")
            return
        }
        #expect(id == activeLeaseId)
        #expect(range?.contains("2026") == true)

        h.viewModel.openConflictingLease()
        #expect(h.viewModel.alert == nil)
        #expect(h.viewModel.navigationTarget == .lease(activeLeaseId))
    }

    @Test func overlapWithoutAnIdOnlyOffersToChangeDates() async throws {
        let h = try makeHarness()
        await fillThroughContract(h.viewModel)
        h.lease.failNextSettle = .leaseOverlap(conflictingLeaseId: nil, from: nil, to: nil)
        h.viewModel.advance()
        await h.viewModel.submitTask?.value
        h.viewModel.openConflictingLease()
        #expect(h.viewModel.navigationTarget == nil)
        h.viewModel.go(to: .contract)
        h.lease.failNextSettle = .leaseOverlap(conflictingLeaseId: nil, from: nil, to: nil)
        h.viewModel.advance()
        await h.viewModel.submitTask?.value
        h.viewModel.dismissOverlapToTerms()
        #expect(h.viewModel.step == .terms && h.viewModel.alert == nil)
    }

    @Test func incompleteIdentityHighlightsTheNamedFields() async throws {
        let h = try makeHarness()
        await fillThroughContract(h.viewModel)
        h.lease.failNextSettle = .identityIncomplete(missing: ["last_name", "tenant.birth_date", "iin"])
        h.viewModel.advance()
        await h.viewModel.submitTask?.value

        #expect(h.viewModel.step == .tenant)
        #expect(h.viewModel.highlightedFields == [.lastName, .birthDate, .iin])
        #expect(h.viewModel.banner?.contains("Фамилия") == true)
        #expect(h.viewModel.isHighlighted(.birthDate))
        h.viewModel.setValue("1990-07-22", for: .birthDate)
        #expect(!h.viewModel.isHighlighted(.birthDate))
    }

    @Test func validationErrorsLeadToTheStepOfTheField() async throws {
        let h = try makeHarness()
        await fillThroughContract(h.viewModel)
        h.lease.failNextSettle = .validation(fields: [SettleFieldError(field: "lease.rent_amount", message: "must be positive")])
        h.viewModel.advance()
        await h.viewModel.submitTask?.value
        #expect(h.viewModel.step == .terms)
        #expect(h.viewModel.banner == "must be positive")

        h.viewModel.go(to: .contract)
        h.lease.failNextSettle = .validation(fields: [SettleFieldError(field: "tenant.iin", message: "bad iin")])
        h.viewModel.advance()
        await h.viewModel.submitTask?.value
        #expect(h.viewModel.step == .tenant)
        #expect(h.viewModel.highlightedFields == [.iin])
    }

    @Test func otherFailuresStayOnTheResultStepWithARetry() async throws {
        let h = try makeHarness()
        await fillThroughContract(h.viewModel)
        h.lease.failNextSettle = .other(.unauthorized)
        h.viewModel.advance()
        await h.viewModel.submitTask?.value
        #expect(h.viewModel.step == .done)
        #expect(h.viewModel.submitState == .failed(LeaseV2Error.unauthorized.userMessage))
        #expect(h.viewModel.errorSignal == 1)
    }

    @Test func mockSettleReplaysTheSameKeyAndRejectsAnotherBody() async throws {
        let h = try makeHarness()
        await fillThroughContract(h.viewModel)
        let request = try #require(h.viewModel.buildRequest())
        let first = try await h.lease.settle(request, idempotencyKey: "k")
        let again = try await h.lease.settle(request, idempotencyKey: "k")
        #expect(first.lease.id == again.lease.id)

        var other = request
        other.lease.rentAmount = 1
        await #expect(throws: SettleError.other(.idempotencyKeyReused)) {
            _ = try await h.lease.settle(other, idempotencyKey: "k")
        }
    }
}

// MARK: - Live error mapping and uploads

@Suite struct SettleErrorMappingTests {
    private func apiError(_ status: Int, _ body: String) -> APIError {
        APIError.make(status: status, body: Data(body.utf8), typed: true)
    }

    @Test func settleCodesMapToSettleErrors() {
        let conflict = apiError(409, #"{"error":{"code":"TENANT_IIN_CONFLICT","message":"m","details":{"tenant":{"id":"t1","first_name":"Айгерим","last_name":"Касымова","iin":"950312401236"},"provided":{"first_name":"Ерлан","last_name":"Ахметов","middle_name":null}}}}"#)
        guard case .tenantIINConflict(let stored, let provided) = LiveLeaseV2Service.mapSettle(conflict) else {
            Issue.record("expected TENANT_IIN_CONFLICT")
            return
        }
        #expect(stored?.id == "t1" && stored?.lastName == "Касымова")
        #expect(provided?.fullName == "Ахметов Ерлан")

        let overlap = apiError(409, #"{"error":{"code":"LEASE_OVERLAP","message":"m","details":{"conflicting_lease_id":"l1","conflicting_range":{"from":"2026-01-01","to":"2026-12-31"}}}}"#)
        #expect(LiveLeaseV2Service.mapSettle(overlap) == .leaseOverlap(conflictingLeaseId: "l1", from: "2026-01-01", to: "2026-12-31"))

        let incomplete = apiError(422, #"{"error":{"code":"TENANT_IDENTITY_INCOMPLETE","message":"m","details":{"missing":["last_name","iin"]}}}"#)
        #expect(LiveLeaseV2Service.mapSettle(incomplete) == .identityIncomplete(missing: ["last_name", "iin"]))

        let validation = apiError(400, #"{"error":{"code":"VALIDATION_ERROR","message":"m","details":[{"field":"tenant.iin","message":"bad"}]}}"#)
        #expect(LiveLeaseV2Service.mapSettle(validation) == .validation(fields: [SettleFieldError(field: "tenant.iin", message: "bad")]))

        let replace = apiError(422, #"{"error":{"code":"REPLACE_TARGET_INVALID","message":"m"}}"#)
        #expect(LiveLeaseV2Service.mapSettle(replace) == .replaceTargetInvalid)

        #expect(LiveLeaseV2Service.mapSettle(apiError(422, #"{"error":{"code":"IDEMPOTENCY_KEY_REUSED","message":"m"}}"#)) == .other(.idempotencyKeyReused))
        #expect(LiveLeaseV2Service.mapSettle(URLError(.notConnectedToInternet)) == .other(.transport))
    }

    @Test func recognitionCodesMapToRecognitionErrors() {
        let unavailable = apiError(502, #"{"error":{"code":"RECOGNITION_UNAVAILABLE","message":"m","details":{"extraction_id":"e1","file_id":"f1"}}}"#)
        #expect(LiveRecognitionService.map(unavailable) == .unavailable(fileId: "f1", extractionId: "e1"))
        #expect(LiveRecognitionService.map(apiError(429, #"{"error":{"code":"RECOGNITION_QUOTA_EXCEEDED","message":"m"}}"#)) == .quotaExceeded)
        #expect(LiveRecognitionService.map(apiError(503, #"{"error":{"code":"RECOGNITION_DISABLED","message":"m"}}"#)) == .disabled)
        #expect(LiveRecognitionService.map(APIError.httpStatus(502)) == .unavailable(fileId: nil, extractionId: nil))
        #expect(LiveRecognitionService.map(APIError.httpStatus(429)) == .quotaExceeded)
        #expect(LiveRecognitionService.map(apiError(404, #"{"error":{"code":"NOT_FOUND","message":"m"}}"#)) == .notFound)
        let invalid = LiveRecognitionService.map(apiError(400, #"{"error":{"code":"VALIDATION_ERROR","message":"m","details":[{"field":"file","message":"unsupported type"}]}}"#))
        #expect(invalid == .validation(message: "Файл не подошёл: unsupported type"))
        #expect(LiveRecognitionService.map(URLError(.timedOut)) == .transport)
        #expect(LiveRecognitionService.map(APIError.unauthorized) == .unauthorized)
    }

    @Test func uploadBuilderKeepsPDFsAndTurnsImagesIntoJPEG() throws {
        let pdf = Data("%PDF-1.4 test".utf8)
        let pdfUpload = try #require(RecognitionUploadBuilder.upload(fromData: pdf, fileName: "scan.PDF"))
        #expect(pdfUpload.mimeType == "application/pdf" && pdfUpload.data == pdf && pdfUpload.fileName == "scan.PDF")

        let image = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000))
        }
        let png = try #require(image.pngData())
        let jpeg = try #require(RecognitionUploadBuilder.upload(fromData: png, fileName: "card.png"))
        #expect(jpeg.mimeType == "image/jpeg" && jpeg.fileName == "card.jpg")
        let decoded = try #require(UIImage(data: jpeg.data))
        #expect(max(decoded.size.width, decoded.size.height) <= RecognitionUploadBuilder.maxDimension)
        #expect(jpeg.data.count <= RecognitionUpload.maxBytes)

        #expect(RecognitionUploadBuilder.upload(fromData: Data("not an image".utf8), fileName: nil) == nil)
    }
}
