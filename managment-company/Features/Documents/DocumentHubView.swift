import SwiftUI

/// Cross-portfolio document hub (GAP-044/GAP-047): search + filter all user files
/// with resolved entity context, open or delete.
struct DocumentHubView: View {
    @StateObject private var viewModel: DocumentHubViewModel
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var deleteCandidate: DocumentFile?
    @State private var showFilters = false

    init(authManager: AuthManager) {
        _viewModel = StateObject(wrappedValue: DocumentHubViewModel(client: LiveDocumentHubClient(authManager: authManager)))
    }

    var body: some View {
        NavigationStack {
            List {
                searchSection
                if showFilters {
                    filterSection
                }
                documentsSection
                if let error = viewModel.errorMessage {
                    Section { Text(error).foregroundStyle(AppTheme.Colors.danger) }
                }
            }
            .navigationTitle("Документы")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    filterToolbarButton
                }
            }
            .task {
                if viewModel.files.isEmpty { await viewModel.reload() }
                await viewModel.loadFilterOptions()
            }
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

    // MARK: - Toolbar

    private var filterToolbarButton: some View {
        Button {
            showFilters.toggle()
        } label: {
            Label("Фильтры", systemImage: viewModel.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .foregroundStyle(viewModel.hasActiveFilters ? AppTheme.Colors.accent : .primary)
        }
    }

    // MARK: - Sections

    private var searchSection: some View {
        Section {
            TextField("Поиск по имени/объекту", text: $viewModel.search)
                .onSubmit { Task { await viewModel.reload() } }
        }
    }

    @ViewBuilder
    private var filterSection: some View {
        Section("Фильтры") {
            Picker("Тип объекта", selection: $viewModel.entityTypeFilter) {
                ForEach(DocumentHubViewModel.entityTypes, id: \.value) {
                    Text($0.label).tag($0.value)
                }
            }
            .onChange(of: viewModel.entityTypeFilter) { _, _ in Task { await viewModel.reload() } }

            if !viewModel.properties.isEmpty {
                Picker("Объект", selection: $viewModel.propertyIdFilter) {
                    Text("Все объекты").tag("")
                    ForEach(viewModel.properties) { property in
                        Text(property.name).tag(property.id)
                    }
                }
                .onChange(of: viewModel.propertyIdFilter) { _, _ in Task { await viewModel.reload() } }
            }

            if !viewModel.tenants.isEmpty {
                Picker("Арендатор", selection: $viewModel.tenantIdFilter) {
                    Text("Все арендаторы").tag("")
                    ForEach(viewModel.tenants) { tenant in
                        Text(tenant.displayName).tag(tenant.id)
                    }
                }
                .onChange(of: viewModel.tenantIdFilter) { _, _ in Task { await viewModel.reload() } }
            }

            datePicker(label: "С даты", selection: $viewModel.dateFromFilter)
            datePicker(label: "По дату", selection: $viewModel.dateToFilter)

            if viewModel.hasActiveFilters {
                Button("Сбросить фильтры", role: .destructive) {
                    viewModel.clearFilters()
                    Task { await viewModel.reload() }
                }
            }
        }
    }

    private var documentsSection: some View {
        Section {
            if viewModel.files.isEmpty, !viewModel.isLoading {
                Text("Документы не найдены")
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            ForEach(viewModel.files) { file in
                row(file)
            }
            if viewModel.canLoadMore {
                Button("Показать ещё") { Task { await viewModel.loadMore() } }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func datePicker(label: String, selection: Binding<Date?>) -> some View {
        if let date = selection.wrappedValue {
            DatePicker(label, selection: Binding(
                get: { date },
                set: { selection.wrappedValue = $0 }
            ), displayedComponents: .date)
            .onChange(of: date) { _, _ in Task { await viewModel.reload() } }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    selection.wrappedValue = nil
                    Task { await viewModel.reload() }
                } label: {
                    Label("Убрать", systemImage: "xmark")
                }
            }
        } else {
            Button {
                selection.wrappedValue = .now
            } label: {
                Label(label, systemImage: "calendar.badge.plus")
                    .foregroundStyle(AppTheme.Colors.accent)
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
