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
    }

    @State private var period: Period = .month
    @State private var dashboard: AnalyticsDashboard?
    @State private var occupancy: OccupancyPayload?
    @State private var profitabilityReport: ProfitabilityReport?
    @State private var overdue: OverduePaymentsPayload?
    @State private var cashflowTrend: CashflowTrendBody?
    @State private var utilities: [PropertyUtility] = []
    @State private var properties: [Property] = []
    @State private var leases: [Lease] = []
    @State private var paymentSchedules: [LeasePaymentSchedule] = []
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
            schedules: paymentSchedules
        )
    }
    private var coverageSummary: DashboardCoverageSummary {
        DashboardAnalyticsLogic.coverageSummary(days: calendarDays)
    }
    private var availableYears: [Int] {
        DashboardAnalyticsLogic.availableYears(leases: leases)
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
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                VStack(spacing: AppTheme.Spacing.lg) {
                    periodSelector
                    if let errorMessage { infoBanner(errorMessage) }
                    kpiSection
                    occupancySection
                    analyticsControls
                    if let overdue { overdueSection(overdue) }
                    if let cashflowTrend, !cashflowTrend.months.isEmpty {
                        cashflowSection(cashflowTrend)
                    }
                    if !profitabilityTotals.isEmpty {
                        profitabilitySection
                    }
                    if !comparisonRows.isEmpty {
                        comparisonSection
                    }
                    if !leases.isEmpty {
                        calendarSection
                    }
                    if !utilities.isEmpty {
                        utilitiesSection
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.lg)
            }
        }
    }

    private var notificationButton: some View {
        Button {
            showNotifications = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.body.weight(.medium))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                if notificationUnreadCount > 0 {
                    Text(notificationUnreadCount > 99 ? "99+" : "\(notificationUnreadCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(AppTheme.Colors.danger.clipShape(Capsule()))
                        .offset(x: 10, y: -10)
                }
            }
            .frame(minWidth: 36, minHeight: 36)
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
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
        .disabled(profitabilityReport == nil)
        .accessibilityLabel("Экспорт аналитики")
    }

    private var periodSelector: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Период сводки")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Picker("Период", selection: $period) {
                    ForEach(Period.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var kpiSection: some View {
        let d = dashboard
        return LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: AppTheme.Spacing.md
        ) {
            KPICard(
                title: "Полученный доход",
                value: money(d?.totalIncome ?? 0),
                icon: "arrow.down.circle",
                color: AppTheme.Colors.success,
                subtitle: d.map { "Депозиты: \(money($0.depositIncome))" } ?? " "
            )
            KPICard(
                title: "Расходы",
                value: money(d?.totalExpense ?? 0),
                icon: "arrow.up.circle",
                color: AppTheme.Colors.danger,
                subtitle: "Операционные траты владельца."
            )
            KPICard(
                title: "Аренда к получению",
                value: money(d?.rentOutstanding ?? 0),
                icon: "banknote",
                color: (d?.rentOutstanding ?? 0) > 0
                    ? AppTheme.Colors.warning
                    : AppTheme.Colors.success,
                subtitle: d.map {
                    "Начислено \(money($0.expectedRent)), оплачено \(money($0.rentReceived))."
                } ?? " "
            )
            KPICard(
                title: "Чистый cashflow",
                value: money(d?.netCashflow ?? 0),
                icon: "chart.line.uptrend.xyaxis",
                color: (d?.netCashflow ?? 0) >= 0
                    ? AppTheme.Colors.success
                    : AppTheme.Colors.danger,
                subtitle: d?.periodLabel ?? period.title
            )
        }
    }

    private var occupancySection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                sectionHeading("Заселенность", subtitle: "Занятые объекты портфеля.")
                HStack(spacing: AppTheme.Spacing.sm) {
                    metric(title: "Занято", value: "\(occupancy?.occupied ?? 0)")
                    metric(title: "Всего", value: "\(occupancy?.total ?? 0)")
                    metric(title: "Доля", value: "\(occupancy?.ratePct ?? 0)%")
                }
            }
        }
    }

    private var analyticsControls: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack {
                    sectionHeading(
                        "Аналитика прибыльности",
                        subtitle: "Диапазон и группировка применяются ко всем строкам ниже."
                    )
                    Spacer()
                    if isAnalyticsLoading { ProgressView().controlSize(.small) }
                }
                Picker("Диапазон", selection: $analyticsRange) {
                    ForEach(DashboardAnalyticsRange.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Группировка", selection: $analyticsGroup) {
                    ForEach(DashboardAnalyticsGroup.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private func overdueSection(_ payload: OverduePaymentsPayload) -> some View {
        SurfaceCard {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: payload.overdueCount > 0 ? "clock.badge.exclamationmark" : "checkmark.circle")
                    .font(.title2)
                    .foregroundStyle(payload.overdueCount > 0 ? AppTheme.Colors.warning : AppTheme.Colors.success)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Просроченные платежи")
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text(payload.overdueCount == 0
                         ? "Просроченных начислений нет."
                         : "Требуют внимания: \(payload.overdueCount)")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                Spacer()
                Text("\(payload.overdueCount)")
                    .font(.title.weight(.bold))
                    .foregroundStyle(payload.overdueCount > 0 ? AppTheme.Colors.warning : AppTheme.Colors.success)
            }
        }
    }

    private func cashflowSection(_ trend: CashflowTrendBody) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                sectionHeading("Cashflow за 12 месяцев", subtitle: "Последние доступные месяцы.")
                ForEach(Array(trend.months.suffix(6).reversed())) { month in
                    HStack {
                        Text(monthLabel(year: month.year, month: month.month))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(money(month.netCashflow))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(month.netCashflow >= 0
                                                 ? AppTheme.Colors.success
                                                 : AppTheme.Colors.danger)
                            Text("\(money(month.totalIncome)) доход · \(money(month.totalExpense)) расход")
                                .font(.caption2)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.xs)
                }
            }
        }
    }

    private var profitabilitySection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                sectionHeading("Прибыльность по периодам", subtitle: "Доход, расход и чистый поток.")
                ForEach(Array(profitabilityTotals.suffix(8).reversed()), id: \.periodKey) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.periodLabel.isEmpty ? row.periodKey : row.periodLabel)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(money(row.netCashflow))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(row.netCashflow >= 0
                                                 ? AppTheme.Colors.success
                                                 : AppTheme.Colors.danger)
                            Text("\(money(row.totalIncome)) доход · \(money(row.totalExpense)) расход")
                                .font(.caption2)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.xs)
                }
            }
        }
    }

    private var comparisonSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                sectionHeading("Сравнение объектов", subtitle: "Нажмите объект, чтобы включить или исключить его.")
                if !properties.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            ForEach(properties) { property in
                                let selected = selectedPropertyIds.isEmpty
                                    || selectedPropertyIds.contains(property.id)
                                Button {
                                    toggleProperty(property.id)
                                } label: {
                                    Label(
                                        property.name,
                                        systemImage: selected ? "checkmark.circle.fill" : "circle"
                                    )
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .foregroundStyle(selected
                                                     ? AppTheme.Colors.accent
                                                     : AppTheme.Colors.textSecondary)
                                    .background(AppTheme.Colors.backgroundSecondary.opacity(0.85))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                ForEach(comparisonRows) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(row.propertyName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                            Spacer()
                            Text(money(row.netCashflow))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(row.netCashflow >= 0
                                                 ? AppTheme.Colors.success
                                                 : AppTheme.Colors.danger)
                        }
                        Text(
                            "\(money(row.income)) доход · "
                            + "\(money(row.operatingCost)) расходы · "
                            + "\(money(row.utilityExpense)) ком. услуги"
                        )
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    .padding(.vertical, AppTheme.Spacing.xs)
                }
            }
        }
    }

    private var calendarSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                sectionHeading(
                    "Покрытие аренды по дням",
                    subtitle: "Один месяц без тяжёлой годовой сетки."
                )
                HStack {
                    Picker("Год", selection: $calendarYear) {
                        ForEach(availableYears, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    Picker("Месяц", selection: $calendarMonth) {
                        ForEach(1...12, id: \.self) { month in
                            Text(monthLabel(year: calendarYear, month: month)).tag(month)
                        }
                    }
                    Spacer()
                    Text("\(coverageSummary.coveragePct)%")
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.accent)
                }
                HStack(spacing: AppTheme.Spacing.sm) {
                    metric(title: "Дней аренды", value: "\(coverageSummary.rentDays)")
                    metric(title: "Оплачено", value: "\(coverageSummary.paidDays)")
                    metric(title: "Без оплаты", value: "\(coverageSummary.unpaidDays)")
                }
                LazyVGrid(columns: calendarColumns, spacing: 6) {
                    ForEach(weekdays, id: \.self) { weekday in
                        Text(weekday)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(
                        0..<DashboardAnalyticsLogic.leadingWeekdaySlots(
                            year: calendarYear,
                            month: calendarMonth
                        ),
                        id: \.self
                    ) { _ in
                        Color.clear.frame(height: 38)
                    }
                    ForEach(calendarDays) { day in
                        calendarCell(day)
                    }
                }
                HStack(spacing: 12) {
                    legendDot("Оплачено", color: AppTheme.Colors.success)
                    legendDot("Частично", color: AppTheme.Colors.warning)
                    legendDot("Не оплачено", color: AppTheme.Colors.danger)
                }
            }
        }
    }

    private func calendarCell(_ day: DashboardCalendarDay) -> some View {
        Text(String(day.day))
            .font(.caption.weight(day.isToday || day.dueScheduleCount > 0 ? .bold : .medium))
            .foregroundStyle(day.state == .noLease
                             ? AppTheme.Colors.textSecondary
                             : Color.white)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(coverageColor(day.state))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        day.isToday
                            ? AppTheme.Colors.accent
                            : (day.dueScheduleCount > 0 ? AppTheme.Colors.warning : Color.clear),
                        lineWidth: day.isToday ? 2.5 : 1.5
                    )
            }
            .accessibilityLabel(calendarAccessibility(day))
    }

    private func legendDot(_ title: String, color: Color) -> some View {
        Label {
            Text(title).font(.caption2)
        } icon: {
            Circle().fill(color).frame(width: 8, height: 8)
        }
        .foregroundStyle(AppTheme.Colors.textSecondary)
    }

    private var utilitiesSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                sectionHeading("История ком. услуг", subtitle: "Начисления арендаторов по объектам.")
                ForEach(Array(utilities.prefix(12))) { utility in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(utility.propertyName ?? "Объект")
                                .font(.subheadline.weight(.medium))
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
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                    }
                    .padding(.vertical, AppTheme.Spacing.xs)
                }
            }
        }
    }

    // MARK: - Small building blocks

    private func sectionHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func infoBanner(_ message: String) -> some View {
        SurfaceCard(padding: AppTheme.Spacing.md) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppTheme.Colors.warning)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
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
        case .paid: return AppTheme.Colors.success
        case .partial: return AppTheme.Colors.warning
        case .unpaid: return AppTheme.Colors.danger
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

    private func tokenProvider() async -> String? {
        await MainActor.run { authManager.accessToken }
    }

    private func refreshProvider() async -> Bool {
        await authManager.refreshToken()
    }
}
