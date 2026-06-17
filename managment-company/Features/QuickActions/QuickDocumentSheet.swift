import SwiftUI
import UniformTypeIdentifiers

/// Global quick document upload with target search (GAP-036): pick target type,
/// search/select the entity, choose a file type, then pick a file. Launching
/// from a property context preselects it.
struct QuickDocumentSheet: View {
    @StateObject private var viewModel: QuickDocumentViewModel
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var showFileImporter = false

    init(authManager: AuthManager, contextPropertyId: String? = nil) {
        _viewModel = StateObject(wrappedValue: QuickDocumentViewModel(
            client: LiveQuickDocumentClient(authManager: authManager),
            contextPropertyId: contextPropertyId
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Куда прикрепить") {
                    Picker("Тип", selection: $viewModel.targetType) {
                        ForEach(DocumentTargetType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Цель") {
                    TextField("Поиск", text: $viewModel.searchText)
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        ForEach(viewModel.filteredItems.prefix(20)) { item in
                            Button {
                                viewModel.selectedEntityId = item.id
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .foregroundStyle(AppTheme.Colors.textPrimary)
                                        if let subtitle = item.subtitle, !subtitle.isEmpty {
                                            Text(subtitle)
                                                .font(.caption)
                                                .foregroundStyle(AppTheme.Colors.textSecondary)
                                        }
                                    }
                                    Spacer()
                                    if viewModel.selectedEntityId == item.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(AppTheme.Colors.accent)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Тип файла") {
                    Picker("Тип файла", selection: $viewModel.fileType) {
                        ForEach(QuickDocumentViewModel.fileTypes, id: \.value) { type in
                            Text(type.label).tag(type.value)
                        }
                    }
                }

                if let error = viewModel.errorMessage {
                    Section { Text(error).foregroundStyle(AppTheme.Colors.danger) }
                }

                Section {
                    Button {
                        showFileImporter = true
                    } label: {
                        if viewModel.isUploading {
                            ProgressView()
                        } else {
                            Label("Выбрать файл и загрузить", systemImage: "paperclip")
                        }
                    }
                    .disabled(!viewModel.canUpload || viewModel.isUploading)
                }
            }
            .navigationTitle("Загрузить документ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .task { await viewModel.loadTargets() }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.pdf, .image, .plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                if case let .success(urls) = result, let url = urls.first {
                    Task { await handlePicked(url) }
                }
            }
        }
    }

    private func handlePicked(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            viewModel.errorMessage = "Не удалось прочитать файл."
            return
        }
        let ok = await viewModel.upload(
            fileData: data,
            fileName: url.lastPathComponent,
            mimeType: Self.mimeType(for: url)
        )
        if ok {
            AppHaptics.success()
            NotificationCenter.default.post(name: .quickActionCompleted, object: nil)
            dismiss()
        }
    }

    private static func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension), let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }
}
