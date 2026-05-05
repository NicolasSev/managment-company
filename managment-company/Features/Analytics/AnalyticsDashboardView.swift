import SwiftUI

struct AnalyticsDashboardView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var dashboard: AnalyticsDashboard?
    @State private var overdue: OverduePaymentsPayload?
    @State private var cashflowTrend: CashflowTrendBody?
    @State private var profitability: ProfitabilityReport?
    @State private var isLoading = true

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

                                        Text("Сводка по контракту API: те же суммы, что и в веб-панели (период — «всё время»).")
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
            .task { await loadDashboard() }
            .refreshable { await loadDashboard() }
        }
    }

    private func loadDashboard() async {
        isLoading = true
        defer { isLoading = false }

        overdue = await fetchOptional(OverduePaymentsPayload.self, path: "/v1/analytics/overdue-payments")
        cashflowTrend = await fetchOptional(CashflowTrendBody.self, path: "/v1/analytics/cashflow-trend?months=12")
        profitability = await fetchOptional(
            ProfitabilityReport.self,
            path: "/v1/analytics/profitability?group_by=month"
        )
        dashboard = await fetchOptional(
            AnalyticsDashboard.self,
            path: "/v1/analytics/dashboard?period=all"
        )
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

    private func shortMonthYear(year: Int, month: Int) -> String {
        guard let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) else {
            return "\(month).\(year)"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date).capitalized
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
