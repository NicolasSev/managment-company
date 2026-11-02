import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// The five step views of the move-in wizard. Each one reads and writes `SettleWizardViewModel`;
// the container (`SettleWizardView`) owns navigation, alerts and the bottom bar.
// Accessibility identifiers: `settle.step.*` (step root), `settle.field.*`, `settle.scan`, ...

private struct SettleStepHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct SettleSectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(AppTheme.Colors.textPrimary)
    }
}

// MARK: - 1. Property

struct SettlePropertyStep: View {
    @ObservedObject var viewModel: SettleWizardViewModel
    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SettleStepHeader(
                title: "Выберите объект",
                subtitle: viewModel.context.locksProperty
                    ? "Объект зафиксирован: новый договор заменяет действующий."
                    : "Договор создаётся для свободного объекта."
            )
            .appearStagger(index: 0, isVisible: isVisible)

            switch viewModel.directoryState {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .accessibilityIdentifier("settle.property.loading")
            case .failed(let message):
                SettleNotice(text: message, tone: .danger, identifier: "settle.property.error")
                Button("Повторить") { Task { await viewModel.loadDirectory() } }
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("settle.property.retry")
            case .loaded:
                list
            }
        }
        .onAppear { isVisible = true }
    }

    /// «Свободно» is good news here, unlike on the property list where the shared badge reads it as a vacancy loss.
    private static func statusTitle(_ status: String) -> String {
        switch status.lowercased() {
        case "vacant": return "Свободно"
        case "occupied": return "Занято"
        case "renovation": return "Ремонт"
        case "for_sale": return "В продаже"
        default: return status
        }
    }

    private static func statusTone(_ status: String) -> StatusTone {
        switch status.lowercased() {
        case "vacant": return .success
        case "occupied": return .neutral
        default: return .warning
        }
    }

    @ViewBuilder
    private var list: some View {
        let properties = viewModel.context.locksProperty
            ? viewModel.properties.filter { $0.id == viewModel.selectedPropertyId }
            : viewModel.selectableProperties
        if properties.isEmpty {
            SurfaceCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text("Свободных объектов нет")
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text("Все объекты заняты или в архиве. Можно показать занятые и создать договор на будущий период.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
            .accessibilityIdentifier("settle.property.empty")
        }
        ForEach(Array(properties.enumerated()), id: \.element.id) { index, property in
            SettleChoiceRow(
                isSelected: viewModel.selectedPropertyId == property.id,
                identifier: "settle.property.\(property.id)",
                action: {
                    guard !viewModel.context.locksProperty else { return }
                    viewModel.selectedPropertyId = property.id
                }
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(property.name)
                            .font(.headline)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Spacer(minLength: 0)
                        StatusBadge(label: Self.statusTitle(property.status), tone: Self.statusTone(property.status))
                    }
                    if let address = property.displayAddress, !address.isEmpty, address != property.name {
                        Text(address)
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
            }
            .appearStagger(index: index + 1, isVisible: isVisible)
        }
        if !viewModel.context.locksProperty, viewModel.hiddenOccupiedCount > 0 {
            Toggle("Показать занятые объекты (\(viewModel.hiddenOccupiedCount))", isOn: $viewModel.showOccupied)
                .font(.subheadline)
                .tint(AppTheme.Colors.accent)
                .accessibilityIdentifier("settle.property.showOccupied")
        }
    }
}

// MARK: - 2. Tenant

struct SettleTenantStep: View {
    @ObservedObject var viewModel: SettleWizardViewModel
    let isCameraAvailable: Bool
    let onScan: () -> Void
    @Binding var photoItem: PhotosPickerItem?
    let onPickFile: () -> Void

    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SettleStepHeader(
                title: "Арендатор",
                subtitle: viewModel.context.locksTenant
                    ? "Арендатор остаётся тем же: договор заменяется новым."
                    : "Сфотографируйте удостоверение или выберите арендатора из списка."
            )
            .appearStagger(index: 0, isVisible: isVisible)

            if viewModel.context.locksTenant {
                lockedTenant
            } else {
                Picker("Арендатор", selection: $viewModel.tenantMode) {
                    ForEach(SettleTenantMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settle.tenant.mode")
                .appearStagger(index: 1, isVisible: isVisible)

                switch viewModel.tenantMode {
                case .new: newTenant
                case .existing: existingTenant
                }
            }
        }
        .onAppear { isVisible = true }
    }

    // MARK: Locked (replacement)

    private var lockedTenant: some View {
        SurfaceCard {
            SettleSummaryRow(
                title: "Арендатор",
                value: viewModel.tenantDisplayName.isEmpty ? "Загружаем..." : viewModel.tenantDisplayName,
                identifier: "settle.tenant.locked"
            )
        }
    }

