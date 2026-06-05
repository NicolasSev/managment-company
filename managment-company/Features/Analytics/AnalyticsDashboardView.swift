import SwiftUI
import UIKit

private enum AnalyticsDashboardPeriod: String, CaseIterable, Identifiable {
    case all
    case month
    case season
    case quarter
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "За всё время"
        case .month: return "За месяц"
        case .season: return "За сезон"
        case .quarter: return "За квартал"
        case .year: return "За год"
        }
    }
}

private enum AnalyticsRangeFilter: String, CaseIterable, Identifiable {
    case all
    case twelveMonths
    case sixMonths
    case threeMonths

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Все"
        case .twelveMonths: return "12 мес."
        case .sixMonths: return "6 мес."
        case .threeMonths: return "3 мес."
        }
    }

    func dateRange(now: Date = Date()) -> (from: String, to: String) {
        let calendar = Calendar.current
        let to = Self.isoDate(now)
        let from: Date
        switch self {
        case .all:
            from = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? now
        case .twelveMonths:
            from = calendar.date(byAdding: .month, value: -11, to: calendar.startOfMonth(for: now)) ?? now
        case .sixMonths:
            from = calendar.date(byAdding: .month, value: -5, to: calendar.startOfMonth(for: now)) ?? now
        case .threeMonths:
            from = calendar.date(byAdding: .month, value: -2, to: calendar.startOfMonth(for: now)) ?? now
        }
        return (Self.isoDate(from), to)
    }

    private static func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private enum AnalyticsGroupFilter: String, CaseIterable, Identifiable {
    case month
    case quarter
    case season
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: return "Месяцы"
        case .quarter: return "Кварталы"
        case .season: return "Сезоны"
        case .year: return "Годы"
        }
    }
}

private enum AnalyticsExportFormat {
    case csv
    case pdf
}

private struct AnalyticsExportDocument: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
}

private struct PropertyProfitabilitySummary: Identifiable {
    let propertyId: String
    let propertyName: String
    let income: Double
    let operatingCost: Double
    let utilityExpense: Double
    let netCashflow: Double

    var id: String { propertyId }
}

private struct UtilityMonthSummary: Identifiable {
    let key: String
    let year: Int
    let month: Int
    let total: Double
    let currency: String
    let items: [PropertyUtility]

    var id: String { key }
}

private struct UtilityPropertySummary: Identifiable {
    let propertyId: String
    let propertyName: String
    let currency: String
    let total: Double
    let months: [UtilityMonthSummary]

    var id: String { propertyId }
    var latest: UtilityMonthSummary? { months.last }
}

private struct OccupancyDaySummary: Identifiable {
    let key: String
    let date: Date
    let day: Int
    let month: Int
    let activeLeaseCount: Int
    let paidLeaseCount: Int
    let dueScheduleCount: Int
    let isToday: Bool

    var id: String { key }
    var hasRent: Bool { activeLeaseCount > 0 }
    var isFullyPaid: Bool { activeLeaseCount > 0 && paidLeaseCount >= activeLeaseCount }
    var isPartlyPaid: Bool { activeLeaseCount > 0 && paidLeaseCount > 0 && paidLeaseCount < activeLeaseCount }
}

private struct OccupancyMonthSummary: Identifiable {
    let year: Int
    let month: Int
    let days: [OccupancyDaySummary]

    var id: String { "\(year)-\(month)" }

    var rentDays: Int {
        days.reduce(0) { $0 + $1.activeLeaseCount }
    }

    var paidDays: Int {
        days.reduce(0) { $0 + min($1.paidLeaseCount, $1.activeLeaseCount) }
    }

    var coveragePct: Int {
        guard rentDays > 0 else { return 0 }
        return Int((Double(paidDays) / Double(rentDays) * 100).rounded())
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: DateComponents(year: components.year, month: components.month, day: 1)) ?? startOfDay(for: date)
    }
}

