import SwiftUI

/// Create / edit form of a tenant. Editing replaces the whole record on the server, so the form
/// starts from the stored tenant (identity fields included) and sends every field back.
struct TenantFormSheet: View {
    let onSave: () async -> Void

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: TenantEditViewModel
    private let isNew: Bool

    init(tenant: Tenant? = nil, onSave: @escaping () async -> Void) {
        self.onSave = onSave
        self.isNew = tenant == nil
        _viewModel = StateObject(wrappedValue: TenantEditViewModel(tenant: tenant))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Имя") {
                    AppTextField(title: "Имя", text: $viewModel.form.firstName, placeholder: "Имя", identifier: "tenants.form.firstName")
                    AppTextField(title: "Фамилия", text: $viewModel.form.lastName, placeholder: "Необязательно")
                    AppTextField(title: "Отчество", text: $viewModel.form.middleName, placeholder: "Необязательно")
                }

                Section("Контакты") {
                    AppTextField(title: "Телефон", text: $viewModel.form.phone, placeholder: "+7...", keyboardType: .phonePad, identifier: "tenants.form.phone")
                    AppTextField(title: "Почта", text: $viewModel.form.email, placeholder: "email@example.com", keyboardType: .emailAddress, autocapitalization: .never)
                }

                Section("Удостоверение") {
                    AppTextField(title: "ИИН", text: $viewModel.form.iin, placeholder: "12 цифр", keyboardType: .numberPad, autocapitalization: .never, identifier: "tenants.form.iin")
                    Picker("Документ", selection: $viewModel.form.documentType) {
                        Text("Не указан").tag("")
                        ForEach(TenantDocumentType.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .accessibilityIdentifier("tenants.form.documentType")
                    AppTextField(title: "Номер документа", text: $viewModel.form.documentNumber, placeholder: "Необязательно", autocapitalization: .characters)
                    AppTextField(title: "Кем выдан", text: $viewModel.form.documentIssuedBy, placeholder: "Необязательно")
                    OptionalDateRow(title: "Дата выдачи", day: $viewModel.form.documentIssuedAt)
                    OptionalDateRow(title: "Дата рождения", day: $viewModel.form.birthDate)
                    AppTextField(title: "Адрес регистрации", text: $viewModel.form.registrationAddress, placeholder: "Необязательно")
                }

                Section("Проживание") {
                    AppTextField(title: "С кем проживает", text: $viewModel.form.cohabitants, placeholder: "Семья, соседи, питомцы")
                    AppTextField(title: "Заметки", text: $viewModel.form.notes, placeholder: "Необязательно")
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(AppTheme.Colors.danger)
                            .accessibilityIdentifier("tenants.form.error")
                    }
                }
            }
            .navigationTitle(isNew ? "Новый арендатор" : "Редактировать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Создать" : "Сохранить") {
                        Task { await save() }
                    }
                    .disabled(!viewModel.form.canSubmit || viewModel.isSaving)
                    .accessibilityIdentifier("tenants.form.save")
                }
            }
        }
        .accessibilityIdentifier("tenants.form")
    }

    private func save() async {
        guard await viewModel.save(client: LiveTenantClient(authManager: authManager)) else { return }
        await onSave()
        dismiss()
    }
}

/// Date field that may stay empty: a toggle reveals a wheel picker. Value is a `YYYY-MM-DD` string.
private struct OptionalDateRow: View {
    let title: String
    @Binding var day: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Toggle(title, isOn: Binding(
                get: { !day.isEmpty },
                set: { day = $0 ? LeaseDay.string(fromPicker: Date()) : "" }
            ))
            if !day.isEmpty {
                DatePicker(
                    title,
                    selection: Binding(
                        get: { LeaseDay.pickerDate(day) ?? Date() },
                        set: { day = LeaseDay.string(fromPicker: $0) }
                    ),
                    displayedComponents: .date
                )
                .labelsHidden()
            }
        }
    }
}