    // MARK: New

    @ViewBuilder
    private var newTenant: some View {
        recognitionCard
            .appearStagger(index: 2, isVisible: isVisible)
        if !viewModel.reviewReasons.isEmpty {
            reasonsCard
        }
        formCard
            .appearStagger(index: 3, isVisible: isVisible)
    }

    private var recognitionCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                SettleSectionTitle(text: "Удостоверение личности")
                Text("Поля заполнятся по фото. Проверьте их перед тем, как продолжить.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                HStack(spacing: AppTheme.Spacing.sm) {
                    if isCameraAvailable {
                        Button(action: onScan) {
                            SettleSourceButtonLabel(title: "Сканировать", systemImage: "camera.viewfinder")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settle.scan")
                    }
                    PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                        SettleSourceButtonLabel(title: "Из фото", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settle.photos")
                    Button(action: onPickFile) {
                        SettleSourceButtonLabel(title: "Из файлов", systemImage: "folder")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settle.files")
                }
                .disabled(viewModel.recognitionState == .uploading || !viewModel.isOnline)

                recognitionStatus
            }
        }
    }

    @ViewBuilder
    private var recognitionStatus: some View {
        switch viewModel.recognitionState {
        case .idle:
            EmptyView()
        case .uploading:
            HStack(spacing: AppTheme.Spacing.sm) {
                ProgressView()
                Text("Распознаём документ...")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("settle.recognition.loading")
        case .recognized:
            SettleNotice(
                text: recognizedText,
                tone: .success,
                identifier: "settle.recognition.done"
            )
        case .notIdentityDocument:
            EmptyView()
        case .failed(let error):
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                SettleNotice(text: error.userMessage, tone: .danger, identifier: "settle.recognition.error")
                if error.offersManualEntry {
                    Button("Заполнить вручную") { viewModel.continueManually() }
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("settle.recognition.manual")
                }
            }
        }
    }

    private var recognizedText: String {
        if let confidence = viewModel.overallConfidence {
            return "Документ распознан, уверенность \(Int((confidence * 100).rounded()))%. Проверьте поля ниже."
        }
        return "Документ распознан. Проверьте поля ниже."
    }

    private var reasonsCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("На что обратить внимание")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
            ForEach(viewModel.reviewReasons) { reason in
                Label(reason.text, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .labelStyle(SettleReasonLabelStyle())
                    .accessibilityIdentifier("settle.reason.\(reason.id)")
            }
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Colors.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settle.reasons")
    }

    private var formCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                SettleSectionTitle(text: "Данные арендатора")
                Text("Для договора нужны все поля, кроме отчества, телефона и почты.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                if let banner = viewModel.banner {
                    SettleNotice(text: banner, tone: .danger, identifier: "settle.banner")
                }

                textField(.lastName, capitalization: .words)
                textField(.firstName, capitalization: .words)
                textField(.middleName, capitalization: .words)
                textField(.iin, keyboard: .numberPad, capitalization: .never, footnote: viewModel.iinFormatWarning)

