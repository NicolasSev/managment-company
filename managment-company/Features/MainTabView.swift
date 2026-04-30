import SwiftUI

enum AppTab: Hashable {
    case dashboard
    case properties
    case tasks
    case analytics
    case settings
}

struct MainTabView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var selectedTab: AppTab = .dashboard
    
    var body: some View {
        TabView(selection: $selectedTab) {
            HomeDashboardView(selectedTab: $selectedTab)
                .environmentObject(authManager)
                .tag(AppTab.dashboard)
                .tabItem {
                    Label("Главная", systemImage: "rectangle.grid.2x2")
                }
            PropertiesListView()
                .tag(AppTab.properties)
                .tabItem {
                    Label("Объекты", systemImage: "building.2")
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
