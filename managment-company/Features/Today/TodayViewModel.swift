import Combine
import Foundation

// MARK: - Presentation models

/// Attention item kinds in their fixed urgency order (mirrors web `/today`
/// Attention block: overdue rent → rent due today → urgent/overdue tasks →
/// upcoming lease renewals → receipts awaiting review).
enum TodayAttentionKind: Int, Comparable, Equatable {
    case overdueRent = 0
    case dueTodayRent = 1
    case task = 2
    case renewal = 3
    case receipt = 4

    static func < (lhs: TodayAttentionKind, rhs: TodayAttentionKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum TodayAttentionTone: Equatable {
    case danger
    case warning
    case info
}

/// Where an attention row points. Inline-resolvable rows also carry the payload
/// needed to act without leaving the screen (the resolved row then disappears
/// after the next reload).
enum TodayDeepLink: Equatable {
    case paymentDetail(scheduleId: String)
    case task(id: String)
    case property(id: String)
    case paymentsList
}

struct TodayAttentionItem: Identifiable, Equatable {
    let id: String
    let kind: TodayAttentionKind
    let tone: TodayAttentionTone
    let title: String
    let detail: String
    let deepLink: TodayDeepLink
    /// Present when the row can be marked paid inline (rent rows).
    let scheduleItem: PaymentQueueItem?
    /// Present when the row can be completed inline (task rows).
    let taskId: String?

    static func == (lhs: TodayAttentionItem, rhs: TodayAttentionItem) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind && lhs.title == rhs.title
    }
}

/// Money summary for the dashboard period, distinguishing rent received, other
/// income, owner expenses, and net cashflow (GAP-031 acceptance).
struct TodayMoneySummary: Equatable {
    let periodLabel: String
    let rentReceived: Double
    let otherIncome: Double
    let expenses: Double
    let net: Double
    let currency: String
}

/// One row of the Today property-performance drilldown table (GAP-035).
struct PropertyPerformanceRow: Identifiable, Equatable {
    let id: String
    let name: String
    let income: Double
    let expense: Double
    var net: Double { income - expense }
}

enum PropertyPerformanceSort: String, CaseIterable, Identifiable {
    case net
    case income
    case expense
    case name

    var id: String { rawValue }
    var title: String {
        switch self {
        case .net: return "Прибыль"
        case .income: return "Доход"
        case .expense: return "Расход"
        case .name: return "Название"
        }
    }
}

/// Independent data sources of the Today screen; tracked separately so a single
/// failed endpoint degrades only its block instead of blanking the page.
enum TodaySource: String, CaseIterable {
    case payments
    case tasks
    case renewals
    case receipts
    case dashboard
    case recent
}

// MARK: - Transport seam

@MainActor
protocol TodayDataClient {
    func fetchUpcomingQueue() async throws -> [PaymentQueueItem]
    func fetchTasks() async throws -> [AppTask]
    func fetchRenewals(days: Int) async throws -> [UpcomingRenewal]
    func fetchReceipts() async throws -> [UtilityReceiptPayload]
    func fetchDashboard() async throws -> AnalyticsDashboard
    func fetchProperties() async throws -> [Property]
    func fetchTenants() async throws -> [Tenant]
    func fetchRecentTransactions(propertyIds: [String]) async throws -> [Transaction]
    func fetchProfitability(from: String, to: String) async throws -> ProfitabilityReport
    func fetchDueRecurring() async throws -> [RecurringExpenseTemplate]
    func confirmRecurring(id: String) async throws
    func skipRecurring(id: String) async throws
    func markPaid(scheduleId: String, body: MarkSchedulePaidRequest, idempotencyKey: String) async throws
    func completeTask(id: String) async throws
}

private struct TaskStatusBody: Encodable {
    let status: String
}

@MainActor
struct LiveTodayClient: TodayDataClient {
    let authManager: AuthManager
    private let queueClient: LivePaymentQueueClient

    init(authManager: AuthManager) {
        self.authManager = authManager
        self.queueClient = LivePaymentQueueClient(authManager: authManager)
    }

