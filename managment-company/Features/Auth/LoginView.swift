import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var apiStatusMessage: String?
    @State private var isCheckingAPI = false
    @State private var showRegister = false
    @State private var showPasswordRecovery = false
    @State private var mfaToken: String?
    @State private var mfaCode = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: AppTheme.Spacing.lg) {
                        SurfaceCard {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                                Label("Рабочее пространство владельца", systemImage: "sparkles")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(AppTheme.Colors.accent)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(AppTheme.Colors.accent.opacity(0.12))
                                    .clipShape(Capsule())

                                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                                    Text("PropManager")
                                        .font(.system(size: 34, weight: .bold, design: .rounded))
                                        .foregroundStyle(AppTheme.Colors.textPrimary)

                                    Text("Управление недвижимостью без хаоса.")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(AppTheme.Colors.textPrimary)

                                    Text("Ведите объекты, задачи и денежный поток в одном спокойном рабочем пространстве.")
                                        .font(.body)
                                        .foregroundStyle(AppTheme.Colors.textSecondary)
                                        .lineSpacing(3)
                                }
                            }
                        }

                        SurfaceCard {
                            VStack(spacing: AppTheme.Spacing.md) {
                                if mfaToken == nil {
                                    AppTextField(
                                        title: "Email",
                                        text: $email,
                                        placeholder: "name@example.com",
                                        keyboardType: .emailAddress,
                                        autocapitalization: .never
                                    )

                                    passwordField
                                } else {
                                    mfaCodeField
                                }

                                if let msg = apiStatusMessage {
                                    Text(msg)
                                        .font(.footnote)
                                        .foregroundStyle(AppTheme.Colors.danger)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                if let msg = errorMessage {
                                    Text(msg)
                                        .font(.footnote)
                                        .foregroundStyle(AppTheme.Colors.danger)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                PrimaryButton(
                                    title: mfaToken == nil ? "Войти" : "Подтвердить вход",
                                    action: { Task { await doLogin() } },
                                    isLoading: isLoading,
                                    isDisabled: primaryActionDisabled,
                                    systemImage: mfaToken == nil ? "arrow.right" : "checkmark.shield"
                                )

                                if mfaToken != nil {
                                    Button("Назад к паролю") {
                                        mfaToken = nil
                                        mfaCode = ""
                                        errorMessage = nil
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.Colors.accent)
                                }
                            }
                        }

                        VStack(spacing: AppTheme.Spacing.sm) {
                            Button("Забыли пароль?") {
                                showPasswordRecovery = true
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.accent)

                            Button("Создать аккаунт") {
                                showRegister = true
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.accent)
                        }
                        .padding(.bottom, AppTheme.Spacing.lg)
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.xxl)
                }
            }
            .sheet(isPresented: $showRegister) {
                RegisterView()
                    .environmentObject(authManager)
            }
            .sheet(isPresented: $showPasswordRecovery) {
                PasswordRecoverySheet(initialEmail: email)
                    .environmentObject(authManager)
            }
            .onAppear {
                #if DEBUG
                Task { await checkAPIHealth() }
                #endif
            }
        }
    }

    private var primaryActionDisabled: Bool {
        if mfaToken != nil {
            return mfaCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text("Пароль")
                .font(.caption)
                .fontWeight(.semibold)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            SecureField("Ваш пароль", text: $password)
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

    private var mfaCodeField: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text("Код 2FA")
                .font(.caption)
                .fontWeight(.semibold)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            TextField("000000 или резервный код", text: $mfaCode)
                .textFieldStyle(.plain)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .tint(AppTheme.Colors.accent)
                .keyboardType(.default)
                .textContentType(.oneTimeCode)
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
    
    private func doLogin() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if let mfaToken {
                try await authManager.authenticateMFA(token: mfaToken, code: mfaCode)
                return
            }

            switch try await authManager.login(email: email, password: password) {
            case .authenticated:
                break
            case .mfaRequired(let token):
                mfaToken = token
                mfaCode = ""
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    #if DEBUG
    private func checkAPIHealth() async {
        guard !isCheckingAPI, let url = URL(string: "\(AppEnvironment.apiBaseURL)/health") else { return }
        isCheckingAPI = true
        apiStatusMessage = nil
        defer { isCheckingAPI = false }

        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                apiStatusMessage = "API health failed at \(AppEnvironment.apiBaseURL)."
                return
            }
        } catch {
            if let urlError = error as? URLError {
                apiStatusMessage = "API health failed at \(AppEnvironment.apiBaseURL): \(urlError.localizedDescription) (\(urlError.code.rawValue))"
                return
            }
            apiStatusMessage = "API health failed at \(AppEnvironment.apiBaseURL): \(error.localizedDescription)"
        }
    }
    #endif
}

