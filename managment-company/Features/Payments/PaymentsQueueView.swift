import SwiftUI

/// Cross-portfolio payment queue (GAP-026/027), iOS counterpart of web `/payments`:
/// **Будущие платежи** — the upcoming APNs reminder queue across all active
/// leases, editable inline (day/amount edits rewrite the lease contract,
/// mark-paid records income, skip drops one installment); **Прошлые платежи** —
/// paid/skipped installments with restore/un-pay actions.
struct PaymentsQueueView: View {
    @StateObject private var viewModel: PaymentsQueueViewModel
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var notificationRouter: NotificationDeepLinkRouter
    @Environment(\.openURL) private var openURL

    @State private var editingItem: PaymentQueueItem?
    @State private var markPaidItem: PaymentQueueItem?
    @State private var skipCandidate: PaymentQueueItem?
    @State private var unpayCandidate: PaymentQueueItem?

    /// When embedded inside another navigation container (the GAP-037 «Деньги»
    /// hub), the view skips its own `NavigationStack`.
    var embedded = false

    init(authManager: AuthManager, embedded: Bool = false) {
        self.embedded = embedded
        _viewModel = StateObject(
            wrappedValue: PaymentsQueueViewModel(client: LivePaymentQueueClient(authManager: authManager))
        )
    }

    var body: some View {
        if embedded {
            core
        } else {
            NavigationStack { core }
        }
    }