    private var token: () async -> String? {
        { await MainActor.run { authManager.accessToken } }
    }
    private var refresh: () async -> Bool {
        { await authManager.refreshToken() }
    }

    func fetchUpcomingQueue() async throws -> [PaymentQueueItem] {
        try await queueClient.fetchQueue(scope: .upcoming, months: 3)
    }

    func fetchTasks() async throws -> [AppTask] {
        try await APIClient.shared.request("/v1/tasks", tokenProvider: token, refreshAndRetry: refresh)
    }

    func fetchRenewals(days: Int) async throws -> [UpcomingRenewal] {
        let data = try await APIClient.shared.requestData(
            "/v1/analytics/upcoming-renewals?days=\(days)",
            tokenProvider: token,
            refreshAndRetry: refresh
        )
        if let direct = try? JSONDecoder().decode([UpcomingRenewal].self, from: data) {
            return direct
        }
        let env = try JSONDecoder().decode(APIListEnvelope<UpcomingRenewal>.self, from: data)
        return env.data
    }

    func fetchReceipts() async throws -> [UtilityReceiptPayload] {
        let env: APIListEnvelope<UtilityReceiptPayload> = try await APIClient.shared.requestRoot(
            "/v1/utility-receipts?per_page=100",
            tokenProvider: token,
            refreshAndRetry: refresh
        )
        return env.data
    }

    func fetchDashboard() async throws -> AnalyticsDashboard {
        try await APIClient.shared.request(
            "/v1/analytics/dashboard?period=month",
            tokenProvider: token,
            refreshAndRetry: refresh
        )
    }

    func fetchProperties() async throws -> [Property] {
        try await APIClient.shared.request("/v1/properties", tokenProvider: token, refreshAndRetry: refresh)
    }

    func fetchTenants() async throws -> [Tenant] {
        try await APIClient.shared.request("/v1/tenants?per_page=100", tokenProvider: token, refreshAndRetry: refresh)
    }

    func fetchRecentTransactions(propertyIds: [String]) async throws -> [Transaction] {
        // No global ledger endpoint on iOS yet; fan out per property like the
        // dashboard does and merge. Best-effort: a single property failure does
        // not blank the recent-activity block.
        var merged: [Transaction] = []
        for id in propertyIds {
            if let rows: [Transaction] = try? await APIClient.shared.request(
                "/v1/properties/\(id)/transactions?per_page=20",
                tokenProvider: token,
                refreshAndRetry: refresh
            ) {
                merged.append(contentsOf: rows)
            }
        }
        return merged
    }

    func fetchProfitability(from: String, to: String) async throws -> ProfitabilityReport {
        try await APIClient.shared.request(
            "/v1/analytics/profitability?from=\(from)&to=\(to)&group_by=month",
            tokenProvider: token,
            refreshAndRetry: refresh
        )
    }

    private var recurringClient: LiveRecurringExpenseClient { LiveRecurringExpenseClient(authManager: authManager) }

    func fetchDueRecurring() async throws -> [RecurringExpenseTemplate] {
        try await recurringClient.listDue()
    }
    func confirmRecurring(id: String) async throws { try await recurringClient.confirm(id: id) }
    func skipRecurring(id: String) async throws { try await recurringClient.skip(id: id) }

    func markPaid(scheduleId: String, body: MarkSchedulePaidRequest, idempotencyKey: String) async throws {
        try await queueClient.markPaid(scheduleId: scheduleId, body: body, idempotencyKey: idempotencyKey)
    }

