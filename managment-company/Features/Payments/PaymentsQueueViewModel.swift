import Combine
import Foundation

/// Tab scope of the payments screen, mirrors `GET /v1/payment-queue?scope=`.
enum PaymentQueueScope: String, CaseIterable, Identifiable {
    case upcoming
    case past

    var id: String { rawValue }

    var title: String {
        switch self {
        case .upcoming: return "Будущие платежи"
        case .past: return "Прошлые платежи"
        }
    }
}

/// Transport seam for `PaymentsQueueViewModel` so the logic is unit-testable
/// without URLSession (mirrored test obligation for GAP-026).
protocol PaymentQueueClient {
    func fetchQueue(scope: PaymentQueueScope, months: Int) async throws -> [PaymentQueueItem]
    func updateSchedule(scheduleId: String, body: PaymentScheduleUpdateRequest) async throws
    func markPaid(scheduleId: String, body: MarkSchedulePaidRequest, idempotencyKey: String) async throws
}

/// Production client: shared `APIClient` with the standard JWT refresh/retry flow.
struct LivePaymentQueueClient: PaymentQueueClient {
    let authManager: AuthManager

    func fetchQueue(scope: PaymentQueueScope, months: Int) async throws -> [PaymentQueueItem] {
        let envelope: APIListEnvelope<PaymentQueueItem> = try await APIClient.shared.requestRoot(
            "/v1/payment-queue?scope=\(scope.rawValue)&months=\(months)",
            tokenProvider: { await MainActor.run { authManager.accessToken } },
            refreshAndRetry: { await authManager.refreshToken() }
        )
        return envelope.data
    }

    func updateSchedule(scheduleId: String, body: PaymentScheduleUpdateRequest) async throws {
        // PATCH answers 204 No Content; requestData avoids decoding an empty body.
        _ = try await APIClient.shared.requestData(
            "/v1/payment-schedules/\(scheduleId)",
            method: "PATCH",
            body: body,
            tokenProvider: { await MainActor.run { authManager.accessToken } },
            refreshAndRetry: { await authManager.refreshToken() }
        )
    }

    func markPaid(scheduleId: String, body: MarkSchedulePaidRequest, idempotencyKey: String) async throws {
        _ = try await APIClient.shared.requestData(
            "/v1/payment-schedules/\(scheduleId)/mark-paid",
            method: "POST",
            body: body,
            idempotencyKey: idempotencyKey,
            tokenProvider: { await MainActor.run { authManager.accessToken } },
            refreshAndRetry: { await authManager.refreshToken() }
        )
    }
}

/// State + actions of the cross-portfolio payment queue screen (GAP-026/027).
/// Day/amount edits are contract-level by product decision: the backend rewrites
/// the tenant's lease and regenerates all future installments.
@MainActor
final class PaymentsQueueViewModel: ObservableObject {
    @Published private(set) var items: [PaymentQueueItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isMutating = false
    @Published var errorMessage: String?
    @Published var scope: PaymentQueueScope = .upcoming
    @Published var months = 3

    static let horizonOptions = [3, 6, 12]

    private let client: PaymentQueueClient

    init(client: PaymentQueueClient) {
        self.client = client
    }

    var totalsByCurrency: [(currency: String, total: Double)] {
        Self.totalsByCurrency(items: items, scope: scope)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await client.fetchQueue(scope: scope, months: months)
        } catch {
            errorMessage = "Не удалось загрузить платежи."
        }
    }

    /// Drops one installment from the queue (`action: "skip"`). Returns success.
    func skip(_ item: PaymentQueueItem) async -> Bool {
        await mutate(scheduleId: item.id, body: .skip, failureMessage: "Не удалось пропустить платёж.")
    }

    /// Returns a skipped or paid installment to the upcoming queue. For paid
    /// rows the backend also reverses the linked income and tenant payment.
    func restore(_ item: PaymentQueueItem) async -> Bool {
        await mutate(scheduleId: item.id, body: .restore, failureMessage: "Не удалось вернуть платёж в очередь.")
    }

    /// Fast "paid today" action (GAP-030), iOS counterpart of the web `/payments`
    /// one-tap mark-paid: records the expected installment with the actual receipt
    /// date set to today in the workspace timezone, never the contractual due date.
    /// The reversal path is the existing restore/un-pay action in `Прошлые платежи`.
    func markPaidToday(_ item: PaymentQueueItem, timeZoneIdentifier: String, now: Date = Date()) async -> Bool {
        let body = Self.fastMarkPaidBody(for: item, timeZoneIdentifier: timeZoneIdentifier, now: now)
        let idempotencyKey = "ios-queue-\(item.id)-\(body.paymentDate ?? "")"
        isMutating = true
        errorMessage = nil
        defer { isMutating = false }
        do {
            try await client.markPaid(scheduleId: item.id, body: body, idempotencyKey: idempotencyKey)
            await load()
            return true
        } catch {
            errorMessage = "Не удалось отметить оплату."
            return false
        }
    }

