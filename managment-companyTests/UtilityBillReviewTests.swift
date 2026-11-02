//
//  UtilityBillReviewTests.swift
//  managment-companyTests
//
//  The review sheet of a utility bill (task U9): the buttons come from `available_actions` and the
//  payer, labels and hints come from the meta, edits become a PATCH of what changed, and every
//  command (confirm, mark paid with a file or without a receipt, unmark, delete, forward, re-read)
//  moves the bill the way the status machine of the API does.
//

import Foundation
import Testing
@testable import managment_company

private let reviewBillId = "b0000000-0000-4000-8000-000000000013"   // needs_review
private let missingBillId = "b0000000-0000-4000-8000-000000000014"  // missing
private let paidNoReceiptId = "b0000000-0000-4000-8000-000000000012"
private let tenantProperty = "7c1e4a52-3b1f-4d1c-9a55-0a1f6c1d2b01"

@MainActor
private func makeModel(
    _ id: String = reviewBillId,
    payer: UtilityPayer? = nil,
    mock: MockUtilityBillsService? = nil,
    rereadPollLimit: Int = 15,
    sleep: @escaping (Duration) async throws -> Void = { _ in }
) throws -> (UtilityBillReviewViewModel, MockUtilityBillsService) {
    let service = try mock ?? MockUtilityBillsService()
    let model = UtilityBillReviewViewModel(
        billId: id, service: service, payer: payer,
        today: { Date(timeIntervalSince1970: 1_793_620_800) },   // 2026-11-02 in Almaty
        rereadPollLimit: rereadPollLimit, sleep: sleep
    )
    return (model, service)
}

@MainActor
@Suite(.serialized)
struct UtilityBillReviewTests {
    // MARK: Buttons (Offers)

    @Test func needsReviewOffersConfirmAndForwardForATenantPayer() async throws {
        let (model, _) = try makeModel()
        await model.load()
        #expect(model.bill?.status == .needsReview)
        let offers = model.offers
        #expect(offers.canConfirm && offers.canEdit && offers.canReextract && offers.canDelete)
        #expect(offers.canForward)
        #expect(!offers.canMarkPaid && !offers.canUnmarkPaid && !offers.canUploadReceipt)
    }

    @Test func forwardButtonIsHiddenWhenTheOwnerPays() async throws {
        let (model, _) = try makeModel(payer: .owner)
        await model.load()
        #expect(model.offers.canConfirm)
        #expect(!model.offers.canForward)
    }

    @Test func payerIsResolvedFromTheProperty() async throws {
        let (model, _) = try makeModel()
        #expect(model.payer == nil)
        await model.load()
        #expect(model.payer == .tenant)
    }

    @Test func missingBillOffersUploadAndNoReceiptButNoProof() async throws {
        let (model, _) = try makeModel(missingBillId)
        await model.load()
        let offers = model.offers
        #expect(offers.canUploadReceipt && offers.canMarkPaid && !offers.allowsPaymentProof)
        #expect(!offers.canConfirm && !offers.canReextract)
    }

    @Test func paidWithoutReceiptOffersUnmarkOnly() async throws {
        let (model, _) = try makeModel(paidNoReceiptId)
        await model.load()
        let offers = model.offers
        #expect(offers.canUnmarkPaid && !offers.canMarkPaid && !offers.canConfirm && !offers.canDelete)
    }

    @Test func aButtonOutsideTheListIsNotShown() throws {
        var json = try UtilityFixtures.object(named: "bill-needs-review")
        json["available_actions"] = ["tenant_message"]
        let bill = try JSONDecoder().decode(UtilityBill.self, from: JSONSerialization.data(withJSONObject: json))
        let offers = UtilityBillOffers(bill: bill, payer: .tenant)
        #expect(offers.canForward)
        #expect(!offers.canConfirm && !offers.canEdit && !offers.canDelete && !offers.canReextract && !offers.canMarkPaid)
    }

    // MARK: Labels and hints from the meta

