import SwiftUI

/// Contract of a lease for printing (GAP-055): PDF preview, template and date, the hand-over act,
/// print, share/save, DOCX and "save to the lease files".
///
/// Opened from the action block of `LeaseDetailView`. Accessibility identifiers: `contract.*`.
struct ContractDocumentView: View {
    let context: ContractLeaseContext
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        ContractDocumentContent(
            context: context,
            service: ContractServiceProvider.makeService(authManager: authManager)
        )
    }
}

struct ContractDocumentContent: View {
    @StateObject private var viewModel: ContractDocumentViewModel
    @EnvironmentObject private var authManager: AuthManager
    @State private var showAct = false

    init(context: ContractLeaseContext, service: ContractService) {
        _viewModel = StateObject(wrappedValue: ContractDocumentViewModel(context: context, service: service))
    }

    var body: some View {
        ZStack {
            AppScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    if let notice = viewModel.notice { noticeView(notice) }
                    previewCard
                    actionsCard
                    savedCard
                    optionsCard
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.lg)
            }
        }
        .navigationTitle("Договор для печати")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("contract.screen")
        .task { await viewModel.start() }
        .onChange(of: viewModel.selectedTemplateId) { _, _ in Task { await viewModel.refreshPreview() } }
        .onChange(of: viewModel.useCustomDate) { _, _ in Task { await viewModel.refreshPreview() } }
        .sheet(item: $viewModel.sharedFile) { file in
            ContractActivityView(url: file.url)
                .presentationDetents([.medium, .large])
                .accessibilityIdentifier("contract.docx.share_sheet")
        }
        .sheet(item: $viewModel.activeFix, onDismiss: { Task { await viewModel.refreshPreview() } }) { target in
            ContractFixSheet(target: target)
                .environmentObject(authManager)
        }
    }

    // MARK: Preview

    private var previewCard: some View {
        SurfaceCard(padding: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                previewBody
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("contract.preview")
    }

    @ViewBuilder
    private var previewBody: some View {
        switch viewModel.previewState {
        case .idle, .loading:
            VStack(spacing: AppTheme.Spacing.sm) {
                ProgressView()
                Text("Готовим договор...")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 280)
            .accessibilityIdentifier("contract.preview.loading")
        case .loaded(let pageCount):
            if let data = viewModel.pdfData {
                ContractPDFView(data: data)
                    .frame(height: 460)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityIdentifier("contract.preview.pdf")
            }
            Text("Страниц: \(pageCount)")
                .font(.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .accessibilityIdentifier("contract.preview.pages")
        case .incomplete(let fields):
            missingFieldsView(fields)
        case .docxOnly:
            infoBlock(
                icon: "doc.richtext",
                title: "PDF недоступен",
                message: "На сервере не настроена конвертация в PDF. Скачайте договор в DOCX, откройте в Word или Pages и распечатайте оттуда.",
                identifier: "contract.preview.docx_only"
            )
        case .error(let message):
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.danger)
                    .accessibilityIdentifier("contract.preview.error")
                Button("Повторить") { Task { await viewModel.refreshPreview() } }
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("contract.preview.retry")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Missing fields (422 CONTRACT_DATA_INCOMPLETE)

    private func missingFieldsView(_ fields: [ContractMissingField]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Label("В договоре не хватает данных", systemImage: "exclamationmark.circle")
                .font(.headline)
                .foregroundStyle(AppTheme.Colors.warning)
                .accessibilityIdentifier("contract.missing.title")
            Text("Заполните отмеченные поля, и договор соберётся.")
                .font(.footnote)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            ForEach(viewModel.missingGroups(fields)) { group in
                missingGroupView(group)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("contract.missing")
    }

    /// One block per place where the values are fixed: the messages, then one button.
    private func missingGroupView(_ group: ContractMissingGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(group.entity.title, systemImage: group.entity.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
            ForEach(Array(group.fields.enumerated()), id: \.offset) { _, field in
                Label {
                    Text(field.message)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(AppTheme.Colors.warning)
                }
                .accessibilityIdentifier("contract.missing.\(field.entity.rawValue).\(field.field)")
            }
            if let target = group.target {
                Button {
                    viewModel.activeFix = target
                } label: {
                    Label(fixTitle(target), systemImage: "pencil")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityIdentifier("contract.missing.fix.\(group.entity.rawValue)")
            } else {
                Text("Измените условия договора на экране договора.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Colors.warning.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("contract.missing.group.\(group.entity.rawValue)")
    }

    private func fixTitle(_ target: ContractFixTarget) -> String {
        switch target {
        case .landlordProfile: return "Открыть профиль арендодателя"
        case .property: return "Открыть объект"
        case .tenant: return "Открыть арендатора"
        }
    }

    // MARK: Actions

    private var actionsCard: some View {
        LeaseSectionCard(title: "Действия", identifier: "contract.actions") {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: AppTheme.Spacing.sm), GridItem(.flexible(), spacing: AppTheme.Spacing.sm)],
                spacing: AppTheme.Spacing.sm
            ) {
                if viewModel.isPDFAvailable {
                    Button { viewModel.printContract() } label: {
                        ContractActionLabel(title: "Печать", systemImage: "printer")
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.canPrintOrShare)
                    .accessibilityIdentifier("contract.action.print")

                    shareControl
                }

                Button { Task { await viewModel.prepareDocx() } } label: {
                    ContractActionLabel(title: "DOCX", systemImage: "doc.richtext", isBusy: viewModel.isFetchingDocx)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isFetchingDocx)
                .accessibilityIdentifier("contract.action.docx")

                Button { Task { await viewModel.saveToLease() } } label: {
                    ContractActionLabel(
                        title: "В файлы договора",
                        systemImage: "tray.and.arrow.down",
                        isBusy: viewModel.saveState == .saving
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.saveState == .saving)
                .accessibilityIdentifier("contract.action.save")
            }
        }
    }

    @ViewBuilder
    private var shareControl: some View {
        if let file = viewModel.pdfFile, viewModel.canPrintOrShare {
            ShareLink(item: file.url, preview: SharePreview(file.url.lastPathComponent)) {
                ContractActionLabel(title: "Поделиться", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("contract.action.share")
        } else {
            ContractActionLabel(title: "Поделиться", systemImage: "square.and.arrow.up")
                .opacity(0.4)
                .accessibilityIdentifier("contract.action.share")
        }
    }

    // MARK: Saved files

    @ViewBuilder
    private var savedCard: some View {
        switch viewModel.saveState {
        case .idle, .saving:
            EmptyView()
        case .saved(let files):
            LeaseSectionCard(title: "Договор сохранён", identifier: "contract.saved") {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text("Файлы добавлены в документы договора.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    ForEach(files) { file in
                        HStack(spacing: AppTheme.Spacing.sm) {
                            Image(systemName: file.fileType == .pdf ? "doc.text" : "doc.richtext")
                                .foregroundStyle(AppTheme.Colors.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.filename)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                    .lineLimit(2)
                                Text(ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file))
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                            }
                            Spacer()
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("contract.saved.file.\(file.id)")
                    }
                }
            }
        case .error(let message):
            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppTheme.Colors.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppTheme.Spacing.md)
                .background(AppTheme.Colors.danger.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityIdentifier("contract.saved.error")
        }
    }

    // MARK: Options

    private var optionsCard: some View {
        LeaseSectionCard(title: "Параметры", identifier: "contract.options") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                templatePicker

                Toggle("Указать дату договора", isOn: $viewModel.useCustomDate)
                    .font(.subheadline)
                    .accessibilityIdentifier("contract.date.toggle")
                if viewModel.useCustomDate {
                    DatePicker("Дата договора", selection: $viewModel.contractDate, displayedComponents: .date)
                        .font(.subheadline)
                        .environment(\.locale, Locale(identifier: "ru_RU"))
                        .accessibilityIdentifier("contract.date.picker")
                        .onChange(of: viewModel.contractDate) { _, _ in
                            Task { await viewModel.refreshPreview() }
                        }
                } else {
                    Text("Без даты: берётся дата подписания, иначе начало аренды.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }

                DisclosureGroup("Акт приёма-передачи (по желанию)", isExpanded: $showAct) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        Text("Что не заполнено, останется пустой строкой для ручной записи.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                        AppTextField(
                            title: "Электричество, кВт·ч",
                            text: $viewModel.meterElectricity,
                            placeholder: "16968",
                            keyboardType: .decimalPad,
                            autocapitalization: .never
                        )
                        .accessibilityIdentifier("contract.act.meter_electricity")
                        AppTextField(
                            title: "Вода, м³",
                            text: $viewModel.meterWater,
                            placeholder: "412,5",
                            keyboardType: .decimalPad,
                            autocapitalization: .never
                        )
                        .accessibilityIdentifier("contract.act.meter_water")
                        AppTextField(
                            title: "Ключей, шт.",
                            text: $viewModel.keysCountText,
                            placeholder: "2",
                            keyboardType: .numberPad,
                            autocapitalization: .never
                        )
                        .accessibilityIdentifier("contract.act.keys_count")
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            Text("Имущество (по строке на предмет)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .textCase(.uppercase)
                                .tracking(1.2)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                            TextEditor(text: $viewModel.inventoryText)
                                .frame(minHeight: 88)
                                .scrollContentBackground(.hidden)
                                .padding(AppTheme.Spacing.sm)
                                .background(Color.white.opacity(0.82))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(AppTheme.Colors.border, lineWidth: 1)
                                )
                                .accessibilityIdentifier("contract.act.inventory")
                        }
                    }
                    .padding(.top, AppTheme.Spacing.sm)
                }
                .font(.subheadline)
                .accessibilityIdentifier("contract.act")

                if let message = viewModel.inputError {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.Colors.danger)
                        .accessibilityIdentifier("contract.act.error")
                }

                Button {
                    Task { await viewModel.refreshPreview() }
                } label: {
                    Label("Обновить превью", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityIdentifier("contract.refresh")
            }
        }
    }

    private var templatePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Шаблон")
                .font(.subheadline)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Picker("Шаблон", selection: $viewModel.selectedTemplateId) {
                Text(viewModel.defaultTemplateName.map { "По умолчанию: \($0)" } ?? "По умолчанию")
                    .tag(String?.none)
                ForEach(viewModel.templates) { template in
                    Text(template.name).tag(Optional(template.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("contract.template.picker")
        }
    }

    // MARK: Small views

    private func noticeView(_ message: String) -> some View {
        Text(message)
            .font(.footnote.weight(.medium))
            .foregroundStyle(AppTheme.Colors.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.Spacing.md)
            .background(AppTheme.Colors.warning.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityIdentifier("contract.notice")
    }

    private func infoBlock(icon: String, title: String, message: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(AppTheme.Colors.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

/// Tile of the action grid.
struct ContractActionLabel: View {
    let title: String
    let systemImage: String
    var isBusy = false

    var body: some View {
        VStack(spacing: 4) {
            if isBusy {
                ProgressView().frame(height: 22)
            } else {
                Image(systemName: systemImage).font(.title3)
            }
            Text(title)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .font(.subheadline)
        .foregroundStyle(AppTheme.Colors.accent)
        .frame(maxWidth: .infinity, minHeight: 64)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppTheme.Colors.accent.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
