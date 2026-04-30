import SwiftUI

struct AnalyticsDashboardView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var dashboard: AnalyticsDashboard?
    @State private var isLoading = true
    
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

                                        Text("Смотрите состояние портфеля без таблиц и ручной сверки.")
                                            .font(.title3.weight(.semibold))
                                            .foregroundStyle(AppTheme.Colors.textPrimary)

                                        Text(formatCurrency(dash.netCashflow))
                                            .font(.system(size: 34, weight: .bold, design: .rounded))
                                            .foregroundStyle(dash.netCashflow >= 0 ? AppTheme.Colors.success : AppTheme.Colors.danger)

                                        Text("\(monthName(dash.periodMonth)) \(dash.periodYear)")
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
                                        subtitle: "Поступления за текущий отчетный период."
                                    )
                                    KPICard(
                                        title: "Расход",
                                        value: formatCurrency(dash.totalExpense),
                                        icon: "arrow.up.circle",
                                        color: AppTheme.Colors.danger,
                                        subtitle: "Расходы на обслуживание, коммуналку и операции."
                                    )
                                    KPICard(
                                        title: "Денежный поток",
                                        value: formatCurrency(dash.netCashflow),
                                        icon: "chart.bar",
                                        color: dash.netCashflow >= 0 ? AppTheme.Colors.success : AppTheme.Colors.danger,
                                        subtitle: dash.netCashflow >= 0 ? "Месяц сейчас в плюсе." : "Расходы за период выше доходов."
                                    )
                                    KPICard(
                                        title: "Период",
                                        value: "\(monthName(dash.periodMonth)) \(dash.periodYear)",
                                        icon: "calendar",
                                        subtitle: "Текущий период, который показан на дашборде."
                                    )
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
        do {
            dashboard = try await APIClient.shared.request(
                "/v1/analytics/dashboard",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
        } catch {
            dashboard = nil
        }
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = authManager.user?.baseCurrency ?? "KZT"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount) \(authManager.user?.baseCurrency ?? "KZT")"
    }
    
    private func monthName(_ month: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "MMMM"
        guard month >= 1, month <= formatter.monthSymbols.count else {
            return "Месяц \(month)"
        }
        return formatter.monthSymbols[month - 1]
    }
}
