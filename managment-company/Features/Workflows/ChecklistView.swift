import SwiftUI

/// Move-in / move-out checklist workspace for a lease (GAP-043).
struct ChecklistView: View {
    @StateObject private var viewModel: ChecklistViewModel
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    init(authManager: AuthManager, leaseId: String) {
        _viewModel = StateObject(wrappedValue: ChecklistViewModel(
            client: LiveChecklistClient(authManager: authManager),
            leaseId: leaseId
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Тип", selection: $viewModel.kind) {
                    ForEach(ChecklistKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.top, AppTheme.Spacing.sm)

                content
            }
            .navigationTitle("Чек-лист")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
            }
            .task { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.checklist == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !viewModel.isStarted {
            VStack(spacing: AppTheme.Spacing.md) {
                Text("Чек-лист \(viewModel.kind.title.lowercased()) ещё не начат.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Начать чек-лист") { Task { _ = await viewModel.start() } }
                    .buttonStyle(.borderedProminent)
            }
            .padding(AppTheme.Spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    let p = viewModel.progress
                    HStack {
                        Text("Готово \(p.done) из \(p.total)")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if ChecklistViewModel.isComplete(viewModel.items) {
                            Label("Завершён", systemImage: "checkmark.seal.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.Colors.success)
                        }
                    }
                }
                Section("Пункты") {
                    ForEach(viewModel.items) { item in
                        Button {
                            Task { _ = await viewModel.toggle(item) }
                        } label: {
                            HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isDone ? AppTheme.Colors.success : AppTheme.Colors.textSecondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.label)
                                        .foregroundStyle(AppTheme.Colors.textPrimary)
                                        .strikethrough(item.isDone)
                                    if let notes = item.notes, !notes.isEmpty {
                                        Text(notes).font(.caption).foregroundStyle(AppTheme.Colors.textSecondary)
                                    }
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let error = viewModel.errorMessage {
                    Section { Text(error).foregroundStyle(AppTheme.Colors.danger) }
                }
            }
        }
    }
}