                SettleFieldFrame(title: "Тип документа") {
                    Picker("Тип документа", selection: $viewModel.form.documentType) {
                        ForEach(TenantDocumentType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settleInputSurface()
                    .accessibilityIdentifier("settle.field.document_type")
                }

                textField(.documentNumber, capitalization: .characters)
                textField(.documentIssuedBy)
                dateField(.documentIssuedAt)
                dateField(.birthDate)
                textField(.registrationAddress, axis: .vertical)
                textField(.phone, keyboard: .phonePad, capitalization: .never)
                textField(.email, keyboard: .emailAddress, capitalization: .never)
            }
        }
    }

    private func textField(
        _ field: SettleTenantField,
        keyboard: UIKeyboardType = .default,
        capitalization: TextInputAutocapitalization = .sentences,
        footnote: String? = nil,
        axis: Axis = .horizontal
    ) -> some View {
        SettleTextField(
            title: field.title,
            text: Binding(get: { viewModel.form[field] }, set: { viewModel.setValue($0, for: field) }),
            keyboard: keyboard,
            capitalization: capitalization,
            identifier: "settle.field.\(field.rawValue)",
            badge: viewModel.badge(for: field),
            highlighted: viewModel.isHighlighted(field),
            footnote: footnote,
            axis: axis
        )
        .id(field)
    }

    private func dateField(_ field: SettleTenantField) -> some View {
        SettleOptionalDateField(
            title: field.title,
            value: Binding(get: { viewModel.form[field] }, set: { viewModel.setValue($0, for: field) }),
            identifier: "settle.field.\(field.rawValue)",
            badge: viewModel.badge(for: field),
            highlighted: viewModel.isHighlighted(field)
        )
        .id(field)
    }

    // MARK: Existing

    @ViewBuilder
    private var existingTenant: some View {
        SurfaceCard(padding: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .accessibilityHidden(true)
                TextField("Имя, ИИН или телефон", text: $viewModel.tenantQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("settle.tenant.search")
            }
        }
        .appearStagger(index: 2, isVisible: isVisible)

        let tenants = viewModel.filteredTenants
        if tenants.isEmpty {
            SurfaceCard {
                Text(viewModel.tenants.isEmpty ? "У вас пока нет арендаторов. Добавьте нового по фото удостоверения." : "Никого не нашли. Проверьте запрос или добавьте нового арендатора.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .accessibilityIdentifier("settle.tenant.empty")
        }
        ForEach(Array(tenants.enumerated()), id: \.element.id) { index, tenant in
            SettleChoiceRow(
                isSelected: viewModel.selectedTenantId == tenant.id,
                identifier: "settle.tenant.\(tenant.id)",
                action: { viewModel.selectedTenantId = tenant.id }
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    Text([tenant.lastName, tenant.firstName, tenant.middleName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "))
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text([tenant.iin.map { "ИИН \($0)" }, tenant.phone].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
            .appearStagger(index: min(index + 3, AppTheme.Motion.staggerLimit), isVisible: isVisible)
        }
    }
}

private struct SettleReasonLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
            configuration.icon
                .foregroundStyle(AppTheme.Colors.warning)
            configuration.title
        }
    }
}

// MARK: - 3. Terms

struct SettleTermsStep: View {
    @ObservedObject var viewModel: SettleWizardViewModel
    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SettleStepHeader(title: "Условия аренды", subtitle: "Срок, оплата и напоминания.")
                .appearStagger(index: 0, isVisible: isVisible)

            if viewModel.context.replacesLeaseId != nil {
                SettleNotice(
                    text: "Новый договор заменит действующий с даты активации. Дату заезда лучше оставить на начале следующего периода.",
                    tone: .info,
                    identifier: "settle.terms.replace_note"
                )
            }

            periodCard.appearStagger(index: 1, isVisible: isVisible)
            paymentCard.appearStagger(index: 2, isVisible: isVisible)
            otherCard.appearStagger(index: 3, isVisible: isVisible)

            if let error = viewModel.termsError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(viewModel.rentText.isEmpty ? AppTheme.Colors.textSecondary : AppTheme.Colors.danger)
                    .accessibilityIdentifier("settle.terms.error")
            }
        }
        .onAppear { isVisible = true }
    }

    private var periodCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                SettleSectionTitle(text: "Срок")
                DatePicker("Дата заезда", selection: $viewModel.startDate, displayedComponents: .date)
                    .environment(\.locale, AppFormatting.displayLocale)
                    .accessibilityIdentifier("settle.field.start_date")

                Picker("Как задать срок", selection: $viewModel.termMode) {
                    ForEach(SettleTermMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settle.field.term_mode")

                switch viewModel.termMode {
                case .months:
                    SettleTextField(
                        title: "Срок, месяцев",
                        text: $viewModel.termMonthsText,
                        keyboard: .numberPad,
                        capitalization: .never,
                        identifier: "settle.field.term_months"
                    )
                case .endDate:
                    DatePicker(
                        "Дата окончания",
                        selection: $viewModel.endDate,
                        in: viewModel.startDate...,
                        displayedComponents: .date
                    )
                    .environment(\.locale, AppFormatting.displayLocale)
                    .accessibilityIdentifier("settle.field.end_date")
                }
                if let end = viewModel.endDay {
                    SettleSummaryRow(title: "Договор до", value: LeaseDay.display(end), identifier: "settle.terms.end")
                }
            }
        }
    }

    private var paymentCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                SettleSectionTitle(text: "Оплата")
                HStack(alignment: .bottom, spacing: AppTheme.Spacing.sm) {
                    SettleTextField(
                        title: "Аренда в месяц",
                        text: $viewModel.rentText,
                        keyboard: .decimalPad,
                        capitalization: .never,
                        identifier: "settle.field.rent"
                    )
                    Picker("Валюта", selection: $viewModel.currency) {
                        ForEach(SettleTerms.currencies, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .settleInputSurface()
                    .accessibilityIdentifier("settle.field.currency")
                }
                SettleTextField(
                    title: "Депозит",
                    text: Binding(get: { viewModel.depositText }, set: { viewModel.editDeposit($0) }),
                    keyboard: .decimalPad,
                    capitalization: .never,
                    identifier: "settle.field.deposit"
                )
                Stepper(
                    value: Binding(get: { viewModel.dueDay }, set: { viewModel.editDueDay($0) }),
                    in: 1...31
                ) {
                    SettleSummaryRow(title: "День оплаты", value: "\(viewModel.dueDay)-е число")
                }
                .accessibilityIdentifier("settle.field.due_day")
                Stepper(value: $viewModel.remindDays, in: 0...28) {
                    SettleSummaryRow(title: "Напомнить об оплате за", value: "\(viewModel.remindDays) дн.")
                }
                .accessibilityIdentifier("settle.field.remind_days")
            }
        }
    }

    private var otherCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                SettleSectionTitle(text: "Прочее")
                SettleFieldFrame(title: "Коммунальные платит") {
                    Picker("Коммунальные платит", selection: $viewModel.utilitiesPaidBy) {
                        Text("Арендатор").tag(UtilitiesPaidBy.tenant)
                        Text("Владелец").tag(UtilitiesPaidBy.owner)
                        Text("Пополам").tag(UtilitiesPaidBy.split)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settle.field.utilities")
                }
                Stepper(value: $viewModel.renewalReminderDays, in: 0...120, step: 5) {
                    SettleSummaryRow(title: "Напомнить об окончании за", value: "\(viewModel.renewalReminderDays) дн.")
                }
                .accessibilityIdentifier("settle.field.renewal_days")
                SettleTextField(
                    title: "Заметки",
                    text: $viewModel.notes,
                    identifier: "settle.field.notes",
                    axis: .vertical
                )
            }
        }
    }
}

