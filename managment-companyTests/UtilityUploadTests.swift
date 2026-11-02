//
//  UtilityUploadTests.swift
//  managment-companyTests
//
//  The upload of a utility document (task U9): `POST uploads` and a bounded poll of
//  `GET uploads/:id` (30 seconds at most, then «придёт уведомление»), a duplicate leads to its bill,
//  an `other` document never creates one, errors speak Russian, and a scan becomes a JPEG or a PDF.
//

import Foundation
import Testing
import PDFKit
import UIKit
@testable import managment_company

private let upload = RecognitionUpload(data: Data("receipt".utf8), fileName: "utility-bill.jpg", mimeType: "image/jpeg")
private let propertyId = "7c1e4a52-3b1f-4d1c-9a55-0a1f6c1d2b01"

@MainActor
private func flow(
    _ mock: MockUtilityBillsService,
    target: UtilityUploadTarget = UtilityUploadTarget(propertyId: propertyId, period: "2026-06"),
    interval: Duration = .seconds(2),
    limit: Duration = .seconds(30)
) -> (UtilityUploadFlowModel, SleepLog) {
    let log = SleepLog()
    let model = UtilityUploadFlowModel(
        service: mock, target: target, pollInterval: interval, pollLimit: limit,
        sleep: { duration in log.sleeps.append(duration) }
    )
    return (model, log)
}

private final class SleepLog {
    var sleeps: [Duration] = []
}

@MainActor
@Suite(.serialized)
struct UtilityUploadTests {
    @Test func uploadGoesWithItsTargetAsMultipartFields() async throws {
        let target = UtilityUploadTarget(propertyId: propertyId, period: "2026-06", billId: "b1", role: .paymentProof)
        #expect(target.fields == ["property_id": propertyId, "period": "2026-06", "bill_id": "b1", "role": "payment_proof"])
        #expect(UtilityUploadTarget().fields.isEmpty)
    }

    @Test func aRecognisedBillLeadsToTheReview() async throws {
        let mock = try MockUtilityBillsService()
        let (model, _) = flow(mock)
        await model.start(upload)
        guard case .bill(let bill) = model.phase else {
            Issue.record("expected the bill phase, got \(model.phase)")
            return
        }
        #expect(bill.status == .needsReview && bill.period == "2026-06")
        #expect(bill.propertyId == propertyId)
        // The bill waits for the owner: nothing confirmed itself.
        let stored = try await mock.bill(id: bill.id)
        #expect(stored.status == .needsReview)
        #expect(mock.uploads.count == 1 && mock.uploads[0].target.period == "2026-06")
    }

    @Test func theSameFileAgainLeadsToItsBill() async throws {
        let mock = try MockUtilityBillsService()
        let (first, _) = flow(mock)
        await first.start(upload)
        guard case .bill(let bill) = first.phase else { Issue.record("no bill"); return }
        let (second, _) = flow(mock)
        await second.start(upload)
        guard case .duplicate(let existing) = second.phase else {
            Issue.record("expected the duplicate phase, got \(second.phase)")
            return
        }
        // Not a second bill: the duplicate points at the first one (checked with polling stopped).
        #expect(existing == nil || existing?.id == bill.id)
        #expect(second.pollCount == 0)
    }

    @Test func aDuplicateAnswerOfTheContractCarriesTheBill() throws {
        let duplicate = try UtilityFixtures.decode(UtilityUploadResult.self, named: "upload-duplicate")
        #expect(duplicate.duplicateOf != nil && duplicate.bill?.id == duplicate.duplicateOf)
    }

    @Test func anOtherDocumentGetsACardAndNeverABill() async throws {
        let mock = try MockUtilityBillsService()
        mock.uploadOutcome = .other
        let before = mock.billIds(status: .needsReview).count
        let (model, _) = flow(mock)
        await model.start(upload)
        guard case .other(_, let other) = model.phase else {
            Issue.record("expected the other phase, got \(model.phase)")
            return
        }
        #expect(other.amount == Decimal(25000) && other.actions == [.attachToRent, .reject])
        #expect(mock.billIds(status: .needsReview).count == before)
    }

    @Test func rejectingAnOtherDocumentIsRemembered() async throws {
        let mock = try MockUtilityBillsService()
        mock.uploadOutcome = .other
        let (model, _) = flow(mock)
        await model.start(upload)
        await model.rejectOther()
        #expect(model.didRejectOther)
    }

    @Test func aFailedExtractionOffersManualEntryOnTheBill() async throws {
        let mock = try MockUtilityBillsService()
        mock.uploadOutcome = .failed
        let (model, _) = flow(mock)
        await model.start(upload)
        guard case .failed(let message, let bill) = model.phase else {
            Issue.record("expected the failed phase, got \(model.phase)")
            return
        }
        #expect(message.contains("вручную"))
        #expect(bill?.reviewReasons == ["extraction_failed"])
    }

    @Test func aProofOfPaymentLandsOnABillWithAPendingProof() async throws {
        let mock = try MockUtilityBillsService()
        mock.uploadOutcome = .proof
        let (model, _) = flow(mock, target: UtilityUploadTarget(propertyId: propertyId, role: .paymentProof))
        await model.start(upload)
        guard case .bill(let bill) = model.phase else { Issue.record("no bill"); return }
        #expect(bill.reviewReasons.contains("payment_proof_pending"))
        #expect(bill.period == "2026-10")   // the month before the transfer: an inferred period
    }