private enum PasswordRecoveryMode: String, CaseIterable, Identifiable {
    case request = "Письмо"
    case reset = "Новый пароль"

    var id: String { rawValue }
}

private struct PasswordRecoverySheet: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    let initialEmail: String

    @State private var mode: PasswordRecoveryMode = .request
    @State private var email: String
    @State private var token = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var message: String?
    @State private var errorMessage: String?

    init(initialEmail: String) {
        self.initialEmail = initialEmail
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: AppTheme.Spacing.lg) {
                        SurfaceCard {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                                Text("Восстановление доступа")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(AppTheme.Colors.textPrimary)

                                Picker("Режим", selection: $mode) {
                                    ForEach(PasswordRecoveryMode.allCases) { item in
                                        Text(item.rawValue).tag(item)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                        }

                        SurfaceCard {
                            VStack(spacing: AppTheme.Spacing.md) {
                                if mode == .request {
                                    AppTextField(
                                        title: "Email",
                                        text: $email,
                                        placeholder: "name@example.com",
                                        keyboardType: .emailAddress,
                                        autocapitalization: .never
                                    )

                                    PrimaryButton(
                                        title: "Отправить письмо",
                                        action: { Task { await requestReset() } },
                                        isLoading: isLoading,
                                        isDisabled: email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                        systemImage: "envelope"
                                    )
                                } else {
                                    AppTextField(
                                        title: "Токен из письма",
                                        text: $token,
                                        placeholder: "reset token",
                                        autocapitalization: .never
                                    )
                                    secureRecoveryField("Новый пароль", text: $password)
                                    secureRecoveryField("Повторите пароль", text: $confirmPassword)

                                    PrimaryButton(
                                        title: "Сохранить новый пароль",
                                        action: { Task { await resetPassword() } },
                                        isLoading: isLoading,
                                        isDisabled: resetDisabled,
                                        systemImage: "key"
                                    )
                                }

                                if let message {
                                    statusMessage(message, color: AppTheme.Colors.success)
                                }

                                if let errorMessage {
                                    statusMessage(errorMessage, color: AppTheme.Colors.danger)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.lg)
                }
            }
            .navigationTitle("Пароль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }

    private var resetDisabled: Bool {
        token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || password.count < 6
            || password != confirmPassword
    }

    private func secureRecoveryField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            SecureField(title, text: text)
                .textFieldStyle(.plain)
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
        }
    }

    private func statusMessage(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func requestReset() async {
        isLoading = true
        message = nil
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await authManager.forgotPassword(email: email)
            message = "Если аккаунт существует, письмо для сброса отправлено."
            mode = .reset
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetPassword() async {
        isLoading = true
        message = nil
        errorMessage = nil
        defer { isLoading = false }

        guard password == confirmPassword else {
            errorMessage = "Пароли не совпадают."
            return
        }

        do {
            try await authManager.resetPassword(token: token, newPassword: password)
            message = "Пароль обновлен. Теперь можно войти."
            password = ""
            confirmPassword = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