struct AnalyticsDashboardView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var dashboard: AnalyticsDashboard?
    @State private var overdue: OverduePaymentsPayload?
    @State private var cashflowTrend: CashflowTrendBody?
    @State private var profitability: ProfitabilityReport?
    @State private var properties: [Property] = []
    @State private var leases: [Lease] = []
    @State private var paymentSchedules: [LeasePaymentSchedule] = []
    @State private var utilityHistory: [PropertyUtility] = []
    @State private var isLoading = true
    @State private var dashboardPeriod: AnalyticsDashboardPeriod = .all
    @State private var analyticsRange: AnalyticsRangeFilter = .all
    @State private var profitabilityGroupBy: AnalyticsGroupFilter = .month
    @State private var selectedComparisonPropertyIds: Set<String> = []
    @State private var selectedOccupancyYear = Calendar.current.component(.year, from: Date())
    @State private var exportDocument: AnalyticsExportDocument?
    @State private var exportErrorMessage: String?

    /// Last months of cashflow trend, newest first.
    private var cashflowMonthsNewestFirst: [CashflowTrendMonth] {
        guard let rows = cashflowTrend?.months, !rows.isEmpty else { return [] }
        return Array(rows.suffix(12).reversed())
    }

    /// Portfolio totals, recent periods first.
    private var profitabilityTotalsNewestFirst: [ProfitabilityPoint] {
        guard let rows = profitability?.totals, !rows.isEmpty else { return [] }
        return Array(rows.reversed())
    }

    private var propertyComparisonRows: [PropertyProfitabilitySummary] {
        let selected = selectedComparisonPropertyIds.isEmpty
            ? Set(properties.map(\.id))
            : selectedComparisonPropertyIds
        var summaries: [String: PropertyProfitabilitySummary] = [:]

        for point in profitability?.points ?? [] {
            guard let propertyId = point.propertyId, selected.contains(propertyId) else { continue }
            let current = summaries[propertyId]
            summaries[propertyId] = PropertyProfitabilitySummary(
                propertyId: propertyId,
                propertyName: point.propertyName ?? properties.first(where: { $0.id == propertyId })?.name ?? "Объект",
                income: (current?.income ?? 0) + point.totalIncome,
                operatingCost: (current?.operatingCost ?? 0) + point.operatingCost,
                utilityExpense: (current?.utilityExpense ?? 0) + point.utilityExpense,
                netCashflow: (current?.netCashflow ?? 0) + point.netCashflow
            )
        }

        return summaries.values.sorted { $0.netCashflow > $1.netCashflow }
    }

    private var utilitySummaries: [UtilityPropertySummary] {
        var grouped: [String: (propertyName: String, currency: String, months: [String: [PropertyUtility]])] = [:]

        for utility in utilityHistory {
            let propertyId = utility.propertyId
            let propertyName = utility.propertyName ?? properties.first(where: { $0.id == propertyId })?.name ?? "Объект"
            let key = "\(utility.periodYear)-\(String(format: "%02d", utility.periodMonth))"
            var entry = grouped[propertyId] ?? (propertyName: propertyName, currency: utility.currency, months: [:])
            entry.months[key, default: []].append(utility)
            grouped[propertyId] = entry
        }

        return grouped.map { propertyId, entry in
            let months = entry.months.map { key, items -> UtilityMonthSummary in
                let first = items[0]
                return UtilityMonthSummary(
                    key: key,
                    year: first.periodYear,
                    month: first.periodMonth,
                    total: items.reduce(0) { $0 + $1.amount },
                    currency: first.currency,
                    items: items.sorted { $0.amount > $1.amount }
                )
            }
                .sorted { ($0.year, $0.month) < ($1.year, $1.month) }

            return UtilityPropertySummary(
                propertyId: propertyId,
                propertyName: entry.propertyName,
                currency: entry.currency,
                total: months.reduce(0) { $0 + $1.total },
                months: months
            )
        }
        .sorted { $0.total > $1.total }
    }

    private var occupancyYears: [Int] {
        var years = Set([selectedOccupancyYear, Calendar.current.component(.year, from: Date())])
        for lease in leases {
            if let start = Self.date(from: lease.moveInDate ?? lease.startDate) {
                years.insert(Calendar.current.component(.year, from: start))
            }
            if let endRaw = lease.terminatedAt ?? lease.endDate,
               let end = Self.date(from: endRaw) {
                years.insert(Calendar.current.component(.year, from: end))
            }
        }
        return years.sorted(by: >)
    }

    private var occupancyMonths: [OccupancyMonthSummary] {
        buildOccupancyMonths(year: selectedOccupancyYear)
    }

    private var occupancyRentDays: Int {
        occupancyMonths.reduce(0) { $0 + $1.rentDays }
    }

    private var occupancyPaidDays: Int {
        occupancyMonths.reduce(0) { $0 + $1.paidDays }
    }

    private var occupancyCoveragePct: Int {
        guard occupancyRentDays > 0 else { return 0 }
        return Int((Double(occupancyPaidDays) / Double(occupancyRentDays) * 100).rounded())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground()

                Group {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let dash = dashboard {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: AppTheme.Spacing.lg) {
                                SurfaceCard {
                                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                                        Text("Аналитика")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .textCase(.uppercase)
                                            .tracking(1.2)
                                            .foregroundStyle(AppTheme.Colors.textSecondary)

                                        Text("Сводка по контракту API: те же суммы, что и в веб-панели (период — \(dashboardPeriod.title.lowercased())).")
                                            .font(.title3.weight(.semibold))
                                            .foregroundStyle(AppTheme.Colors.textPrimary)

                                        Text(formatCurrency(dash.netCashflow))
                                            .font(.system(size: 34, weight: .bold, design: .rounded))
                                            .foregroundStyle(dash.netCashflow >= 0 ? AppTheme.Colors.success : AppTheme.Colors.danger)

                                        Text(dash.displayPeriodLabel)
                                            .font(.body)
                                            .foregroundStyle(AppTheme.Colors.textSecondary)
                                    }
                                }

                                analyticsControls

                                if let exportErrorMessage {
                                    SurfaceCard(padding: AppTheme.Spacing.md) {
                                        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundStyle(AppTheme.Colors.warning)
                                            Text(exportErrorMessage)
                                                .font(.subheadline)
                                                .foregroundStyle(AppTheme.Colors.textSecondary)
                                        }
                                    }
                                }

                                LazyVGrid(columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible())
                                ], spacing: AppTheme.Spacing.md) {
                                    KPICard(
                                        title: "Доход",
                                        value: formatCurrency(dash.totalIncome),
                                        icon: "arrow.down.circle",
                                        color: AppTheme.Colors.success,
                                        subtitle: "Фактические поступления \(dash.periodLabel.lowercased())."
                                    )
                                    KPICard(
                                        title: "Расход",
                                        value: formatCurrency(dash.totalExpense),
                                        icon: "arrow.up.circle",
                                        color: AppTheme.Colors.danger,
                                        subtitle: "Операционные расходы за период."
                                    )
                                    KPICard(
                                        title: "Аренда к получению",
                                        value: formatCurrency(dash.rentOutstanding),
                                        icon: "banknote",
                                        color: dash.rentOutstanding > 0 ? AppTheme.Colors.warning : AppTheme.Colors.success,
                                        subtitle: "Начислено \(formatCurrency(dash.expectedRent)), оплачено \(formatCurrency(dash.rentReceived))."
                                    )
                                    KPICard(
                                        title: "Чистый cashflow",
                                        value: formatCurrency(dash.netCashflow),
                                        icon: "chart.bar",
                                        color: dash.netCashflow >= 0 ? AppTheme.Colors.success : AppTheme.Colors.danger,
                                        subtitle: dash.netCashflow >= 0 ? "Поступления выше расходов." : "Расходы выше поступлений."
                                    )
                                    if dash.depositIncome > 0 {
                                        KPICard(
                                            title: "Депозиты (в поступлениях)",
                                            value: formatCurrency(dash.depositIncome),
                                            icon: "lock.rectangle",
                                            color: AppTheme.Colors.accent,
                                            subtitle: "Учтены в сумме дохода периода."
                                        )
                                    }
                                }

                                if let overdue = overdue {
                                    SurfaceCard {
                                        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                                            Image(systemName: overdue.overdueCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                                .foregroundStyle(overdue.overdueCount > 0 ? AppTheme.Colors.warning : AppTheme.Colors.success)
                                                .font(.title2)
                                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                                                Text("Просроченные платежи по аренде")
                                                    .font(.headline)
                                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                                Text(overdue.overdueCount == 0 ? "Нет просроченных строк графика." : "Строк графика с просрочкой: \(overdue.overdueCount). Сверьтесь с фактами оплат.")
                                                    .font(.subheadline)
                                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                                                    .lineSpacing(2)
                                            }
                                        }
                                    }
                                }

                                if !cashflowMonthsNewestFirst.isEmpty {
                                    SurfaceCard {
                                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                                            Text("Динамика cashflow")
                                                .font(.headline)
                                                .foregroundStyle(AppTheme.Colors.textPrimary)
                                            Text("Доход, расход и чистый поток по календарным месяцам (последние месяцы).")
                                                .font(.caption)
                                                .foregroundStyle(AppTheme.Colors.textSecondary)
                                            ForEach(Array(cashflowMonthsNewestFirst.prefix(8))) { row in
                                                HStack {
                                                    Text(shortMonthYear(year: row.year, month: row.month))
                                                        .font(.subheadline.weight(.medium))
                                                        .foregroundStyle(AppTheme.Colors.textPrimary)
                                                        .frame(minWidth: 100, alignment: .leading)
                                                    Spacer(minLength: 8)
                                                    VStack(alignment: .trailing, spacing: 2) {
                                                        Text(formatCurrency(row.netCashflow))
                                                            .font(.subheadline.weight(.semibold))
                                                            .foregroundStyle(row.netCashflow >= 0 ? AppTheme.Colors.success : AppTheme.Colors.danger)
                                                        Text("\(formatCurrency(row.totalExpense)) расход · \(formatCurrency(row.totalIncome)) доход")
                                                            .font(.caption2)
                                                            .foregroundStyle(AppTheme.Colors.textSecondary)
                                                            .lineLimit(1)
                                                            .minimumScaleFactor(0.8)
                                                    }
                                                }
                                                Divider().opacity(0.35)
                                            }
                                        }
                                    }
                                }

                                if !profitabilityTotalsNewestFirst.isEmpty {
                                    SurfaceCard {
                                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                                            Text("Прибыльность портфеля")
                                                .font(.headline)
                                                .foregroundStyle(AppTheme.Colors.textPrimary)
                                            if let p = profitability {
                                                Text("\(periodRangeLabel(from: p.from, to: p.to)) · \(groupByRussian(p.groupBy))")
                                                    .font(.caption)
                                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                                            }
                                            ForEach(Array(profitabilityTotalsNewestFirst.prefix(8)), id: \.periodKey) { row in
                                                HStack(alignment: .firstTextBaseline) {
                                                    Text(row.periodLabel.isEmpty ? row.periodKey : row.periodLabel)
                                                        .font(.subheadline.weight(.medium))
                                                        .foregroundStyle(AppTheme.Colors.textPrimary)
                                                        .frame(minWidth: 84, alignment: .leading)
                                                    Spacer(minLength: 8)
                                                    VStack(alignment: .trailing, spacing: 2) {
                                                        Text(formatCurrency(row.netCashflow))
                                                            .font(.subheadline.weight(.semibold))
                                                            .foregroundStyle(row.netCashflow >= 0 ? AppTheme.Colors.success : AppTheme.Colors.danger)
                                                        Text("маржа \(String(format: "%.1f", row.profitMarginPct))%")
                                                            .font(.caption2)
                                                            .foregroundStyle(AppTheme.Colors.textSecondary)
                                                    }
                                                }
                                                Divider().opacity(0.35)
                                            }
                                        }
                                    }
                                }

                                propertyComparisonSection

                                utilityHistorySection

                                occupancyCalendarSection

                                SurfaceCard {
                                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                                        Text("Интерпретация")
                                            .font(.headline)
                                            .foregroundStyle(AppTheme.Colors.textPrimary)

                                        Text(dash.netCashflow >= 0
                                            ? "Доход сейчас выше расходов. Хороший момент проверить резерв, обслуживание и плановые улучшения."
                                            : "Расходы сейчас выше доходов. Проверьте крупные списания и убедитесь, что аренда и компенсации внесены полностью."
                                        )
                                        .font(.body)
                                        .foregroundStyle(AppTheme.Colors.textSecondary)
                                        .lineSpacing(3)
                                    }
                                }
                            }
                            .padding(.horizontal, AppTheme.Spacing.md)
                            .padding(.vertical, AppTheme.Spacing.lg)
                        }
                    } else {
                        EmptyStateView(
                            title: "Аналитика",
                            message: "Аналитика появится после добавления объектов и транзакций.",
                            actionName: "Повторить",
                            action: { Task { await loadDashboard() } },
                            icon: "chart.bar"
                        )
                    }
                }
            }
            .navigationTitle("Аналитика")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            exportAnalytics(as: .csv)
                        } label: {
                            Label("CSV", systemImage: "tablecells")
                        }
                        .disabled(profitabilityTotalsNewestFirst.isEmpty)

                        Button {
                            exportAnalytics(as: .pdf)
                        } label: {
                            Label("PDF", systemImage: "doc.richtext")
                        }
                        .disabled(profitabilityTotalsNewestFirst.isEmpty)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Экспорт аналитики")
                }
            }
            .sheet(item: $exportDocument) { document in
                NavigationStack {
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.title2)
                                .foregroundStyle(AppTheme.Colors.accent)

                            Text(document.title)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(AppTheme.Colors.textPrimary)

                            Text("Файл построен по выбранному диапазону, группировке и текущим данным profitability.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Colors.textSecondary)

                            ShareLink(item: document.url) {
                                Label("Поделиться файлом", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(AppTheme.Spacing.md)
                    .navigationTitle("Экспорт")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Готово") { exportDocument = nil }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .task { await loadDashboard() }
            .refreshable { await loadDashboard() }
            .onChange(of: dashboardPeriod) { _, _ in Task { await loadDashboard() } }
            .onChange(of: analyticsRange) { _, _ in Task { await loadDashboard() } }
            .onChange(of: profitabilityGroupBy) { _, _ in Task { await loadDashboard() } }
        }
    }

    private var analyticsControls: some View {
        SurfaceCard(padding: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Параметры отчетности")
                            .font(.headline)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Text("Период KPI, диапазон PnL, группировка и экспорт используют серверные analytics endpoints.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }

                    Spacer()

                    Menu {
                        Button {
                            exportAnalytics(as: .csv)
                        } label: {
                            Label("CSV", systemImage: "tablecells")
                        }
                        .disabled(profitabilityTotalsNewestFirst.isEmpty)

                        Button {
                            exportAnalytics(as: .pdf)
                        } label: {
                            Label("PDF", systemImage: "doc.richtext")
                        }
                        .disabled(profitabilityTotalsNewestFirst.isEmpty)
                    } label: {
                        Label("Экспорт", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }

                Picker("Период KPI", selection: $dashboardPeriod) {
                    ForEach(AnalyticsDashboardPeriod.allCases) { period in
                        Text(period.title).tag(period)
                    }
                }
                .pickerStyle(.menu)

                Picker("Диапазон PnL", selection: $analyticsRange) {
                    ForEach(AnalyticsRangeFilter.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Группировка PnL", selection: $profitabilityGroupBy) {
                    ForEach(AnalyticsGroupFilter.allCases) { group in
                        Text(group.title).tag(group)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var propertyComparisonSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Сравнение объектов")
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text("Доход, расходы владельца, ком. услуги арендаторов и итог за выбранный диапазон.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }

                if !properties.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            ForEach(properties) { property in
                                let selected = selectedComparisonPropertyIds.isEmpty || selectedComparisonPropertyIds.contains(property.id)
                                Button {
                                    toggleComparisonProperty(property.id)
                                } label: {
                                    Label(property.name, systemImage: selected ? "checkmark.circle.fill" : "circle")
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.bordered)
                                .tint(selected ? AppTheme.Colors.accent : AppTheme.Colors.textSecondary)
                            }
                        }
                    }
                }

                if propertyComparisonRows.isEmpty {
                    Text("Сравнение появится после PnL-точек с `property_id`.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                } else {
                    let maxMagnitude = max(propertyComparisonRows.map { max(abs($0.income), abs($0.operatingCost), abs($0.netCashflow)) }.max() ?? 1, 1)
                    ForEach(propertyComparisonRows) { row in
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            HStack {
                                Text(row.propertyName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Text(formatCurrency(row.netCashflow))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(row.netCashflow >= 0 ? AppTheme.Colors.success : AppTheme.Colors.danger)
                            }

                            analyticsBar(label: "Доход", amount: row.income, maxMagnitude: maxMagnitude, color: AppTheme.Colors.success)
                            analyticsBar(label: "Расходы", amount: row.operatingCost, maxMagnitude: maxMagnitude, color: AppTheme.Colors.danger)
                            analyticsBar(label: "Ком. услуги", amount: row.utilityExpense, maxMagnitude: maxMagnitude, color: AppTheme.Colors.warning)
                        }
                        .padding(.vertical, AppTheme.Spacing.xs)
                        Divider().opacity(0.35)
                    }
                }
            }
        }
    }

    private var utilityHistorySection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("История ком. услуг")
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text("Помесячная динамика по всем объектам. Это информационный учет платежей арендаторов, не расход владельца.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }

                if utilitySummaries.isEmpty {
                    Text("История появится после добавления ком. услуг или подтверждения OCR-квитанций.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                } else {
                    ForEach(Array(utilitySummaries.prefix(4))) { summary in
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(summary.propertyName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.Colors.textPrimary)
                                    if let latest = summary.latest {
                                        Text("Последний месяц: \(shortMonthYear(year: latest.year, month: latest.month))")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.Colors.textSecondary)
                                    }
                                }

                                Spacer()

                                Text(AppFormatting.compactAmount(summary.total, currency: summary.currency))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                            }

                            utilitySparkBars(summary)

                            if let latest = summary.latest {
                                ForEach(Array(latest.items.prefix(3))) { item in
                                    HStack {
                                        Text(utilityTypeLabel(item.utilityType))
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.Colors.textSecondary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(AppFormatting.compactAmount(item.amount, currency: item.currency))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(AppTheme.Colors.textPrimary)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, AppTheme.Spacing.sm)
                        Divider().opacity(0.35)
                    }
                }
            }
        }
    }

    private var occupancyCalendarSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Календарь занятости")
                            .font(.headline)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Text("День считается закрытым, когда график аренды за этот день связан с оплатой.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }

                    Spacer()

                    Picker("Год", selection: $selectedOccupancyYear) {
                        ForEach(occupancyYears, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    .pickerStyle(.menu)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppTheme.Spacing.sm) {
                    analyticsMiniMetric(title: "Дней аренды", value: "\(occupancyRentDays)")
                    analyticsMiniMetric(title: "Оплачено", value: "\(occupancyPaidDays)")
                    analyticsMiniMetric(title: "Без оплаты", value: "\(max(0, occupancyRentDays - occupancyPaidDays))")
                    analyticsMiniMetric(title: "Покрытие", value: "\(occupancyCoveragePct)%")
                }

                if leases.isEmpty {
                    Text("Календарь появится после договоров аренды.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                } else {
                    ForEach(occupancyMonths) { month in
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            HStack {
                                Text(shortMonthYear(year: month.year, month: month.month))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                                Spacer()
                                Text("\(month.coveragePct)%")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(month.coveragePct >= 90 ? AppTheme.Colors.success : AppTheme.Colors.warning)
                            }

                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(9), spacing: 3), count: 7), spacing: 3) {
                                ForEach(month.days) { day in
                                    Circle()
                                        .fill(occupancyDayColor(day))
                                        .frame(width: 9, height: 9)
                                        .overlay(
                                            Circle()
                                                .stroke(day.dueScheduleCount > 0 ? AppTheme.Colors.danger : Color.clear, lineWidth: 1)
                                        )
                                        .accessibilityLabel(occupancyDayAccessibility(day))
                                }
                            }
                        }
                        .padding(.vertical, AppTheme.Spacing.xs)
                    }
                }
            }
        }
    }

    private func analyticsMiniMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func analyticsBar(label: String, amount: Double, maxMagnitude: Double, color: Color) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text(label)
                .font(.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .frame(width: 72, alignment: .leading)

            GeometryReader { proxy in
                let width = max(4, proxy.size.width * CGFloat(min(abs(amount) / maxMagnitude, 1)))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.Colors.backgroundSecondary.opacity(0.85))
                    Capsule()
                        .fill(color.opacity(0.75))
                        .frame(width: width)
                }
            }
            .frame(height: 8)

            Text(AppFormatting.compactAmount(amount, currency: baseCurrency))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(width: 72, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func utilitySparkBars(_ summary: UtilityPropertySummary) -> some View {
        let months = Array(summary.months.suffix(12))
        let maxTotal = max(months.map(\.total).max() ?? 1, 1)

        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(months) { month in
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(AppTheme.Colors.warning.opacity(0.72))
                        .frame(width: 12, height: max(5, 44 * CGFloat(month.total / maxTotal)))
                    Text(String(format: "%02d", month.month))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                }
                .accessibilityLabel("\(shortMonthYear(year: month.year, month: month.month)): \(AppFormatting.compactAmount(month.total, currency: month.currency))")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func loadDashboard() async {
        if dashboard == nil { isLoading = true }
        exportErrorMessage = nil
        defer { isLoading = false }

        let range = analyticsRange.dateRange()
        overdue = await fetchOptional(OverduePaymentsPayload.self, path: "/v1/analytics/overdue-payments")
        cashflowTrend = await fetchOptional(CashflowTrendBody.self, path: "/v1/analytics/cashflow-trend?months=12")
        profitability = await fetchOptional(
            ProfitabilityReport.self,
            path: "/v1/analytics/profitability?from=\(range.from)&to=\(range.to)&group_by=\(profitabilityGroupBy.rawValue)"
        )
        dashboard = await fetchOptional(
            AnalyticsDashboard.self,
            path: "/v1/analytics/dashboard?period=\(dashboardPeriod.rawValue)"
        )

        properties = await fetchOptional([Property].self, path: "/v1/properties") ?? []
        syncSelectedComparisonProperties()
        leases = await loadLeases(for: properties)
        paymentSchedules = await loadPaymentSchedules(for: leases)
        utilityHistory = await fetchList(PropertyUtility.self, path: "/v1/analytics/utilities-history?months=24")
    }

    private func fetchOptional<T: Decodable>(_: T.Type, path: String) async -> T? {
        do {
            return try await APIClient.shared.request(
                path,
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
        } catch {
            return nil
        }
    }

    private func fetchList<T: Decodable>(_: T.Type, path: String) async -> [T] {
        do {
            let data = try await APIClient.shared.requestData(
                path,
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            if let page = try? JSONDecoder().decode(APIListEnvelope<T>.self, from: data) {
                return page.data
            }
            if let response = try? JSONDecoder().decode(APIResponse<[T]>.self, from: data) {
                return response.data
            }
            return (try? JSONDecoder().decode([T].self, from: data)) ?? []
        } catch {
            return []
        }
    }

    private func loadLeases(for properties: [Property]) async -> [Lease] {
        var merged: [Lease] = []
        for property in properties {
            merged.append(contentsOf: await fetchList(Lease.self, path: "/v1/properties/\(property.id)/leases"))
        }
        return merged.sorted { ($0.moveInDate ?? $0.startDate) < ($1.moveInDate ?? $1.startDate) }
    }

    private func loadPaymentSchedules(for leases: [Lease]) async -> [LeasePaymentSchedule] {
        var merged: [LeasePaymentSchedule] = []
        for lease in leases {
            merged.append(contentsOf: await fetchList(LeasePaymentSchedule.self, path: "/v1/leases/\(lease.id)/payment-schedule"))
        }
        return merged
    }

    private func syncSelectedComparisonProperties() {
        let ids = Set(properties.map(\.id))
        if selectedComparisonPropertyIds.isEmpty {
            selectedComparisonPropertyIds = ids
            return
        }
        selectedComparisonPropertyIds = selectedComparisonPropertyIds.intersection(ids)
        if selectedComparisonPropertyIds.isEmpty {
            selectedComparisonPropertyIds = ids
        }
    }

    private func toggleComparisonProperty(_ propertyId: String) {
        if selectedComparisonPropertyIds.isEmpty {
            selectedComparisonPropertyIds = Set(properties.map(\.id))
        }
        if selectedComparisonPropertyIds.contains(propertyId) {
            selectedComparisonPropertyIds.remove(propertyId)
        } else {
            selectedComparisonPropertyIds.insert(propertyId)
        }
    }

    private var baseCurrency: String {
        authManager.user?.baseCurrency ?? "KZT"
    }

    private func exportAnalytics(as format: AnalyticsExportFormat) {
        exportErrorMessage = nil
        do {
            let url: URL
            let title: String
            switch format {
            case .csv:
                url = try makeAnalyticsCSV()
                title = "CSV готов"
            case .pdf:
                url = try makeAnalyticsPDF()
                title = "PDF готов"
            }
            exportDocument = AnalyticsExportDocument(title: title, url: url)
        } catch {
            exportErrorMessage = "Не удалось подготовить экспорт аналитики."
        }
    }

    private func makeAnalyticsCSV() throws -> URL {
        let headers = ["period", "total_income", "owner_operating_cost", "tenant_utilities", "net_cashflow", "profit_margin_pct"]
        let lines = [headers] + (profitability?.totals ?? []).map { row in
            [
                row.periodLabel.isEmpty ? row.periodKey : row.periodLabel,
                String(row.totalIncome),
                String(row.operatingCost),
                String(row.utilityExpense),
                String(row.netCashflow),
                String(row.profitMarginPct)
            ]
        }
        let csv = lines.map { $0.map(Self.csvEscape).joined(separator: ",") }.joined(separator: "\n")
        let url = temporaryExportURL(prefix: "analytics-profitability", fileExtension: "csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeAnalyticsPDF() throws -> URL {
        let url = temporaryExportURL(prefix: "analytics-profitability", fileExtension: "pdf")
        let bounds = CGRect(x: 0, y: 0, width: 842, height: 595)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let totals = profitability?.totals ?? []
        let comparison = propertyComparisonRows
        let summary = analyticsExportSummary

        try renderer.writePDF(to: url) { context in
            var y = drawAnalyticsPDFHeader(context: context, bounds: bounds, summary: summary)
            drawAnalyticsPDFTableHeader(at: &y, bounds: bounds)

            for row in totals {
                if y > bounds.height - 46 {
                    y = drawAnalyticsPDFHeader(context: context, bounds: bounds, summary: summary)
                    drawAnalyticsPDFTableHeader(at: &y, bounds: bounds)
                }
                drawAnalyticsPDFRow(row, at: &y, bounds: bounds)
            }

            if !comparison.isEmpty {
                if y > bounds.height - 120 {
                    y = drawAnalyticsPDFHeader(context: context, bounds: bounds, summary: summary)
                }
                y += 14
                drawPDFText("Сравнение объектов", x: 32, y: y, width: bounds.width - 64, font: .boldSystemFont(ofSize: 14))
                y += 22
                for row in comparison {
                    if y > bounds.height - 36 {
                        y = drawAnalyticsPDFHeader(context: context, bounds: bounds, summary: summary)
                    }
                    drawPDFText(row.propertyName, x: 32, y: y, width: 220, font: .systemFont(ofSize: 9))
                    drawPDFText(formatCurrency(row.netCashflow), x: 260, y: y, width: 120, font: .boldSystemFont(ofSize: 9))
                    drawPDFText("доход \(formatCurrency(row.income)) · расходы \(formatCurrency(row.operatingCost)) · ком. услуги \(formatCurrency(row.utilityExpense))", x: 390, y: y, width: bounds.width - 422, font: .systemFont(ofSize: 8), color: .darkGray)
                    y += 16
                }
            }
        }

        return url
    }

    private var analyticsExportSummary: String {
        let range = analyticsRange.dateRange()
        return "KPI: \(dashboardPeriod.title) · PnL: \(range.from) — \(range.to) · \(profitabilityGroupBy.title)"
    }

    private func temporaryExportURL(prefix: String, fileExtension ext: String) -> URL {
        let stamp = Self.exportTimestamp()
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(stamp).\(ext)")
    }

    private func drawAnalyticsPDFHeader(
        context: UIGraphicsPDFRendererContext,
        bounds: CGRect,
        summary: String
    ) -> CGFloat {
        context.beginPage()
        var y: CGFloat = 34
        drawPDFText("Динамика прибыльности", x: 32, y: y, width: bounds.width - 64, font: .boldSystemFont(ofSize: 20))
        y += 28
        drawPDFText(summary, x: 32, y: y, width: bounds.width - 64, font: .systemFont(ofSize: 10), color: .darkGray)
        return y + 28
    }

    private func drawAnalyticsPDFTableHeader(at y: inout CGFloat, bounds: CGRect) {
        let headers = ["Период", "Доход", "Расходы", "Ком. услуги", "Итог", "Маржа"]
        let columns = analyticsPDFColumns(bounds: bounds)
        for index in headers.indices {
            drawPDFText(headers[index], x: columns[index].minX, y: y, width: columns[index].width, font: .boldSystemFont(ofSize: 9))
        }
        y += 17
    }

    private func drawAnalyticsPDFRow(_ row: ProfitabilityPoint, at y: inout CGFloat, bounds: CGRect) {
        let columns = analyticsPDFColumns(bounds: bounds)
        let values = [
            row.periodLabel.isEmpty ? row.periodKey : row.periodLabel,
            formatCurrency(row.totalIncome),
            formatCurrency(row.operatingCost),
            formatCurrency(row.utilityExpense),
            formatCurrency(row.netCashflow),
            "\(String(format: "%.1f", row.profitMarginPct))%"
        ]
        for index in values.indices {
            drawPDFText(values[index], x: columns[index].minX, y: y, width: columns[index].width, font: .systemFont(ofSize: 8.5), color: .black)
        }
        y += 15
    }

    private func analyticsPDFColumns(bounds: CGRect) -> [CGRect] {
        let x: CGFloat = 32
        return [
            CGRect(x: x, y: 0, width: 130, height: 14),
            CGRect(x: x + 140, y: 0, width: 118, height: 14),
            CGRect(x: x + 266, y: 0, width: 118, height: 14),
            CGRect(x: x + 392, y: 0, width: 118, height: 14),
            CGRect(x: x + 518, y: 0, width: 118, height: 14),
            CGRect(x: x + 644, y: 0, width: bounds.width - 676, height: 14)
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
                .paragraphStyle: paragraph
            ]
        )
    }

    private func buildOccupancyMonths(year: Int) -> [OccupancyMonthSummary] {
        let calendar = Calendar.current
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else {
            return []
        }

        var days: [OccupancyDaySummary] = []
        var current = start
        while current < end {
            let components = calendar.dateComponents([.year, .month, .day], from: current)
            guard let month = components.month, let day = components.day else { break }
            days.append(occupancyDay(for: current, month: month, day: day))
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? end
        }

        return Dictionary(grouping: days, by: \.month)
            .map { month, days in
                OccupancyMonthSummary(year: year, month: month, days: days.sorted { $0.date < $1.date })
            }
            .sorted { $0.month < $1.month }
    }

    private func occupancyDay(for date: Date, month: Int, day: Int) -> OccupancyDaySummary {
        let activeLeases = leases.filter { leaseIsActive($0, on: date) }
        let activeLeaseIds = Set(activeLeases.map(\.id))
        let coveringPaidLeaseIds = Set(paymentSchedules.compactMap { schedule -> String? in
            guard activeLeaseIds.contains(schedule.leaseId),
                  scheduleCovers(schedule, date: date),
                  scheduleIsPaid(schedule) else { return nil }
            return schedule.leaseId
        })
        let dueCount = paymentSchedules.filter { schedule in
            guard activeLeaseIds.contains(schedule.leaseId),
                  let due = Self.date(from: schedule.dueDate) else { return false }
            return Calendar.current.isDate(due, inSameDayAs: date)
        }.count

        return OccupancyDaySummary(
            key: Self.isoDate(date),
            date: date,
            day: day,
            month: month,
            activeLeaseCount: activeLeases.count,
            paidLeaseCount: coveringPaidLeaseIds.count,
            dueScheduleCount: dueCount,
            isToday: Calendar.current.isDateInToday(date)
        )
    }

    private func leaseIsActive(_ lease: Lease, on date: Date) -> Bool {
        guard let start = Self.date(from: lease.moveInDate ?? lease.startDate) else { return false }
        let end = (lease.terminatedAt ?? lease.endDate).flatMap(Self.date(from:))
        if date < Calendar.current.startOfDay(for: start) { return false }
        if let end, date > Calendar.current.startOfDay(for: end) { return false }
        return true
    }

    private func scheduleCovers(_ schedule: LeasePaymentSchedule, date: Date) -> Bool {
        guard let start = Self.date(from: schedule.periodStartDate ?? schedule.dueDate) else { return false }
        let end = Self.date(from: schedule.periodEndDate ?? schedule.periodStartDate ?? schedule.dueDate) ?? start
        let day = Calendar.current.startOfDay(for: date)
        return day >= Calendar.current.startOfDay(for: start) && day <= Calendar.current.startOfDay(for: end)
    }

    private func scheduleIsPaid(_ schedule: LeasePaymentSchedule) -> Bool {
        let status = schedule.status.lowercased()
        return status == "paid" || status == "matched" || schedule.actualPaymentId != nil || schedule.transactionId != nil || schedule.paidAt != nil
    }

    private func occupancyDayColor(_ day: OccupancyDaySummary) -> Color {
        if day.isFullyPaid { return AppTheme.Colors.success }
        if day.isPartlyPaid { return AppTheme.Colors.success.opacity(0.45) }
        if day.hasRent { return AppTheme.Colors.textTertiary.opacity(0.55) }
        return AppTheme.Colors.backgroundSecondary.opacity(0.9)
    }

    private func occupancyDayAccessibility(_ day: OccupancyDaySummary) -> String {
        if !day.hasRent { return "\(day.day): нет аренды" }
        if day.isFullyPaid { return "\(day.day): оплачено \(day.paidLeaseCount) из \(day.activeLeaseCount)" }
        if day.isPartlyPaid { return "\(day.day): частично оплачено \(day.paidLeaseCount) из \(day.activeLeaseCount)" }
        return "\(day.day): без оплаты, договоров \(day.activeLeaseCount)"
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

    private func shortMonthYear(year: Int, month: Int) -> String {
        guard let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) else {
            return "\(month).\(year)"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date).capitalized
    }

    nonisolated private static func date(from raw: String) -> Date? {
        let trimmed = String(raw.prefix(10))
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: trimmed)
    }

    nonisolated private static func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    nonisolated private static func csvEscape(_ raw: String) -> String {
        let escaped = raw.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\n") || escaped.contains("\"") {
            return "\"\(escaped)\""
        }
        return escaped
    }

    nonisolated private static func exportTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func periodRangeLabel(from: String, to: String) -> String {
        let trimmedFrom = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTo = to.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedFrom.isEmpty, trimmedTo.isEmpty { return "" }
        if trimmedFrom.isEmpty { return trimmedTo }
        if trimmedTo.isEmpty { return trimmedFrom }
        return "\(trimmedFrom) — \(trimmedTo)"
    }

    private func groupByRussian(_ groupBy: String) -> String {
        switch groupBy {
        case "quarter": return "по кварталам"
        case "season": return "по сезону"
        case "year": return "по году"
        default: return "по месяцам"
        }
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = authManager.user?.baseCurrency ?? "KZT"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount) \(authManager.user?.baseCurrency ?? "KZT")"
    }
}