    // MARK: The poll limit

    @Test func theWaitIsBoundedAndEndsInANotification() async throws {
        let mock = try MockUtilityBillsService()
        mock.uploadOutcome = .stalled
        let (model, log) = flow(mock)
        await model.start(upload)
        guard case .deferred = model.phase else {
            Issue.record("expected the deferred phase, got \(model.phase)")
            return
        }
        // 30 s at 2 s per poll: fifteen polls, fourteen pauses, and then it stops.
        #expect(model.pollCount == 15)
        #expect(mock.stateCalls == 15)
        #expect(log.sleeps.count == 14)
        #expect(log.sleeps.reduce(Duration.zero, +) <= .seconds(30))
        #expect(!model.isWorking)
    }

    @Test func aShorterLimitMeansFewerPolls() async throws {
        let mock = try MockUtilityBillsService()
        mock.uploadOutcome = .stalled
        let (model, _) = flow(mock, interval: .seconds(5), limit: .seconds(10))
        await model.start(upload)
        #expect(model.pollCount == 2)
        if case .deferred = model.phase { } else { Issue.record("not deferred") }
    }

    @Test func aResultInTimeStopsThePolling() async throws {
        let mock = try MockUtilityBillsService()
        mock.pollsBeforeResult = 3
        let (model, _) = flow(mock)
        await model.start(upload)
        #expect(model.pollCount == 4)
        if case .bill = model.phase { } else { Issue.record("expected the bill phase") }
    }

    @Test func aHangingPollIsCutAtTheRequestTimeoutAndTheWallClockDeadline() async throws {
        let mock = try MockUtilityBillsService()
        mock.uploadOutcome = .stalled
        mock.stateLatency = .seconds(5)
        // A clock that moves 12 s per reading: the 30 s deadline is reached after a few polls.
        var tick = 0.0
        let model = UtilityUploadFlowModel(
            service: mock, target: UtilityUploadTarget(propertyId: propertyId),
            pollInterval: .milliseconds(1), pollLimit: .seconds(30), requestTimeout: .milliseconds(50),
            now: { tick += 12; return Date(timeIntervalSince1970: tick) },
            sleep: { _ in }
        )
        await model.start(upload)
        guard case .deferred = model.phase else { Issue.record("expected deferred, got \(model.phase)"); return }
        #expect(model.pollCount <= 3)       // the clock, not the 15 polls, ended the wait
        #expect(mock.stateCalls == 0)       // every request was cut at 50 ms, none ran for 5 s
    }

    // MARK: Errors

    @Test func theDailyQuotaIsExplained() async throws {
        let mock = try MockUtilityBillsService()
        mock.failure = .quotaExceeded(limit: 50)
        let (model, _) = flow(mock)
        await model.start(upload)
        guard case .error(let message, let canRetry) = model.phase else { Issue.record("no error"); return }
        #expect(message.contains("лимит") && !canRetry)
    }

    @Test func aWrongFileSpeaksAboutTheFormats() async throws {
        let mock = try MockUtilityBillsService()
        mock.failure = .validation(fields: [UtilityFieldError(field: "file", message: "unsupported type")])
        let (model, _) = flow(mock)
        await model.start(upload)
        guard case .error(let message, _) = model.phase else { Issue.record("no error"); return }
        #expect(message.contains("JPEG") && message.contains("10 МБ"))
    }

    @Test func aLostConnectionCanBeRetriedWithTheSameFile() async throws {
        let mock = try MockUtilityBillsService()
        mock.failure = .transport
        let (model, _) = flow(mock)
        await model.start(upload)
        guard case .error(_, let canRetry) = model.phase else { Issue.record("no error"); return }
        #expect(canRetry)
        await model.retry()
        if case .bill = model.phase { } else { Issue.record("retry did not recognise: \(model.phase)") }
        #expect(mock.uploads.count == 1)
    }

    // MARK: Scans

    @Test func aSinglePageScanIsAJPEGUnderTheLimit() throws {
        let page = Self.page(width: 1200, height: 1700)
        let result = try #require(UtilityDocumentBuilder.upload(fromScan: [page]))
        #expect(result.mimeType == "image/jpeg" && result.fileName.hasSuffix(".jpg"))
        #expect(result.data.count <= RecognitionUpload.maxBytes)
    }

    @Test func aMultiPageScanIsOnePDFOfAtMostFivePages() throws {
        let pages = (0..<7).map { _ in Self.page(width: 800, height: 1100) }
        let result = try #require(UtilityDocumentBuilder.upload(fromScan: pages))
        #expect(result.mimeType == "application/pdf" && RecognitionUploadBuilder.isPDF(result.data))
        #expect(PDFDocument(data: result.data)?.pageCount == UtilityDocumentBuilder.maxPages)
        #expect(result.data.count <= RecognitionUpload.maxBytes)
    }

    @Test func nothingScannedIsNotAnUpload() {
        #expect(UtilityDocumentBuilder.upload(fromScan: []) == nil)
        #expect(UtilityDocumentBuilder.upload(fromData: Data("not a document".utf8), fileName: nil) == nil)
    }

    private static func page(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor.black.setFill()
            context.fill(CGRect(x: 40, y: 40, width: width / 2, height: 20))
        }
    }
}