    func completeTask(id: String) async throws {
        _ = try await APIClient.shared.requestData(
            "/v1/tasks/\(id)",
            method: "PUT",
            body: TaskStatusBody(status: "done"),
            tokenProvider: token,
            refreshAndRetry: refresh
        )
    }
}

// MARK: - View model

/// Assembles the iOS `Сегодня` operating screen (GAP-031): the Attention block,
/// quick actions, money summary, and recent activity. It is a separate surface
/// from the Dashboard and never restructures it.
@MainActor
final class TodayViewModel: ObservableObject {
    @Published private(set) var attentionItems: [TodayAttentionItem] = []
    @Published private(set) var moneySummary: TodayMoneySummary?
    @Published private(set) var recentRows: [DashboardRecentTransactionRow] = []
    @Published private(set) var dueRecurring: [RecurringExpenseTemplate] = []
    @Published private(set) var properties: [Property] = []
    @Published private(set) var performanceRows: [PropertyPerformanceRow] = []
    @Published var performanceSort: PropertyPerformanceSort = .net {
        didSet { performanceRows = Self.sortPerformance(performanceRows, by: performanceSort) }
    }
    @Published private(set) var failedSources: Set<TodaySource> = []
    @Published private(set) var isLoading = false

    private let client: TodayDataClient
    private let timeZoneIdentifier: String
    private let baseCurrency: String

    init(client: TodayDataClient, timeZoneIdentifier: String, baseCurrency: String) {
        self.client = client
        self.timeZoneIdentifier = timeZoneIdentifier
        self.baseCurrency = baseCurrency
    }

    var attentionCount: Int { attentionItems.count }
    var hasPartialError: Bool { !failedSources.isEmpty }

    func load(now: Date = Date()) async {
        isLoading = true
        defer { isLoading = false }

        async let queueR = capture { try await self.client.fetchUpcomingQueue() }
        async let tasksR = capture { try await self.client.fetchTasks() }
        async let renewalsR = capture { try await self.client.fetchRenewals(days: 30) }
        async let receiptsR = capture { try await self.client.fetchReceipts() }
        async let dashboardR = capture { try await self.client.fetchDashboard() }
        async let propertiesR = capture { try await self.client.fetchProperties() }
        async let tenantsR = capture { try await self.client.fetchTenants() }

        let queueRes = await queueR
        let tasksRes = await tasksR
        let renewalsRes = await renewalsR
        let receiptsRes = await receiptsR
        let dashboardRes = await dashboardR
        let properties = (try? await propertiesR.get()) ?? []
        let tenants = (try? await tenantsR.get()) ?? []
        self.properties = properties

        var failures: Set<TodaySource> = []
        let queue = value(queueRes, source: .payments, into: &failures)
        let tasks = value(tasksRes, source: .tasks, into: &failures)
        let renewals = value(renewalsRes, source: .renewals, into: &failures)
        let receipts = value(receiptsRes, source: .receipts, into: &failures)
        let dashboard = optionalValue(dashboardRes, source: .dashboard, into: &failures)

        let propertyNames = Dictionary(uniqueKeysWithValues: properties.map { ($0.id, $0.name) })
        let tenantNames = Dictionary(uniqueKeysWithValues: tenants.map { ($0.id, $0.displayName) })

        let today = AppFormatting.dayKey(for: now, timeZoneIdentifier: timeZoneIdentifier)

        attentionItems = Self.attentionItems(
            today: today,
            queue: queue,
            tasks: tasks,
            renewals: renewals,
            receipts: receipts,
            propertyNames: propertyNames,
            tenantNames: tenantNames
        )
        moneySummary = dashboard.map { Self.moneySummary(from: $0, baseCurrency: baseCurrency) }

        // Property-performance drilldown table (GAP-035) over the dashboard period.
        let from = dashboard?.periodFrom ?? "\(today.prefix(7))-01"
        let to = dashboard?.periodTo ?? today
        if let report = try? await client.fetchProfitability(from: from, to: to) {
            performanceRows = Self.sortPerformance(
                Self.propertyPerformance(points: report.points),
                by: performanceSort
            )
        }

        // Recent activity is best-effort and never reports a partial error on its
        // own (it is a secondary block); the fan-out already swallows per-row
        // failures inside the client.
        let recent = (try? await client.fetchRecentTransactions(propertyIds: properties.map(\.id))) ?? []
        if recent.isEmpty && !properties.isEmpty {
            failures.insert(.recent)
        }
        recentRows = DashboardRecentTransactionsLogic.rows(transactions: recent, propertyNames: propertyNames)

        // Due recurring expense occurrences (GAP-039), best-effort.
        dueRecurring = (try? await client.fetchDueRecurring()) ?? []

        failedSources = failures
    }

