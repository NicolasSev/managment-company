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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                        masthead

                        SurfaceCard {
                            VStack(spacing: AppTheme.Spacing.md) {
                                if mfaToken == nil {
                                    AppTextField(
                                        title: "Email",
                                        text: $email,
                                        placeholder: "name@example.com",
                                        keyboardType: .emailAddress,
                                        autocapitalization: .never,
                                        contentType: .username
                                    )

                                    AppTextField(
                                        title: "Пароль",
                                        text: $password,
                                        placeholder: "Ваш пароль",
                                        isSecure: true,
                                        contentType: .password
                                    )
                                } else {
                                    AppTextField(
                                        title: "Код 2FA",
                                        text: $mfaCode,
                                        placeholder: "000000 или резервный код",
                                        autocapitalization: .never,
                                        contentType: .oneTimeCode
                                    )
                                    .autocorrectionDisabled()
                                }

                                if let msg = apiStatusMessage {
                                    errorLine(msg)
                                }

                                if let msg = errorMessage {
                                    errorLine(msg)
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
                                    .frame(minHeight: 44)
                                }
                            }
                            .animation(
                                AppTheme.Motion.resolved(AppTheme.Motion.normal, reduceMotion: reduceMotion),
                                value: mfaToken
                            )
                        }

                        HStack {
                            Button("Создать аккаунт") {
                                showRegister = true
                            }
                            Spacer()
                            Button("Забыли пароль?") {
                                showPasswordRecovery = true
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.accent)
                        .frame(minHeight: 44)
                        .padding(.horizontal, AppTheme.Spacing.xs)
                        .padding(.bottom, AppTheme.Spacing.lg)
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.top, AppTheme.Spacing.xl)
                    .padding(.bottom, AppTheme.Spacing.xxl)
                }
                .scrollDismissesKeyboard(.interactively)
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
                // UI-тесты: клавиатурный ввод в SecureField на симуляторах
                // теряет клавиши с неактивной раскладки, поэтому пароль
                // подставляется напрямую из окружения запуска.
                if let prefill = ProcessInfo.processInfo.environment["UITEST_PASSWORD"],
                   !prefill.isEmpty {
                    password = prefill
                }
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

    /// Masthead: the product as a street of line-drawn buildings above the wordmark.
    private var masthead: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            IsometricStreet(buildings: Self.mastheadStreet, height: 120)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Рабочее пространство владельца")
                    .sectionLabelStyle(AppTheme.Colors.accent)

                Text("PropManager")
                    .font(.system(size: 40, weight: .light).width(.expanded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)

                Text("Объекты, арендаторы и платежи — на одном рабочем листе.")
                    .font(.body)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.xs)
    }

    /// Decorative street of the masthead (art, not portfolio data).
    private static let mastheadStreet: [IsometricBuildingSpec] = [
        .init(kind: .house, isOccupied: false),
        .init(kind: .tower, floors: 8, unitFloor: 5, windows: 2, isOccupied: true),
        .init(kind: .commercial, isOccupied: false),
        .init(kind: .tower, floors: 5, unitFloor: 2, windows: 3, isOccupied: true),
        .init(kind: .land, isOccupied: false),
    ]

    private func errorLine(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(AppTheme.Colors.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        AppTextField(title: title, text: text, isSecure: true, contentType: .newPassword)
    }

    private func statusMessage(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.inner, style: .continuous))
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
