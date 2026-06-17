import SwiftUI

/// Cross-portfolio document hub (GAP-044): search + filter all user files with
/// resolved entity context, open or delete.
struct DocumentHubView: View {
    @StateObject private var viewModel: DocumentHubViewModel
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var deleteCandidate: DocumentFile?

    init(authManager: AuthManager) {
        _viewModel = StateObject(wrappedValue: DocumentHubViewModel(client: LiveDocumentHubClient(authManager: authManager)))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Поиск по имени/объекту", text: $viewModel.search)
                        .onSubmit { Task { await viewModel.reload() } }
                    Picker("Тип", selection: $viewModel.entityTypeFilter) {
                        ForEach(DocumentHubViewModel.entityTypes, id: \.value) { Text($0.label).tag($0.value) }
                    }
                    .onChange(of: viewModel.entityTypeFilter) { _, _ in Task { await viewModel.reload() } }
                }
                Section {
                    if viewModel.files.isEmpty, !viewModel.isLoading {
                        Text("Документы не найдены").foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    ForEach(viewModel.files) { file in
                        row(file)
                    }
                    if viewModel.canLoadMore {
                        Button("Показать ещё") { Task { await viewModel.loadMore() } }
                    }
                }
                if let error = viewModel.errorMessage {
                    Section { Text(error).foregroundStyle(AppTheme.Colors.danger) }
                }
            }
            .navigationTitle("Документы")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
            }
            .task { if viewModel.files.isEmpty { await viewModel.reload() } }
            .refreshable { await viewModel.reload() }
            .confirmationDialog(
                "Удалить документ?",
                isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }),
                titleVisibility: .visible,
                presenting: deleteCandidate
            ) { file in
                Button("Удалить", role: .destructive) {
                    Task { _ = await viewModel.delete(file); deleteCandidate = nil }
                }
                Button("Отмена", role: .cancel) {}
            }
        }
    }

    private func row(_ file: DocumentFile) -> some View {
        Button {
            if let path = file.downloadURL,
               let url = APIURLBuilder.absoluteDownloadURL(base: AppEnvironment.apiBaseURL, downloadPath: path) {
                openURL(url)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.displayName)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                    Text([DocumentHubViewModel.entityTypeLabel(file.entityType), file.propertyName ?? file.contextName]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(AppTheme.Colors.accent)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { deleteCandidate = file } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
    }
}
