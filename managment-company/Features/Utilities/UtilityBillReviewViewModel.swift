import Combine
import Foundation

/// The buttons of the review sheet, derived from `available_actions` and the payer of the property
/// (the server is the source: a button the list does not name is not shown).
struct UtilityBillOffers: Equatable {
    var canEdit = false
    var canConfirm = false
    var canMarkPaid = false
    var canUnmarkPaid = false
    var canReextract = false
    var canDelete = false
    /// «Переслать арендатору»: offered by the server and hidden when the owner pays the utilities.
    var canForward = false
    /// A proof file can be attached only to a confirmed bill; an expected or missing one is
    /// marked paid «без квитанции».
    var allowsPaymentProof = false
    /// An expected or missing bill has no document yet: «Загрузить квитанцию» attaches one to it.
    var canUploadReceipt = false

    init() {}

    init(bill: UtilityBill, payer: UtilityPayer?) {
        canEdit = bill.offers(.edit)
        canConfirm = bill.offers(.confirm)
        canMarkPaid = bill.offers(.markPaid)
        canUnmarkPaid = bill.offers(.unmarkPaid)
        canReextract = bill.offers(.reextract)
        canDelete = bill.offers(.delete)
        canForward = bill.offers(.tenantMessage) && payer != .owner
        allowsPaymentProof = bill.status == .confirmed
        canUploadReceipt = bill.status == .expected || bill.status == .missing
    }
}

enum UtilityBillReviewState: Equatable {
    case loading
    case loaded
    case error(String)
}

/// Sheets and dialogs over the review sheet.
enum UtilityReviewPrompt: Identifiable, Equatable {
    case markPaid
    case confirmDelete
    case confirmUnmark
    case tenantMessage(UtilityTenantMessage)
    case ownerPays

    var id: String {
        switch self {
        case .markPaid: return "mark_paid"
        case .confirmDelete: return "delete"
        case .confirmUnmark: return "unmark"
        case .tenantMessage: return "tenant_message"
        case .ownerPays: return "owner_pays"
        }
    }
}

/// State and commands of `UtilityBillReviewSheet`.
@MainActor
final class UtilityBillReviewViewModel: ObservableObject {
    @Published private(set) var state: UtilityBillReviewState = .loading
    @Published private(set) var bill: UtilityBill?
    @Published private(set) var meta: UtilityMeta?
    @Published private(set) var payer: UtilityPayer?
    @Published private(set) var isBusy = false
    @Published private(set) var isRereading = false
    @Published var draft: UtilityBillDraft?
    @Published var prompt: UtilityReviewPrompt?
    /// Error under the action bar; cleared by the next command.
    @Published var message: String?
    /// Bumped once per confirmed bill and once per paid mark: the success haptic.
    @Published private(set) var successSignal = 0
    @Published private(set) var errorSignal = 0
    @Published private(set) var didChange = false
    @Published private(set) var wasDeleted = false

    let billId: String
    private let service: UtilityBillsService
    private let today: () -> Date
    private let timeZoneIdentifier: String
    private let pollInterval: Duration
    private let rereadPollLimit: Int
    private let sleep: (Duration) async throws -> Void

    init(
        billId: String,
        service: UtilityBillsService,
        payer: UtilityPayer? = nil,
        meta: UtilityMeta? = nil,
        timeZoneIdentifier: String = "Asia/Almaty",
        today: @escaping () -> Date = { Date() },
        pollInterval: Duration = .seconds(2),
        rereadPollLimit: Int = 15,
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.billId = billId
        self.service = service
        self.payer = payer
        self.meta = meta
        self.timeZoneIdentifier = timeZoneIdentifier
        self.today = today
        self.pollInterval = pollInterval
        self.rereadPollLimit = rereadPollLimit
        self.sleep = sleep
    }

    var labels: UtilityLabelBook { UtilityLabelBook(meta) }

    var offers: UtilityBillOffers {
        guard let bill else { return UtilityBillOffers() }
        return UtilityBillOffers(bill: bill, payer: payer)
    }

    var isEditing: Bool { draft != nil }

    /// Hints of the bill as texts of the meta; «проверок не найдено» is shown by the view for an
    /// empty list and is not a confirmation.
    var reasonTexts: [String] {
        labels.reasonTexts(bill?.reviewReasons ?? [])
    }

    var confidenceText: String? {
        guard let confidence = bill?.extraction?.overallConfidence else { return nil }
        return UtilityFormat.percent(confidence)
    }

    /// Confirm will move this bill straight to «Оплачено» (the invoice carries a payment date).
    var confirmPaysImmediately: Bool {
        guard let bill else { return false }
        return bill.status == .needsReview && bill.paidAt != nil
    }

    var todayKey: String {
        UtilityFormat.dayKey(today(), timeZoneIdentifier: timeZoneIdentifier)
    }

    // MARK: Loading

    func load() async {
        if bill == nil { state = .loading }
        await reload()
    }

    func reload() async {
        do {
            async let metaTask = loadMeta()
            let loaded = try await service.bill(id: billId)
            meta = await metaTask
            apply(loaded)
            state = .loaded
            await resolvePayer(for: loaded)
        } catch let error as UtilityBillsError {
            if bill == nil { state = .error(error.userMessage) } else { message = error.userMessage }
        } catch {
            if bill == nil { state = .error(UtilityBillsError.unknown.userMessage) } else { message = UtilityBillsError.unknown.userMessage }
        }
    }

    private func loadMeta() async -> UtilityMeta? {
        if let meta { return meta }
        return try? await service.meta()
    }

