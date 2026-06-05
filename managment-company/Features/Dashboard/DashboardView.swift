import SwiftUI

/// Portfolio dashboard. Mirrors the web `/dashboard` blocks: period selector,
/// financial KPIs, occupancy summary, profitability by period, and utility
/// history. Written from scratch with defensive rendering (no GeometryReader
/// bars or day-grid) to stay crash-safe across portfolios.
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
    @State private var profitabilityTotals: [ProfitabilityPoint] = []
    @State private var utilities: [PropertyUtility] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showNotifications = false
    @State private var notificationUnreadCount = 0

    private var currency: String { authManager.user?.baseCurrency ?? "KZT" }

    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground()
                content
            }
            .navigationTitle("Дашборд")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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
            }
            .sheet(isPresented: $showNotifications) {
                NotificationsInboxView(onDataChanged: {
                    await refreshNotificationUnread()
                })
                .environmentObject(authManager)
            }
            .onChange(of: showNotifications) { _, open in
                if !open { Task { await refreshNotificationUnread() } }
            }
            .task { await load(); await refreshNotificationUnread() }
            .refreshable { await load(); await refreshNotificationUnread() }
            .onChange(of: period) { _, _ in Task { await load() } }
            .onChange(of: rentPreviewRouter.paidSignal) { _, _ in
                Task { await load(); await refreshNotificationUnread() }
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

                    if let errorMessage {
                        infoBanner(errorMessage)
                    }

                    kpiSection

                    occupancySection

                    if !profitabilityTotals.isEmpty {
                        profitabilitySection
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

    private var periodSelector: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Период сводки")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Picker("Период", selection: $period) {
                    ForEach(Period.allCases) { p in
                        Text(p.title).tag(p)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var kpiSection: some View {
        let d = dashboard
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppTheme.Spacing.md) {
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
                color: (d?.rentOutstanding ?? 0) > 0 ? AppTheme.Colors.warning : AppTheme.Colors.success,
                subtitle: d.map { "Начислено \(money($0.expectedRent)), оплачено \(money($0.rentReceived))." } ?? " "
            )
            KPICard(
                title: "Чистый cashflow",
                value: money(d?.netCashflow ?? 0),
                icon: "chart.line.uptrend.xyaxis",
                color: (d?.netCashflow ?? 0) >= 0 ? AppTheme.Colors.success : AppTheme.Colors.danger,
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

    private var profitabilitySection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                sectionHeading("Прибыльность по периодам", subtitle: "Доход, расход и чистый поток.")
                VStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(Array(profitabilityTotals.suffix(8).reversed()), id: \.periodKey) { row in
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.periodLabel.isEmpty ? row.periodKey : row.periodLabel)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(money(row.netCashflow))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(row.netCashflow >= 0 ? AppTheme.Colors.success : AppTheme.Colors.danger)
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
    }

    private var utilitiesSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                sectionHeading("История ком. услуг", subtitle: "Начисления арендаторов по объектам.")
                VStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(Array(utilities.prefix(12))) { u in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(u.propertyName ?? "Объект")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                    .lineLimit(1)
                                Text("\(utilityTypeLabel(u.utilityType)) · \(String(format: "%02d.%d", u.periodMonth, u.periodYear))")
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                            }
                            Spacer(minLength: 8)
                            Text(AppFormatting.currency(u.amount, currency: u.currency))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                        }
                        .padding(.vertical, AppTheme.Spacing.xs)
                    }
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

    // MARK: - Data

    private func refreshNotificationUnread() async {
        do {
            let u: UnreadCountData = try await APIClient.shared.request(
                "/v1/notifications/unread-count",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            await MainActor.run { notificationUnreadCount = u.count }
        } catch {
            await MainActor.run { notificationUnreadCount = 0 }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        let token: () async -> String? = { await MainActor.run { authManager.accessToken } }
        let refresh: () async -> Bool = { await authManager.refreshToken() }

        do {
            let d: AnalyticsDashboard = try await APIClient.shared.request(
                "/v1/analytics/dashboard?period=\(period.rawValue)",
                tokenProvider: token, refreshAndRetry: refresh
            )
            dashboard = d
            errorMessage = nil
        } catch {
            if dashboard == nil {
                errorMessage = "Не удалось загрузить дашборд. Проверьте соединение."
            } else {
                errorMessage = "Часть данных не обновилась."
            }
        }

        // Secondary blocks are best-effort: a failure must never blank the dashboard.
        occupancy = try? await APIClient.shared.request(
            "/v1/analytics/occupancy", tokenProvider: token, refreshAndRetry: refresh
        )

        if let report: ProfitabilityReport = try? await APIClient.shared.request(
            "/v1/analytics/profitability?group_by=month", tokenProvider: token, refreshAndRetry: refresh
        ) {
            profitabilityTotals = report.totals
        }

        if let history: [PropertyUtility] = try? await APIClient.shared.request(
            "/v1/analytics/utilities-history?months=24", tokenProvider: token, refreshAndRetry: refresh
        ) {
            utilities = history.sorted {
                ($0.periodYear, $0.periodMonth) > ($1.periodYear, $1.periodMonth)
            }
        }
    }
}
