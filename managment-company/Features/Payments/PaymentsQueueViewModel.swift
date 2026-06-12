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
}

/// State + actions of the cross-portfolio payment queue screen (GAP-026).
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