// MARK: - 4. Contract

struct SettleContractStep: View {
    @ObservedObject var viewModel: SettleWizardViewModel
    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SettleStepHeader(title: "Договор", subtitle: "Шаблон и статус подписания.")
                .appearStagger(index: 0, isVisible: isVisible)

            templateCard.appearStagger(index: 1, isVisible: isVisible)
            signingCard.appearStagger(index: 2, isVisible: isVisible)
            summaryCard.appearStagger(index: 3, isVisible: isVisible)

            if let error = viewModel.contractError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.Colors.danger)
                    .accessibilityIdentifier("settle.contract.error")
            }
        }
        .onAppear { isVisible = true }
        .task { await viewModel.loadTemplates() }
    }

    private var templateCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                SettleSectionTitle(text: "Шаблон договора")
                if viewModel.templates.isEmpty {
                    Text("Будет использован шаблон по умолчанию.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .accessibilityIdentifier("settle.contract.template.default")
                } else {
                    Menu {
                        Picker("Шаблон", selection: $viewModel.selectedTemplateId) {
                            ForEach(viewModel.templates) { template in
                                Text(template.isDefault ? "\(template.name) (по умолчанию)" : template.name)
                                    .tag(Optional(template.id))
                            }
                        }
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(viewModel.selectedTemplate?.name ?? "Выберите шаблон")
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: AppTheme.Spacing.sm)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                        }
                        .foregroundStyle(AppTheme.Colors.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .settleInputSurface()
                    }
                    .accessibilityIdentifier("settle.contract.template")
                }
            }
        }
    }

    private var signingCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                SettleSectionTitle(text: "Подписание")
                Toggle("Подписан на бумаге", isOn: $viewModel.signedOnPaper)
                    .tint(AppTheme.Colors.accent)
                    .accessibilityIdentifier("settle.contract.paper")
                if viewModel.signedOnPaper {
                    DatePicker(
                        "Дата подписания",
                        selection: $viewModel.signedOnDate,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .environment(\.locale, AppFormatting.displayLocale)
                    .accessibilityIdentifier("settle.contract.signed_on")
                    Toggle("Активировать с даты заезда", isOn: $viewModel.activateFromStart)
                        .tint(AppTheme.Colors.accent)
                        .accessibilityIdentifier("settle.contract.activate")
                } else {
                    Toggle("Отправить на подпись", isOn: $viewModel.sendForSignature)
                        .tint(AppTheme.Colors.accent)
                        .accessibilityIdentifier("settle.contract.send")
                }
                Text(viewModel.outcomeSummary)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .accessibilityIdentifier("settle.contract.outcome")
            }
        }
    }

    private var summaryCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                SettleSectionTitle(text: "Проверьте перед заселением")
                SettleSummaryRow(title: "Объект", value: viewModel.selectedProperty?.name ?? "-", identifier: "settle.summary.property")
                SettleSummaryRow(title: "Арендатор", value: viewModel.tenantDisplayName.isEmpty ? "-" : viewModel.tenantDisplayName, identifier: "settle.summary.tenant")
                SettleSummaryRow(
                    title: "Срок",
                    value: viewModel.endDay.map { "\(LeaseDay.display(viewModel.startDay)) — \(LeaseDay.display($0))" } ?? LeaseDay.display(viewModel.startDay),
                    identifier: "settle.summary.period"
                )
                SettleSummaryRow(
                    title: "Аренда",
                    value: viewModel.rentAmount.map { AppFormatting.currency(NSDecimalNumber(decimal: $0).doubleValue, currency: viewModel.currency) } ?? "-",
                    identifier: "settle.summary.rent"
                )
                SettleSummaryRow(
                    title: "Депозит",
                    value: viewModel.depositAmount.map { AppFormatting.currency(NSDecimalNumber(decimal: $0).doubleValue, currency: viewModel.currency) } ?? "Нет",
                    identifier: "settle.summary.deposit"
                )
                SettleSummaryRow(title: "День оплаты", value: "\(viewModel.dueDay)-е число", identifier: "settle.summary.due_day")
            }
        }
    }
}

