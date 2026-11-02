import SwiftUI

/// «Коммуналка» of the «Ещё» menu: what waits for the owner (the review inbox), the matrix of the
/// properties by month and the year over year card.
struct UtilitiesOverviewView: View {
    @StateObject private var viewModel: UtilitiesOverviewViewModel
    private let service: UtilityBillsService
    private let timeZoneIdentifier: String

    @EnvironmentObject private var notificationRouter: NotificationDeepLinkRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reviewRoute: UtilityBillRoute?
    @State private var uploadRequest: UtilityUploadRequest?
    @State private var addMonth: UtilityOverviewAddMonth?
    @State private var unreadable = false
    @State private var isVisible = false
    @State private var scrollTarget: String?

    init(authManager: AuthManager) {
        let service = UtilityBillsServiceProvider.makeService(authManager: authManager)
        _viewModel = StateObject(wrappedValue: UtilitiesOverviewViewModel(service: service))
        self.service = service
        self.timeZoneIdentifier = authManager.user?.timezone ?? "Asia/Almaty"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground()
                content
            }
            .navigationTitle("Коммуналка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                        .accessibilityIdentifier("utilities.overview.close")
                }
                ToolbarItem(placement: .primaryAction) {
                    UtilityDocumentMenu(
                        identifier: "utilities.overview.upload",
                        onPicked: { upload in
                            uploadRequest = UtilityUploadRequest(upload: upload, target: UtilityUploadTarget())
                        },
                        onUnreadable: { unreadable = true }
                    ) {
                        Image(systemName: "arrow.up.doc")
                    }
                    .accessibilityLabel("Загрузить квитанцию")
                }
            }
        }
        .task {
            await viewModel.load()
            withAnimation(AppTheme.Motion.resolved(AppTheme.Motion.normal, reduceMotion: reduceMotion)) { isVisible = true }
            handlePendingRoute()
        }
        .onChange(of: notificationRouter.pendingRoute) { _, _ in handlePendingRoute() }
        .refreshable { await viewModel.load() }
        .utilityBillReview(route: $reviewRoute, service: service, timeZoneIdentifier: timeZoneIdentifier) {
            await viewModel.load()
        }
        .utilityUploadFlow(
            request: $uploadRequest,
            service: service,
            onOpenBill: { id in reviewRoute = UtilityBillRoute(billId: id) },
            onGoToRent: {
                dismiss()
                notificationRouter.selectTab = .payments
            },
            onFinished: { await viewModel.load() }
        )
        .sheet(item: $addMonth) { item in
            UtilityAddMonthSheet(
                propertyId: item.propertyId,
                propertyName: item.propertyName,
                period: item.period,
                currency: viewModel.grid?.baseCurrency ?? "KZT",
                service: service,
                onUpload: { upload in
                    addMonth = nil
                    uploadRequest = UtilityUploadRequest(
                        upload: upload,
                        target: UtilityUploadTarget(propertyId: item.propertyId, period: item.period)
                    )
                },
                onCreated: { id in
                    addMonth = nil
                    Task {
                        await viewModel.load()
                        reviewRoute = UtilityBillRoute(billId: id, payer: item.payer)
                    }
                }
            )
        }
        .accessibilityContainer("utilities.overview")
    }

    // MARK: Deep links

    /// A push opens the bill or the inbox: the route stays in the router until this screen takes it.
    private func handlePendingRoute() {
        guard let route = notificationRouter.pendingRoute else { return }
        switch route.kind {
        case .utilityBill(let billId, _):
            reviewRoute = UtilityBillRoute(billId: billId)
            notificationRouter.clearRoute(route)
        case .utilitiesInbox:
            scrollTarget = "inbox"
            notificationRouter.clearRoute(route)
        default:
            break
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("utilities.overview.loading")
        case .error(let text):
            EmptyStateView(
                title: "Не удалось загрузить коммуналку",
                message: text,
                actionName: "Повторить",
                action: { Task { await viewModel.load() } },
                icon: "wifi.exclamationmark"
            )
        case .loaded:
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        yearBar
                        if let message = viewModel.message {
                            UtilityBanner(text: message, identifier: "utilities.overview.error")
                        }
                        if unreadable {
                            UtilityBanner(text: "Не удалось прочитать файл. Выберите JPEG, PNG, HEIC или PDF.", identifier: "utilities.overview.unreadable")
                        }
                        countersRow
                        inboxSection
                            .id("inbox")
                        matrixSection
                        yearOverYearSection
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.md)
                }
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(AppTheme.Motion.resolved(AppTheme.Motion.slow, reduceMotion: reduceMotion)) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                    scrollTarget = nil
                }
            }
        }
    }

    private var yearBar: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Button { Task { await viewModel.previousYear() } } label: {
                Image(systemName: "chevron.left").frame(width: 32, height: 32)
            }
            .accessibilityLabel("Предыдущий год")
            .accessibilityIdentifier("utilities.overview.year.prev")
            Text(String(viewModel.year))
                .font(.headline)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(AppTheme.Motion.resolved(AppTheme.Motion.fast, reduceMotion: reduceMotion), value: viewModel.year)
                .accessibilityIdentifier("utilities.overview.year")
            Button { Task { await viewModel.nextYear() } } label: {
                Image(systemName: "chevron.right").frame(width: 32, height: 32)
            }
            .disabled(!viewModel.canGoForward)
            .accessibilityLabel("Следующий год")
            .accessibilityIdentifier("utilities.overview.year.next")
            Spacer()
        }
        .tint(AppTheme.Colors.accent)
    }

    // MARK: Counters

    @ViewBuilder
    private var countersRow: some View {
        if let counters = viewModel.counters {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    counterChip(
                        title: "Нет квитанции", count: counters.missing, tone: .danger,
                        isSelected: viewModel.onlyMissing, identifier: "utilities.overview.counter.missing"
                    ) {
                        withAnimation(AppTheme.Motion.resolved(AppTheme.Motion.fast, reduceMotion: reduceMotion)) { viewModel.onlyMissing.toggle() }
                        AppHaptics.selection()
                    }
                    counterChip(
                        title: "Ждут проверки", count: counters.needsReview, tone: .warning,
                        isSelected: false, identifier: "utilities.overview.counter.needs_review"
                    ) { scrollTarget = "inbox" }
                    if counters.otherUploads > 0 {
                        counterChip(
                            title: "Другие файлы", count: counters.otherUploads, tone: .warning,
                            isSelected: false, identifier: "utilities.overview.counter.other"
                        ) { scrollTarget = "inbox" }
                    }
                    if counters.unassigned > 0 {
                        counterChip(
                            title: "Без объекта", count: counters.unassigned, tone: .info,
                            isSelected: false, identifier: "utilities.overview.counter.unassigned"
                        ) { scrollTarget = "inbox" }
                    }
                }
            }
        }
    }

    private func counterChip(
        title: String, count: Int, tone: StatusTone, isSelected: Bool, identifier: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("\(count)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(count)))
                Text(title)
                    .font(.subheadline)
            }
            .foregroundStyle(count > 0 ? tone.color : AppTheme.Colors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background((count > 0 ? tone.color : AppTheme.Colors.textSecondary).opacity(isSelected ? 0.18 : 0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke((count > 0 ? tone.color : AppTheme.Colors.border).opacity(isSelected ? 0.6 : 0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(count)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(identifier)
    }

    // MARK: Inbox

    private var inboxSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                UtilitySectionTitle(text: "Ждут решения", detail: viewModel.inboxRows.isEmpty ? nil : "\(viewModel.inboxRows.count)")
                if viewModel.inboxRows.isEmpty {
                    Text("Всё проверено. Новые квитанции появятся здесь после распознавания.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .accessibilityIdentifier("utilities.overview.inbox.empty")
                } else {
                    ForEach(Array(viewModel.inboxRows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider() }
                        inboxRow(row)
                            .appearStagger(index: index, isVisible: isVisible)
                    }
                }
            }
        }
        .accessibilityContainer("utilities.overview.inbox")
    }

    @ViewBuilder
    private func inboxRow(_ row: UtilityInboxRow) -> some View {
        switch row.kind {
        case .bill(let billId, let propertyId):
            Button {
                reviewRoute = UtilityBillRoute(billId: billId, payer: payer(of: propertyId))
            } label: {
                inboxLabel(row)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("utilities.overview.inbox.bill.\(billId)")
        case .upload(let extractionId, let actions):
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                inboxLabel(row)
                HStack(spacing: AppTheme.Spacing.sm) {
                    if actions.contains(.attachToRent) {
                        Button {
                            dismiss()
                            notificationRouter.selectTab = .payments
                        } label: {
                            Label("К платежам аренды", systemImage: "arrow.right.circle")
                        }
                        .buttonStyle(UtilitySecondaryButtonStyle())
                        .accessibilityIdentifier("utilities.overview.inbox.rent.\(extractionId)")
                    }
                    if actions.contains(.reject) {
                        Button { Task { await viewModel.reject(extractionId: extractionId) } } label: {
                            Label("Отклонить", systemImage: "xmark.circle")
                        }
                        .buttonStyle(UtilitySecondaryButtonStyle(tone: AppTheme.Colors.danger))
                        .disabled(viewModel.isRejecting)
                        .accessibilityIdentifier("utilities.overview.inbox.reject.\(extractionId)")
                    }
                }
            }
        }
    }

    private func inboxLabel(_ row: UtilityInboxRow) -> some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(2)
                Text(row.subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                if let detail = row.detail {
                    Text(detail)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }
            }
            Spacer(minLength: AppTheme.Spacing.sm)
            UtilityStatusLabel(text: row.statusText, tone: row.tone)
            if case .bill = row.kind {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }

    private func payer(of propertyId: String?) -> UtilityPayer? {
        guard let propertyId else { return nil }
        return viewModel.grid?.properties.first(where: { $0.propertyId == propertyId })?.utilityPayer
    }

    // MARK: Matrix

    private var matrixSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                UtilitySectionTitle(
                    text: "Объекты по месяцам",
                    detail: viewModel.onlyMissing ? "Только без квитанции" : nil
                )
                if viewModel.matrixRows.isEmpty {
                    Text(viewModel.onlyMissing ? "Квитанций, которых не хватает, нет." : "Объектов с коммунальными счетами пока нет.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .accessibilityIdentifier("utilities.overview.matrix.empty")
                }
                ForEach(Array(viewModel.matrixRows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider() }
                    matrixRow(row)
                        .appearStagger(index: index, isVisible: isVisible)
                }
                legend
            }
        }
        .accessibilityContainer("utilities.overview.matrix")
    }

    private func matrixRow(_ row: UtilityMatrixRow) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.propertyName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(2)
                    if let account = row.accountText {
                        Text(account)
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
                Spacer(minLength: AppTheme.Spacing.sm)
                Text(row.yearTotalText)
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            HStack(spacing: 3) {
                ForEach(row.cells) { cell in
                    Button {
                        AppHaptics.selection()
                        if let billId = cell.billId {
                            reviewRoute = UtilityBillRoute(billId: billId, payer: row.payer)
                        } else {
                            addMonth = UtilityOverviewAddMonth(
                                propertyId: row.propertyId, propertyName: row.propertyName, period: cell.period, payer: row.payer
                            )
                        }
                    } label: {
                        matrixCell(cell)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(row.propertyName): \(cell.accessibilityText)")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("utilities.overview.cell.\(row.propertyId).\(cell.period)")
                }
            }
        }
    }

    private func matrixCell(_ cell: UtilityMonthCell) -> some View {
        VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(cell.status == nil ? AppTheme.Colors.backgroundSecondary : cell.tone.color.opacity(0.14))
                if cell.status != nil {
                    Image(systemName: cell.tone.systemImage)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(cell.tone.color)
                }
            }
            .frame(height: 26)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(cell.status == nil ? AppTheme.Colors.border : cell.tone.color.opacity(0.3), lineWidth: 1)
            )
            Text(String(UtilityFormat.monthShort(cell.period).prefix(3)))
                .font(.system(size: 9))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var legend: some View {
        let statuses: [UtilityBillStatus] = [.paid, .confirmed, .needsReview, .missing, .expected]
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(statuses, id: \.self) { status in
                HStack(spacing: 6) {
                    Image(systemName: status.tone.systemImage)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(status.tone.color)
                        .frame(width: 14)
                        .accessibilityHidden(true)
                    Text(viewModel.labels.statusLabel(status))
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
        }
    }

    // MARK: Year over year

    @ViewBuilder
    private var yearOverYearSection: some View {
        if let yoy = viewModel.yearOverYear {
            SurfaceCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    UtilitySectionTitle(text: "\(UtilityFormat.year(yoy.year)) к \(UtilityFormat.year(yoy.compareYear))")
                    HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
                        Text(yoy.currentText)
                            .font(.title2.weight(.semibold))
                            .moneyText()
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .accessibilityIdentifier("utilities.overview.yoy.current")
                        if let delta = yoy.deltaText {
                            Text(delta)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(yoy.isIncrease == true ? AppTheme.Colors.warning : AppTheme.Colors.success)
                                .accessibilityIdentifier("utilities.overview.yoy.delta")
                        }
                    }
                    Text("В \(UtilityFormat.year(yoy.compareYear)) году: \(yoy.previousText)")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    ForEach(yoy.lines) { line in
                        yoyLine(line)
                    }
                    if let missing = yoy.missingMonthsText {
                        Text(missing)
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    if let note = yoy.unconvertedText {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.warning)
                    }
                }
            }
            .accessibilityContainer("utilities.overview.yoy")
        }
    }

    private func yoyLine(_ line: UtilityYearOverYear.Line) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(line.title)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Spacer()
                Text(line.currentText)
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                if let delta = line.deltaText {
                    Text(delta)
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: 2) {
                    RoundedRectangle(cornerRadius: 2).fill(AppTheme.Colors.accent)
                        .frame(width: max(2, proxy.size.width * line.currentShare), height: 4)
                    RoundedRectangle(cornerRadius: 2).fill(AppTheme.Colors.border)
                        .frame(width: max(2, proxy.size.width * line.previousShare), height: 4)
                }
            }
            .frame(height: 10)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(line.title): \(line.currentText), в прошлом году \(line.previousText)")
    }
}

struct UtilityOverviewAddMonth: Identifiable {
    let propertyId: String
    let propertyName: String
    let period: String
    let payer: UtilityPayer

    var id: String { "\(propertyId).\(period)" }
}
