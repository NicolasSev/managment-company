import SwiftUI

struct HomeDashboardView: View {
    @EnvironmentObject var authManager: AuthManager
    @Binding var selectedTab: AppTab

    @State private var properties: [Property] = []
    @State private var tasks: [AppTask] = []
    @State private var analytics: AnalyticsDashboard?
    /// Server-derived occupancy counts (GET `/v1/analytics/occupancy`).
    @State private var occupancy: OccupancyPayload?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showNotifications = false
    @State private var notificationUnreadCount = 0

    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground()

                content
            }
            .navigationTitle("Главная")
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
            .task {
                await loadOverview()
                await refreshNotificationUnread()
            }
            .refreshable { await loadOverview(); await refreshNotificationUnread() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && properties.isEmpty && tasks.isEmpty && analytics == nil {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, properties.isEmpty && tasks.isEmpty && analytics == nil {
            EmptyStateView(
                title: "Не удалось загрузить рабочее пространство",
                message: errorMessage,
                actionName: "Повторить",
                action: { Task { await loadOverview() } },
                icon: "wifi.exclamationmark"
            )
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: AppTheme.Spacing.lg) {
                    heroCard

                    if let errorMessage {
                        infoBanner(message: errorMessage)
                    }

                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: AppTheme.Spacing.md) {
                        KPICard(
                            title: "Объекты",
                            value: "\(properties.count)",
                            icon: "building.2",
                            subtitle: "\(occupiedPropertiesCount) occupied, \(vacantPropertiesCount) vacant."
                        )
                        KPICard(
                            title: "Открытые задачи",
                            value: "\(openTasksCount)",
                            icon: "checklist",
                            color: AppTheme.Colors.warning,
                            subtitle: "Сегодня: \(dueTodayCount), просрочено: \(overdueTasksCount)."
                        )
                        KPICard(
                            title: "Завершено",
                            value: "\(completionRate)%",
                            icon: "checkmark.circle",
                            color: AppTheme.Colors.success,
                            subtitle: "Закрыто \(completedTasksCount) из \(tasks.count) задач."
                        )
                        KPICard(
                            title: "Денежный поток",
                            value: formatCurrency(analytics?.netCashflow ?? 0),
                            icon: "chart.line.uptrend.xyaxis",
                            color: (analytics?.netCashflow ?? 0) >= 0 ? AppTheme.Colors.success : AppTheme.Colors.danger,
                            subtitle: analyticsPeriodLabel
                        )
                    }

                    quickActionsCard

                    if !focusTasks.isEmpty {
                        SurfaceCard {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                                sectionHeading(
                                    eyebrow: "Фокус",
                                    title: "Ближайшие задачи, требующие внимания."
                                )

                                VStack(spacing: AppTheme.Spacing.sm) {
                                    ForEach(focusTasks) { task in
                                        focusTaskRow(task)
                                    }
                                }
                            }
                        }
                    }

                    SurfaceCard {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                            sectionHeading(
                                eyebrow: "Заметки по портфелю",
                                title: "Короткая сводка перед началом рабочего дня."
                            )

                            VStack(spacing: AppTheme.Spacing.sm) {
                                insightRow(
                                    icon: "building.2.crop.circle",
                                    title: "Заселенность",
                                    message: occupancyInsight
                                )
                                insightRow(
                                    icon: "clock.badge.exclamationmark",
                                    title: "Ритм задач",
                                    message: taskInsight
                                )
                                insightRow(
                                    icon: "banknote",
                                    title: "Денежный поток",
                                    message: cashflowInsight
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.lg)
            }
        }
    }

    private var heroCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Пульс портфеля")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .textCase(.uppercase)
                            .tracking(1.2)
                            .foregroundStyle(AppTheme.Colors.textSecondary)

                        Text(heroName)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)

                        Text("Смотрите состояние портфеля, переходите к важным процессам и держите задачи дня под рукой.")
                            .font(.body)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .lineSpacing(3)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 8) {
                        Label(baseCurrency, systemImage: "banknote")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.accent)

                        Text(analyticsPeriodLabel)
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }

                HStack(spacing: AppTheme.Spacing.sm) {
                    heroMetric(title: "Открыто", value: "\(openTasksCount)")
                    heroMetric(title: "Сегодня", value: "\(dueTodayCount)")
                    heroMetric(title: "Занято", value: "\(occupiedPropertiesCount)")
                }
            }
        }
    }

    private var quickActionsCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                sectionHeading(
                    eyebrow: "Быстрые действия",
                    title: "Переходите сразу туда, где сейчас нужно внимание."
                )

                VStack(spacing: AppTheme.Spacing.sm) {
                    quickActionButton(
                        title: "Открыть задачи",
                        subtitle: "Откройте список задач и закройте просроченные дела.",
                        systemImage: "checklist",
                        tint: AppTheme.Colors.warning
                    ) {
                        selectedTab = .tasks
                    }

                    quickActionButton(
                        title: "Открыть портфель",
                        subtitle: "Проверьте заселенность, адреса и детали объектов.",
                        systemImage: "building.2",
                        tint: AppTheme.Colors.accent
                    ) {
                        selectedTab = .properties
                    }

                    quickActionButton(
                        title: "Открыть аналитику",
                        subtitle: "Перейдите к доходам, расходам и динамике денежного потока.",
                        systemImage: "chart.bar",
                        tint: AppTheme.Colors.success
                    ) {
                        selectedTab = .analytics
                    }
                }
            }
        }
    }

    private var focusTasks: [AppTask] {
        tasks
            .filter(isOpenTask)
            .sorted { lhs, rhs in
                let lhsDate = dueDateValue(for: lhs) ?? .distantFuture
                let rhsDate = dueDateValue(for: rhs) ?? .distantFuture
                if lhsDate == rhsDate {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhsDate < rhsDate
            }
            .prefix(3)
            .map { $0 }
    }

    private var occupiedPropertiesCount: Int {
        if let occupancy { return occupancy.occupied }
        return properties.filter { $0.status.lowercased() == "occupied" }.count
    }

    private var vacantPropertiesCount: Int {
        if let occupancy {
            return max(0, occupancy.total - occupancy.occupied)
        }
        return properties.filter { $0.status.lowercased() == "vacant" }.count
    }

    private var openTasksCount: Int {
        tasks.filter(isOpenTask).count
    }

    private var completedTasksCount: Int {
        tasks.filter(isCompletedTask).count
    }

    private var overdueTasksCount: Int {
        tasks.filter { task in
            guard let dueDate = dueDateValue(for: task) else { return false }
            return dueDate < startOfToday && !calendar.isDate(dueDate, inSameDayAs: Date()) && isOpenTask(task)
        }.count
    }

    private var dueTodayCount: Int {
        tasks.filter { task in
            guard let dueDate = dueDateValue(for: task) else { return false }
            return calendar.isDate(dueDate, inSameDayAs: Date()) && isOpenTask(task)
        }.count
    }

    private var completionRate: Int {
        guard !tasks.isEmpty else { return 0 }
        return Int((Double(completedTasksCount) / Double(tasks.count) * 100).rounded())
    }

    private var occupancyInsight: String {
        if properties.isEmpty {
            return "Объекты еще не добавлены. Добавьте первый объект, чтобы видеть заселенность."
        }
        if let occupancy {
            return "По серверу: занято \(occupancy.occupied) из \(occupancy.total) (\(occupancy.ratePct)%). Локально в списке \(properties.count) объектов."
        }
        return "Сейчас занято \(occupiedPropertiesCount) из \(properties.count) объектов по статусам в приложении."
    }

    private var taskInsight: String {
        if tasks.isEmpty {
            return "Задач пока нет. Доска станет полезнее, когда появятся регулярные операции и обслуживание."
        }
        if overdueTasksCount > 0 {
            return "Просрочено задач: \(overdueTasksCount). Стоит проверить доску перед следующим контактом с арендатором или подрядчиком."
        }
        if dueTodayCount > 0 {
            return "На сегодня задач: \(dueTodayCount). Хороший момент быстро пройтись по доске."
        }
        return "Открытых задач пока немного (\(openTasksCount)). Хороший момент заранее запланировать обслуживание."
    }

    private var cashflowInsight: String {
        guard let analytics else {
            return "Аналитика появится здесь после добавления транзакций."
        }
        if analytics.netCashflow >= 0 {
            return "Денежный поток за \(analyticsPeriodLabel.lowercased()) положительный, можно планировать резерв или обслуживание."
        }
        return "Денежный поток за \(analyticsPeriodLabel.lowercased()) отрицательный, стоит проверить расходы и сбор аренды."
    }

    private var heroName: String {
        let fallbackName = authManager.user?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstName = fallbackName?.split(separator: " ").first.map(String.init)
        if let firstName, !firstName.isEmpty {
            return "Рады видеть, \(firstName)."
        }
        return "Спокойное начало дня."
    }

    private var baseCurrency: String {
        authManager.user?.baseCurrency ?? "KZT"
    }

    private var analyticsPeriodLabel: String {
        guard let analytics else {
            return "Текущий период"
        }
        return analytics.displayPeriodLabel
    }

    private var calendar: Calendar {
        .current
    }

    private var startOfToday: Date {
        calendar.startOfDay(for: Date())
    }

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

    private func loadOverview() async {
        guard let userId = authManager.user?.id else { return }
        isLoading = true
        defer { isLoading = false }
        occupancy = nil

        do {
            async let propertiesRequest: [Property] = APIClient.shared.request(
                "/v1/properties",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            async let tasksRequest: [AppTask] = APIClient.shared.request(
                "/v1/tasks?per_page=50",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )

            let (loadedProperties, loadedTasks) = try await (propertiesRequest, tasksRequest)
            properties = loadedProperties
            tasks = loadedTasks
            errorMessage = nil

            var loadedAnalytics: AnalyticsDashboard?
            do {
                loadedAnalytics = try await APIClient.shared.request(
                    "/v1/analytics/dashboard?period=all",
                    tokenProvider: { await MainActor.run { authManager.accessToken } },
                    refreshAndRetry: { await authManager.refreshToken() }
                )
                analytics = loadedAnalytics
            } catch {
                loadedAnalytics = nil
                analytics = nil
                errorMessage = "Данные портфеля загружены, но аналитика пока недоступна."
            }

            let occ: OccupancyPayload? = try? await APIClient.shared.request(
                "/v1/analytics/occupancy",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            occupancy = occ

            DashboardOverviewCache.save(
                DashboardOverviewSnapshot(
                    userId: userId,
                    properties: loadedProperties,
                    tasks: loadedTasks,
                    analytics: loadedAnalytics,
                    occupancy: occ,
                    savedAt: Date()
                )
            )
        } catch {
            if let cached = DashboardOverviewCache.load(), cached.userId == userId {
                properties = cached.properties
                tasks = cached.tasks
                analytics = cached.analytics
                occupancy = cached.occupancy
                errorMessage = Self.offlineStaleMessage(savedAt: cached.savedAt)
            } else {
                errorMessage = "Не удалось подключиться к API. Проверьте, что сервер доступен."
            }
        }
    }

    private static func offlineStaleMessage(savedAt: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ru_RU")
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        return "Нет связи с сервером. Показаны сохранённые данные (\(fmt.string(from: savedAt)))."
    }

    private func heroMetric(title: String, value: String) -> some View {
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

    private func sectionHeading(eyebrow: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(.caption)
                .fontWeight(.semibold)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
    }

    private func infoBanner(message: String) -> some View {
        SurfaceCard(padding: AppTheme.Spacing.md) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppTheme.Colors.warning)
                    .font(.headline)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineSpacing(2)
            }
        }
    }

    private func quickActionButton(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(tint.opacity(0.12))
                        .frame(width: 52, height: 52)

                    Image(systemName: systemImage)
                        .font(.headline)
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineSpacing(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textTertiary)
            }
            .padding(.vertical, AppTheme.Spacing.sm)
            .padding(.horizontal, AppTheme.Spacing.md)
            .background(AppTheme.Colors.backgroundSecondary.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func focusTaskRow(_ task: AppTask) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text(taskDueLabel(for: task))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                StatusBadge(status: normalizedTaskStatus(task.status))
                StatusBadge(status: task.priority)
            }
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func insightRow(icon: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.Colors.backgroundSecondary.opacity(0.9))
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = baseCurrency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount) \(baseCurrency)"
    }

    private func taskDueLabel(for task: AppTask) -> String {
        guard let dueDate = dueDateValue(for: task) else {
            return "Без срока"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .medium
        return "Срок: \(formatter.string(from: dueDate))"
    }

    private func normalizedTaskStatus(_ status: String) -> String {
        let normalized = status.lowercased().replacingOccurrences(of: " ", with: "_")
        switch normalized {
        case "completed":
            return "done"
        case "todo":
            return "pending"
        default:
            return normalized
        }
    }

    private func isCompletedTask(_ task: AppTask) -> Bool {
        normalizedTaskStatus(task.status) == "done"
    }

    private func isOpenTask(_ task: AppTask) -> Bool {
        let status = normalizedTaskStatus(task.status)
        return status != "done" && status != "cancelled"
    }

    private func dueDateValue(for task: AppTask) -> Date? {
        guard let dueDate = task.dueDate else { return nil }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: dueDate) {
            return date
        }

        let fallbackISOFormatter = ISO8601DateFormatter()
        if let date = fallbackISOFormatter.date(from: dueDate) {
            return date
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.date(from: dueDate)
    }
}