    func confirmDueRecurring(_ template: RecurringExpenseTemplate, now: Date = Date()) async -> Bool {
        do { try await client.confirmRecurring(id: template.id); await load(now: now); return true }
        catch { return false }
    }

    func skipDueRecurring(_ template: RecurringExpenseTemplate, now: Date = Date()) async -> Bool {
        do { try await client.skipRecurring(id: template.id); await load(now: now); return true }
        catch { return false }
    }

    /// Inline-resolve a rent row with today's actual date (GAP-030 semantics),
    /// then reload so the resolved row disappears from Attention.
    func markPaidToday(_ item: PaymentQueueItem, now: Date = Date()) async -> Bool {
        let body = PaymentsQueueViewModel.fastMarkPaidBody(
            for: item,
            timeZoneIdentifier: timeZoneIdentifier,
            now: now
        )
        let key = "ios-today-\(item.id)-\(body.paymentDate ?? "")"
        do {
            try await client.markPaid(scheduleId: item.id, body: body, idempotencyKey: key)
            await load(now: now)
            return true
        } catch {
            return false
        }
    }

    func completeTask(id: String, now: Date = Date()) async -> Bool {
        do {
            try await client.completeTask(id: id)
            await load(now: now)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Concurrency helpers

    private func capture<T>(_ work: @escaping () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }

    private func value<T>(
        _ result: Result<[T], Error>,
        source: TodaySource,
        into failures: inout Set<TodaySource>
    ) -> [T] {
        switch result {
        case .success(let value):
            return value
        case .failure:
            failures.insert(source)
            return []
        }
    }

    private func optionalValue<T>(
        _ result: Result<T, Error>,
        source: TodaySource,
        into failures: inout Set<TodaySource>
    ) -> T? {
        switch result {
        case .success(let value):
            return value
        case .failure:
            failures.insert(source)
            return nil
        }
    }

    // MARK: - Pure aggregation (unit-tested)

    /// Ordered Attention rows. Within a kind, rent keeps queue order (already
    /// due-date sorted by the backend) and tasks sort by due date ascending.
    nonisolated static func attentionItems(
        today: String,
        queue: [PaymentQueueItem],
        tasks: [AppTask],
        renewals: [UpcomingRenewal],
        receipts: [UtilityReceiptPayload],
        propertyNames: [String: String],
        tenantNames: [String: String]
    ) -> [TodayAttentionItem] {
        var items: [TodayAttentionItem] = []

        for item in queue where item.isOverdue {
            items.append(TodayAttentionItem(
                id: "overdue-\(item.id)",
                kind: .overdueRent,
                tone: .danger,
                title: "\(item.propertyName): аренда просрочена на \(item.daysOverdue) дн.",
                detail: "\(item.tenantName) · \(AppFormatting.currency(item.expectedAmount, currency: item.currency))",
                deepLink: .paymentDetail(scheduleId: item.id),
                scheduleItem: item,
                taskId: nil
            ))
        }

        for item in queue where !item.isOverdue && item.dueDate == today {
            items.append(TodayAttentionItem(
                id: "due-\(item.id)",
                kind: .dueTodayRent,
                tone: .warning,
                title: "\(item.propertyName): аренда сегодня",
                detail: "\(item.tenantName) · \(AppFormatting.currency(item.expectedAmount, currency: item.currency))",
                deepLink: .paymentDetail(scheduleId: item.id),
                scheduleItem: item,
                taskId: nil
            ))
        }

        let urgentTasks = tasks
            .filter { isUrgentTask($0, today: today) }
            .sorted { ($0.dueDate ?? "9999") < ($1.dueDate ?? "9999") }
        for task in urgentTasks {
            let due = task.dueDate.flatMap { AppFormatting.dateString(from: $0) }
            items.append(TodayAttentionItem(
                id: "task-\(task.id)",
                kind: .task,
                tone: (task.dueDate.map { $0.prefix(10) <= today } ?? false) ? .danger : .warning,
                title: task.title,
                detail: [due.map { "Срок \($0)" }, taskPriorityLabel(task.priority)].compactMap { $0 }.joined(separator: " · "),
                deepLink: .task(id: task.id),
                scheduleItem: nil,
                taskId: task.id
            ))
        }

        for renewal in renewals {
            let property = propertyNames[renewal.propertyId] ?? "Объект"
            let tenant = tenantNames[renewal.tenantId]
            let end = AppFormatting.dateString(from: renewal.endDate) ?? renewal.endDate
            items.append(TodayAttentionItem(
                id: "renewal-\(renewal.leaseId)",
                kind: .renewal,
                tone: .info,
                title: "\(property): договор истекает \(end)",
                detail: tenant ?? "Продление аренды",
                deepLink: .property(id: renewal.propertyId),
                scheduleItem: nil,
                taskId: nil
            ))
        }

        for receipt in receipts where receipt.status == "parsed" || receipt.status == "failed" {
            let property = receipt.propertyId.flatMap { propertyNames[$0] } ?? "Квитанция"
            items.append(TodayAttentionItem(
                id: "receipt-\(receipt.id)",
                kind: .receipt,
                tone: .info,
                title: "\(property): квитанция ждёт проверки",
                detail: receipt.status == "failed" ? "Распознавание не удалось" : "Проверьте распознанные данные",
                deepLink: receipt.propertyId.map { .property(id: $0) } ?? .paymentsList,
                scheduleItem: nil,
                taskId: nil
            ))
        }

        return items.sorted { $0.kind < $1.kind }
    }

    /// A task is urgent when it is open and either due on/before today or
    /// high/urgent priority (mirrors web `/today`).
    nonisolated static func isUrgentTask(_ task: AppTask, today: String) -> Bool {
        let status = task.status.lowercased()
        guard status != "done" && status != "completed" && status != "cancelled" else { return false }
        if let due = task.dueDate, due.prefix(10) <= today { return true }
        let priority = task.priority.lowercased()
        return priority == "high" || priority == "urgent"
    }

    /// Aggregates canonical profitability points into one row per property
    /// (summing income/expense across the period's points).
    nonisolated static func propertyPerformance(points: [ProfitabilityPoint]) -> [PropertyPerformanceRow] {
        var order: [String] = []
        var income: [String: Double] = [:]
        var expense: [String: Double] = [:]
        var names: [String: String] = [:]
        for point in points {
            guard let id = point.propertyId else { continue }
            if names[id] == nil {
                order.append(id)
                names[id] = point.propertyName ?? "Объект"
            }
            income[id, default: 0] += point.totalIncome
            expense[id, default: 0] += point.totalExpense
        }
        return order.map {
            PropertyPerformanceRow(id: $0, name: names[$0] ?? "Объект", income: income[$0] ?? 0, expense: expense[$0] ?? 0)
        }
    }

    nonisolated static func sortPerformance(
        _ rows: [PropertyPerformanceRow],
        by sort: PropertyPerformanceSort
    ) -> [PropertyPerformanceRow] {
        switch sort {
        case .name:
            return rows.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .income:
            return rows.sorted { $0.income > $1.income }
        case .expense:
            return rows.sorted { $0.expense > $1.expense }
        case .net:
            return rows.sorted { $0.net > $1.net }
        }
    }

    nonisolated static func moneySummary(from dashboard: AnalyticsDashboard, baseCurrency: String) -> TodayMoneySummary {
        let other = max(0, dashboard.totalIncome - dashboard.rentReceived)
        return TodayMoneySummary(
            periodLabel: dashboard.displayPeriodLabel,
            rentReceived: dashboard.rentReceived,
            otherIncome: other,
            expenses: dashboard.totalExpense,
            net: dashboard.netCashflow,
            currency: baseCurrency
        )
    }

    nonisolated private static func taskPriorityLabel(_ priority: String) -> String? {
        switch priority.lowercased() {
        case "urgent": return "Срочно"
        case "high": return "Высокий приоритет"
        default: return nil
        }
    }
}
