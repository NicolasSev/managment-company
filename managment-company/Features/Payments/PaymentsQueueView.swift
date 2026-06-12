import SwiftUI

/// Cross-portfolio payment queue (GAP-026/027), iOS counterpart of web `/payments`:
/// **Будущие платежи** — the upcoming APNs reminder queue across all active
/// leases, editable inline (day/amount edits rewrite the lease contract,
/// mark-paid records income, skip drops one installment); **Прошлые платежи** —
/// paid/skipped installments with restore/un-pay actions.
struct PaymentsQueueView: View {
    @StateObject private var viewModel: PaymentsQueueViewModel
    @EnvironmentObject private var authManager: AuthManager

    @State private var editingItem: PaymentQueueItem?
    @State private var markPaidItem: PaymentQueueItem?
    @State private var skipCandidate: PaymentQueueItem?
    @State private var unpayCandidate: PaymentQueueItem?

    init(authManager: AuthManager) {
        _viewModel = StateObject(
            wrappedValue: PaymentsQueueViewModel(client: LivePaymentQueueClient(authManager: authManager))
        )
    }

    var body: some View {
        NavigationStack {
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
                    scopePicker

                    if let errorMessage = viewModel.errorMessage {
                        statusBanner(errorMessage)
                    }

                    if viewModel.items.isEmpty {
                        emptyState
                    } else {
                        summaryLine
                        rowsSection
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

    private var scopePicker: some View {
        Picker("Раздел", selection: $viewModel.scope) {
            ForEach(PaymentQueueScope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .pickerStyle(.segmented)
    }

    private var summaryLine: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Text("\(viewModel.items.count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
            Text(viewModel.scope == .past ? "платежей в истории" : "платежей в очереди")
                .font(.subheadline)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            if !viewModel.totalsByCurrency.isEmpty {
                Text("·")
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Text(totalsLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }

            Spacer()
        }
        .padding(.horizontal, AppTheme.Spacing.xs)
    }

    private var totalsLabel: String {
        viewModel.totalsByCurrency
            .map { AppFormatting.currency($0.total, currency: $0.currency) }
            .joined(separator: " + ")
    }

    private var rowsSection: some View {
        LazyVStack(spacing: AppTheme.Spacing.sm) {
            ForEach(viewModel.items) { item in
                SurfaceCard(padding: AppTheme.Spacing.md) {
                    if viewModel.scope == .past {
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

                    propertyTenantBlock(item)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text(AppFormatting.currency(item.expectedAmount, currency: item.currency))
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)

                    StatusBadge(status: PaymentsQueueViewModel.displayStatus(of: item, scope: .upcoming))
                }
            }

            HStack(spacing: AppTheme.Spacing.sm) {
                rowActionButton(title: "Изменить", systemImage: "pencil") {
                    editingItem = item
                }
                rowActionButton(title: "Оплачено", systemImage: "checkmark.circle") {
                    markPaidItem = item
                }
                rowActionButton(title: "Пропустить", systemImage: "forward.end") {
                    skipCandidate = item
                }
            }
            .disabled(viewModel.isMutating)
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