    private func resolvePayer(for bill: UtilityBill) async {
        guard payer == nil, let propertyId = bill.propertyId else { return }
        payer = try? await service.propertyPayer(propertyId: propertyId)
    }

    private func apply(_ updated: UtilityBill) {
        bill = updated
        if draft != nil { draft = UtilityBillDraft(bill: updated) }
    }

    // MARK: Editing

    func startEditing() {
        guard let bill, offers.canEdit else { return }
        draft = UtilityBillDraft(bill: bill)
        message = nil
    }

    func cancelEditing() {
        draft = nil
        message = nil
    }

    func addLine() {
        let first = labels.serviceCodes.first(where: { $0 != "other" }) ?? "other"
        draft?.addLine(serviceType: first)
    }

    /// `PATCH`: sends what changed and returns to the review.
    @discardableResult
    func saveEdits() async -> Bool {
        guard let draft else { return false }
        guard draft.isValid else {
            message = "Проверьте отмеченные поля."
            return false
        }
        guard let patch = draft.patch() else {
            self.draft = nil
            return true
        }
        return await run { [self] in
            let updated = try await service.patchBill(id: billId, patch)
            self.draft = nil
            bill = updated
            didChange = true
            return true
        } ?? false
    }

    // MARK: Commands

    /// «Подтвердить»: `confirm` moves the bill to `confirmed`, or to `paid` when it carries a payment date.
    func confirm() async {
        guard offers.canConfirm else { return }
        await run { [self] in
            let updated = try await service.confirm(id: billId)
            bill = updated
            didChange = true
            successSignal += 1
            return true
        }
    }

    /// «Оплачено» with the proof the owner attached: the file goes up as a `payment_proof` of this
    /// bill, then `mark-paid` takes its `file_id`.
    func markPaid(proof: RecognitionUpload, on day: String) async {
        guard offers.canMarkPaid, offers.allowsPaymentProof else { return }
        await run { [self] in
            let started = try await service.upload(
                proof,
                target: UtilityUploadTarget(propertyId: bill?.propertyId, period: bill?.period, billId: billId, role: .paymentProof)
            )
            let fileId = try await proofFileId(of: started)
            let updated = try await service.markPaid(id: billId, .proof(fileId: fileId, paidAt: day))
            bill = updated
            didChange = true
            successSignal += 1
            prompt = nil
            return true
        }
    }

    /// «Оплачено» without a receipt: stops the reminders and counts as paid.
    func markPaidWithoutReceipt(on day: String) async {
        guard offers.canMarkPaid else { return }
        await run { [self] in
            let updated = try await service.markPaid(id: billId, .noReceipt(paidAt: day, currency: bill?.currency == nil ? meta?.currencies.first : nil))
            bill = updated
            didChange = true
            successSignal += 1
            prompt = nil
            return true
        }
    }

    func unmarkPaid() async {
        guard offers.canUnmarkPaid else { return }
        await run { [self] in
            bill = try await service.unmarkPaid(id: billId)
            didChange = true
            prompt = nil
            return true
        }
    }

    func delete() async {
        guard offers.canDelete else { return }
        await run { [self] in
            try await service.deleteBill(id: billId)
            wasDeleted = true
            didChange = true
            prompt = nil
            return true
        }
    }

    /// «Переслать арендатору»: the text comes from the server; the view hands it to the share sheet.
    func forwardToTenant() async {
        guard offers.canForward else { return }
        await run { [self] in
            let text = try await service.tenantMessage(id: billId)
            // The payer is a property attribute: the answer settles it when the sheet did not know it.
            payer = text.utilityPayer
            prompt = text.utilityPayer == .owner ? .ownerPays : .tenantMessage(text)
            return true
        }
    }

    /// «Распознать заново»: queues a new extraction and waits for it a bounded time.
    func reextract() async {
        guard offers.canReextract else { return }
        isRereading = true
        defer { isRereading = false }
        let started: UtilityUploadResult? = await run { [self] in try await service.reextract(id: billId) }
        guard let uploadId = started?.uploadId else { return }
        for _ in 0..<rereadPollLimit {
            guard let state = try? await service.uploadState(id: uploadId) else { break }
            if !state.status.isPending { break }
            try? await sleep(pollInterval)
        }
        await reload()
        didChange = true
    }

    // MARK: Plumbing

    /// Runs a command, shows its error under the action bar and counts the haptics.
    @discardableResult
    private func run<T>(_ command: () async throws -> T) async -> T? {
        guard !isBusy else { return nil }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            return try await command()
        } catch let error as UtilityBillsError {
            fail(error)
        } catch {
            fail(.unknown)
        }
        return nil
    }

    private func fail(_ error: UtilityBillsError) {
        errorSignal += 1
        message = error.userMessage
        // A stale screen: take the bill the server has now.
        if error == .invalidTransition || error == .notFound {
            Task { await reload() }
        }
    }

    /// The `file_id` of an uploaded proof: the accepted answer has only the upload id, the first state
    /// answer carries the file. A duplicate answer names the bill the file is already on.
    private func proofFileId(of started: UtilityUploadResult) async throws -> String {
        if let existing = bill?.paymentProofFile?.fileId, started.uploadId == nil { return existing }
        guard let uploadId = started.uploadId else { throw UtilityBillsError.fileAlreadyAttached }
        let state = try await service.uploadState(id: uploadId)
        guard let fileId = state.fileId else { throw UtilityBillsError.unknown }
        return fileId
    }
}
