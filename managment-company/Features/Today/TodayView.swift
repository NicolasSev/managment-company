import SwiftUI

/// `Сегодня` operating screen (GAP-031), iOS counterpart of web `/today`: a
/// distinct day-operations surface that assembles urgent work. It never
/// replaces or restructures the Dashboard, which stays a separate tab/route.
struct TodayView: View {
    @StateObject private var viewModel: TodayViewModel
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var notificationRouter: NotificationDeepLinkRouter
    @EnvironmentObject private var quickActions: QuickActionsController
    @ObservedObject private var expenseReminder = ExpenseReminderController.shared

    @State private var markPaidItem: PaymentQueueItem?
    @State private var showRecurring = false

    init(authManager: AuthManager) {
        _viewModel = StateObject(wrappedValue: TodayViewModel(
            client: LiveTodayClient(authManager: authManager),
            timeZoneIdentifier: authManager.user?.timezone ?? "Asia/Almaty",
            baseCurrency: authManager.user?.baseCurrency ?? "KZT"
        ))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground()
                content
            }
            .navigationTitle("Сегодня")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { notificationRouter.selectTab = .dashboard } label: {
                            Label("Дашборд", systemImage: "rectangle.grid.2x2")
                        }
                        Button { notificationRouter.selectTab = .tenants } label: {
                            Label("Арендаторы", systemImage: "person.2")
                        }
                        Button { notificationRouter.selectTab = .settings } label: {
                            Label("Настройки", systemImage: "gearshape")
                        }
                        Button { showRecurring = true } label: {
                            Label("Повторяющиеся расходы", systemImage: "arrow.triangle.2.circlepath")
                        }
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Ещё")
                }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .sheet(item: $markPaidItem) { item in
                MarkSchedulePaidSheet(schedule: item.asLeaseSchedule) {
                    await viewModel.load()
                }
                .environmentObject(authManager)
            }
            .onReceive(NotificationCenter.default.publisher(for: .quickActionCompleted)) { _ in
                Task { await viewModel.load() }
            }
            .sheet(isPresented: $showRecurring) {
                RecurringExpensesView(authManager: authManager)
                    .environmentObject(authManager)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.attentionItems.isEmpty && viewModel.moneySummary == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    hero
                    if viewModel.hasPartialError { partialErrorBanner }
                    if expenseReminder.shouldShowCard { expenseReminderCard }
                    quickActionsSection
                    attentionSection
                    if !viewModel.dueRecurring.isEmpty { recurringSection }
                    if let money = viewModel.moneySummary { moneySection(money) }
                    if !viewModel.performanceRows.isEmpty { performanceSection }
                    if !viewModel.recentRows.isEmpty { recentSection }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.lg)
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("СЕГОДНЯ")
                    .font(.caption.weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Text(viewModel.attentionCount > 0
                     ? "\(viewModel.attentionCount) пунктов требуют внимания"
                     : "Срочных вопросов нет")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text("Операционный экран на день. Подробная аналитика остаётся в Дашборде.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Button {
                    notificationRouter.selectTab = .dashboard
                } label: {
                    Label("Открыть Дашборд", systemImage: "rectangle.grid.2x2")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.top, 2)
            }
        }
    }

    private var expenseReminderCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Label("Расходы за день", systemImage: "banknote")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text("Записать сегодняшние расходы по объектам?")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                HStack(spacing: AppTheme.Spacing.sm) {
                    Button("Записать расход") {
                        quickActions.open(.expense)
                    }
                    .font(.caption.weight(.semibold))
                    Button("Не сегодня") {
                        expenseReminder.dismissForToday()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    Spacer()
                }
            }
        }
    }

    private var partialErrorBanner: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.Colors.warning)
            Text("Часть данных временно недоступна. Остальные блоки продолжают работать.")
                .font(.footnote)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.Colors.warning.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Quick actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("Быстрые действия")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textSecondary)
            HStack(spacing: AppTheme.Spacing.sm) {
                quickAction("Оплата", "wallet.bullet") { quickActions.open(.payment) }
                quickAction("Расход", "banknote") { quickActions.open(.expense) }
                quickAction("Квитанция", "doc.text.viewfinder") { quickActions.open(.receipt) }
                quickAction("Задача", "checklist") { quickActions.open(.task) }
            }
        }
    }

    private func quickAction(_ title: String, _ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(AppTheme.Colors.accent.opacity(0.1))
            .foregroundStyle(AppTheme.Colors.accent)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Attention

    private var attentionSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Text("Сначала важное")
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Spacer()
                Button("Все платежи") { notificationRouter.selectTab = .payments }
                    .font(.subheadline.weight(.semibold))
            }

            if viewModel.attentionItems.isEmpty {
                SurfaceCard {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.Colors.success)
                        Text("Просрочек и срочных задач сейчас нет.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                    }
                }
            } else {
                ForEach(viewModel.attentionItems) { item in
                    attentionRow(item)
                }
            }
        }
    }

    private func attentionRow(_ item: TodayAttentionItem) -> some View {
        SurfaceCard(padding: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                    Image(systemName: icon(for: item.kind))
                        .foregroundStyle(tint(for: item.tone))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    Spacer()
                }

                HStack(spacing: AppTheme.Spacing.sm) {
                    if let schedule = item.scheduleItem {
                        Button("Оплачено") {
                            Task {
                                if await viewModel.markPaidToday(schedule) { AppHaptics.success() }
                            }
                        }
                        .font(.caption.weight(.semibold))
                        Button("Открыть") { markPaidItem = schedule }
                            .font(.caption.weight(.semibold))
                    } else if let taskId = item.taskId {
                        Button("Готово") {
                            Task {
                                if await viewModel.completeTask(id: taskId) { AppHaptics.success() }
                            }
                        }
                        .font(.caption.weight(.semibold))
                        Button("Открыть") { open(item.deepLink) }
                            .font(.caption.weight(.semibold))
                    } else {
                        Button("Открыть") { open(item.deepLink) }
                            .font(.caption.weight(.semibold))
                    }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isLoading)
            }
        }
    }

    private var recurringSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack {
                    Text("Повторяющиеся расходы")
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Spacer()
                    Button("Управление") { showRecurring = true }
                        .font(.subheadline.weight(.semibold))
                }
                ForEach(viewModel.dueRecurring) { template in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(template.categoryName.isEmpty ? "Расход" : template.categoryName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                            Spacer()
                            Text(AppFormatting.currency(template.amount, currency: template.currency))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                        }
                        Text(template.propertyName)
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                        HStack(spacing: AppTheme.Spacing.sm) {
                            Button("Подтвердить") {
                                Task { if await viewModel.confirmDueRecurring(template) { AppHaptics.success() } }
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Пропустить") {
                                Task { _ = await viewModel.skipDueRecurring(template) }
                            }
                            .buttonStyle(.bordered)
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
            }
        }
    }

    private func open(_ link: TodayDeepLink) {
        switch link {
        case .paymentsList:
            notificationRouter.selectTab = .payments
        case .paymentDetail:
            notificationRouter.selectTab = .payments
        case .task(let id):
            notificationRouter.open(NotificationRoute(kind: .task(id)))
        case .property(let id):
            notificationRouter.open(NotificationRoute(kind: .property(id)))
        }
    }

    // MARK: - Money

    private func moneySection(_ money: TodayMoneySummary) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Деньги · \(money.periodLabel)")
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                // Drilldowns (GAP-035): rent → collection, the rest → ledger.
                moneyRow("Аренда получена", money.rentReceived, money.currency, AppTheme.Colors.success, tab: .payments)
                moneyRow("Прочий доход", money.otherIncome, money.currency, AppTheme.Colors.textPrimary, tab: .transactions)
                moneyRow("Расходы", money.expenses, money.currency, AppTheme.Colors.danger, tab: .transactions)
                Divider()
                moneyRow("Чистый поток", money.net, money.currency,
                         money.net >= 0 ? AppTheme.Colors.success : AppTheme.Colors.danger, tab: .transactions)
            }
        }
    }

    private func moneyRow(_ label: String, _ amount: Double, _ currency: String, _ color: Color, tab: AppTab) -> some View {
        Button {
            notificationRouter.selectTab = tab
        } label: {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Spacer()
                Text(AppFormatting.currency(amount, currency: currency))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var performanceSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack {
                    Text("Доходность по объектам")
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Spacer()
                    Menu {
                        ForEach(PropertyPerformanceSort.allCases) { sort in
                            Button {
                                viewModel.performanceSort = sort
                            } label: {
                                if viewModel.performanceSort == sort {
                                    Label(sort.title, systemImage: "checkmark")
                                } else {
                                    Text(sort.title)
                                }
                            }
                        }
                    } label: {
                        Label(viewModel.performanceSort.title, systemImage: "arrow.up.arrow.down")
                            .font(.caption.weight(.semibold))
                    }
                }
                ForEach(viewModel.performanceRows) { row in
                    Button {
                        notificationRouter.open(NotificationRoute(kind: .property(row.id)))
                    } label: {
                        HStack {
                            Text(row.name)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(AppFormatting.currency(row.net, currency: viewModel.moneySummary?.currency ?? "KZT"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(row.net >= 0 ? AppTheme.Colors.success : AppTheme.Colors.danger)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Recent

    private var recentSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack {
                    Text("Последние операции")
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Spacer()
                    Button("Все") { notificationRouter.selectTab = .transactions }
                        .font(.subheadline.weight(.semibold))
                }
                ForEach(DashboardRecentTransactionsLogic.visibleRows(viewModel.recentRows, expanded: false)) { row in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.propertyName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                            Text(row.categoryName ?? row.description ?? "")
                                .font(.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text("\(row.amountSign)\(AppFormatting.currency(row.amount, currency: row.currency))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(row.isIncome ? AppTheme.Colors.success : AppTheme.Colors.danger)
                    }
                }
            }
        }
    }

    // MARK: - Styling

    private func icon(for kind: TodayAttentionKind) -> String {
        switch kind {
        case .overdueRent, .dueTodayRent: return "calendar.badge.clock"
        case .task: return "checklist"
        case .renewal: return "arrow.triangle.2.circlepath"
        case .receipt: return "doc.text.viewfinder"
        }
    }

    private func tint(for tone: TodayAttentionTone) -> Color {
        switch tone {
        case .danger: return AppTheme.Colors.danger
        case .warning: return AppTheme.Colors.warning
        case .info: return AppTheme.Colors.accent
        }
    }
}
