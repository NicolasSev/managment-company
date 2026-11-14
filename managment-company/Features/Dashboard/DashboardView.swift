import Charts
import SwiftUI
import UIKit

private enum DashboardExportFormat {
    case csv
    case pdf
}

private struct DashboardExportDocument: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
}

/// Portfolio dashboard. Advanced analytics are split into small, defensive
/// sections so a secondary endpoint failure never blanks the primary KPIs.
struct DashboardView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject private var rentPreviewRouter: RentPreviewRouter
    @EnvironmentObject private var notificationRouter: NotificationDeepLinkRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    enum Period: String, CaseIterable, Identifiable {
        case all, month, season, quarter, year
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "Всё время"
            case .month: return "Месяц"
            case .season: return "Сезон"
            case .quarter: return "Квартал"
            case .year: return "Год"
            }
        }
        /// Label that fits a five-segment control.
        var shortTitle: String { self == .all ? "Всё" : title }
    }

    @State private var period: Period = .month
    @State private var dashboard: AnalyticsDashboard?
    @State private var occupancy: OccupancyPayload?
    @State private var profitabilityReport: ProfitabilityReport?
    @State private var overdue: OverduePaymentsPayload?
    @State private var cashflowTrend: CashflowTrendBody?
    @State private var utilities: [PropertyUtility] = []
    @State private var properties: [Property] = []
    @State private var tenants: [Tenant] = []
    @State private var leases: [Lease] = []
    @State private var paymentSchedules: [LeasePaymentSchedule] = []
    @State private var portfolioTransactions: [Transaction] = []
    @State private var incomeCategories: [Category] = []
    @State private var recentTransactions: [DashboardRecentTransactionRow] = []
    @State private var recentTransactionsExpanded = false
    @State private var recentTransactionsLoadFailed = false
    @State private var analyticsRange: DashboardAnalyticsRange = .twelveMonths
    @State private var analyticsGroup: DashboardAnalyticsGroup = .month
    @State private var selectedPropertyIds: Set<String> = []
    @State private var calendarYear = Calendar.current.component(.year, from: Date())
    @State private var calendarMonth = Calendar.current.component(.month, from: Date())
    @State private var isLoading = true
    @State private var isAnalyticsLoading = false
    @State private var errorMessage: String?
    @State private var showNotifications = false
    @State private var notificationUnreadCount = 0
    @State private var exportDocument: DashboardExportDocument?
    @State private var exportErrorMessage: String?
    @State private var selectedCalendarDay: DashboardCalendarDayDetail?

    private let calendarColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let weekdays = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    private var currency: String { authManager.user?.baseCurrency ?? "KZT" }
    private var profitabilityTotals: [ProfitabilityPoint] { profitabilityReport?.totals ?? [] }
    private var propertyNames: [String: String] {
        Dictionary(uniqueKeysWithValues: properties.map { ($0.id, $0.name) })
    }
    private var comparisonRows: [DashboardPropertyComparisonRow] {
        DashboardAnalyticsLogic.comparisonRows(
            points: profitabilityReport?.points ?? [],
            propertyNames: propertyNames,
            selectedPropertyIds: selectedPropertyIds
        )
    }
    private var calendarDays: [DashboardCalendarDay] {
        DashboardAnalyticsLogic.calendarDays(
            year: calendarYear,
            month: calendarMonth,
            leases: leases,
            schedules: paymentSchedules,
            transactions: portfolioTransactions,
            categories: incomeCategories
        )
    }
    private var coverageSummary: DashboardCoverageSummary {
        DashboardAnalyticsLogic.coverageSummary(days: calendarDays)
    }
    private var availableYears: [Int] {
        DashboardAnalyticsLogic.availableYears(leases: leases)
    }
    private var visibleRecentTransactions: [DashboardRecentTransactionRow] {
        DashboardRecentTransactionsLogic.visibleRows(
            recentTransactions,
            expanded: recentTransactionsExpanded
        )
    }
    private var recentTransactionsAction: DashboardRecentTransactionsAction? {
        DashboardRecentTransactionsLogic.action(
            rowCount: recentTransactions.count,
            expanded: recentTransactionsExpanded
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground()
                content
            }
            .navigationTitle("Дашборд")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    exportMenu
                    notificationButton
                }
            }
            .sheet(isPresented: $showNotifications) {
                NotificationsInboxView(onDataChanged: {
                    await refreshNotificationUnread()
                })
                .environmentObject(authManager)
            }
            .sheet(item: $exportDocument) { document in
                NavigationStack {
                    VStack(spacing: AppTheme.Spacing.lg) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 42))
                            .foregroundStyle(AppTheme.Colors.accent)
                        Text(document.title)
                            .font(.title3.weight(.semibold))
                        ShareLink(item: document.url) {
                            Label("Поделиться", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.Colors.accent)
                    }
                    .padding(AppTheme.Spacing.lg)
                    .navigationTitle("Экспорт")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Готово") { exportDocument = nil }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .sheet(item: $selectedCalendarDay) { detail in
                DashboardCalendarDayDetailSheet(detail: detail)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .alert(
                "Экспорт недоступен",
                isPresented: Binding(
                    get: { exportErrorMessage != nil },
                    set: { if !$0 { exportErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { exportErrorMessage = nil }
            } message: {
                Text(exportErrorMessage ?? "")
            }
            .onChange(of: showNotifications) { _, open in
                if !open { Task { await refreshNotificationUnread() } }
            }
            .task {
                await load()
                await refreshNotificationUnread()
            }
            .refreshable {
                await load()
                await refreshNotificationUnread()
            }
            .onChange(of: period) { _, _ in Task { await loadDashboard() } }
            .onChange(of: analyticsRange) { _, _ in Task { await loadProfitability() } }
            .onChange(of: analyticsGroup) { _, _ in Task { await loadProfitability() } }
            .onChange(of: rentPreviewRouter.paidSignal) { _, _ in
                Task {
                    await load()
                    await refreshNotificationUnread()
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && dashboard == nil {
            loadingSkeleton
        } else if let errorMessage, dashboard == nil {
            EmptyStateView(
                title: "Дашборд недоступен",
                message: errorMessage,
                actionName: "Повторить",
                action: { Task { await load() } },
                icon: "chart.bar.xaxis"
            )
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: AppTheme.Spacing.md) {
                    masthead
                    if let errorMessage { infoBanner(errorMessage) }
                    kpiSection
                    if let overdue { overdueSection(overdue) }
                    if let cashflowTrend, !cashflowTrend.months.isEmpty {
                        cashflowSection(cashflowTrend)
                    }
                    analyticsControls
                    if !profitabilityTotals.isEmpty {
                        profitabilitySection
                    }
                    if !comparisonRows.isEmpty {
                        comparisonSection
                    }
                    recentTransactionsSection
                    if !leases.isEmpty {
                        calendarSection
                    }
                    if !utilities.isEmpty {
                        utilitiesSection
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.top, AppTheme.Spacing.sm)
                .padding(.bottom, AppTheme.Spacing.xl)
            }
        }
    }

    /// Skeleton in the shape of the loaded screen: masthead and the four figure tiles.
    private var loadingSkeleton: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: AppTheme.Spacing.md) {
                masthead
                kpiSection
            }
            .shimmerPlaceholder(true)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.top, AppTheme.Spacing.sm)
        }
        .accessibilityLabel("Загружаем дашборд")
    }

    private var notificationButton: some View {
        Button {
            showNotifications = true
        } label: {
            Image(systemName: notificationUnreadCount > 0 ? "bell.badge" : "bell")
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    notificationUnreadCount > 0 ? AppTheme.Colors.danger : AppTheme.Colors.textPrimary,
                    AppTheme.Colors.textPrimary
                )
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityLabel(
            notificationUnreadCount > 0
                ? "Уведомления, непрочитано: \(notificationUnreadCount)"
                : "Уведомления"
        )
    }

    private var exportMenu: some View {
        Menu {
            Button {
                exportDashboard(as: .csv)
            } label: {
                Label("Экспорт CSV", systemImage: "tablecells")
            }
            Button {
                exportDashboard(as: .pdf)
            } label: {
                Label("Экспорт PDF", systemImage: "doc.richtext")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .disabled(profitabilityReport == nil)
        .accessibilityLabel("Экспорт аналитики")
    }

    // MARK: - Masthead

    /// Hero of the screen: net cashflow of the period above the portfolio drawn as a street.
    private var masthead: some View {
        let net = dashboard?.netCashflow ?? 0
        return SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Чистый денежный поток")
                        .sectionLabelStyle()
                    Spacer()
                    Text(dashboard?.periodLabel ?? period.title)
                        .sectionLabelStyle(AppTheme.Colors.accent)
                }

                Text(money(net))
                    .font(AppTheme.Typography.masthead)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: net))
                    .animation(AppTheme.Motion.resolved(AppTheme.Motion.normal, reduceMotion: reduceMotion), value: net)

                if !properties.isEmpty {
                    IsometricStreet(buildings: properties.map(IsometricBuildingSpec.init(property:)), height: 92)
                }

                HStack(spacing: 0) {
                    MetricTile(title: "Занято", value: "\(occupancy?.occupied ?? 0)", tint: AppTheme.Colors.accent)
                    MetricTile(title: "Всего", value: "\(occupancy?.total ?? 0)")
                    MetricTile(title: "Доля", value: "\(occupancy?.ratePct ?? 0)%")
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "Заселённость: занято \(occupancy?.occupied ?? 0) из \(occupancy?.total ?? 0)"
                )

                Picker("Период", selection: $period) {
                    ForEach(Period.allCases) { option in
                        Text(option.shortTitle).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var kpiSection: some View {
        let d = dashboard
        return LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: AppTheme.Spacing.sm),
                GridItem(.flexible(), spacing: AppTheme.Spacing.sm)
            ],
            spacing: AppTheme.Spacing.sm
        ) {
            KPICard(
                title: "Полученный доход",
                value: money(d?.totalIncome ?? 0),
                icon: "arrow.down.left",
                color: AppTheme.Colors.accent,
                subtitle: d.map { "Депозиты: \(money($0.depositIncome))" } ?? " "
            )
            KPICard(
                title: "Расходы",
                value: money(d?.totalExpense ?? 0),
                icon: "arrow.up.right",
                color: AppTheme.Colors.textSecondary,
                subtitle: "Операционные траты владельца."
            )
            KPICard(
                title: "Аренда к получению",
                value: money(d?.rentOutstanding ?? 0),
                icon: (d?.rentOutstanding ?? 0) > 0 ? "clock" : "checkmark",
                color: (d?.rentOutstanding ?? 0) > 0
                    ? AppTheme.Colors.warning
                    : AppTheme.Colors.accent,
                subtitle: d.map {
                    "Начислено \(money($0.expectedRent)), оплачено \(money($0.rentReceived))."
                } ?? " "
            )
            KPICard(
                title: "Оплачено аренды",
                value: money(d?.rentReceived ?? 0),
                icon: "banknote",
                color: AppTheme.Colors.accent,
                subtitle: d.map { "Из начисленных \(money($0.expectedRent))." } ?? " "
            )
        }
        .animation(AppTheme.Motion.resolved(AppTheme.Motion.normal, reduceMotion: reduceMotion), value: dashboard?.totalIncome)
    }

    private var analyticsControls: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                SectionHeader(
                    title: "Аналитика прибыльности",
                    subtitle: "Диапазон и группировка применяются ко всем строкам ниже."
                ) {
                    if isAnalyticsLoading { ProgressView().controlSize(.small) }
                }
                Picker("Диапазон", selection: $analyticsRange) {
                    ForEach(DashboardAnalyticsRange.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("Группировка")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    Spacer()
                    Picker("Группировка", selection: $analyticsGroup) {
                        ForEach(DashboardAnalyticsGroup.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    private func overdueSection(_ payload: OverduePaymentsPayload) -> some View {
        let hasOverdue = payload.overdueCount > 0
        return Button {
            notificationRouter.selectTab = .payments
            dismiss()
        } label: {
            SurfaceCard(padding: AppTheme.Spacing.md) {
                HStack(spacing: AppTheme.Spacing.md) {
                    Text("\(payload.overdueCount)")
                        .font(AppTheme.Typography.masthead)
                        .monospacedDigit()
                        .foregroundStyle(hasOverdue ? AppTheme.Colors.danger : AppTheme.Colors.accent)
                        .contentTransition(.numericText())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Просроченные платежи")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Text(hasOverdue
                             ? "Требуют внимания. Открыть очередь."
                             : "Просроченных начислений нет.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    Spacer(minLength: 0)
                    if hasOverdue {
                        Image(systemName: "arrow.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.danger)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.accent)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!hasOverdue)
        .accessibilityElement(children: .combine)
    }

    private func cashflowSection(_ trend: CashflowTrendBody) -> some View {
        let months = Array(trend.months.suffix(12))
        return SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                SectionHeader(title: "Денежный поток за 12 месяцев", subtitle: nil) {
                    HStack(spacing: AppTheme.Spacing.md) {
                        legendMark("Доход", color: AppTheme.Colors.accent)
                        legendMark("Расход", color: AppTheme.Colors.textTertiary)
                    }
                }

                ChartDrawIn { factor in
                    Chart {
                        ForEach(months) { month in
                            BarMark(
                                x: .value("Месяц", Self.shortMonth(month.month)),
                                y: .value("Доход", month.totalIncome * factor),
                                width: .ratio(0.5)
                            )
                            .foregroundStyle(AppTheme.Colors.accent)
                            .cornerRadius(1.5)
                            BarMark(
                                x: .value("Месяц", Self.shortMonth(month.month)),
                                y: .value("Расход", -month.totalExpense * factor),
                                width: .ratio(0.5)
                            )
                            .foregroundStyle(AppTheme.Colors.textTertiary.opacity(0.75))
                            .cornerRadius(1.5)
                        }
                        RuleMark(y: .value("Ноль", 0))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.6))
                    }
                    .blueprintChartAxes(xLabelStride: months.count > 8 ? 2 : 1) { BlueprintChartFormat.compact($0) }
                    .frame(height: 170)
                }
                .accessibilityLabel("График дохода и расхода по месяцам")

                VStack(spacing: 0) {
                    ForEach(Array(months.suffix(6).reversed())) { month in
                        HStack(alignment: .firstTextBaseline) {
                            Text(monthLabel(year: month.year, month: month.month))
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(money(month.netCashflow))
                                    .font(AppTheme.Typography.moneyRow)
                                    .foregroundStyle(AppTheme.Colors.amount(month.netCashflow))
                                Text("\(money(month.totalIncome)) доход · \(money(month.totalExpense)) расход")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                            }
                        }
                        .padding(.vertical, AppTheme.Spacing.sm)
                        .overlay(alignment: .top) {
                            Rectangle().fill(AppTheme.Colors.border).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private var profitabilitySection: some View {
        let rows = Array(profitabilityTotals.suffix(8).reversed())
        let maximum = rows.map { abs($0.netCashflow) }.max() ?? 0
        return SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                SectionHeader("Прибыльность по периодам", subtitle: "Доход, расход и чистый поток.")
                VStack(spacing: AppTheme.Spacing.md) {
                    ForEach(rows, id: \.periodKey) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(DashboardAnalyticsLogic.periodTitle(row))
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                Spacer(minLength: 8)
                                Text(money(row.netCashflow))
                                    .font(AppTheme.Typography.moneyRow)
                                    .foregroundStyle(AppTheme.Colors.amount(row.netCashflow))
                            }
                            ProportionBar(value: row.netCashflow, maximum: maximum)
                            Text("\(money(row.totalIncome)) доход · \(money(row.totalExpense)) расход")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private var comparisonSection: some View {
        let maximum = comparisonRows.map { abs($0.netCashflow) }.max() ?? 0
        return SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                SectionHeader("Сравнение объектов", subtitle: "Нажмите объект, чтобы включить или исключить его.")
                if !properties.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            ForEach(properties) { property in
                                let selected = selectedPropertyIds.isEmpty
                                    || selectedPropertyIds.contains(property.id)
                                Button {
                                    withAnimation(AppTheme.Motion.resolved(AppTheme.Motion.normal, reduceMotion: reduceMotion)) {
                                        toggleProperty(property.id)
                                    }
                                } label: {
                                    Label(
                                        property.name,
                                        systemImage: selected ? "checkmark" : "plus"
                                    )
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 36)
                                    .foregroundStyle(selected
                                                     ? AppTheme.Colors.accent
                                                     : AppTheme.Colors.textSecondary)
                                    .background(
                                        selected ? AppTheme.Colors.accent.opacity(0.08) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: AppTheme.Radius.inner, style: .continuous)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: AppTheme.Radius.inner, style: .continuous)
                                            .strokeBorder(
                                                selected ? AppTheme.Colors.accent.opacity(0.4) : AppTheme.Colors.border,
                                                lineWidth: 1
                                            )
                                    )
                                    .contentTransition(.symbolEffect(.replace))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }
                    }
                }
                VStack(spacing: AppTheme.Spacing.md) {
                    ForEach(comparisonRows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.propertyName)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Text(money(row.netCashflow))
                                    .font(AppTheme.Typography.moneyRow)
                                    .foregroundStyle(AppTheme.Colors.amount(row.netCashflow))
                            }
                            ProportionBar(value: row.netCashflow, maximum: maximum)
                            Text(
                                "\(money(row.income)) доход · "
                                + "\(money(row.operatingCost)) расходы · "
                                + "\(money(row.utilityExpense)) ком. услуги"
                            )
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                        .transition(.opacity)
                    }
                }
            }
        }
    }

    private var recentTransactionsSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                SectionHeader(
                    "Последние операции",
                    subtitle: "Движение денег по всему портфелю."
                )

                if recentTransactionsLoadFailed {
                    HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(AppTheme.Colors.warning)
                        Text(
                            recentTransactions.isEmpty
                                ? "Не удалось загрузить операции. Потяните экран, чтобы повторить."
                                : "Часть операций не обновилась; показаны доступные данные."
                        )
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    .padding(AppTheme.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.Colors.warning.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.inner, style: .continuous))
                }

                if recentTransactions.isEmpty, !recentTransactionsLoadFailed {
                    Text("Операций пока нет.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, AppTheme.Spacing.sm)
                } else {
                    VStack(spacing: 0) {
                        ForEach(visibleRecentTransactions) { row in
                            Button {
                                notificationRouter.open(
                                    NotificationRoute(kind: .transaction(row.id))
                                )
                            } label: {
                                recentTransactionRow(row)
                            }
                            .buttonStyle(.plain)

                            if row.id != visibleRecentTransactions.last?.id {
                                Rectangle().fill(AppTheme.Colors.border).frame(height: 1)
                            }
                        }
                    }
                }

                if let recentTransactionsAction {
                    Button {
                        withAnimation(AppTheme.Motion.resolved(AppTheme.Motion.normal, reduceMotion: reduceMotion)) {
                            handleRecentTransactionsAction(recentTransactionsAction)
                        }
                    } label: {
                        Label(
                            recentTransactionsAction == .expand
                                ? "Смотреть больше"
                                : "Перейти на страницу Операций",
                            systemImage: recentTransactionsAction == .expand
                                ? "chevron.down"
                                : "arrow.right"
                        )
                    }
                    .buttonStyle(QuietActionButtonStyle())
                }
            }
        }
    }

    private func recentTransactionRow(
        _ row: DashboardRecentTransactionRow
    ) -> some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.sm) {
            Image(systemName: row.isIncome ? "arrow.down.left" : "arrow.up.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(row.isIncome ? AppTheme.Colors.accent : AppTheme.Colors.textSecondary)
                .frame(width: 20)
                .accessibilityLabel(row.isIncome ? "Доход" : "Расход")

            VStack(alignment: .leading, spacing: 3) {
                Text(row.propertyName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)

                Text(Self.recentDetail(row))
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: AppTheme.Spacing.sm)

            Text(
                "\(row.amountSign)"
                + AppFormatting.currency(abs(row.amount), currency: row.currency)
            )
            .font(AppTheme.Typography.moneyRow)
            .foregroundStyle(
                row.isIncome ? AppTheme.Colors.income : AppTheme.Colors.expense
            )
        }
        .contentShape(Rectangle())
        .frame(minHeight: 44)
        .padding(.vertical, AppTheme.Spacing.xs)
    }

    private static func recentDetail(_ row: DashboardRecentTransactionRow) -> String {
        var parts = [
            AppFormatting.dateString(
                from: row.transactionDate,
                dateStyle: .medium,
                timeStyle: DateFormatter.Style.none
            ) ?? row.transactionDate
        ]
        if let category = row.categoryName?.trimmingCharacters(in: .whitespacesAndNewlines), !category.isEmpty {
            parts.append(category)
        }
        if let description = row.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            parts.append(description)
        }
        return parts.joined(separator: " · ")
    }

    private func handleRecentTransactionsAction(
        _ action: DashboardRecentTransactionsAction
    ) {
        switch action {
        case .expand:
            recentTransactionsExpanded = true
        case .openTransactions:
            notificationRouter.open(NotificationRoute(kind: .transactions))
        }
    }

    private var calendarSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                SectionHeader(title: "Покрытие аренды по дням", subtitle: nil) {
                    Text("\(coverageSummary.coveragePct)%")
                        .font(AppTheme.Typography.moneyRow)
                        .foregroundStyle(AppTheme.Colors.accent)
                        .contentTransition(.numericText())
                }
                HStack {
                    Picker("Месяц", selection: $calendarMonth) {
                        ForEach(1...12, id: \.self) { month in
                            Text(monthLabel(year: calendarYear, month: month)).tag(month)
                        }
                    }
                    Picker("Год", selection: $calendarYear) {
                        ForEach(availableYears, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    Spacer()
                }
                .padding(.leading, -12)
                HStack(spacing: 0) {
                    MetricTile(title: "Дней", value: "\(coverageSummary.rentDays)")
                    MetricTile(title: "Оплачено", value: "\(coverageSummary.paidDays)", tint: AppTheme.Colors.accent)
                    MetricTile(
                        title: "Без оплаты",
                        value: "\(coverageSummary.unpaidDays)",
                        tint: coverageSummary.unpaidDays > 0 ? AppTheme.Colors.danger : AppTheme.Colors.textPrimary
                    )
                }
                LazyVGrid(columns: calendarColumns, spacing: 6) {
                    ForEach(weekdays, id: \.self) { weekday in
                        Text(weekday)
                            .sectionLabelStyle()
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(
                        0..<DashboardAnalyticsLogic.leadingWeekdaySlots(
                            year: calendarYear,
                            month: calendarMonth
                        ),
                        id: \.self
                    ) { _ in
                        Color.clear.frame(height: 40)
                    }
                    ForEach(calendarDays) { day in
                        calendarCell(day)
                    }
                }
                .animation(AppTheme.Motion.resolved(AppTheme.Motion.normal, reduceMotion: reduceMotion), value: calendarMonth)
                HStack(spacing: 12) {
                    legendMark("Оплачено", color: AppTheme.Colors.accent)
                    legendMark("Частично", color: AppTheme.Colors.accent.opacity(0.35))
                    legendMark("Не оплачено", color: AppTheme.Colors.danger, outlined: true)
                }
            }
        }
    }

    private func calendarCell(_ day: DashboardCalendarDay) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return Button {
            selectedCalendarDay = DashboardAnalyticsLogic.calendarDayDetail(
                date: day.date,
                properties: properties,
                leases: leases,
                schedules: paymentSchedules,
                tenants: tenants,
                transactions: portfolioTransactions,
                categories: incomeCategories
            )
        } label: {
            Text(String(day.day))
                .font(.caption.weight(day.isToday || day.dueScheduleCount > 0 ? .bold : .medium))
                .monospacedDigit()
                .foregroundStyle(coverageInk(day.state))
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(coverageColor(day.state), in: shape)
                .overlay {
                    shape.strokeBorder(
                        day.isToday
                            ? AppTheme.Colors.textPrimary
                            : (day.state == .unpaid ? AppTheme.Colors.danger.opacity(0.55) : Color.clear),
                        lineWidth: day.isToday ? 2 : 1
                    )
                }
                .overlay(alignment: .bottom) {
                    if day.dueScheduleCount > 0 {
                        Circle()
                            .fill(coverageInk(day.state))
                            .frame(width: 4, height: 4)
                            .padding(.bottom, 4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(calendarAccessibility(day))
        .accessibilityHint("Открывает детали аренды за этот день")
    }

    private func legendMark(_ title: String, color: Color, outlined: Bool = false) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(outlined ? color.opacity(0.1) : color)
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(outlined ? color : Color.clear, lineWidth: 1)
                )
                .frame(width: 10, height: 10)
            Text(title)
                .font(.caption2)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
    }

    private var utilitiesSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                SectionHeader("История ком. услуг", subtitle: "Начисления арендаторов по объектам.")
                VStack(spacing: 0) {
                    ForEach(Array(utilities.prefix(12))) { utility in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(utility.propertyName ?? "Объект")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                    .lineLimit(1)
                                Text(
                                    "\(utilityTypeLabel(utility.utilityType)) · "
                                    + "\(String(format: "%02d.%d", utility.periodMonth, utility.periodYear))"
                                )
                                .font(.caption2)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                            }
                            Spacer(minLength: 8)
                            Text(AppFormatting.currency(utility.amount, currency: utility.currency))
                                .font(AppTheme.Typography.moneyRow)
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                        }
                        .padding(.vertical, AppTheme.Spacing.sm)
                        .overlay(alignment: .top) {
                            Rectangle().fill(AppTheme.Colors.border).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Small building blocks

    private func infoBanner(_ message: String) -> some View {
        SurfaceCard(padding: AppTheme.Spacing.md) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(AppTheme.Colors.warning)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
    }

    private static let shortMonths = [
        "янв", "фев", "мар", "апр", "май", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"
    ]

    private static func shortMonth(_ month: Int) -> String {
        shortMonths.indices.contains(month - 1) ? shortMonths[month - 1] : String(month)
    }

    private func coverageInk(_ state: DashboardCoverageState) -> Color {
        switch state {
        case .noLease: return AppTheme.Colors.textSecondary
        case .paid: return AppTheme.Colors.onAccent
        case .partial: return AppTheme.Colors.textPrimary
        case .unpaid: return AppTheme.Colors.danger
        }
    }

    private func money(_ amount: Double) -> String {
        guard amount.isFinite else { return AppFormatting.currency(0, currency: currency) }
        return AppFormatting.currency(amount, currency: currency)
    }

    private func monthLabel(year: Int, month: Int) -> String {
        DashboardAnalyticsLogic.monthTitle(year: year, month: month)
    }

    private func coverageColor(_ state: DashboardCoverageState) -> Color {
        switch state {
        case .noLease: return AppTheme.Colors.backgroundSecondary
        case .paid: return AppTheme.Colors.accent
        case .partial: return AppTheme.Colors.accent.opacity(0.35)
        case .unpaid: return Color.clear
        }
    }

    private func calendarAccessibility(_ day: DashboardCalendarDay) -> String {
        let status: String
        switch day.state {
        case .noLease: status = "нет активной аренды"
        case .paid: status = "оплачено"
        case .partial: status = "оплачено частично"
        case .unpaid: status = "не оплачено"
        }
        let due = day.dueScheduleCount > 0 ? ", срок платежа" : ""
        return "\(day.day), \(status)\(due)"
    }

    private func toggleProperty(_ id: String) {
        if selectedPropertyIds.isEmpty {
            selectedPropertyIds = Set(properties.map(\.id))
        }
        if selectedPropertyIds.contains(id) {
            selectedPropertyIds.remove(id)
        } else {
            selectedPropertyIds.insert(id)
        }
    }

    private func utilityTypeLabel(_ type: String) -> String {
        switch type {
        case "electricity": return "Электричество"
        case "cold_water": return "Холодная вода"
        case "hot_water": return "Горячая вода"
        case "water": return "Вода"
        case "water_disposal": return "Водоотведение"
        case "gas": return "Газ"
        case "heating": return "Отопление"
        case "common_area": return "МОП"
        case "waste": return "Вывоз отходов"
        case "elevator": return "Лифт"
        case "intercom": return "Домофон"
        case "internet": return "Интернет"
        case "tv": return "ТВ"
        case "capital_repair": return "Капремонт"
        case "maintenance": return "Обслуживание"
        case "utilities": return "Ком. услуги"
        case "other": return "Другое"
        default: return type.replacingOccurrences(of: "_", with: " ")
        }
    }

    // MARK: - Export

    private func exportDashboard(as format: DashboardExportFormat) {
        guard let report = profitabilityReport else { return }
        exportErrorMessage = nil
        do {
            let url: URL
            let title: String
            switch format {
            case .csv:
                url = temporaryExportURL(fileExtension: "csv")
                try DashboardAnalyticsLogic.csv(report: report)
                    .write(to: url, atomically: true, encoding: .utf8)
                title = "CSV аналитики готов"
            case .pdf:
                url = try makeDashboardPDF(report: report)
                title = "PDF аналитики готов"
            }
            exportDocument = DashboardExportDocument(title: title, url: url)
        } catch {
            exportErrorMessage = "Не удалось подготовить файл аналитики."
        }
    }

    private func makeDashboardPDF(report: ProfitabilityReport) throws -> URL {
        let url = temporaryExportURL(fileExtension: "pdf")
        let bounds = CGRect(x: 0, y: 0, width: 842, height: 595)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        try renderer.writePDF(to: url) { context in
            var y: CGFloat = 34
            beginPDFPage(context: context, bounds: bounds, report: report, y: &y)
            for row in report.totals {
                if y > bounds.height - 42 {
                    beginPDFPage(context: context, bounds: bounds, report: report, y: &y)
                }
                drawPDFRow(row, bounds: bounds, y: y)
                y += 18
            }
        }
        return url
    }

    private func beginPDFPage(
        context: UIGraphicsPDFRendererContext,
        bounds: CGRect,
        report: ProfitabilityReport,
        y: inout CGFloat
    ) {
        context.beginPage()
        y = 34
        drawPDFText(
            "Аналитика прибыльности",
            x: 32,
            y: y,
            width: bounds.width - 64,
            font: .boldSystemFont(ofSize: 20)
        )
        y += 28
        drawPDFText(
            "\(report.from) – \(report.to) · \(analyticsGroup.title)",
            x: 32,
            y: y,
            width: bounds.width - 64,
            font: .systemFont(ofSize: 10),
            color: .darkGray
        )
        y += 24
        drawPDFHeaders(bounds: bounds, y: y)
        y += 18
    }

    private func drawPDFHeaders(bounds: CGRect, y: CGFloat) {
        let headers = ["Период", "Доход", "Расходы", "Ком. услуги", "Чистое", "Маржа"]
        let columns = pdfColumns(bounds: bounds)
        for index in headers.indices {
            drawPDFText(
                headers[index],
                x: columns[index].minX,
                y: y,
                width: columns[index].width,
                font: .boldSystemFont(ofSize: 9)
            )
        }
    }

    private func drawPDFRow(_ row: ProfitabilityPoint, bounds: CGRect, y: CGFloat) {
        let columns = pdfColumns(bounds: bounds)
        let values = [
            row.periodLabel.isEmpty ? row.periodKey : row.periodLabel,
            money(row.totalIncome),
            money(row.operatingCost),
            money(row.utilityExpense),
            money(row.netCashflow),
            String(format: "%.1f%%", row.profitMarginPct),
        ]
        for index in values.indices {
            drawPDFText(
                values[index],
                x: columns[index].minX,
                y: y,
                width: columns[index].width,
                font: .systemFont(ofSize: 8.5)
            )
        }
    }

    private func pdfColumns(bounds: CGRect) -> [CGRect] {
        let x: CGFloat = 32
        return [
            CGRect(x: x, y: 0, width: 170, height: 16),
            CGRect(x: x + 176, y: 0, width: 110, height: 16),
            CGRect(x: x + 292, y: 0, width: 110, height: 16),
            CGRect(x: x + 408, y: 0, width: 110, height: 16),
            CGRect(x: x + 524, y: 0, width: 110, height: 16),
            CGRect(x: x + 640, y: 0, width: bounds.width - 672, height: 16),
        ]
    }

    private func drawPDFText(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        font: UIFont,
        color: UIColor = .black
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(
            in: CGRect(x: x, y: y, width: width, height: 18),
            withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph,
            ]
        )
    }

    private func temporaryExportURL(fileExtension: String) -> URL {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "dashboard-profitability-\(formatter.string(from: Date())).\(fileExtension)"
            )
    }

    // MARK: - Data

    private func refreshNotificationUnread() async {
        do {
            let unread: UnreadCountData = try await APIClient.shared.request(
                "/v1/notifications/unread-count",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            notificationUnreadCount = unread.count
        } catch {
            notificationUnreadCount = 0
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        await loadDashboard()
        await loadSecondaryAnalytics()
        await loadProfitability()
        await loadPortfolioCalendar()
        await loadRecentTransactions()
        await loadUtilities()
    }

    private func loadDashboard() async {
        do {
            let result: AnalyticsDashboard = try await APIClient.shared.request(
                "/v1/analytics/dashboard?period=\(period.rawValue)",
                tokenProvider: tokenProvider,
                refreshAndRetry: refreshProvider
            )
            dashboard = result
            errorMessage = nil
        } catch {
            errorMessage = dashboard == nil
                ? "Не удалось загрузить дашборд. Проверьте соединение."
                : "Часть данных не обновилась."
        }
    }

    private func loadSecondaryAnalytics() async {
        occupancy = try? await APIClient.shared.request(
            "/v1/analytics/occupancy",
            tokenProvider: tokenProvider,
            refreshAndRetry: refreshProvider
        )
        overdue = try? await APIClient.shared.request(
            "/v1/analytics/overdue-payments",
            tokenProvider: tokenProvider,
            refreshAndRetry: refreshProvider
        )
        cashflowTrend = try? await APIClient.shared.request(
            "/v1/analytics/cashflow-trend?months=12",
            tokenProvider: tokenProvider,
            refreshAndRetry: refreshProvider
        )
    }

    private func loadProfitability() async {
        isAnalyticsLoading = true
        defer { isAnalyticsLoading = false }
        let range = analyticsRange.dateRange()
        let path = "/v1/analytics/profitability"
            + "?from=\(range.from)&to=\(range.to)&group_by=\(analyticsGroup.rawValue)"
        if let report: ProfitabilityReport = try? await APIClient.shared.request(
            path,
            tokenProvider: tokenProvider,
            refreshAndRetry: refreshProvider
        ) {
            profitabilityReport = report
        }
    }

    private func loadUtilities() async {
        if let history: [PropertyUtility] = try? await APIClient.shared.request(
            "/v1/analytics/utilities-history?months=24",
            tokenProvider: tokenProvider,
            refreshAndRetry: refreshProvider
        ) {
            utilities = history.sorted {
                ($0.periodYear, $0.periodMonth) > ($1.periodYear, $1.periodMonth)
            }
        }
    }

    private func loadPortfolioCalendar() async {
        guard let loadedProperties: [Property] = try? await APIClient.shared.request(
            "/v1/properties",
            tokenProvider: tokenProvider,
            refreshAndRetry: refreshProvider
        ) else {
            return
        }
        properties = loadedProperties
        if selectedPropertyIds.isEmpty {
            selectedPropertyIds = Set(loadedProperties.map(\.id))
        }
        if let loadedTenants: [Tenant] = try? await APIClient.shared.request(
            "/v1/tenants?per_page=100",
            tokenProvider: tokenProvider,
            refreshAndRetry: refreshProvider
        ) {
            tenants = loadedTenants
        }
        if let loadedCategories: [Category] = try? await APIClient.shared.request(
            "/v1/categories?type=income",
            tokenProvider: tokenProvider,
            refreshAndRetry: refreshProvider
        ) {
            incomeCategories = loadedCategories
        }

        var loadedLeases: [Lease] = []
        for property in loadedProperties {
            if let propertyLeases: [Lease] = try? await APIClient.shared.request(
                "/v1/properties/\(property.id)/leases",
                tokenProvider: tokenProvider,
                refreshAndRetry: refreshProvider
            ) {
                loadedLeases.append(contentsOf: propertyLeases)
            }
        }
        leases = loadedLeases

        var loadedSchedules: [LeasePaymentSchedule] = []
        for lease in loadedLeases {
            guard let data = try? await APIClient.shared.requestData(
                "/v1/leases/\(lease.id)/payment-schedule",
                tokenProvider: tokenProvider,
                refreshAndRetry: refreshProvider
            ), let envelope = try? JSONDecoder().decode(
                APIListEnvelope<LeasePaymentSchedule>.self,
                from: data
            ) else {
                continue
            }
            loadedSchedules.append(contentsOf: envelope.data)
        }
        paymentSchedules = loadedSchedules
    }

    private func loadRecentTransactions() async {
        var sourceProperties = properties
        if sourceProperties.isEmpty {
            do {
                sourceProperties = try await APIClient.shared.request(
                    "/v1/properties",
                    tokenProvider: tokenProvider,
                    refreshAndRetry: refreshProvider
                )
            } catch {
                recentTransactionsLoadFailed = true
                return
            }
        }

        var merged: [Transaction] = []
        var failed = false
        for property in sourceProperties {
            do {
                let data = try await APIClient.shared.requestData(
                    "/v1/properties/\(property.id)/transactions?per_page=100",
                    tokenProvider: tokenProvider,
                    refreshAndRetry: refreshProvider
                )
                let decoded = try JSONDecoder().decode(
                    APIResponse<[Transaction]>.self,
                    from: data
                )
                merged.append(contentsOf: decoded.data)
            } catch {
                failed = true
            }
        }

        let rows = DashboardRecentTransactionsLogic.rows(
            transactions: merged,
            propertyNames: Dictionary(
                uniqueKeysWithValues: sourceProperties.map { ($0.id, $0.name) }
            )
        )
        if !rows.isEmpty || !failed {
            portfolioTransactions = merged
            recentTransactions = rows
        }
        recentTransactionsLoadFailed = failed
    }

    private func tokenProvider() async -> String? {
        await MainActor.run { authManager.accessToken }
    }

    private func refreshProvider() async -> Bool {
        await authManager.refreshToken()
    }
}

private struct DashboardCalendarDayDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let detail: DashboardCalendarDayDetail

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    summary

                    if detail.entries.isEmpty {
                        SurfaceCard {
                            VStack(spacing: AppTheme.Spacing.sm) {
                                Image(systemName: "house")
                                    .font(.title2)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                                Text("На эту дату активной аренды нет.")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppTheme.Spacing.lg)
                        }
                    } else {
                        ForEach(detail.entries) { entry in
                            leaseCard(entry)
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.lg)
            }
            .background(AppScreenBackground())
            .navigationTitle("Детали дня")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }

    private var summary: some View {
        SurfaceCard {
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(formattedDay)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(1.2)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    Text(
                        detail.activeLeaseCount == 0
                            ? "Активной аренды нет"
                            : "Оплачено \(detail.paidLeaseCount) из \(detail.activeLeaseCount)"
                    )
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                }
                Spacer()
                Text("\(detail.coveragePct)%")
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.onAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppTheme.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.stamp, style: .continuous))
            }
        }
    }

    private func leaseCard(
        _ entry: DashboardCalendarLeaseDetail
    ) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.propertyName)
                            .font(.headline)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Text(entry.tenantName)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    Spacer()
                    paymentBadge(entry.isPaid)
                }

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .leading,
                    spacing: AppTheme.Spacing.md
                ) {
                    detailField(
                        title: "Аренда",
                        value: AppFormatting.currency(
                            entry.rentAmount,
                            currency: entry.rentCurrency
                        )
                    )
                    detailField(
                        title: "Въезд",
                        value: formattedDate(entry.moveInDate)
                    )
                    detailField(
                        title: "Выезд",
                        value: entry.moveOutDate.map(formattedDate)
                            ?? "Сейчас проживает"
                    )
                    if entry.isPaymentDue {
                        detailField(title: "Срок оплаты", value: "Сегодня")
                    }
                }

                Divider()

                detailField(
                    title: "Оплата",
                    value: paymentDescription(entry.payment)
                )
            }
        }
    }

    private func paymentBadge(_ isPaid: Bool) -> some View {
        StatusBadge(label: isPaid ? "Оплачено" : "Без оплаты", tone: isPaid ? .success : .danger)
    }

    private func detailField(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.9)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func paymentDescription(
        _ payment: DashboardCalendarPaymentDetail?
    ) -> String {
        guard let payment else {
            return "Нет оплаты за этот период"
        }
        return AppFormatting.currency(payment.amount, currency: payment.currency)
            + " за \(formattedDate(payment.periodStartDate))"
            + " – \(formattedDate(payment.periodEndDate))"
    }

    private var formattedDay: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy 'г.'"
        return formatter.string(from: detail.date)
    }

    private func formattedDate(_ raw: String) -> String {
        AppFormatting.dateString(
            from: raw,
            dateStyle: .medium,
            timeStyle: DateFormatter.Style.none
        ) ?? raw
    }
}
