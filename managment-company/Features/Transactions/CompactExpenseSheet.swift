import SwiftUI

/// Compact `Добавить расход` sheet (GAP-033): amount-first capture with type
/// fixed to expense, today's date, base currency, recent-category chips, and
/// optional collapsed fields. Offers Undo and «Добавить ещё» after save.
struct CompactExpenseSheet: View {
    @StateObject private var viewModel: CompactExpenseViewModel
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @FocusState private var amountFocused: Bool
    @State private var showUndo = false

    init(authManager: AuthManager, contextPropertyId: String? = nil) {
        _viewModel = StateObject(wrappedValue: CompactExpenseViewModel(
            client: LiveCompactExpenseClient(authManager: authManager),
            baseCurrency: authManager.user?.baseCurrency ?? "KZT",
            timeZoneIdentifier: authManager.user?.timezone ?? "Asia/Almaty",
            contextPropertyId: contextPropertyId
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                amountSection
                categorySection
                propertySection
                optionalSection
                if let error = viewModel.errorMessage {
                    Section { Text(error).foregroundStyle(AppTheme.Colors.danger) }
                }
                if showUndo {
                    Section { undoRow }
                }
            }
            .navigationTitle("Добавить расход")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { Task { await saveAndDismiss() } }
                        .disabled(!viewModel.canSave || viewModel.isSaving)
                }
            }
            .task {
                await viewModel.load()
                amountFocused = true
            }
        }
    }

    private var amountSection: some View {
        Section("Сумма") {
            HStack {
                TextField("0", text: $viewModel.amountText)
                    .keyboardType(.decimalPad)
                    .font(.title2.weight(.semibold))
                    .focused($amountFocused)
                Text(viewModel.currency)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
    }

    private var categorySection: some View {
        Section("Категория") {
            if !viewModel.recentChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(viewModel.recentChips) { category in
                            chip(category)
                        }
                    }
                }
            }
            Picker("Категория", selection: Binding(
                get: { viewModel.selectedCategoryId ?? "" },
                set: { viewModel.selectedCategoryId = $0.isEmpty ? nil : $0 }
            )) {
                Text("Не выбрано").tag("")
                ForEach(viewModel.expenseCategories) { category in
                    Text(category.name).tag(category.id)
                }
            }
        }
    }

    private func chip(_ category: Category) -> some View {
        let selected = viewModel.selectedCategoryId == category.id
        return Button {
            viewModel.selectedCategoryId = category.id
        } label: {
            Text(category.name)
                .font(.caption.weight(.medium))
                .padding(.horizontal, AppTheme.Spacing.sm)
                .padding(.vertical, 6)
                .background((selected ? AppTheme.Colors.accent : AppTheme.Colors.accent.opacity(0.12)))
                .foregroundStyle(selected ? .white : AppTheme.Colors.accent)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var propertySection: some View {
        Section("Объект") {
            Picker("Объект", selection: $viewModel.selectedPropertyId) {
                Text("Не выбрано").tag("")
                ForEach(viewModel.properties) { property in
                    Text(property.name).tag(property.id)
                }
            }
        }
    }

    private var optionalSection: some View {
        Section {
            DisclosureGroup("Дополнительно", isExpanded: $viewModel.showOptionalFields) {
                DatePicker("Дата", selection: $viewModel.date, displayedComponents: .date)
                AppTextField(title: "Комментарий", text: $viewModel.note, placeholder: "Необязательно")
            }
        } footer: {
            Text("По умолчанию: расход, сегодня, \(viewModel.currency). Раскройте, чтобы изменить дату или добавить комментарий.")
        }
    }

    private var undoRow: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("Расход добавлен.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            HStack(spacing: AppTheme.Spacing.md) {
                Button("Отменить", role: .destructive) {
                    Task {
                        if await viewModel.undoLast() {
                            AppHaptics.success()
                            showUndo = false
                            NotificationCenter.default.post(name: .quickActionCompleted, object: nil)
                        }
                    }
                }
                .font(.subheadline.weight(.semibold))
                Button("Добавить ещё") {
                    viewModel.resetForAnother()
                    showUndo = false
                    amountFocused = true
                }
                .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Готово") { dismiss() }
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func saveAndDismiss() async {
        if await viewModel.save() {
            AppHaptics.success()
            NotificationCenter.default.post(name: .quickActionCompleted, object: nil)
            showUndo = true
        }
    }
}
