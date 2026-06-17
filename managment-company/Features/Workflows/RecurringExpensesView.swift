import SwiftUI

/// Manage recurring expense templates (GAP-039): due occurrences to confirm/skip,
/// active templates to edit/pause/delete, and paused templates to resume.
struct RecurringExpensesView: View {
    @StateObject private var viewModel: RecurringExpensesViewModel
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var editing: RecurringExpenseTemplate?
    @State private var showCreate = false
    @State private var deleteCandidate: RecurringExpenseTemplate?

    private let timeZoneIdentifier: String

    init(authManager: AuthManager) {
        _viewModel = StateObject(wrappedValue: RecurringExpensesViewModel(
            client: LiveRecurringExpenseClient(authManager: authManager)
        ))
        self.timeZoneIdentifier = authManager.user?.timezone ?? "Asia/Almaty"
    }

    private var today: String { AppFormatting.dayKey(timeZoneIdentifier: timeZoneIdentifier) }

    var body: some View {
        NavigationStack {
            List {
                let due = viewModel.dueTemplates(today: today)
                if !due.isEmpty {
                    Section("Требуют подтверждения") {
                        ForEach(due) { template in
                            dueRow(template)
                        }
                    }
                }
                Section("Активные") {
                    if viewModel.activeTemplates.isEmpty {
                        Text("Нет активных шаблонов").foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    ForEach(viewModel.activeTemplates) { template in
                        templateRow(template)
                    }
                }
                if !viewModel.pausedTemplates.isEmpty {
                    Section("На паузе") {
                        ForEach(viewModel.pausedTemplates) { template in
                            templateRow(template)
                        }
                    }
                }
                if let error = viewModel.errorMessage {
                    Section { Text(error).foregroundStyle(AppTheme.Colors.danger) }
                }
            }
            .navigationTitle("Повторяющиеся расходы")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { showCreate = true } label: { Image(systemName: "plus") }
                }
            }
            .task { await viewModel.load() }
            .sheet(isPresented: $showCreate) {
                RecurringExpenseFormSheet(authManager: authManager, template: nil) { input in
                    await viewModel.create(input)
                }
            }
            .sheet(item: $editing) { template in
                RecurringExpenseFormSheet(authManager: authManager, template: template) { input in
                    await viewModel.update(id: template.id, input)
                }
            }
            .confirmationDialog(
                "Удалить шаблон?",
                isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }),
                titleVisibility: .visible,
                presenting: deleteCandidate
            ) { template in
                Button("Удалить", role: .destructive) {
                    Task { _ = await viewModel.delete(template); deleteCandidate = nil }
                }
                Button("Отмена", role: .cancel) {}
            }
        }
    }

    private func dueRow(_ template: RecurringExpenseTemplate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            templateSummary(template)
            HStack(spacing: AppTheme.Spacing.sm) {
                Button("Подтвердить") { Task { _ = await viewModel.confirm(template) } }
                    .buttonStyle(.borderedProminent)
                Button("Пропустить") { Task { _ = await viewModel.skip(template) } }
                    .buttonStyle(.bordered)
            }
            .font(.caption.weight(.semibold))
        }
    }

    private func templateRow(_ template: RecurringExpenseTemplate) -> some View {
        templateSummary(template)
            .contentShape(Rectangle())
            .onTapGesture { editing = template }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { deleteCandidate = template } label: {
                    Label("Удалить", systemImage: "trash")
                }
                Button {
                    Task { _ = await viewModel.togglePause(template) }
                } label: {
                    Label(template.isPaused ? "Возобновить" : "Пауза",
                          systemImage: template.isPaused ? "play" : "pause")
                }
                .tint(AppTheme.Colors.accent)
            }
    }

    private func templateSummary(_ template: RecurringExpenseTemplate) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(template.categoryName.isEmpty ? "Расход" : template.categoryName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Spacer()
                Text(AppFormatting.currency(template.amount, currency: template.currency))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            Text("\(template.propertyName) · \(cadenceLabel(template.cadence)) · с \(AppFormatting.dateString(from: template.nextOccurrence) ?? template.nextOccurrence)")
                .font(.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
    }

    private func cadenceLabel(_ cadence: String) -> String {
        switch cadence.lowercased() {
        case "monthly": return "Ежемесячно"
        case "weekly": return "Еженедельно"
        case "quarterly": return "Ежеквартально"
        case "yearly": return "Ежегодно"
        default: return cadence
        }
    }
}
