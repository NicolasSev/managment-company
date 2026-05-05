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
                                AppTextField(
                                    title: "Email",
                                    text: $email,
                                    placeholder: "name@example.com",
                                    keyboardType: .emailAddress,
                                    autocapitalization: .never
                                )

                                passwordField

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
                                    title: "Войти",
                                    action: { Task { await doLogin() } },
                                    isLoading: isLoading,
                                    isDisabled: email.isEmpty || password.isEmpty,
                                    systemImage: "arrow.right"
                                )
                            }
                        }

                        Button("Создать аккаунт") {
                            showRegister = true
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.accent)
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
            .onAppear {
                #if DEBUG
                Task { await checkAPIHealth() }
                #endif
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
    
    private func doLogin() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await authManager.login(email: email, password: password)
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