    @Test func labelsComeFromTheMeta() async throws {
        let (model, _) = try makeModel()
        await model.load()
        #expect(model.labels.statusLabel(.needsReview) == "Нужна проверка")
        #expect(model.labels.serviceLabel("gas_service") == "ВДГО (обслуживание газа)")
        #expect(model.labels.payerLabel(.owner) == "Владелец")
        // A code the meta does not know is shown as it is, never a label of the app.
        #expect(model.labels.serviceLabel("sauna") == "sauna")
    }

    @Test func reviewReasonsAreLocalisedFromTheMeta() async throws {
        let (model, _) = try makeModel()
        await model.load()
        let labels = model.labels
        #expect(labels.reasonText("sum_mismatch") == "Сумма строк не сходится с итогом")
        #expect(labels.reasonText("period_missing") == "Не найден период")
        #expect(labels.reasonText("item_invalid") == "Строка без суммы пропущена")
        #expect(labels.reasonText("amount_changed") == "Сумма изменилась после повторного распознавания")
        #expect(labels.reasonText("low_confidence") == "Низкая уверенность распознавания")
        // The two codes the catalogue does not list yet have a text of their own.
        #expect(labels.reasonText("period_mismatch") == "Период в документе отличается от выбранного")
        #expect(labels.reasonText("not_utility_document") == "Файл не похож на коммунальную квитанцию")
        // `<code>:<field>`: the label of the code and the field.
        #expect(labels.reasonText("low_confidence:provider") == "Низкая уверенность распознавания: поставщик")
        #expect(labels.reasonText("missing:total_due") == "Поле не найдено в документе: сумма к оплате")
        #expect(labels.reasonText("something_new") == "Проверьте данные документа")
    }

    @Test func hintsAreListedOnceAndAnEmptyListIsNotAConfirmation() async throws {
        let mock = try MockUtilityBillsService()
        mock.mutateBill(id: reviewBillId) { $0["review_reasons"] = ["low_confidence", "low_confidence:provider", "sum_mismatch", "sum_mismatch"] }
        let (model, _) = try makeModel(mock: mock)
        await model.load()
        #expect(model.reasonTexts.count == 3)
        let clean = try MockUtilityBillsService()
        clean.mutateBill(id: reviewBillId) { $0["review_reasons"] = [] }
        let (empty, _) = try makeModel(mock: clean)
        await empty.load()
        #expect(empty.reasonTexts.isEmpty)
        #expect(empty.offers.canConfirm)   // nothing confirms itself: the button is still the owner's
        #expect(empty.bill?.status == .needsReview)
    }

    // MARK: Confirm

    @Test func confirmMovesTheBillToConfirmedAndSignalsSuccess() async throws {
        let (model, service) = try makeModel()
        await model.load()
        let before = model.successSignal
        await model.confirm()
        #expect(model.bill?.status == .confirmed)
        #expect(model.successSignal == before + 1)
        #expect(service.confirmCalls == 1)
        #expect(model.offers.canMarkPaid && model.offers.allowsPaymentProof && !model.offers.canConfirm)
        #expect(model.didChange)
    }

    @Test func confirmOfAnInvoiceWithAPaymentDateGoesStraightToPaid() async throws {
        let mock = try MockUtilityBillsService()
        mock.mutateBill(id: reviewBillId) { $0["paid_at"] = "2026-03-20"; $0["paid_on_confirm"] = true }
        let (model, _) = try makeModel(mock: mock)
        await model.load()
        #expect(model.confirmPaysImmediately)
        await model.confirm()
        #expect(model.bill?.status == .paid)
        #expect(model.bill?.paidAt == "2026-03-20")
    }

    @Test func incompleteBillShowsWhatIsMissing() async throws {
        let mock = try MockUtilityBillsService()
        mock.mutateBill(id: reviewBillId) { $0["items"] = [[String: Any]](); $0["currency"] = NSNull() }
        let (model, _) = try makeModel(mock: mock)
        await model.load()
        let errors = model.errorSignal
        await model.confirm()
        #expect(model.bill?.status == .needsReview)
        #expect(model.message?.contains("строку") == true && model.message?.contains("валюту") == true)
        #expect(model.errorSignal == errors + 1)
    }

    // MARK: Paid