    @ViewBuilder
    private var core: some View {
            ZStack {
                AppScreenBackground()
                content
            }
            .navigationTitle("Оплата")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    horizonMenu
                }
            }
            .task(id: "\(viewModel.scope.rawValue)-\(viewModel.months)") {
                await viewModel.load()
            }
            .refreshable { await viewModel.load() }
            .sheet(item: $editingItem) { item in
                PaymentScheduleEditSheet(item: item) { day, amount in
                    await viewModel.applyEdit(to: item, day: day, amount: amount)
                }
            }
            .sheet(item: $markPaidItem) { item in
                MarkSchedulePaidSheet(schedule: item.asLeaseSchedule) {
                    await viewModel.load()
                }
                .environmentObject(authManager)
            }
            .confirmationDialog(
                "Пропустить этот платёж?",
                isPresented: Binding(
                    get: { skipCandidate != nil },
                    set: { if !$0 { skipCandidate = nil } }
                ),
                titleVisibility: .visible,
                presenting: skipCandidate
            ) { item in
                Button("Пропустить", role: .destructive) {
                    Task {
                        if await viewModel.skip(item) {
                            AppHaptics.success()
                        }
                    }
                }
                Button("Отмена", role: .cancel) {}
            } message: { item in
                Text("\(item.propertyName) · \(AppFormatting.currency(item.expectedAmount, currency: item.currency)). Платёж будет помечен как пропущенный и не уйдёт в напоминания.")
            }
            .confirmationDialog(
                "Отменить оплату?",
                isPresented: Binding(
                    get: { unpayCandidate != nil },
                    set: { if !$0 { unpayCandidate = nil } }
                ),
                titleVisibility: .visible,
                presenting: unpayCandidate
            ) { item in
                Button("Отменить оплату", role: .destructive) {
                    Task {
                        if await viewModel.restore(item) {
                            unpayCandidate = nil
                            AppHaptics.success()
                        }
                    }
                }
                Button("Оставить оплату", role: .cancel) {}
            } message: { item in
                Text("\(item.propertyName) · \(PaymentsQueueViewModel.periodLabel(of: item)) · \(AppFormatting.currency(item.actualAmount ?? item.expectedAmount, currency: item.currency)). Связанная операция дохода будет удалена, а платёж вернётся в очередь.")
            }
    }

    private var horizonMenu: some View {
        Menu {
            ForEach(PaymentsQueueViewModel.horizonOptions, id: \.self) { months in
                Button {
                    viewModel.months = months
                } label: {
                    if viewModel.months == months {
                        Label(horizonLabel(months), systemImage: "checkmark")
                    } else {
                        Text(horizonLabel(months))
                    }
                }
            }
        } label: {
            Label(horizonLabel(viewModel.months), systemImage: "calendar")
        }
        .accessibilityLabel("Горизонт очереди")
    }

    private func horizonLabel(_ months: Int) -> String {
        "\(months) мес."
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    headerSection
                    segmentPicker

                    if let errorMessage = viewModel.errorMessage {
                        statusBanner(errorMessage)
                    }

                    if viewModel.segment == .overdue, viewModel.overdueSummary.count > 0 {
                        overdueSummaryCard
                    }

                    let rows = viewModel.displayedItems(today: today)
                    if rows.isEmpty {
                        emptyState
                    } else {
                        summaryLine(rows)
                        rowsSection(rows)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.lg)
            }
        }
    }

    private var headerSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Расписание платежей")
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text("Грядущая очередь по оплате — ровно та, что уходит в push-напоминания. Правка даты или суммы меняет договор арендатора и все будущие платежи.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineSpacing(3)
            }
        }
    }

    private var today: String {
        AppFormatting.dayKey(timeZoneIdentifier: authManager.user?.timezone ?? "Asia/Almaty")
    }

    private var segmentPicker: some View {
        Picker("Раздел", selection: $viewModel.segment) {
            ForEach(PaymentCollectionSegment.allCases) { segment in
                Text(segment.title).tag(segment)
            }
        }
        .pickerStyle(.segmented)
    }

    private var overdueSummaryCard: some View {
        let summary = viewModel.overdueSummary
        return SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack {
                    Text("\(summary.count) просрочено")
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.danger)
                    Spacer()
                    if summary.oldestDaysOverdue > 0 {
                        Text("Старейший долг: \(summary.oldestDaysOverdue) дн.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
                ForEach(summary.totalsByCurrency, id: \.currency) { entry in
                    Text("Долг: \(AppFormatting.currency(entry.remaining, currency: entry.currency))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }
            }
        }
    }

    private func summaryLine(_ rows: [PaymentQueueItem]) -> some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Text("\(rows.count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
            Text(viewModel.segment == .history ? "платежей в истории" : "платежей")
                .font(.subheadline)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Spacer()
        }
        .padding(.horizontal, AppTheme.Spacing.xs)
    }

    private func rowsSection(_ rows: [PaymentQueueItem]) -> some View {
        LazyVStack(spacing: AppTheme.Spacing.sm) {
            ForEach(rows) { item in
                SurfaceCard(padding: AppTheme.Spacing.md) {
                    if viewModel.segment == .history {
                        pastRow(item)
                    } else {
                        upcomingRow(item)
                    }
                }
            }
        }
    }

    private func upcomingRow(_ item: PaymentQueueItem) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppFormatting.dateString(from: item.dueDate) ?? item.dueDate)
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)

                    Text("Период: \(PaymentsQueueViewModel.periodLabel(of: item))")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)

                    if item.isOverdue, item.daysOverdue > 0 {
                        Text("Просрочено на \(item.daysOverdue) дн.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.danger)
                    }

                    propertyTenantBlock(item)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text(AppFormatting.currency(item.outstandingAmount, currency: item.currency))
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)

                    if let allocations = item.allocationCount, allocations > 0,
                       item.outstandingAmount < item.expectedAmount {
                        Text("из \(AppFormatting.currency(item.expectedAmount, currency: item.currency))")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }

                    StatusBadge(status: PaymentsQueueViewModel.displayStatus(of: item, scope: .upcoming))
                }
            }

            HStack(spacing: AppTheme.Spacing.sm) {
                rowActionButton(title: "Изменить", systemImage: "pencil") {
                    editingItem = item
                }
                rowActionButton(title: "Оплачено", systemImage: "checkmark.circle") {
                    Task {
                        if await viewModel.markPaidToday(
                            item,
                            timeZoneIdentifier: authManager.user?.timezone ?? "Asia/Almaty"
                        ) {
                            AppHaptics.success()
                        }
                    }
                }
                .contextMenu {
                    Button {
                        markPaidItem = item
                    } label: {
                        Label("Указать дату и сумму…", systemImage: "calendar")
                    }
                }
                rowActionButton(title: "Пропустить", systemImage: "forward.end") {
                    skipCandidate = item
                }
            }
            .disabled(viewModel.isMutating)

            collectionActionsRow(item)
        }
    }

    /// Tenant contact + open-context actions (GAP-034). Contact buttons appear
    /// only when the channel exists; open navigates to the property/tenant.
    @ViewBuilder
    private func collectionActionsRow(_ item: PaymentQueueItem) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            if let phone = item.tenantPhone, !phone.isEmpty,
               let telURL = URL(string: "tel:\(phone.filter { !$0.isWhitespace })") {
                rowActionButton(title: "Позвонить", systemImage: "phone") { openURL(telURL) }
                if let smsURL = URL(string: "sms:\(phone.filter { !$0.isWhitespace })") {
                    rowActionButton(title: "Написать", systemImage: "message") { openURL(smsURL) }
                }
            } else if let email = item.tenantEmail, !email.isEmpty,
                      let mailURL = URL(string: "mailto:\(email)") {
                rowActionButton(title: "Написать", systemImage: "envelope") { openURL(mailURL) }
            }
            rowActionButton(title: "Открыть", systemImage: "arrow.up.right.square") {
                notificationRouter.open(NotificationRoute(kind: .property(item.propertyId)))
            }
        }
    }

    private func pastRow(_ item: PaymentQueueItem) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    if let recorded = PaymentsQueueViewModel.recordedDate(of: item) {
                        Text(AppFormatting.dateString(from: recorded) ?? recorded)
                            .font(.headline)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                    } else {
                        Text("—")
                            .font(.headline)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }

                    Text("Период: \(PaymentsQueueViewModel.periodLabel(of: item))")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)

                    propertyTenantBlock(item)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text(AppFormatting.currency(item.actualAmount ?? item.expectedAmount, currency: item.currency))
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)

                    StatusBadge(status: PaymentsQueueViewModel.displayStatus(of: item, scope: .past))
                }
            }

            if PaymentsQueueViewModel.restoreRequiresConfirmation(for: item) {
                rowActionButton(
                    title: "Отменить оплату",
                    systemImage: "arrow.uturn.backward.circle",
                    tint: AppTheme.Colors.danger
                ) {
                    unpayCandidate = item
                }
                .disabled(viewModel.isMutating)
            } else {
                rowActionButton(title: "Вернуть в очередь", systemImage: "arrow.counterclockwise.circle") {
                    Task {
                        if await viewModel.restore(item) {
                            AppHaptics.success()
                        }
                    }
                }
                .disabled(viewModel.isMutating)
            }
        }
    }

    private func propertyTenantBlock(_ item: PaymentQueueItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.propertyName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .lineLimit(1)

            if let address = item.propertyAddress, !address.isEmpty {
                Text(address)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(1)
            }

            Text(item.tenantName.isEmpty ? "—" : item.tenantName)
                .font(.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .lineLimit(1)
        }
    }

    private func rowActionButton(
        title: String,
        systemImage: String,
        tint: Color = AppTheme.Colors.accent,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, AppTheme.Spacing.sm)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(tint.opacity(0.1))
                .foregroundStyle(tint)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text(viewModel.scope == .past ? "Прошлых платежей нет" : "Очередь пуста")
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text(
                    viewModel.scope == .past
                        ? "Нет записанных платежей за выбранный период."
                        : "Нет предстоящих платежей в выбранном горизонте. Очередь формируется из активных договоров с расписанием."
                )
                .font(.subheadline)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .lineSpacing(3)
            }
        }
    }

    private func statusBanner(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(AppTheme.Colors.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(AppTheme.Colors.danger.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
