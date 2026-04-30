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
                        SurfaceCard {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                                Text("Создайте рабочее пространство")
                                    .font(.system(size: 30, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppTheme.Colors.textPrimary)

                                Text("Настройте аккаунт и переходите к объектам, задачам и аналитике.")
                                    .font(.body)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                                    .lineSpacing(3)
                            }
                        }

                        SurfaceCard {
                            VStack(spacing: AppTheme.Spacing.md) {
                                AppTextField(title: "Имя", text: $name, placeholder: "Alex Morgan")
                                AppTextField(
                                    title: "Email",
                                    text: $email,
                                    placeholder: "name@example.com",
                                    keyboardType: .emailAddress,
                                    autocapitalization: .never
                                )
                                passwordField

                                if let msg = errorMessage {
                                    Text(msg)
                                        .font(.footnote)
                                        .foregroundStyle(AppTheme.Colors.danger)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                PrimaryButton(
                                    title: "Создать аккаунт",
                                    action: { Task { await doRegister() } },
                                    isLoading: isLoading,
                                    isDisabled: email.isEmpty || password.isEmpty,
                                    systemImage: "person.crop.circle.badge.plus"
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

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text("Пароль")
                .font(.caption)
                .fontWeight(.semibold)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            SecureField("Придумайте пароль", text: $password)
                .textFieldStyle(.plain)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .tint(AppTheme.Colors.accent)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.md)
                .background(Color.white.opacity(0.82))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.Colors.border, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 16, x: 0, y: 10)
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