    /// Applies the edit-sheet result: day first, then amount — one intent per
    /// PATCH, same order as web. Returns success.
    func applyEdit(to item: PaymentQueueItem, day: Int?, amount: Double?) async -> Bool {
        if let day {
            guard await mutate(scheduleId: item.id, body: .day(day), failureMessage: "Не удалось изменить день оплаты.") else {
                return false
            }
        }
        if let amount {
            guard await mutate(scheduleId: item.id, body: .amount(amount), failureMessage: "Не удалось изменить сумму платежа.") else {
                return false
            }
        }
        return true
    }

    @discardableResult
    private func mutate(scheduleId: String, body: PaymentScheduleUpdateRequest, failureMessage: String) async -> Bool {
        isMutating = true
        errorMessage = nil
        defer { isMutating = false }
        do {
            try await client.updateSchedule(scheduleId: scheduleId, body: body)
            await load()
            return true
        } catch {
            errorMessage = failureMessage
            return false
        }
    }

    // MARK: - Pure presentation logic (unit-tested)

    /// Payload for the fast "paid today" action (GAP-030). The actual receipt date
    /// is today in the workspace timezone via the shared `AppFormatting.dayKey`
    /// helper — identical semantics to the Live Activity / reminder-banner fast
    /// action — and is independent of the installment's contractual `dueDate`.
    static func fastMarkPaidBody(
        for item: PaymentQueueItem,
        timeZoneIdentifier: String,
        now: Date = Date()
    ) -> MarkSchedulePaidRequest {
        MarkSchedulePaidRequest(
            amount: item.expectedAmount,
            currency: item.currency,
            paymentDate: AppFormatting.dayKey(for: now, timeZoneIdentifier: timeZoneIdentifier),
            notes: nil
        )
    }

    /// Per-currency totals, first-appearance currency order. In history only
    /// actually received money counts: skipped rows (no recorded payment) are
    /// excluded, paid rows contribute their actual amount.
    static func totalsByCurrency(
        items: [PaymentQueueItem],
        scope: PaymentQueueScope
    ) -> [(currency: String, total: Double)] {
        var order: [String] = []
        var sums: [String: Double] = [:]
        for item in items {
            let amount: Double
            switch scope {
            case .upcoming:
                amount = item.expectedAmount
            case .past:
                guard let actual = item.actualAmount else { continue }
                amount = actual
            }
            if sums[item.currency] == nil {
                order.append(item.currency)
            }
            sums[item.currency, default: 0] += amount
        }
        return order.map { ($0, sums[$0] ?? 0) }
    }

    /// Record date of a history row: skipped installments never carried a
    /// payment, so they have no record date.
    static func recordedDate(of item: PaymentQueueItem) -> String? {
        guard item.status != "skipped" else { return nil }
        return item.paidAt ?? item.dueDate
    }

    /// Restoring a paid row deletes the linked income transaction, so it needs
    /// explicit confirmation. A skipped row can return immediately.
    static func restoreRequiresConfirmation(for item: PaymentQueueItem) -> Bool {
        item.status != "skipped"
    }

    /// Status string fed to `StatusBadge`: overdue wins over `pending` in the
    /// upcoming queue, history rows keep their stored status.
    static func displayStatus(of item: PaymentQueueItem, scope: PaymentQueueScope) -> String {
        scope == .upcoming && item.isOverdue ? "overdue" : item.status
    }

    /// Day-of-month of an ISO `yyyy-MM-dd` date (seed for the edit sheet).
    static func dueDay(fromISODate isoDate: String) -> Int? {
        guard isoDate.count >= 10 else { return nil }
        let start = isoDate.index(isoDate.startIndex, offsetBy: 8)
        let end = isoDate.index(isoDate.startIndex, offsetBy: 10)
        return Int(isoDate[start..<end])
    }

    /// Covered period of a history row, e.g. "Май 2026".
    static func periodLabel(of item: PaymentQueueItem) -> String {
        let anchor = item.periodStartDate ?? item.dueDate
        guard let date = AppFormatting.parsedDate(from: anchor) else { return anchor }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date).capitalized
    }
}
