import Combine
import Foundation

/// Offline queue seam for payments (`PendingMutationQueue` in production).
protocol LeaseChargePaymentQueueing {
    func enqueueLeaseChargePayment(chargeId: String, leaseId: String, body: PayChargeRequest, idempotencyKey: String) throws
}

extension PendingMutationQueue: LeaseChargePaymentQueueing {}

/// Screen state of `LeaseDetailView`.
enum LeaseDetailState: Equatable {
    case loading
    case loaded(LeaseAggregate)
    case error(String)
}

/// Sheets presented over the lease screen.
enum LeaseSheet: Identifiable, Equatable {
    case markSigned
    case activate
    case cancel
    case terminate
    case amendRent
    case addExtraCharge
    case payCharge(chargeId: String)
    case returnDeposit
    case replaceWithNew

    var id: String {
        switch self {
        case .markSigned: return "mark_signed"
        case .activate: return "activate"
        case .cancel: return "cancel"
        case .terminate: return "terminate"
        case .amendRent: return "amend_rent"
        case .addExtraCharge: return "add_extra_charge"
        case .payCharge(let chargeId): return "pay_charge.\(chargeId)"
        case .returnDeposit: return "return_deposit"
        case .replaceWithNew: return "replace_with_new"
        }
    }

    /// Sheets that create money or debt need an `Idempotency-Key` per user intent.
    var needsIdempotencyKey: Bool {
        switch self {
        case .payCharge, .addExtraCharge, .returnDeposit: return true
        default: return false
        }
    }
}

/// One button of the action row, derived from `available_actions` only (spec §2.2: clients
/// render buttons from that list).
struct LeaseActionButton: Identifiable, Equatable {
    let action: LeaseAction
    let title: String
    let systemImage: String
    let isDestructive: Bool

    var id: String { action.rawValue }
}

/// State and commands of the lease screen. Works against any `LeaseV2Service`; today that is
/// `MockLeaseV2Service`.
@MainActor
final class LeaseDetailViewModel: ObservableObject {
    @Published private(set) var state: LeaseDetailState = .loading
    @Published var activeSheet: LeaseSheet?
    @Published private(set) var isSubmitting = false
    /// Error shown inside the open sheet.
    @Published var sheetError: String?
    /// Informational line on the screen (queued payment, nothing to pay).
    @Published var banner: String?
    /// Bumped once per accepted payment: applied by the server, or parked in
    /// `PendingMutationQueue` (the local application). Drives haptics and success motion.
    @Published private(set) var paidSignal = 0
    /// Bumped once per command the server or transport refused. Drives the error haptic.
    @Published private(set) var errorSignal = 0

    let leaseId: String
    private let service: LeaseV2Service
    private let paymentQueue: LeaseChargePaymentQueueing?
    private let todayProvider: () -> Date
    private var intentKeys: [String: String] = [:]
    private var queueObserver: AnyCancellable?

    init(
        leaseId: String,
        service: LeaseV2Service,
        paymentQueue: LeaseChargePaymentQueueing? = nil,
        today: @escaping () -> Date = { Date() }
    ) {
        self.leaseId = leaseId
        self.service = service
        self.paymentQueue = paymentQueue
        self.todayProvider = today
        queueObserver = NotificationCenter.default
            .publisher(for: .pendingMarkPaidQueueLeaseAffected)
            .sink { [weak self] note in
                guard let self, (note.userInfo?["leaseId"] as? String) == self.leaseId else { return }
                Task { await self.reload() }
            }
    }

    var lease: LeaseAggregate? {
        if case .loaded(let lease) = state { return lease }
        return nil
    }

    // MARK: Loading

    func load() async {
        if lease == nil { state = .loading }
        await reload()
    }

    /// Refetches without flipping a visible screen back to the spinner.
    func reload() async {
        do {
            state = .loaded(try await service.fetchLease(id: leaseId))
        } catch let error as LeaseV2Error {
            if lease == nil { state = .error(error.userMessage) } else { banner = error.userMessage }
        } catch {
            if lease == nil { state = .error(LeaseV2Error.unknown.userMessage) } else { banner = LeaseV2Error.unknown.userMessage }
        }
    }

    // MARK: Buttons

    /// Display order of the action row.
    private static let actionOrder: [LeaseAction] = [
        .markSigned, .activate, .recordPayment, .addExtraCharge, .amendRent,
        .returnDeposit, .replaceWithNew, .terminate, .cancel,
    ]

