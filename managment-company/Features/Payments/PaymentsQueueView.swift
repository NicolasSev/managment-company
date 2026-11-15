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
    /// Batch mark-paid confirmation (GAP-050).
    @State private var batchConfirmPresented = false
    /// Per-allocation history sheet (GAP-048).
    @State private var allocationItem: PaymentQueueItem?
    /// Lease opened from a queue row («Договор»); the queue reloads when it comes back.
    @State private var leaseRoute: QueueLeaseRoute?
    @State private var reloadOnReturn = false
    /// Rows whose "paid" request is in flight: the check mark is already morphed.
    @State private var payingIds: Set<String> = []
    @State private var rowsVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                if !embedded { AppScreenBackground() }
                content
            }
            .navigationTitle(embedded ? "Деньги" : "Оплата")
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
            .sheet(item: $allocationItem, content: allocationSheet)
            .navigationDestination(item: $leaseRoute) { route in
                LeaseDetailView(
                    leaseId: route.leaseId,
                    service: LeaseV2ServiceProvider.makeService(authManager: authManager)
                )
            }
            .onAppear {
                guard reloadOnReturn else { return }
                reloadOnReturn = false
                Task { await viewModel.load() }
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

    @ViewBuilder
    private func allocationSheet(for item: PaymentQueueItem) -> some View {
        AllocationHistorySheet(
            item: item,
            onAllocationReversed: { Task { await viewModel.load() } },
            onFullRestore: { await viewModel.restore(item) }
        )
        .environmentObject(authManager)
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
            loadingSkeleton
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    segmentPicker

                    if let errorMessage = viewModel.errorMessage {
                        statusBanner(errorMessage)
                    }

                    let rows = viewModel.displayedItems(today: today)
                    summaryCard(rows)

                    if rows.isEmpty {
                        emptyState
                    } else {
                        if viewModel.segment != .history {
                            selectionHeader(rows)
                            if !viewModel.selectedRows(in: rows).isEmpty {
                                selectionBar(rows)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        rowsSection(rows)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.top, AppTheme.Spacing.sm)
                .padding(.bottom, AppTheme.Spacing.xxl + AppTheme.Spacing.xl)
                .animation(
                    AppTheme.Motion.resolved(AppTheme.Motion.normal, reduceMotion: reduceMotion),
                    value: viewModel.selectedIds.isEmpty
                )
            }
        }
    }

    /// Skeleton in the shape of the queue: summary and three rows.
    private var loadingSkeleton: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                segmentPicker
                Group {
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            Text("К получению").sectionLabelStyle()
                            Text("000 000 ₸").font(AppTheme.Typography.masthead)
                            Text("0 платежей").font(.caption)
                        }
                    }
                    ForEach(0..<3, id: \.self) { _ in
                        SurfaceCard(padding: AppTheme.Spacing.md) {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                                HStack {
                                    Text("1 января 2026").font(.headline)
                                    Spacer()
                                    Text("000 000 ₸").font(AppTheme.Typography.money)
                                }
                                Text("Название объекта").font(.subheadline)
                                Text("Имя арендатора").font(.caption)
                            }
                        }
                    }
                }
                .shimmerPlaceholder(true)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.top, AppTheme.Spacing.sm)
        }
        .accessibilityLabel("Загружаем платежи")
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

    /// Hero of the segment: what is due (or recorded) in total, with the count beside it.
    private func summaryCard(_ rows: [PaymentQueueItem]) -> some View {
        let isHistory = viewModel.segment == .history
        let isOverdue = viewModel.segment == .overdue
        let overdue = viewModel.overdueSummary
        let totals: [(currency: String, total: Double)] = isHistory
            ? Self.recordedTotals(rows)
            : PaymentsQueueViewModel.selectionTotals(items: rows)
        let tint = isOverdue && !rows.isEmpty ? AppTheme.Colors.danger : AppTheme.Colors.textPrimary
        return SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(isHistory ? "Записано" : (isOverdue ? "Долг" : "К получению"))
                        .sectionLabelStyle(isOverdue && !rows.isEmpty ? AppTheme.Colors.danger : AppTheme.Colors.textSecondary)
                    Spacer()
                    Text("\(rows.count) \(Self.paymentsWord(rows.count))")
                        .sectionLabelStyle()
                        .contentTransition(.numericText())
                }

                if totals.isEmpty {
                    Text(AppFormatting.currency(0, currency: authManager.user?.baseCurrency ?? "KZT"))
                        .font(AppTheme.Typography.masthead)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                } else {
                    ForEach(totals, id: \.currency) { entry in
                        Text(AppFormatting.currency(entry.total, currency: entry.currency))
                            .font(AppTheme.Typography.masthead)
                            .monospacedDigit()
                            .foregroundStyle(tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .contentTransition(reduceMotion ? .opacity : .numericText(value: entry.total))
                    }
                }

                DimensionRule(ticks: 5)

                Text(summaryNote(isHistory: isHistory, isOverdue: isOverdue, overdue: overdue))
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .animation(
                AppTheme.Motion.resolved(AppTheme.Motion.normal, reduceMotion: reduceMotion),
                value: rows.map(\.id)
            )
        }
        .accessibilityElement(children: .combine)
    }

    private func summaryNote(isHistory: Bool, isOverdue: Bool, overdue: OverdueSummary) -> String {
        if isHistory {
            return "Оплаченные и пропущенные платежи за выбранный горизонт."
        }
        if isOverdue, overdue.oldestDaysOverdue > 0 {
            return "Старейший долг: \(overdue.oldestDaysOverdue) дн. Очередь — ровно та, что уходит в push-напоминания."
        }
        return "Очередь — ровно та, что уходит в push-напоминания. Правка даты или суммы меняет договор и все будущие платежи."
    }

    private static func recordedTotals(_ rows: [PaymentQueueItem]) -> [(currency: String, total: Double)] {
        var order: [String] = []
        var sums: [String: Double] = [:]
        for item in rows where PaymentsQueueViewModel.displayStatus(of: item, scope: .past) == "paid" {
            if sums[item.currency] == nil { order.append(item.currency) }
            sums[item.currency, default: 0] += item.actualAmount ?? item.expectedAmount
        }
        return order.map { ($0, sums[$0] ?? 0) }
    }

    private static func paymentsWord(_ count: Int) -> String {
        let mod100 = count % 100
        let mod10 = count % 10
        if (11...14).contains(mod100) { return "платежей" }
        switch mod10 {
        case 1: return "платёж"
        case 2, 3, 4: return "платежа"
        default: return "платежей"
        }
    }

    private func selectionHeader(_ rows: [PaymentQueueItem]) -> some View {
        HStack {
            Text("Очередь")
                .sectionLabelStyle()
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                viewModel.toggleSelectAll(rows: rows)
            } label: {
                Text(
                    viewModel.selectedRows(in: rows).count == rows.count
                        ? "Снять выбор"
                        : "Выбрать все"
                )
                .font(.footnote.weight(.semibold))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .disabled(viewModel.isBatchRunning)
            .accessibilityLabel("Выбрать все платежи")
        }
        .padding(.horizontal, AppTheme.Spacing.xs)
        .padding(.vertical, -AppTheme.Spacing.sm)
    }

    /// Selection bar for batch mark-paid (GAP-050): count, per-currency
    /// outstanding totals, clear + one confirmed batch action.
    private func selectionBar(_ rows: [PaymentQueueItem]) -> some View {
        let selected = viewModel.selectedRows(in: rows)
        let totals = PaymentsQueueViewModel.selectionTotals(items: selected)
        return SurfaceCard(padding: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Выбрано: \(selected.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .contentTransition(.numericText())
                    Spacer()
                    Button("Сбросить") {
                        viewModel.selectedIds = []
                    }
                    .font(.footnote.weight(.semibold))
                    .disabled(viewModel.isBatchRunning)
                }
                ForEach(totals, id: \.currency) { entry in
                    Text("К получению: \(AppFormatting.currency(entry.total, currency: entry.currency))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                PrimaryButton(
                    title: viewModel.isBatchRunning ? "Записываем…" : "Отметить оплаченными (\(selected.count))",
                    action: { batchConfirmPresented = true },
                    isLoading: viewModel.isBatchRunning,
                    systemImage: "checkmark"
                )
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.surface, style: .continuous)
                .strokeBorder(AppTheme.Colors.accent.opacity(0.5), lineWidth: 1)
        )
        .confirmationDialog(
            "Отметить оплаченными?",
            isPresented: $batchConfirmPresented,
            titleVisibility: .visible
        ) {
            Button("Оплачено (\(selected.count))") {
                Task {
                    let result = await viewModel.batchMarkPaid(
                        rows: viewModel.displayedItems(today: today),
                        timeZoneIdentifier: authManager.user?.timezone ?? "Asia/Almaty"
                    )
                    if result.succeeded > 0 {
                        AppHaptics.success()
                    }
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            let totalsText = totals
                .map { AppFormatting.currency($0.total, currency: $0.currency) }
                .joined(separator: " + ")
            Text("Платежей: \(selected.count) на \(totalsText). Каждый будет закрыт на остаток суммы с сегодняшней датой получения; плановая дата и период не меняются.")
        }
    }

    private func rowsSection(_ rows: [PaymentQueueItem]) -> some View {
        LazyVStack(spacing: AppTheme.Spacing.sm) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                SurfaceCard(padding: AppTheme.Spacing.md) {
                    if viewModel.segment == .history {
                        pastRow(item)
                    } else {
                        upcomingRow(item)
                    }
                }
                .overlay(alignment: .leading) {
                    if item.isOverdue, viewModel.segment != .history {
                        // Overdue marker: a red rule on the binding edge of the sheet.
                        Rectangle()
                            .fill(AppTheme.Colors.danger)
                            .frame(width: 3)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.surface, style: .continuous))
                .appearStagger(index: index, isVisible: rowsVisible)
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)).combined(with: .move(edge: .trailing))
                ))
            }
        }
        .animation(
            AppTheme.Motion.resolved(AppTheme.Motion.normal, reduceMotion: reduceMotion),
            value: rows.map(\.id)
        )
        .onAppear { rowsVisible = true }
    }

    private func rowHeader(
        date: String,
        isDatePlaceholder: Bool = false,
        amount: Double,
        item: PaymentQueueItem,
        scope: PaymentQueueScope
    ) -> some View {
        // Large text: the amount and the badge go under the date instead of beside it.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppTheme.Spacing.sm))
            : AnyLayout(HStackLayout(alignment: .top, spacing: AppTheme.Spacing.sm))
        return layout {
            VStack(alignment: .leading, spacing: 4) {
                Text(date)
                    .font(.headline)
                    .foregroundStyle(isDatePlaceholder ? AppTheme.Colors.textSecondary : AppTheme.Colors.textPrimary)

                Text("Период: \(PaymentsQueueViewModel.periodLabel(of: item))")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                if scope == .upcoming, item.isOverdue, item.daysOverdue > 0 {
                    Text("Просрочено на \(item.daysOverdue) дн.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.danger)
                }
            }

            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: AppTheme.Spacing.sm)
            }

            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 6) {
                Text(AppFormatting.currency(amount, currency: item.currency))
                    .font(AppTheme.Typography.money)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())

                if scope == .upcoming, let allocations = item.allocationCount, allocations > 0,
                   item.outstandingAmount < item.expectedAmount {
                    Text("из \(AppFormatting.currency(item.expectedAmount, currency: item.currency))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }

                StatusBadge(status: PaymentsQueueViewModel.displayStatus(of: item, scope: scope))
            }
        }
    }

    private func upcomingRow(_ item: PaymentQueueItem) -> some View {
        let isSelected = viewModel.selectedIds.contains(item.id)
        let isPaying = payingIds.contains(item.id)
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                Button {
                    AppHaptics.selection()
                    viewModel.toggleSelection(item)
                } label: {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundStyle(isSelected ? AppTheme.Colors.accent : AppTheme.Colors.textTertiary)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 32, height: 44, alignment: .topLeading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isBatchRunning)
                .accessibilityLabel("Выбрать платёж: \(item.propertyName)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])

                rowHeader(
                    date: AppFormatting.dateString(from: item.dueDate) ?? item.dueDate,
                    amount: item.outstandingAmount,
                    item: item,
                    scope: .upcoming
                )
            }

            propertyTenantBlock(item)
                .padding(.leading, 32 + AppTheme.Spacing.sm)

            Rectangle().fill(AppTheme.Colors.border).frame(height: 1)

            // Large text: the primary action takes its own line.
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppTheme.Spacing.xs))
                : AnyLayout(HStackLayout(spacing: AppTheme.Spacing.sm))) {
                Button {
                    markPaid(item)
                } label: {
                    HStack(spacing: 6) {
                        PaidCheckMark(isOn: isPaying, size: 16, haptic: false, onTint: AppTheme.Colors.onAccent, offTint: AppTheme.Colors.onAccent)
                        Text("Оплачено")
                            .lineLimit(1)
                    }
                }
                .buttonStyle(MarkPaidButtonStyle(isPaying: isPaying))
                .contextMenu {
                    Button {
                        markPaidItem = item
                    } label: {
                        Label("Указать дату и сумму…", systemImage: "calendar")
                    }
                }
                .accessibilityHint("Записывает оплату сегодняшней датой")

                HStack(spacing: AppTheme.Spacing.sm) {
                    Button("Договор") { openLease(item) }
                        .buttonStyle(QuietActionButtonStyle(fills: dynamicTypeSize.isAccessibilitySize))
                        .accessibilityIdentifier("payments.row.\(item.id).lease")

                    rowMoreMenu(item)
                }
            }
            .disabled(viewModel.isMutating)
        }
        .contextMenu { rowMenuItems(item) }
    }

    private func markPaid(_ item: PaymentQueueItem) {
        payingIds.insert(item.id)
        Task {
            // Let the ring finish its morph into the check before the row leaves the queue:
            // on a fast connection the reload would otherwise remove it mid-animation.
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(320))
            }
            let paid = await viewModel.markPaidToday(
                item,
                timeZoneIdentifier: authManager.user?.timezone ?? "Asia/Almaty"
            )
            if paid {
                AppHaptics.success()
            } else {
                AppHaptics.warning()
            }
            payingIds.remove(item.id)
        }
    }

    /// Secondary actions of an upcoming row: allocations, skip, tenant contact (GAP-034)
    /// and the property. Contact entries appear only when the channel exists.
    private func rowMoreMenu(_ item: PaymentQueueItem) -> some View {
        Menu {
            rowMenuItems(item)
        } label: {
            Image(systemName: "ellipsis")
                .font(.footnote.weight(.bold))
                .foregroundStyle(AppTheme.Colors.accent)
                .frame(width: 44, height: 38)
                .background(
                    AppTheme.Colors.accent.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: AppTheme.Radius.inner, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.inner, style: .continuous)
                        .strokeBorder(AppTheme.Colors.accent.opacity(0.28), lineWidth: 1)
                )
                .padding(.vertical, 3)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Ещё действия: \(item.propertyName)")
    }

    @ViewBuilder
    private func rowMenuItems(_ item: PaymentQueueItem) -> some View {
        Button {
            editingItem = item
        } label: {
            Label("Изменить день или сумму", systemImage: "pencil")
        }
        Button {
            markPaidItem = item
        } label: {
            Label("Оплачено: указать дату и сумму…", systemImage: "calendar")
        }
        if let count = item.allocationCount, count > 0 {
            Button {
                allocationItem = item
            } label: {
                Label("Платежи (\(count))", systemImage: "list.bullet.clipboard")
            }
        }
        if let phone = item.tenantPhone, !phone.isEmpty,
           let telURL = URL(string: "tel:\(phone.filter { !$0.isWhitespace })") {
            Button { openURL(telURL) } label: { Label("Позвонить", systemImage: "phone") }
            if let smsURL = URL(string: "sms:\(phone.filter { !$0.isWhitespace })") {
                Button { openURL(smsURL) } label: { Label("Написать", systemImage: "message") }
            }
        } else if let email = item.tenantEmail, !email.isEmpty,
                  let mailURL = URL(string: "mailto:\(email)") {
            Button { openURL(mailURL) } label: { Label("Написать", systemImage: "envelope") }
        }
        Button {
            notificationRouter.open(NotificationRoute(kind: .property(item.propertyId)))
        } label: {
            Label("Открыть объект", systemImage: "building.2")
        }
        Divider()
        Button(role: .destructive) {
            skipCandidate = item
        } label: {
            Label("Пропустить", systemImage: "forward.end")
        }
    }

    private func openLease(_ item: PaymentQueueItem) {
        reloadOnReturn = true
        leaseRoute = QueueLeaseRoute(leaseId: item.leaseId)
    }

    private func pastRow(_ item: PaymentQueueItem) -> some View {
        let recorded = PaymentsQueueViewModel.recordedDate(of: item)
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            rowHeader(
                date: recorded.map { AppFormatting.dateString(from: $0) ?? $0 } ?? "—",
                isDatePlaceholder: recorded == nil,
                amount: item.actualAmount ?? item.expectedAmount,
                item: item,
                scope: .past
            )

            propertyTenantBlock(item)

            Rectangle().fill(AppTheme.Colors.border).frame(height: 1)

            HStack(spacing: AppTheme.Spacing.sm) {
                Button("Платежи") { allocationItem = item }
                    .buttonStyle(QuietActionButtonStyle())
                Button("Договор") { openLease(item) }
                    .buttonStyle(QuietActionButtonStyle())
                    .accessibilityIdentifier("payments.row.\(item.id).lease")
                if PaymentsQueueViewModel.restoreRequiresConfirmation(for: item) {
                    Button("Отменить оплату") { unpayCandidate = item }
                        .buttonStyle(QuietActionButtonStyle(tint: AppTheme.Colors.danger))
                } else {
                    Button("Вернуть в очередь") {
                        Task {
                            if await viewModel.restore(item) {
                                AppHaptics.success()
                            }
                        }
                    }
                    .buttonStyle(QuietActionButtonStyle())
                }
            }
            .disabled(viewModel.isMutating)
        }
    }

    private func propertyTenantBlock(_ item: PaymentQueueItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.propertyName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .lineLimit(1)

            Text(
                [item.tenantName.isEmpty ? "—" : item.tenantName, item.propertyAddress ?? ""]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
            )
            .font(.caption)
            .foregroundStyle(AppTheme.Colors.textSecondary)
            .lineLimit(1)
        }
    }

    private var emptyState: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text(viewModel.scope == .past ? "Прошлых платежей нет" : "Очередь пуста")
                    .font(AppTheme.Typography.display)
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
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(AppTheme.Colors.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(AppTheme.Colors.danger.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.inner, style: .continuous))
    }
}

/// Primary action of a queue row. While its own payment is being recorded the button stays
/// solid, so the check morph is readable; other rows dim as disabled.
private struct MarkPaidButtonStyle: ButtonStyle {
    let isPaying: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AppTheme.Colors.onAccent)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(
                AppTheme.Colors.accent,
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.inner, style: .continuous)
            )
            .opacity(isPaying ? 1 : (isEnabled ? (configuration.isPressed ? 0.86 : 1) : 0.45))
            .padding(.vertical, 3)
            .contentShape(Rectangle())
    }
}

/// Navigation value of the «Договор» row action.
private struct QueueLeaseRoute: Identifiable, Hashable {
    let leaseId: String
    var id: String { leaseId }
}
