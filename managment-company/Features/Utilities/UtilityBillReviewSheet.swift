import SwiftUI

/// The review of one bill: the header, the hints of the recognition, the document, the lines and the
/// buttons the server offers (`available_actions`). Nothing confirms itself: «Подтвердить» is the owner's.
struct UtilityBillReviewSheet: View {
    @StateObject private var viewModel: UtilityBillReviewViewModel
    private let onChanged: () async -> Void
    private let service: UtilityBillsService

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false
    @State private var showViewer = false
    @State private var uploadRequest: UtilityUploadRequest?
    @State private var unreadable = false

    init(
        billId: String,
        service: UtilityBillsService,
        payer: UtilityPayer? = nil,
        meta: UtilityMeta? = nil,
        timeZoneIdentifier: String = "Asia/Almaty",
        onChanged: @escaping () async -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: UtilityBillReviewViewModel(
            billId: billId, service: service, payer: payer, meta: meta, timeZoneIdentifier: timeZoneIdentifier
        ))
        self.onChanged = onChanged
        self.service = service
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground()
                content
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if viewModel.bill != nil { actionBar }
            }
        }
        .task {
            await viewModel.load()
            withAnimation(AppTheme.Motion.resolved(AppTheme.Motion.normal, reduceMotion: reduceMotion)) { isVisible = true }
        }
        .sensoryFeedback(.success, trigger: viewModel.successSignal)
        .sensoryFeedback(.error, trigger: viewModel.errorSignal)
        .onChange(of: viewModel.wasDeleted) { _, deleted in
            guard deleted else { return }
            Task {
                await onChanged()
                dismiss()
            }
        }
        .sheet(item: promptBinding) { prompt in
            promptSheet(prompt)
        }
        // «Загрузить квитанцию» of an expected or missing bill: the file lands on this bill.
        .utilityUploadFlow(
            request: $uploadRequest,
            service: service,
            onOpenBill: { _ in Task { await viewModel.reload() } },
            onFinished: { await viewModel.reload() }
        )
        .confirmationDialog("Удалить счёт?", isPresented: dialogBinding(.confirmDelete), titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { Task { await viewModel.delete() } }
            Button("Отмена", role: .cancel) { viewModel.prompt = nil }
        } message: {
            Text("Счёт и его строки будут удалены. Файлы освободятся.")
        }
        .confirmationDialog("Снять отметку об оплате?", isPresented: dialogBinding(.confirmUnmark), titleVisibility: .visible) {
            Button("Снять отметку") { Task { await viewModel.unmarkPaid() } }
            Button("Отмена", role: .cancel) { viewModel.prompt = nil }
        } message: {
            Text("Напоминания о квитанции за этот месяц возобновятся.")
        }
        .sheet(isPresented: $showViewer) {
            if let file = viewModel.bill?.primaryFile {
                NavigationStack {
                    UtilityFilePreview(file: file, height: 640)
                        .padding(AppTheme.Spacing.md)
                        .navigationTitle(file.originalName ?? "Документ")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Готово") { showViewer = false }
                            }
                        }
                }
            }
        }
        .accessibilityContainer("utilities.review")
    }

    // MARK: Title and toolbar

    private var title: String {
        guard let bill = viewModel.bill else { return "Счёт" }
        return UtilityFormat.periodTitle(bill.period)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(viewModel.isEditing ? "Отмена" : "Закрыть") {
                if viewModel.isEditing {
                    viewModel.cancelEditing()
                } else {
                    finish()
                }
            }
            .accessibilityIdentifier("utilities.review.close")
        }
        if viewModel.bill != nil, !viewModel.isEditing {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if viewModel.offers.canEdit {
                        Button { viewModel.startEditing() } label: { Label("Изменить", systemImage: "pencil") }
                            .accessibilityIdentifier("utilities.review.edit")
                    }
                    if viewModel.offers.canReextract {
                        Button { Task { await viewModel.reextract() } } label: { Label("Распознать заново", systemImage: "arrow.clockwise") }
                            .accessibilityIdentifier("utilities.review.reextract")
                    }
                    if viewModel.offers.canDelete {
                        Button(role: .destructive) { viewModel.prompt = .confirmDelete } label: { Label("Удалить", systemImage: "trash") }
                            .accessibilityIdentifier("utilities.review.delete")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Действия")
                .accessibilityIdentifier("utilities.review.menu")
                .disabled(!(viewModel.offers.canEdit || viewModel.offers.canReextract || viewModel.offers.canDelete))
            }
        }
    }

    private func finish() {
        Task {
            if viewModel.didChange { await onChanged() }
            dismiss()
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("utilities.review.loading")
        case .error(let text):
            EmptyStateView(
                title: "Не удалось открыть счёт",
                message: text,
                actionName: "Повторить",
                action: { Task { await viewModel.load() } },
                icon: "wifi.exclamationmark"
            )
        case .loaded:
            if let bill = viewModel.bill {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        headerCard(bill)
                            .appearStagger(index: 0, isVisible: isVisible)
                        if viewModel.isRereading {
                            UtilityBanner(text: "Распознаём заново, это займёт до полуминуты.", tone: .info, identifier: "utilities.review.rereading")
                        }
                        if let draft = viewModel.draft {
                            editHeaderCard(draft)
                            editLinesCard(draft)
                        } else {
                            if bill.status == .needsReview || !viewModel.reasonTexts.isEmpty {
                                hintsCard(bill)
                                    .appearStagger(index: 1, isVisible: isVisible)
                            }
                            if let file = bill.primaryFile {
                                documentCard(file, bill: bill)
                                    .appearStagger(index: 2, isVisible: isVisible)
                            }
                            linesCard(bill)
                                .appearStagger(index: 3, isVisible: isVisible)
                            if let notes = bill.notes, !notes.isEmpty {
                                notesCard(notes)
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.top, AppTheme.Spacing.md)
                    .padding(.bottom, AppTheme.Spacing.lg)
                }
            }
        }
    }

    // MARK: Header

    private func headerCard(_ bill: UtilityBill) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(bill.propertyName ?? "Объект не определён")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(bill.propertyId == nil ? AppTheme.Colors.warning : AppTheme.Colors.textSecondary)
                        .lineLimit(2)
                        .accessibilityIdentifier("utilities.review.property")
                    Spacer(minLength: AppTheme.Spacing.sm)
                    UtilityStatusLabel(
                        text: viewModel.labels.statusLabel(bill.status),
                        tone: bill.status.tone,
                        identifier: "utilities.review.status"
                    )
                    .symbolEffect(.bounce, value: viewModel.successSignal)
                }

                Text(UtilityFormat.money(bill.total, currency: bill.currency, alwaysFraction: bill.total != nil))
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .moneyText(value: bill.total.map { NSDecimalNumber(decimal: $0).doubleValue })
                    .animation(AppTheme.Motion.resolved(AppTheme.Motion.normal, reduceMotion: reduceMotion), value: bill.total)
                    .accessibilityIdentifier("utilities.review.total")

                VStack(alignment: .leading, spacing: 6) {
                    if let provider = bill.providerName, !provider.isEmpty {
                        SettleSummaryRow(title: "Поставщик", value: provider, identifier: "utilities.review.provider")
                    }
                    if let account = bill.accountNumber, !account.isEmpty {
                        SettleSummaryRow(title: "Лицевой счёт", value: account, identifier: "utilities.review.account")
                    }
                    if let issued = UtilityFormat.day(bill.issuedAt) {
                        SettleSummaryRow(title: "Дата квитанции", value: issued)
                    }
                    paymentRows(bill)
                    if let confidence = viewModel.confidenceText {
                        SettleSummaryRow(title: "Уверенность распознавания", value: confidence, identifier: "utilities.review.confidence")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func paymentRows(_ bill: UtilityBill) -> some View {
        if bill.status == .paid, let paidAt = UtilityFormat.day(bill.paidAt) {
            SettleSummaryRow(
                title: "Оплачено",
                value: bill.noReceipt ? "\(paidAt), без квитанции" : paidAt,
                identifier: "utilities.review.paid_at"
            )
            if let payer = bill.paidBy {
                SettleSummaryRow(title: "Платил", value: viewModel.labels.payerLabel(payer))
            }
        } else if viewModel.confirmPaysImmediately, let paidAt = UtilityFormat.day(bill.paidAt) {
            SettleSummaryRow(title: "В квитанции оплата", value: paidAt, identifier: "utilities.review.paid_on_confirm")
        }
    }

    // MARK: Hints, document, lines

    private func hintsCard(_ bill: UtilityBill) -> some View {
        let reasons = viewModel.reasonTexts
        return SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                UtilitySectionTitle(text: "Проверьте")
                if reasons.isEmpty {
                    // The empty list is not a confirmation: the owner still reads the lines.
                    Text(bill.status == .needsReview ? "Проверок не найдено. Сверьте строки с документом." : "Замечаний нет.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .accessibilityIdentifier("utilities.review.reasons.empty")
                } else {
                    ForEach(Array(reasons.enumerated()), id: \.offset) { index, text in
                        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(AppTheme.Colors.warning)
                                .accessibilityHidden(true)
                            Text(text)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("utilities.review.reason.\(index)")
                    }
                }
            }
        }
        .accessibilityContainer("utilities.review.reasons")
    }

    private func documentCard(_ file: UtilityBillFile, bill: UtilityBill) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                UtilitySectionTitle(text: "Документ", detail: bill.files.count > 1 ? "Файлов: \(bill.files.count)" : nil)
                Button { showViewer = true } label: {
                    UtilityFilePreview(file: file, height: 220)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("utilities.review.document")
                .accessibilityHint("Открыть документ на весь экран")
            }
        }
    }

    private func linesCard(_ bill: UtilityBill) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                UtilitySectionTitle(text: "Строки", detail: bill.items.isEmpty ? nil : "\(bill.items.count)")
                if bill.items.isEmpty {
                    Text("Строк пока нет. Добавьте их вручную или загрузите квитанцию.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .accessibilityIdentifier("utilities.review.lines.empty")
                } else {
                    ForEach(Array(bill.items.sorted { $0.position < $1.position }.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider() }
                        lineRow(item, currency: bill.currency)
                    }
                }
            }
        }
        .accessibilityContainer("utilities.review.lines")
    }

    private func lineRow(_ item: UtilityBillItem, currency: String?) -> some View {
        let name = viewModel.labels.serviceLabel(item.serviceType)
        var details: [String] = []
        if let raw = item.labelRaw, !raw.isEmpty, raw.caseInsensitiveCompare(name) != .orderedSame { details.append(raw) }
        if let consumption = item.consumption {
            details.append("Расход \(UtilityFormat.editableText(consumption))" + (item.unit.map { " \($0)" } ?? ""))
        }
        if let tariff = item.tariff { details.append("Тариф \(UtilityFormat.editableText(tariff))") }
        if let prev = item.readingPrev, let curr = item.readingCurr {
            details.append("Показания \(UtilityFormat.editableText(prev)) → \(UtilityFormat.editableText(curr))")
        }
        return HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
            Spacer(minLength: AppTheme.Spacing.sm)
            Text(UtilityFormat.money(item.amount, currency: currency, alwaysFraction: true))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("utilities.review.line.\(item.serviceType)")
    }

    private func notesCard(_ notes: String) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                UtilitySectionTitle(text: "Заметка")
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
        }
    }

    // MARK: Editing

    private func editHeaderCard(_ draft: UtilityBillDraft) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                UtilitySectionTitle(text: "Данные счёта")
                SettleTextField(
                    title: "Поставщик",
                    text: draftBinding(\.providerName),
                    placeholder: "АлСеКо",
                    identifier: "utilities.edit.provider"
                )
                SettleTextField(
                    title: "Лицевой счёт",
                    text: draftBinding(\.accountNumber),
                    keyboard: .asciiCapable,
                    capitalization: .never,
                    identifier: "utilities.edit.account"
                )
                periodField(draft)
                SettleFieldFrame(title: "Валюта", identifier: "utilities.edit.currency") {
                    Picker("Валюта", selection: draftBinding(\.currency)) {
                        ForEach(viewModel.labels.currencies, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("utilities.edit.currency")
                }
                SettleOptionalDateField(title: "Дата квитанции", value: draftBinding(\.issuedAt), identifier: "utilities.edit.issued_at")
                SettleTextField(
                    title: "Заметка",
                    text: draftBinding(\.notes),
                    identifier: "utilities.edit.notes",
                    axis: .vertical
                )
            }
        }
    }

    private func periodField(_ draft: UtilityBillDraft) -> some View {
        let parts = UtilityFormat.components(ofPeriod: draft.period) ?? (year: 2026, month: 1)
        let years = Array(2015...(parts.year + 1))
        return SettleFieldFrame(title: "Месяц", note: draft.errors["period"], noteTone: .danger, identifier: "utilities.edit.period") {
            HStack(spacing: AppTheme.Spacing.sm) {
                Picker("Месяц", selection: Binding(
                    get: { parts.month },
                    set: { viewModel.draft?.period = UtilityFormat.periodKey(year: parts.year, month: $0) }
                )) {
                    ForEach(1...12, id: \.self) { month in
                        Text(UtilityFormat.monthName(UtilityFormat.periodKey(year: 2000, month: month))).tag(month)
                    }
                }
                .accessibilityIdentifier("utilities.edit.period.month")
                Picker("Год", selection: Binding(
                    get: { parts.year },
                    set: { viewModel.draft?.period = UtilityFormat.periodKey(year: $0, month: parts.month) }
                )) {
                    ForEach(years, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .accessibilityIdentifier("utilities.edit.period.year")
                Spacer()
            }
            .settleInputSurface()
        }
    }

    private func editLinesCard(_ draft: UtilityBillDraft) -> some View {
        let errors = draft.errors
        return SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                UtilitySectionTitle(text: "Строки")
                ForEach(Array(draft.lines.enumerated()), id: \.element.id) { index, line in
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        HStack {
                            Picker("Услуга", selection: lineBinding(index, \.serviceType)) {
                                ForEach(serviceOptions(including: line.serviceType), id: \.self) { code in
                                    Text(viewModel.labels.serviceLabel(code)).tag(code)
                                }
                            }
                            .labelsHidden()
                            .accessibilityIdentifier("utilities.edit.line.\(index).service")
                            Spacer()
                            Button(role: .destructive) {
                                viewModel.draft?.removeLine(at: index)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Удалить строку")
                            .accessibilityIdentifier("utilities.edit.line.\(index).remove")
                        }
                        SettleTextField(
                            title: "Сумма",
                            text: lineBinding(index, \.amountText),
                            keyboard: .decimalPad,
                            capitalization: .never,
                            identifier: "utilities.edit.line.\(index).amount",
                            highlighted: errors["lines.\(index).amount"] != nil,
                            footnote: errors["lines.\(index).amount"]
                        )
                        SettleTextField(
                            title: "Как в квитанции",
                            text: lineBinding(index, \.labelRaw),
                            identifier: "utilities.edit.line.\(index).label"
                        )
                    }
                    if index < draft.lines.count - 1 { Divider() }
                }
                Button { viewModel.addLine() } label: {
                    Label("Добавить строку", systemImage: "plus")
                }
                .buttonStyle(UtilitySecondaryButtonStyle())
                .disabled(draft.lines.count >= (viewModel.meta?.limits.maxItems ?? 60))
                .accessibilityIdentifier("utilities.edit.add_line")
            }
        }
    }

    private func serviceOptions(including code: String) -> [String] {
        let all = viewModel.labels.serviceCodes
        return all.contains(code) || code.isEmpty ? all : all + [code]
    }

    private func draftBinding(_ keyPath: WritableKeyPath<UtilityBillDraft, String>) -> Binding<String> {
        Binding(
            get: { viewModel.draft?[keyPath: keyPath] ?? "" },
            set: { viewModel.draft?[keyPath: keyPath] = $0 }
        )
    }

    private func lineBinding(_ index: Int, _ keyPath: WritableKeyPath<UtilityBillDraft.Line, String>) -> Binding<String> {
        Binding(
            get: { viewModel.draft?.lines[safe: index]?[keyPath: keyPath] ?? "" },
            set: {
                guard viewModel.draft?.lines.indices.contains(index) == true else { return }
                viewModel.draft?.lines[index][keyPath: keyPath] = $0
            }
        )
    }

    // MARK: Action bar

    private var actionBar: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            if let message = viewModel.message {
                UtilityBanner(text: message, tone: .danger, identifier: "utilities.review.error")
            }
            if viewModel.isEditing {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Button("Отмена") { viewModel.cancelEditing() }
                        .buttonStyle(UtilitySecondaryButtonStyle(tone: AppTheme.Colors.textSecondary))
                        .accessibilityIdentifier("utilities.edit.cancel")
                    PrimaryButton(
                        title: "Сохранить",
                        action: { Task { await viewModel.saveEdits() } },
                        isLoading: viewModel.isBusy,
                        isDisabled: !(viewModel.draft?.isValid ?? false)
                    )
                    .accessibilityIdentifier("utilities.edit.save")
                }
            } else {
                viewActions
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppTheme.Colors.background)
        .overlay(alignment: .top) {
            Rectangle().fill(AppTheme.Colors.border).frame(height: 1)
        }
    }

    @ViewBuilder
    private var viewActions: some View {
        let offers = viewModel.offers
        if offers.canUploadReceipt, let bill = viewModel.bill {
            UtilityDocumentMenu(
                identifier: "utilities.review.upload",
                onPicked: { upload in
                    uploadRequest = UtilityUploadRequest(
                        upload: upload,
                        target: UtilityUploadTarget(propertyId: bill.propertyId, period: bill.period, billId: bill.id)
                    )
                },
                onUnreadable: { unreadable = true }
            ) {
                Label("Загрузить квитанцию", systemImage: "arrow.up.doc")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(AppTheme.Colors.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(viewModel.isBusy)
            if unreadable {
                UtilityBanner(text: "Не удалось прочитать файл. Выберите JPEG, PNG, HEIC или PDF.", identifier: "utilities.review.unreadable")
            }
        }
        if offers.canConfirm {
            if viewModel.confirmPaysImmediately {
                Text("В документе есть дата оплаты: после подтверждения счёт станет оплаченным.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("utilities.review.pays_note")
            }
            PrimaryButton(
                title: "Подтвердить",
                action: { Task { await viewModel.confirm() } },
                isLoading: viewModel.isBusy,
                systemImage: "checkmark"
            )
            .accessibilityIdentifier("utilities.review.confirm")
        }
        HStack(spacing: AppTheme.Spacing.sm) {
            if offers.canMarkPaid {
                Button { viewModel.prompt = .markPaid } label: {
                    Label("Оплачено", systemImage: "banknote")
                }
                .buttonStyle(UtilitySecondaryButtonStyle())
                .disabled(viewModel.isBusy)
                .accessibilityIdentifier("utilities.review.mark_paid")
            }
            if offers.canUnmarkPaid {
                Button { viewModel.prompt = .confirmUnmark } label: {
                    Label("Снять отметку", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(UtilitySecondaryButtonStyle())
                .disabled(viewModel.isBusy)
                .accessibilityIdentifier("utilities.review.unmark_paid")
            }
            if offers.canForward {
                Button { Task { await viewModel.forwardToTenant() } } label: {
                    Label("Переслать арендатору", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(UtilitySecondaryButtonStyle())
                .disabled(viewModel.isBusy)
                .accessibilityIdentifier("utilities.review.forward")
            }
        }
    }

    // MARK: Prompts

    private var promptBinding: Binding<UtilityReviewPrompt?> {
        Binding(
            get: {
                switch viewModel.prompt {
                case .markPaid, .tenantMessage, .ownerPays: return viewModel.prompt
                default: return nil
                }
            },
            set: { if $0 == nil { viewModel.prompt = nil } }
        )
    }

    private func dialogBinding(_ prompt: UtilityReviewPrompt) -> Binding<Bool> {
        Binding(
            get: { viewModel.prompt == prompt },
            set: { if !$0, viewModel.prompt == prompt { viewModel.prompt = nil } }
        )
    }

    @ViewBuilder
    private func promptSheet(_ prompt: UtilityReviewPrompt) -> some View {
        switch prompt {
        case .markPaid:
            UtilityMarkPaidSheet(viewModel: viewModel)
        case .tenantMessage(let message):
            UtilityTenantMessageSheet(message: message)
        case .ownerPays:
            UtilityOwnerPaysSheet()
        case .confirmDelete, .confirmUnmark:
            EmptyView()
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Mark paid

/// «Оплачено»: the day of the payment and the proof, or «без квитанции».
struct UtilityMarkPaidSheet: View {
    @ObservedObject var viewModel: UtilityBillReviewViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var day = Date()
    @State private var unreadable = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        SurfaceCard {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                                UtilitySectionTitle(text: "Дата оплаты")
                                DatePicker("Дата оплаты", selection: $day, in: ...Date(), displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                    .environment(\.locale, AppFormatting.displayLocale)
                                    .accessibilityIdentifier("utilities.mark_paid.date")
                            }
                        }
                        SurfaceCard {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                                UtilitySectionTitle(text: "Подтверждение")
                                if viewModel.offers.allowsPaymentProof {
                                    Text("Приложите чек или квитанцию об оплате. Файл сохранится в счёте.")
                                        .font(.footnote)
                                        .foregroundStyle(AppTheme.Colors.textSecondary)
                                    UtilityDocumentMenu(
                                        identifier: "utilities.mark_paid.proof",
                                        onPicked: { proof in
                                            Task { await viewModel.markPaid(proof: proof, on: dayKey) }
                                        },
                                        onUnreadable: { unreadable = true }
                                    ) {
                                        Label("Приложить подтверждение", systemImage: "paperclip")
                                            .font(.subheadline.weight(.semibold))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .foregroundStyle(.white)
                                            .background(AppTheme.Colors.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    }
                                    .disabled(viewModel.isBusy)
                                } else {
                                    Text("Квитанции ещё нет. Отметьте оплату без квитанции: напоминания остановятся.")
                                        .font(.footnote)
                                        .foregroundStyle(AppTheme.Colors.textSecondary)
                                }
                                Button { Task { await viewModel.markPaidWithoutReceipt(on: dayKey) } } label: {
                                    Label("Оплачено без квитанции", systemImage: "checkmark.circle")
                                }
                                .buttonStyle(UtilitySecondaryButtonStyle())
                                .disabled(viewModel.isBusy)
                                .accessibilityIdentifier("utilities.mark_paid.no_receipt")
                            }
                        }
                        if unreadable {
                            UtilityBanner(text: "Не удалось прочитать файл. Выберите JPEG, PNG, HEIC или PDF.", identifier: "utilities.mark_paid.unreadable")
                        }
                        if let message = viewModel.message {
                            UtilityBanner(text: message, identifier: "utilities.mark_paid.error")
                        }
                        if viewModel.isBusy {
                            HStack(spacing: AppTheme.Spacing.sm) {
                                ProgressView()
                                Text("Отмечаем оплату…")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                            }
                        }
                    }
                    .padding(AppTheme.Spacing.md)
                }
            }
            .navigationTitle("Оплачено")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .accessibilityIdentifier("utilities.mark_paid.cancel")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityContainer("utilities.mark_paid")
    }

    private var dayKey: String {
        UtilityFormat.localDayKey(day)
    }
}

// MARK: - Tenant message

/// «Переслать арендатору»: the text of the server and the share sheet.
struct UtilityTenantMessageSheet: View {
    let message: UtilityTenantMessage
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        SurfaceCard {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                                UtilitySectionTitle(text: "Сообщение")
                                Text(message.text)
                                    .font(.body)
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                    .textSelection(.enabled)
                                    .accessibilityIdentifier("utilities.tenant_message.text")
                            }
                        }
                        ShareLink(item: message.text, subject: Text("Квитанция за \(UtilityFormat.periodTitle(message.period).lowercased())")) {
                            Label("Поделиться", systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(.white)
                                .background(AppTheme.Colors.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .accessibilityIdentifier("utilities.tenant_message.share")
                        Button {
                            UIPasteboard.general.string = message.text
                            copied = true
                        } label: {
                            Label(copied ? "Скопировано" : "Скопировать", systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(UtilitySecondaryButtonStyle())
                        .accessibilityIdentifier("utilities.tenant_message.copy")
                    }
                    .padding(AppTheme.Spacing.md)
                }
            }
            .navigationTitle("Арендатору")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                        .accessibilityIdentifier("utilities.tenant_message.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityContainer("utilities.tenant_message")
    }
}

/// The server answered that the owner pays the utilities: there is nobody to ask for a receipt.
struct UtilityOwnerPaysSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 40))
                    .foregroundStyle(AppTheme.Colors.textTertiary)
                    .accessibilityHidden(true)
                Text("Коммуналку платит владелец")
                    .font(.headline)
                Text("Пересылать арендатору нечего. Если это не так, измените плательщика в карточке объекта.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(AppTheme.Spacing.lg)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.fraction(0.35)])
        .accessibilityContainer("utilities.owner_pays")
    }
}
