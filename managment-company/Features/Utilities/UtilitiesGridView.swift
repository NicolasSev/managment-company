import SwiftUI

/// The «Коммуналка» section of a property: twelve months of one year, a chip of the status per
/// month, the receipts that are missing, and the upload of a document.
struct UtilitiesGridView: View {
    @StateObject private var viewModel: UtilitiesGridViewModel
    private let propertyName: String
    private let service: UtilityBillsService
    private let timeZoneIdentifier: String
    private let onChanged: () async -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var notificationRouter: NotificationDeepLinkRouter
    @State private var reviewRoute: UtilityBillRoute?
    @State private var uploadRequest: UtilityUploadRequest?
    @State private var addMonth: UtilityAddMonth?
    @State private var unreadable = false
    @State private var isVisible = false

    init(
        propertyId: String,
        propertyName: String,
        authManager: AuthManager,
        onChanged: @escaping () async -> Void = {}
    ) {
        let service = UtilityBillsServiceProvider.makeService(authManager: authManager)
        _viewModel = StateObject(wrappedValue: UtilitiesGridViewModel(propertyId: propertyId, service: service))
        self.propertyName = propertyName
        self.service = service
        self.timeZoneIdentifier = authManager.user?.timezone ?? "Asia/Almaty"
        self.onChanged = onChanged
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.sm), count: 3)

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                header
                content
            }
        }
        .accessibilityContainer("utilities.grid")
        .task {
            await viewModel.load()
            withAnimation(AppTheme.Motion.resolved(AppTheme.Motion.normal, reduceMotion: reduceMotion)) { isVisible = true }
        }
        .utilityBillReview(route: $reviewRoute, service: service, timeZoneIdentifier: timeZoneIdentifier) {
            await viewModel.load()
            await onChanged()
        }
        .utilityUploadFlow(
            request: $uploadRequest,
            service: service,
            onOpenBill: { id in reviewRoute = UtilityBillRoute(billId: id, payer: viewModel.payer) },
            onGoToRent: { notificationRouter.selectTab = .payments },
            onFinished: { await viewModel.load() }
        )
        .sheet(item: $addMonth) { month in
            UtilityAddMonthSheet(
                propertyId: viewModel.propertyId,
                propertyName: propertyName,
                period: month.period,
                currency: viewModel.grid?.baseCurrency ?? "KZT",
                service: service,
                onUpload: { upload in
                    addMonth = nil
                    uploadRequest = UtilityUploadRequest(
                        upload: upload,
                        target: UtilityUploadTarget(propertyId: viewModel.propertyId, period: month.period)
                    )
                },
                onCreated: { id in
                    addMonth = nil
                    Task {
                        await viewModel.load()
                        reviewRoute = UtilityBillRoute(billId: id, payer: viewModel.payer)
                    }
                }
            )
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Коммуналка")
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    if let account = viewModel.accountText {
                        Text(account)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .accessibilityIdentifier("utilities.grid.account")
                    } else {
                        Text("Квитанции по месяцам")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
                Spacer(minLength: AppTheme.Spacing.sm)
                UtilityDocumentMenu(
                    identifier: "utilities.grid.upload",
                    onPicked: { upload in
                        uploadRequest = UtilityUploadRequest(upload: upload, target: UtilityUploadTarget(propertyId: viewModel.propertyId))
                    },
                    onUnreadable: { unreadable = true }
                ) {
                    Label("Загрузить", systemImage: "arrow.up.doc")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppTheme.Colors.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            yearSwitcher
            if unreadable {
                UtilityBanner(text: "Не удалось прочитать файл. Выберите JPEG, PNG, HEIC или PDF.", identifier: "utilities.grid.unreadable")
            }
        }
    }

    private var yearSwitcher: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Button { Task { await viewModel.previousYear() } } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Предыдущий год")
            .accessibilityIdentifier("utilities.grid.year.prev")
            Text(String(viewModel.year))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(AppTheme.Motion.resolved(AppTheme.Motion.fast, reduceMotion: reduceMotion), value: viewModel.year)
                .accessibilityIdentifier("utilities.grid.year")
            Button { Task { await viewModel.nextYear() } } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 32, height: 32)
            }
            .disabled(!viewModel.canGoForward)
            .accessibilityLabel("Следующий год")
            .accessibilityIdentifier("utilities.grid.year.next")
            Spacer()
            if let total = viewModel.yearTotalText {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(total)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .accessibilityIdentifier("utilities.grid.year_total")
                    Text("за год")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
        }
        .tint(AppTheme.Colors.accent)
    }

    // MARK: Months

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            LazyVGrid(columns: columns, spacing: AppTheme.Spacing.sm) {
                ForEach(0..<12, id: \.self) { _ in
                    placeholderCell
                }
            }
            .shimmerPlaceholder(true)
            .accessibilityIdentifier("utilities.grid.loading")
        case .error(let message):
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                UtilityBanner(text: message, identifier: "utilities.grid.error")
                Button("Повторить") { Task { await viewModel.load() } }
                    .buttonStyle(UtilitySecondaryButtonStyle())
                    .accessibilityIdentifier("utilities.grid.retry")
            }
        case .loaded:
            if viewModel.isEmptyYear {
                Text("За \(UtilityFormat.year(viewModel.year)) год счетов нет. Загрузите квитанцию или добавьте месяц вручную.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .accessibilityIdentifier("utilities.grid.empty")
            }
            LazyVGrid(columns: columns, spacing: AppTheme.Spacing.sm) {
                ForEach(Array(viewModel.cells.enumerated()), id: \.element.id) { index, cell in
                    Button { open(cell) } label: {
                        monthCell(cell)
                    }
                    .buttonStyle(.plain)
                    .appearStagger(index: index, isVisible: isVisible)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(cell.accessibilityText)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("utilities.grid.month.\(cell.period)")
                }
            }
        }
    }

    private var placeholderCell: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(AppTheme.Colors.backgroundSecondary)
            .frame(height: 84)
    }

    private func monthCell(_ cell: UtilityMonthCell) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(cell.monthName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: cell.status == nil ? "plus" : cell.tone.systemImage)
                    .font(.system(size: 9, weight: .heavy))
                    .accessibilityHidden(true)
                Text(cell.statusText)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(cell.status == nil ? AppTheme.Colors.textTertiary : cell.tone.color)
            if let note = cell.note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if let amount = cell.amountText {
                Text(amount)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .padding(10)
        .background(cell.status.map { _ in cell.tone.color.opacity(0.07) } ?? AppTheme.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(cell.status == nil ? AppTheme.Colors.border : cell.tone.color.opacity(0.2), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func open(_ cell: UtilityMonthCell) {
        AppHaptics.selection()
        if let billId = cell.billId {
            reviewRoute = UtilityBillRoute(billId: billId, payer: viewModel.payer)
        } else {
            addMonth = UtilityAddMonth(period: cell.period)
        }
    }
}

struct UtilityAddMonth: Identifiable {
    let period: String
    var id: String { period }
}

// MARK: - A month without a bill

/// A month nobody has a bill for: upload the receipt for it or type the bill in.
struct UtilityAddMonthSheet: View {
    let propertyId: String
    let propertyName: String
    let period: String
    let currency: String
    let service: UtilityBillsService
    let onUpload: (RecognitionUpload) -> Void
    let onCreated: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var unreadable = false
    @State private var showManual = false
    @State private var amountText = ""
    @State private var provider = ""
    @State private var isSaving = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        SurfaceCard {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                                Text("\(UtilityFormat.periodTitle(period)) · \(propertyName)")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                                UtilityDocumentMenu(
                                    identifier: "utilities.add.upload",
                                    onPicked: onUpload,
                                    onUnreadable: { unreadable = true }
                                ) {
                                    Label("Загрузить квитанцию", systemImage: "arrow.up.doc")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .foregroundStyle(.white)
                                        .background(AppTheme.Colors.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                                Button { showManual.toggle() } label: {
                                    Label("Ввести вручную", systemImage: "pencil")
                                }
                                .buttonStyle(UtilitySecondaryButtonStyle())
                                .accessibilityIdentifier("utilities.add.manual")
                            }
                        }
                        if showManual {
                            SurfaceCard {
                                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                                    UtilitySectionTitle(text: "Счёт вручную")
                                    SettleTextField(
                                        title: "Сумма, \(AppFormatting.currencySymbol(for: currency))",
                                        text: $amountText,
                                        keyboard: .decimalPad,
                                        capitalization: .never,
                                        identifier: "utilities.add.amount"
                                    )
                                    SettleTextField(title: "Поставщик", text: $provider, identifier: "utilities.add.provider")
                                    PrimaryButton(
                                        title: "Создать счёт",
                                        action: { Task { await create() } },
                                        isLoading: isSaving,
                                        isDisabled: Money.parse(amountText, currency: currency) == nil
                                    )
                                    .accessibilityIdentifier("utilities.add.create")
                                }
                            }
                        }
                        if unreadable {
                            UtilityBanner(text: "Не удалось прочитать файл. Выберите JPEG, PNG, HEIC или PDF.", identifier: "utilities.add.unreadable")
                        }
                        if let message {
                            UtilityBanner(text: message, identifier: "utilities.add.error")
                        }
                    }
                    .padding(AppTheme.Spacing.md)
                }
            }
            .navigationTitle(UtilityFormat.periodTitle(period))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                        .accessibilityIdentifier("utilities.add.close")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityContainer("utilities.add")
    }

    private func create() async {
        guard let money = Money.parse(amountText, currency: currency) else { return }
        isSaving = true
        message = nil
        defer { isSaving = false }
        let trimmed = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let bill = try await service.createBill(UtilityBillCreate(
                propertyId: propertyId, period: period, currency: currency,
                providerName: trimmed.isEmpty ? nil : trimmed, total: money.major
            ))
            onCreated(bill.id)
        } catch let error as UtilityBillsError {
            message = error.userMessage
        } catch {
            message = UtilityBillsError.unknown.userMessage
        }
    }
}