// MARK: - 5. Done

struct SettleDoneStep: View {
    @ObservedObject var viewModel: SettleWizardViewModel
    let onOpenLease: () -> Void
    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            switch viewModel.submitState {
            case .idle, .submitting:
                progress("Создаём договор...", identifier: "settle.done.submitting")
            case .failed(let message):
                failure(message)
            case .settled:
                settled
            }
        }
        .onAppear { isVisible = true }
    }

    private func progress(_ text: String, identifier: String) -> some View {
        SurfaceCard {
            HStack(spacing: AppTheme.Spacing.md) {
                ProgressView()
                Text(text)
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SettleStepHeader(title: "Не получилось заселить")
            SettleNotice(text: message, tone: .danger, identifier: "settle.done.error")
            if viewModel.isOnline {
                PrimaryButton(title: "Повторить", action: { Task { await viewModel.submit() } }, systemImage: "arrow.clockwise")
                    .accessibilityIdentifier("settle.done.retry")
            }
        }
    }

    @ViewBuilder
    private var settled: some View {
        if let lease = viewModel.settleResponse?.lease {
            SurfaceCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(AppTheme.Colors.success)
                            .accessibilityHidden(true)
                        Text(title(for: lease.status))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .accessibilityIdentifier("settle.done.title")
                    }
                    SettleSummaryRow(title: "Объект", value: lease.property.name, identifier: "settle.done.property")
                    SettleSummaryRow(title: "Арендатор", value: lease.tenant.fullName, identifier: "settle.done.tenant")
                    SettleSummaryRow(title: "Срок", value: lease.endDate.map { "\(LeaseDay.display(lease.startDate)) — \(LeaseDay.display($0))" } ?? LeaseDay.display(lease.startDate))
                    SettleSummaryRow(title: "Аренда", value: lease.rentAmount.formatted(), identifier: "settle.done.rent")
                    HStack {
                        Text("Статус")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                        Spacer()
                        LeaseStatusBadge(status: lease.status)
                            .accessibilityIdentifier("settle.done.status")
                    }
                }
            }
            .appearStagger(index: 0, isVisible: isVisible)

            contractCard.appearStagger(index: 1, isVisible: isVisible)

            PrimaryButton(title: "К договору", action: onOpenLease, systemImage: "doc.text")
                .accessibilityIdentifier("settle.done.open")
                .appearStagger(index: 2, isVisible: isVisible)
        }
    }

    @ViewBuilder
    private var contractCard: some View {
        switch viewModel.contractState {
        case .idle, .generating:
            progress("Собираем договор...", identifier: "settle.done.contract.generating")
        case .ready:
            SurfaceCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Label("Документ договора собран", systemImage: "doc.richtext")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .accessibilityIdentifier("settle.done.contract.ready")
                    Button {
                        viewModel.navigationTarget = .contract
                    } label: {
                        Text("Посмотреть и распечатать")
                            .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityIdentifier("settle.done.contract.preview")
                }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                SettleNotice(text: message, tone: .warning, identifier: "settle.done.contract.error")
                Button("Собрать документ ещё раз") { Task { await viewModel.retryContract() } }
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("settle.done.contract.retry")
            }
        }
    }

    private func title(for status: LeaseStatus) -> String {
        switch status {
        case .active: return "Арендатор заселён"
        case .pendingSignature: return "Договор ждёт подписи"
        case .draft: return "Черновик договора создан"
        default: return "Договор создан"
        }
    }
}