    @Test func markPaidWithAProofAttachesTheUploadedFile() async throws {
        let (model, service) = try makeModel()
        await model.load()
        await model.confirm()
        let proof = RecognitionUpload(data: Data("proof".utf8), fileName: "proof.jpg", mimeType: "image/jpeg")
        await model.markPaid(proof: proof, on: "2026-03-10")
        #expect(model.bill?.status == .paid)
        #expect(model.bill?.paidAt == "2026-03-10")
        #expect(model.bill?.paymentProofFile != nil)
        #expect(model.bill?.noReceipt == false)
        let sent = try #require(service.uploads.last)
        #expect(sent.target.billId == reviewBillId && sent.target.role == .paymentProof)
    }

    @Test func markPaidWithoutAReceiptIsOfferedForAMissingBill() async throws {
        let (model, _) = try makeModel(missingBillId)
        await model.load()
        await model.markPaidWithoutReceipt(on: "2026-04-12")
        #expect(model.bill?.status == .paid)
        #expect(model.bill?.noReceipt == true)
        #expect(model.bill?.paidBy == .tenant)
        #expect(model.offers.canUnmarkPaid)
    }

    @Test func aProofCannotBeAttachedBeforeTheBillIsConfirmed() async throws {
        let (model, service) = try makeModel()
        await model.load()
        await model.markPaid(proof: RecognitionUpload(data: Data("x".utf8), fileName: "p.jpg", mimeType: "image/jpeg"), on: "2026-03-10")
        #expect(service.uploads.isEmpty)
        #expect(model.bill?.status == .needsReview)
    }

    @Test func unmarkReturnsABillWithItemsToConfirmed() async throws {
        let (model, _) = try makeModel(paidNoReceiptId)
        await model.load()
        await model.unmarkPaid()
        #expect(model.bill?.status == .confirmed)
        #expect(model.bill?.noReceipt == false && model.bill?.paidAt == nil)
    }

    // MARK: Delete

    @Test func deleteRemovesTheBillAndMarksTheSheetForClosing() async throws {
        let (model, service) = try makeModel()
        await model.load()
        await model.delete()
        #expect(model.wasDeleted)
        await #expect(throws: UtilityBillsError.notFound) { _ = try await service.bill(id: reviewBillId) }
    }

    @Test func aPaidBillCannotBeDeleted() async throws {
        let (model, service) = try makeModel("b0000000-0000-4000-8000-000000000011")
        await model.load()
        #expect(!model.offers.canDelete)
        await model.delete()
        #expect(!model.wasDeleted)
        _ = try await service.bill(id: "b0000000-0000-4000-8000-000000000011")
    }

    // MARK: Forward to the tenant

    @Test func forwardFetchesTheTextForTheShareSheet() async throws {
        let (model, service) = try makeModel()
        await model.load()
        await model.forwardToTenant()
        guard case .tenantMessage(let message)? = model.prompt else {
            Issue.record("expected the tenant message prompt")
            return
        }
        #expect(message.text.contains("квитанцию"))
        #expect(message.utilityPayer == .tenant)
        #expect(service.tenantMessageCalls == 1)
    }

    @Test func forwardForAnOwnerPayedPropertyShowsNoShareSheet() async throws {
        // The sheet did not know the payer; the answer of the server settles it.
        let service = try MockUtilityBillsService()
        let create = UtilityBillCreate(
            propertyId: "7c1e4a52-3b1f-4d1c-9a55-0a1f6c1d2b02", period: "2026-06", currency: "KZT", total: Decimal(1000)
        )
        let bill = try await service.createBill(create)
        let (model, _) = try makeModel(bill.id, mock: service)
        await model.load()
        #expect(model.payer == .owner)       // resolved from the property
        #expect(!model.offers.canForward)
        await model.forwardToTenant()
        #expect(model.prompt == nil && service.tenantMessageCalls == 0)
    }

    // MARK: Editing

    @Test func editingStartsOnlyWhenTheServerOffersIt() async throws {
        let (model, _) = try makeModel()
        await model.load()
        model.startEditing()
        #expect(model.isEditing)
        #expect(model.draft?.lines.count == 10)
        model.cancelEditing()
        #expect(!model.isEditing)
    }

