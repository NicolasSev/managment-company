import SwiftUI

struct RegisterView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: AppTheme.Spacing.lg) {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            Text("Новый аккаунт")
                                .sectionLabelStyle(AppTheme.Colors.accent)

                            Text("Создайте рабочее пространство")
                                .font(AppTheme.Typography.masthead)
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("Настройте аккаунт и переходите к объектам, задачам и аналитике.")
                                .font(.body)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                                .lineSpacing(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, AppTheme.Spacing.xs)

                        SurfaceCard {
                            VStack(spacing: AppTheme.Spacing.md) {
                                AppTextField(title: "Имя", text: $name, placeholder: "Как к вам обращаться", contentType: .name)
                                AppTextField(
                                    title: "Email",
                                    text: $email,
                                    placeholder: "name@example.com",
                                    keyboardType: .emailAddress,
                                    autocapitalization: .never
                                )
                                AppTextField(
                                    title: "Пароль",
                                    text: $password,
                                    placeholder: "Придумайте пароль",
                                    isSecure: true,
                                    contentType: .newPassword
                                )

                                if let msg = errorMessage {
                                    Label(msg, systemImage: "exclamationmark.circle")
                                        .font(.footnote)
                                        .foregroundStyle(AppTheme.Colors.danger)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                PrimaryButton(
                                    title: "Создать аккаунт",
                                    action: { Task { await doRegister() } },
                                    isLoading: isLoading,
                                    isDisabled: email.isEmpty || password.isEmpty,
                                    systemImage: "arrow.right"
                                )
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.xl)
                }
            }
            .navigationTitle("Регистрация")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }

    private func doRegister() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await authManager.register(email: email, password: password, name: name)
            dismiss()
        } catch {
            errorMessage = "Не удалось зарегистрироваться"
        }
    }
}