    /// Buttons for every action in `available_actions` that this screen can run. Actions the
    /// screen has no UI for (`update`, `prolong`, `generate_contract`, ...) are not shown.
    var actionButtons: [LeaseActionButton] {
        guard let lease else { return [] }
        return Self.actionOrder.filter { lease.can($0) }.compactMap(Self.button(for:))
    }

    private static func button(for action: LeaseAction) -> LeaseActionButton? {
        switch action {
        case .markSigned: return .init(action: action, title: "Подписан", systemImage: "signature", isDestructive: false)
        case .activate: return .init(action: action, title: "Активировать", systemImage: "checkmark.seal", isDestructive: false)
        case .recordPayment: return .init(action: action, title: "Принять оплату", systemImage: "banknote", isDestructive: false)
        case .addExtraCharge: return .init(action: action, title: "Доп. начисление", systemImage: "plus.circle", isDestructive: false)
        case .amendRent: return .init(action: action, title: "Изменить аренду", systemImage: "arrow.up.arrow.down.circle", isDestructive: false)
        case .returnDeposit: return .init(action: action, title: "Депозит возвращён", systemImage: "arrow.uturn.backward.circle", isDestructive: false)
        case .replaceWithNew: return .init(action: action, title: "Заменить новым договором", systemImage: "doc.on.doc", isDestructive: false)
        case .terminate: return .init(action: action, title: "Расторгнуть", systemImage: "door.left.hand.open", isDestructive: true)
        case .cancel: return .init(action: action, title: "Отменить договор", systemImage: "xmark.circle", isDestructive: true)
        default: return nil
        }
    }

    func perform(_ action: LeaseAction) {
        guard let lease else { return }
        switch action {
        case .markSigned: present(.markSigned)
        case .activate: present(.activate)
        case .cancel: present(.cancel)
        case .terminate: present(.terminate)
        case .amendRent: present(.amendRent)
        case .addExtraCharge: present(.addExtraCharge)
        case .returnDeposit: present(.returnDeposit)
        case .replaceWithNew: present(.replaceWithNew)
        case .recordPayment:
            if let charge = lease.payableCharges.first, let id = charge.id {
                present(.payCharge(chargeId: id))
            } else {
                banner = "Нет начислений к оплате."
            }
        default: break
        }
    }

    // MARK: Sheets and intents

    func present(_ sheet: LeaseSheet) {
        sheetError = nil
        banner = nil
        if sheet.needsIdempotencyKey {
            // One key per user intent: created when the dialog opens, kept across retries.
            intentKeys[sheet.id] = UUID().uuidString
        }
        activeSheet = sheet
    }

    func dismissSheet() {
        if let sheet = activeSheet { intentKeys[sheet.id] = nil }
        activeSheet = nil
        sheetError = nil
    }

    func idempotencyKey(for sheet: LeaseSheet) -> String {
        if let key = intentKeys[sheet.id] { return key }
        let key = UUID().uuidString
        intentKeys[sheet.id] = key
        return key
    }

    func terminationPreview(moveOutDate: String, forfeitAmount: Money?) -> LeaseTerminationPreview? {
        guard let lease else { return nil }
        return LeaseTerminationPreview.make(lease: lease, moveOutDate: moveOutDate, forfeitAmount: forfeitAmount)
    }

    /// Picker default: today in the device calendar.
    var todayDay: String {
        LeaseDay.string(fromPicker: todayProvider())
    }

    // MARK: Commands

    @discardableResult
    func submitMarkSigned(signedOn: String, scan: LeaseScanAttachment?) async -> Bool {
        await run(.markSigned) { lease in
            try await self.service.markSigned(
                leaseId: lease.id,
                version: lease.version,
                request: MarkSignedRequest(signedOn: signedOn, signedFileId: nil),
                scan: scan
            )
        }
    }

    @discardableResult
    func submitActivate(activationDate: String, signedOn: String?) async -> Bool {
        await run(.activate) { lease in
            try await self.service.activate(
                leaseId: lease.id,
                version: lease.version,
                request: ActivateLeaseRequest(activationDate: activationDate, signedOn: signedOn, signedFileId: nil)
            )
        }
    }

    @discardableResult
    func submitCancel(reason: String) async -> Bool {
        await run(.cancel) { lease in
            try await self.service.cancel(
                leaseId: lease.id,
                version: lease.version,
                request: CancelLeaseRequest(reason: reason, confirm: nil)
            )
        }
    }

