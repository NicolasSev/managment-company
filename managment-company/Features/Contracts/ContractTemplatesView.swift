import SwiftUI
import UniformTypeIdentifiers

/// `Settings → Шаблоны договора`: the system template and the owner's own, QuickLook preview,
/// upload of a `.docx` of one's own. Accessibility identifiers: `settings.templates.*`.
struct ContractTemplatesView: View {
    @StateObject private var viewModel: ContractTemplatesViewModel
    @State private var showImporter = false

    init(service: ContractService) {
        _viewModel = StateObject(wrappedValue: ContractTemplatesViewModel(service: service))
    }

    private static let docxTypes: [UTType] = {
        [UTType("org.openxmlformats.wordprocessingml.document"), UTType(filenameExtension: "docx")]
            .compactMap { $0 }
    }()

    var body: some View {
        ZStack {
            AppScreenBackground()
            content
        }
        .navigationTitle("Шаблоны договора")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings.templates.screen")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showImporter = true
                } label: {
                    Label("Загрузить DOCX", systemImage: "plus")
                }
                .accessibilityIdentifier("settings.templates.add")
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: Self.docxTypes.isEmpty ? [.data] : Self.docxTypes) { result in
            if case .success(let url) = result { viewModel.prepareUpload(from: url) }
        }
        .sheet(item: $viewModel.previewFile) { file in
            NavigationStack {
                ContractQuickLookView(url: file.url)
                    .ignoresSafeArea()
                    .navigationTitle(file.url.lastPathComponent)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .accessibilityIdentifier("settings.templates.preview")
        }
        .sheet(item: $viewModel.draft) { _ in
            ContractTemplateUploadSheet(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("settings.templates.loading")
        case .error(let message):
            EmptyStateView(
                title: "Шаблоны недоступны",
                message: message,
                actionName: "Повторить",
                action: { Task { await viewModel.load() } },
                icon: "doc.badge.exclamationmark"
            )
            .accessibilityIdentifier("settings.templates.error")
        case .loaded:
            list
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                if let notice = viewModel.notice {
                    Text(notice)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.Colors.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppTheme.Spacing.md)
                        .background(AppTheme.Colors.warning.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityIdentifier("settings.templates.notice")
                }

                Text("Шаблон договора - файл Word (.docx) с полями вида {{tenant.full_name}}. Откройте системный шаблон, чтобы увидеть все поля, и загрузите свой вариант. Размер до 5 МБ.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                ForEach(viewModel.templates) { template in
                    row(template)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.lg)
        }
    }

    private func row(_ template: DocumentTemplate) -> some View {
        Button {
            Task { await viewModel.open(template) }
        } label: {
            SurfaceCard(padding: AppTheme.Spacing.md) {
                HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                    if viewModel.openingId == template.id {
                        ProgressView().frame(width: 28)
                    } else {
                        Image(systemName: template.isSystem ? "doc.text.fill" : "doc.text")
                            .font(.title3)
                            .foregroundStyle(AppTheme.Colors.accent)
                            .frame(width: 28)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(template.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            if template.isSystem { badge("Системный", color: AppTheme.Colors.textSecondary) }
                            if template.isDefault { badge("По умолчанию", color: AppTheme.Colors.success) }
                            Text(caption(template))
                                .font(.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.openingId != nil)
        .accessibilityIdentifier("settings.templates.row.\(template.id)")
    }

    private func badge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func caption(_ template: DocumentTemplate) -> String {
        var parts = ["версия \(template.version)"]
        if let size = template.sizeBytes {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }
}

/// Name and the "use by default" choice for a picked `.docx`.
private struct ContractTemplateUploadSheet: View {
    @ObservedObject var viewModel: ContractTemplatesViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Файл") {
                    Text(viewModel.draft?.fileName ?? "")
                        .accessibilityIdentifier("settings.templates.upload.file")
                }
                Section("Название") {
                    TextField(
                        "Название шаблона",
                        text: Binding(
                            get: { viewModel.draft?.name ?? "" },
                            set: { viewModel.draft?.name = $0 }
                        )
                    )
                    .accessibilityIdentifier("settings.templates.upload.name")
                }
                Section {
                    Toggle(
                        "Использовать по умолчанию",
                        isOn: Binding(
                            get: { viewModel.draft?.isDefault ?? false },
                            set: { viewModel.draft?.isDefault = $0 }
                        )
                    )
                    .accessibilityIdentifier("settings.templates.upload.default")
                } footer: {
                    Text("Новые договоры собираются из шаблона по умолчанию, если в договоре не выбран другой.")
                }
                if let error = viewModel.uploadError {
                    Section {
                        Text(error)
                            .foregroundStyle(AppTheme.Colors.danger)
                            .accessibilityIdentifier("settings.templates.upload.error")
                    }
                }
            }
            .navigationTitle("Новый шаблон")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { viewModel.cancelUpload() }
                        .accessibilityIdentifier("settings.templates.upload.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await viewModel.confirmUpload() }
                    } label: {
                        if viewModel.isUploading { ProgressView() } else { Text("Загрузить") }
                    }
                    .disabled(viewModel.isUploading)
                    .accessibilityIdentifier("settings.templates.upload.submit")
                }
            }
        }
    }
}