    @Test func anUntouchedDraftSendsNothing() async throws {
        let (model, _) = try makeModel()
        await model.load()
        model.startEditing()
        #expect(model.draft?.patch() == nil)
        #expect(model.draft?.isValid == true)
    }

    @Test func aChangedLineReplacesTheWholeSetAndKeepsTheRest() async throws {
        let (model, service) = try makeModel()
        await model.load()
        model.startEditing()
        model.draft?.lines[0].amountText = "1100,50"
        let patch = try #require(model.draft?.patch())
        #expect(patch.items?.count == 10)
        #expect(patch.items?[0].amount == Decimal(string: "1100.5"))
        #expect(patch.items?[1].amount == Decimal(string: "821.96"))
        #expect(patch.items?[0].tariff == Decimal(string: "8.5"))   // untouched recognised data goes back unchanged
        #expect(patch.providerName.isUnchanged && patch.period.isUnchanged)
        let saved = await model.saveEdits()
        #expect(saved && !model.isEditing)
        #expect(model.bill?.items.first?.amount == Decimal(string: "1100.5"))
        #expect(model.bill?.total == Decimal(string: "12065.32"))   // the server sums, the client does not
        _ = service
    }

    @Test func headerFieldsAreSentOnlyWhenChanged() async throws {
        let (model, _) = try makeModel()
        await model.load()
        model.startEditing()
        model.draft?.providerName = "Алматы Су"
        model.draft?.notes = "Проверено по оригиналу"
        model.draft?.period = "2026-02"
        let patch = try #require(model.draft?.patch())
        #expect(patch.providerName == .set("Алматы Су"))
        #expect(patch.notes == .set("Проверено по оригиналу"))
        #expect(patch.period == .set("2026-02"))
        #expect(patch.accountNumber.isUnchanged && patch.items == nil)
        model.draft?.accountNumber = ""
        #expect(model.draft?.patch()?.accountNumber == .clear)
    }

    @Test func aBadAmountBlocksTheSave() async throws {
        let (model, service) = try makeModel()
        await model.load()
        model.startEditing()
        model.draft?.lines[2].amountText = "12,345"
        #expect(model.draft?.errors["lines.2.amount"] != nil)
        let saved = await model.saveEdits()
        #expect(!saved && model.isEditing && model.message != nil)
        #expect(model.bill?.items[2].amount == Decimal(string: "2170.5"))
        _ = service
    }

    @Test func addedAndRemovedLinesAreTheNewSet() async throws {
        let (model, _) = try makeModel()
        await model.load()
        model.startEditing()
        model.draft?.removeLine(at: 9)
        model.addLine()
        let lastIndex = (model.draft?.lines.count ?? 1) - 1
        model.draft?.lines[lastIndex].serviceType = "internet"
        model.draft?.lines[lastIndex].amountText = "5000"
        let saved = await model.saveEdits()
        #expect(saved)
        #expect(model.bill?.items.count == 10)
        #expect(model.bill?.items.last?.serviceType == "internet")
        #expect(model.bill?.items.last?.amount == Decimal(5000))
    }

    // MARK: Re-reading

    @Test func rereadPollsAtMostTheLimitThenReloads() async throws {
        let mock = try MockUtilityBillsService()
        mock.uploadOutcome = .stalled
        var slept = 0
        let (model, service) = try makeModel(mock: mock, rereadPollLimit: 4) { _ in slept += 1 }
        await model.load()
        await model.reextract()
        #expect(service.stateCalls == 4)
        #expect(slept == 4)
        #expect(!model.isRereading)
        #expect(model.bill != nil)
    }

    // MARK: A stale screen

    @Test func aStaleScreenReloadsTheBillTheServerHasNow() async throws {
        let mock = try MockUtilityBillsService()
        let (model, service) = try makeModel(mock: mock)
        await model.load()
        _ = try await service.confirm(id: reviewBillId)   // done on another device
        await model.confirm()
        #expect(model.message == UtilityBillsError.invalidTransition.userMessage)
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.bill?.status == .confirmed)
    }
}