    @discardableResult
    func submitTerminate(moveOutDate: String, reason: String, forfeitAmount: Money?) async -> Bool {
        await run(.terminate) { lease in
            try await self.service.terminate(
                leaseId: lease.id,
                version: lease.version,
                request: TerminateLeaseRequest(
                    moveOutDate: moveOutDate,
                    reason: reason,
                    forfeitAmount: forfeitAmount?.major,
                    confirm: nil
                )
            )
        }
    }

    @discardableResult
    func submitAmendRent(effectiveFrom: String, rent: Money?, dueDay: Int?, note: String?) async -> Bool {
        await run(.amendRent) { lease in
            try await self.service.amendRent(
                leaseId: lease.id,
                version: lease.version,
                request: AmendRentRequest(effectiveFrom: effectiveFrom, rentAmount: rent?.major, dueDay: dueDay, note: note)
            )
        }
    }

    @discardableResult
    func submitAddExtraCharge(amount: Money, chargedOn: String, dueDate: String?, description: String) async -> Bool {
        let key = idempotencyKey(for: .addExtraCharge)
        return await run(.addExtraCharge) { lease in
            try await self.service.addExtraCharge(
                leaseId: lease.id,
                version: lease.version,
                request: AddExtraChargeRequest(amount: amount.major, chargedOn: chargedOn, dueDate: dueDate, description: description),
                idempotencyKey: key
            )
        }
    }

    /// Pays a charge. On a transport failure the request (with the same `Idempotency-Key`) is
    /// parked in `PendingMutationQueue` and the screen reloads when the queue delivers it.
    @discardableResult
    func submitPayCharge(chargeId: String, amount: Money?, receivedOn: String, method: LeasePaymentMethod, notes: String?) async -> Bool {
        let sheet = LeaseSheet.payCharge(chargeId: chargeId)
        let key = idempotencyKey(for: sheet)
        let request = PayChargeRequest(amount: amount?.major, receivedOn: receivedOn, method: method.rawValue, notes: notes)
        let accepted = await run(sheet, onTransportFailure: { [weak self] lease in
            guard let self, let queue = self.paymentQueue else { return false }
            do {
                try queue.enqueueLeaseChargePayment(chargeId: chargeId, leaseId: lease.id, body: request, idempotencyKey: key)
                self.banner = "Нет связи. Оплата сохранена в очереди и уйдёт автоматически."
                return true
            } catch {
                return false
            }
        }) { lease in
            try await self.service.payCharge(leaseId: lease.id, chargeId: chargeId, request: request, idempotencyKey: key)
        }
        if accepted { paidSignal += 1 }
        return accepted
    }

    @discardableResult
    func submitReturnDeposit(amount: Money?, returnedOn: String, method: LeasePaymentMethod, applyToDebt: Money?, notes: String?) async -> Bool {
        let key = idempotencyKey(for: .returnDeposit)
        return await run(.returnDeposit) { lease in
            try await self.service.returnDeposit(
                leaseId: lease.id,
                version: lease.version,
                request: ReturnDepositRequest(
                    amount: amount?.major,
                    returnedOn: returnedOn,
                    method: method.rawValue,
                    applyToDebt: (applyToDebt?.isPositive ?? false) ? applyToDebt?.major : nil,
                    notes: notes,
                    confirm: nil
                ),
                idempotencyKey: key
            )
        }
    }

    // MARK: Plumbing

    /// Runs a command: the aggregate in the response replaces the state, the sheet closes.
    /// A stale version reloads the lease and keeps the sheet open with an explanation.
    private func run(
        _ sheet: LeaseSheet,
        onTransportFailure: ((LeaseAggregate) -> Bool)? = nil,
        _ operation: (LeaseAggregate) async throws -> LeaseAggregate
    ) async -> Bool {
        guard let current = lease, !isSubmitting else { return false }
        isSubmitting = true
        sheetError = nil
        defer { isSubmitting = false }
        do {
            let updated = try await operation(current)
            state = .loaded(updated)
            intentKeys[sheet.id] = nil
            activeSheet = nil
            return true
        } catch let error as LeaseV2Error {
            if error.isRetryable, let onTransportFailure, onTransportFailure(current) {
                intentKeys[sheet.id] = nil
                activeSheet = nil
                return true
            }
            sheetError = error.userMessage
            errorSignal += 1
            if case .versionMismatch = error { await reload() }
            return false
        } catch {
            sheetError = PendingMutationQueue.isRetryableTransportError(error)
                ? LeaseV2Error.transport.userMessage
                : LeaseV2Error.unknown.userMessage
            errorSignal += 1
            return false
        }
    }
}
