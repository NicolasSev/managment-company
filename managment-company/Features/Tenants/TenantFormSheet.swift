import SwiftUI

struct TenantFormSheet: View {
    let tenant: Tenant?
    let onSave: () async -> Void

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var firstName: String
    @State private var lastName: String
    @State private var phone: String
    @State private var email: String
    @State private var cohabitants: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(tenant: Tenant? = nil, onSave: @escaping () async -> Void) {
        self.tenant = tenant
        self.onSave = onSave
        _firstName = State(initialValue: tenant?.firstName ?? "")
        _lastName = State(initialValue: tenant?.lastName ?? "")
        _phone = State(initialValue: tenant?.phone ?? "")
        _email = State(initialValue: tenant?.email ?? "")
        _cohabitants = State(initialValue: tenant?.cohabitants ?? "")
        _notes = State(initialValue: tenant?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Имя") {
                    AppTextField(title: "Имя", text: $firstName, placeholder: "Имя")
                    AppTextField(title: "Фамилия", text: $lastName, placeholder: "Необязательно")
                }

                Section("Контакты") {
                    AppTextField(title: "Телефон", text: $phone, placeholder: "+7...", keyboardType: .phonePad)
                    AppTextField(title: "Почта", text: $email, placeholder: "email@example.com", keyboardType: .emailAddress, autocapitalization: .never)
                }

                Section("Проживание") {
                    AppTextField(title: "С кем проживает", text: $cohabitants, placeholder: "Семья, соседи, питомцы")
                    AppTextField(title: "Заметки", text: $notes, placeholder: "Необязательно")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(AppTheme.Colors.danger)
                    }
                }
            }
            .navigationTitle(tenant == nil ? "Новый арендатор" : "Редактировать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tenant == nil ? "Создать" : "Сохранить") {
                        Task { await save() }
                    }
                    .disabled(!canSubmit || isSaving)
                }
            }
        }
    }

    private var canSubmit: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() async {
        guard canSubmit else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let body = TenantUpsertBody(
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: optionalTrimmed(lastName),
            phone: optionalTrimmed(phone),
            email: optionalTrimmed(email),
            cohabitants: optionalTrimmed(cohabitants),
            notes: optionalTrimmed(notes)
        )

        do {
            if let tenant {
                _ = try await APIClient.shared.request(
                    "/v1/tenants/\(tenant.id)",
                    method: "PUT",
                    body: body,
                    tokenProvider: { await MainActor.run { authManager.accessToken } },
                    refreshAndRetry: { await authManager.refreshToken() }
                ) as Tenant
            } else {
                _ = try await APIClient.shared.request(
                    "/v1/tenants",
                    method: "POST",
                    body: body,
                    tokenProvider: { await MainActor.run { authManager.accessToken } },
                    refreshAndRetry: { await authManager.refreshToken() }
                ) as Tenant
            }
            await onSave()
            await MainActor.run { dismiss() }
        } catch APIError.httpStatus(let code) {
            await MainActor.run {
                errorMessage = code == 400
                    ? "Проверьте имя и email."
                    : "Не удалось сохранить арендатора."
            }
        } catch {
            await MainActor.run {
                errorMessage = "Не удалось сохранить арендатора."
            }
        }
    }

    private func optionalTrimmed(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct TenantUpsertBody: Encodable {
    let firstName: String
    let lastName: String?
    let phone: String?
    let email: String?
    let cohabitants: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case phone
        case email
        case cohabitants
        case notes
    }
}
