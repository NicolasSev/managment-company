import SwiftUI

enum AppTab: Hashable {
    case dashboard
    case transactions
    case properties
    case tenants
    case tasks
    case analytics
    case settings
}

struct MainTabView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject private var notificationRouter: NotificationDeepLinkRouter
    @ObservedObject private var pendingMutations = PendingMutationQueue.shared
    @State private var selectedTab: AppTab = .dashboard
    
    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
            HomeDashboardView(selectedTab: $selectedTab)
                .environmentObject(authManager)
                .tag(AppTab.dashboard)
                .tabItem {
                    Label("Дашборд", systemImage: "rectangle.grid.2x2")
                }
            TransactionsListView()
                .environmentObject(authManager)
                .tag(AppTab.transactions)
                .tabItem {
                    Label("Операции", systemImage: "arrow.left.arrow.right")
                }
            PropertiesListView()
                .tag(AppTab.properties)
                .tabItem {
                    Label("Объекты", systemImage: "building.2")
                }
            TenantsListView()
                .environmentObject(authManager)
                .tag(AppTab.tenants)
                .tabItem {
                    Label("Арендаторы", systemImage: "person.2")
                }
            TasksListView()
                .tag(AppTab.tasks)
                .tabItem {
                    Label("Задачи", systemImage: "checklist")
                }
            AnalyticsDashboardView()
                .tag(AppTab.analytics)
                .tabItem {
                    Label("Аналитика", systemImage: "chart.bar")
                }
            SettingsView()
                .tag(AppTab.settings)
                .tabItem {
                    Label("Настройки", systemImage: "gearshape")
                }
        }
        .tint(AppTheme.Colors.accent)

            if pendingMutations.pendingCount > 0 {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Ожидают отправки: \(pendingMutations.pendingCount)")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
                .frame(maxWidth: .infinity)
                .background(AppTheme.Colors.accent.opacity(0.15))
            }
        }
        .onChange(of: notificationRouter.selectTab) { _, tab in
            if let tab {
                selectedTab = tab
                notificationRouter.clearTabSelection()
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var profileName = ""
    @State private var timezone = "Asia/Almaty"
    @State private var baseCurrency = "KZT"
    @State private var isSaving = false
    @State private var saveMessage: String?
    @State private var errorMessage: String?
    @State private var mfaSetup: MFASetupResult?
    @State private var mfaCode = ""
    @State private var disableMFACode = ""
    @State private var isMFAWorking = false
    @State private var mfaMessage: String?
    @State private var mfaErrorMessage: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: AppTheme.Spacing.lg) {
                        if let user = authManager.user {
                            SurfaceCard {
                                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                                    Text("Аккаунт")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .textCase(.uppercase)
                                        .tracking(1.2)
                                        .foregroundStyle(AppTheme.Colors.textSecondary)

                                    Text(user.name ?? "Владелец")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(AppTheme.Colors.textPrimary)

                                    Text(user.email)
                                        .font(.subheadline)
                                        .foregroundStyle(AppTheme.Colors.textSecondary)

                                    Label("Часовой пояс: \(user.timezone)", systemImage: "globe")
                                        .font(.subheadline)
                                        .foregroundStyle(AppTheme.Colors.textSecondary)

                                    Label("Базовая валюта: \(user.baseCurrency)", systemImage: "banknote")
                                        .font(.subheadline)
                                        .foregroundStyle(AppTheme.Colors.textSecondary)
                                }
                            }
                        }

                        SurfaceCard {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                                Text("Профиль")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .textCase(.uppercase)
                                    .tracking(1.2)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)

                                Text("Профиль и настройки формата будут одинаковыми в мобильном и веб-приложении.")
                                    .font(.body)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                                    .lineSpacing(3)

                                AppTextField(
                                    title: "Отображаемое имя",
                                    text: $profileName,
                                    placeholder: "Управляющий"
                                )

                                AppTextField(
                                    title: "Часовой пояс",
                                    text: $timezone,
                                    placeholder: "Asia/Almaty",
                                    autocapitalization: .never
                                )

                                AppTextField(
                                    title: "Базовая валюта",
                                    text: $baseCurrency,
                                    placeholder: "KZT",
                                    autocapitalization: .never
                                )

                                Text("Используйте IANA-часовой пояс, например `Asia/Almaty`, и трехбуквенный код валюты, например `KZT` или `USD`.")
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                                    .lineSpacing(2)

                                if let saveMessage {
                                    statusMessage(saveMessage, color: AppTheme.Colors.success)
                                }

                                if let errorMessage {
                                    statusMessage(errorMessage, color: AppTheme.Colors.danger)
                                }

                                PrimaryButton(
                                    title: isSaving ? "Сохраняем..." : "Сохранить профиль",
                                    action: { Task { await saveProfile() } },
                                    isLoading: isSaving,
                                    isDisabled: isSaving || timezone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || baseCurrency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                    systemImage: "square.and.arrow.down"
                                )
                            }
                        }

                        mfaSection

                        SurfaceCard {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                                Text("Сессия")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .textCase(.uppercase)
                                    .tracking(1.2)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)

                                Text("Выйдите, если передаете устройство другому человеку или переключаетесь на другой аккаунт.")
                                    .font(.body)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                                    .lineSpacing(3)

                                PrimaryButton(
                                    title: "Выйти",
                                    action: { authManager.logout() },
                                    systemImage: "rectangle.portrait.and.arrow.right"
                                )
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.lg)
                }
            }
            .navigationTitle("Настройки")
            .task(id: authManager.user?.id) {
                syncProfileFields()
            }
        }
    }

    private var mfaSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Безопасность")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "checkmark.shield")
                        .font(.title3)
                        .foregroundStyle(AppTheme.Colors.accent)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Двухфакторная аутентификация")
                            .font(.headline)
                            .foregroundStyle(AppTheme.Colors.textPrimary)

                        Text(authManager.user?.mfaEnabled == true ? "2FA включена для этого аккаунта." : "Добавьте второй шаг входа через приложение-аутентификатор.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }

                if let mfaMessage {
                    statusMessage(mfaMessage, color: AppTheme.Colors.success)
                }

                if let mfaErrorMessage {
                    statusMessage(mfaErrorMessage, color: AppTheme.Colors.danger)
                }

                if authManager.user?.mfaEnabled == true {
                    AppTextField(
                        title: "Код или резервный код",
                        text: $disableMFACode,
                        placeholder: "000000 или backup",
                        keyboardType: .default,
                        autocapitalization: .never
                    )

                    PrimaryButton(
                        title: "Отключить 2FA",
                        action: { Task { await disableMFA() } },
                        isLoading: isMFAWorking,
                        isDisabled: disableMFACode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        systemImage: "shield.slash"
                    )
                } else if let setup = mfaSetup {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text("Добавьте аккаунт в приложении")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.textSecondary)

                        Text(setup.otpauthURL)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(AppTheme.Spacing.sm)
                            .background(AppTheme.Colors.backgroundSecondary.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                        Text("Резервные коды")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.warning)

                        ForEach(setup.backupCodes, id: \.self) { code in
                            Text(code)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppTheme.Spacing.md)
                    .background(AppTheme.Colors.warning.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    AppTextField(
                        title: "Код подтверждения",
                        text: $mfaCode,
                        placeholder: "000000",
                        keyboardType: .numberPad,
                        autocapitalization: .never
                    )

                    PrimaryButton(
                        title: "Включить 2FA",
                        action: { Task { await verifyMFA() } },
                        isLoading: isMFAWorking,
                        isDisabled: mfaCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        systemImage: "shield"
                    )
                } else {
                    PrimaryButton(
                        title: "Настроить аутентификатор",
                        action: { Task { await setupMFA() } },
                        isLoading: isMFAWorking,
                        systemImage: "qrcode"
                    )
                }
            }
        }
    }

    private func syncProfileFields() {
        guard let user = authManager.user else { return }
        profileName = user.name ?? ""
        timezone = user.timezone
        baseCurrency = user.baseCurrency
    }

    private func saveProfile() async {
        isSaving = true
        saveMessage = nil
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await authManager.updateProfile(
                name: profileName,
                timezone: timezone,
                baseCurrency: baseCurrency
            )
            syncProfileFields()
            saveMessage = "Профиль обновлен."
        } catch {
            errorMessage = "Не удалось сохранить профиль. Проверьте часовой пояс и валюту, затем попробуйте снова."
        }
    }

    private func setupMFA() async {
        isMFAWorking = true
        mfaMessage = nil
        mfaErrorMessage = nil
        defer { isMFAWorking = false }

        do {
            mfaSetup = try await authManager.setupMFA()
        } catch {
            mfaErrorMessage = error.localizedDescription
        }
    }

    private func verifyMFA() async {
        isMFAWorking = true
        mfaMessage = nil
        mfaErrorMessage = nil
        defer { isMFAWorking = false }

        do {
            try await authManager.verifyMFA(code: mfaCode)
            mfaSetup = nil
            mfaCode = ""
            mfaMessage = "Двухфакторная аутентификация включена."
        } catch {
            mfaErrorMessage = error.localizedDescription
        }
    }

    private func disableMFA() async {
        isMFAWorking = true
        mfaMessage = nil
        mfaErrorMessage = nil
        defer { isMFAWorking = false }

        do {
            try await authManager.disableMFA(code: disableMFACode)
            disableMFACode = ""
            mfaSetup = nil
            mfaMessage = "Двухфакторная аутентификация отключена."
        } catch {
            mfaErrorMessage = error.localizedDescription
        }
    }

    private func statusMessage(_ message: String, color: Color) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
