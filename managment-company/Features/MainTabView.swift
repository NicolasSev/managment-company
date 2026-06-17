import SwiftUI

enum AppTab: Hashable {
    case today
    case money
    case dashboard
    case transactions
    case payments
    case properties
    case tenants
    case tasks
    case settings
}

struct MainTabView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject private var notificationRouter: NotificationDeepLinkRouter
    @ObservedObject private var pendingMutations = PendingMutationQueue.shared
    @ObservedObject private var overdueBadge = PaymentsOverdueBadge.shared
    @StateObject private var quickActions = QuickActionsController()
    @State private var selectedTab: AppTab = .today
    @State private var showDashboard = false
    @State private var showTenants = false
    @State private var showSettings = false
    
    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
            TodayView(authManager: authManager)
                .environmentObject(authManager)
                .tag(AppTab.today)
                .tabItem {
                    Label("Сегодня", systemImage: "sun.max")
                }
            MoneyHubView(authManager: authManager)
                .environmentObject(authManager)
                .tag(AppTab.money)
                .tabItem {
                    Label("Деньги", systemImage: "creditcard")
                }
                .badge(overdueBadge.count)
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
        }
        .tint(AppTheme.Colors.accent)
        .environmentObject(quickActions)
        // Secondary routes moved out of the primary bar (GAP-037): Dashboard,
        // Tenants, and Settings remain reachable without being primary tabs.
        .sheet(isPresented: $showDashboard) {
            DashboardView().environmentObject(authManager)
        }
        .sheet(isPresented: $showTenants) {
            TenantsListView().environmentObject(authManager)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(authManager)
        }

            QuickActionLauncher()
                .environmentObject(authManager)
                .environmentObject(quickActions)
                .environmentObject(notificationRouter)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, AppTheme.Spacing.lg)
                .padding(.bottom, 64)

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
        .onReceive(NotificationCenter.default.publisher(for: .openCompactExpense)) { _ in
            selectedTab = .today
            quickActions.open(.expense)
        }
        .onChange(of: notificationRouter.selectTab) { _, tab in
            guard let tab else { return }
            switch MainTabView.target(for: tab) {
            case .tab(let resolved): selectedTab = resolved
            case .dashboardSheet: showDashboard = true
            case .tenantsSheet: showTenants = true
            case .settingsSheet: showSettings = true
            }
            notificationRouter.clearTabSelection()
        }
    }

    /// Resolves a requested `AppTab` to a destination after the GAP-037 nav
    /// simplification: routes whose tab left the primary bar open as a secondary
    /// sheet, and the two money routes land on the «Деньги» hub.
    static func target(for tab: AppTab) -> AppNavigationTarget {
        switch tab {
        case .dashboard: return .dashboardSheet
        case .tenants: return .tenantsSheet
        case .settings: return .settingsSheet
        case .transactions, .payments: return .tab(.money)
        case .today, .money, .properties, .tasks: return .tab(tab)
        }
    }
}

/// Where a requested route lands under the GAP-037 five-position navigation.
enum AppNavigationTarget: Equatable {
    case tab(AppTab)
    case dashboardSheet
    case tenantsSheet
    case settingsSheet
}

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @ObservedObject private var expenseReminder = ExpenseReminderController.shared
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

                        expenseReminderSettings

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

    private static let weekdayLabels: [(day: Int, label: String)] = [
        (2, "Пн"), (3, "Вт"), (4, "Ср"), (5, "Чт"), (6, "Пт"), (7, "Сб"), (1, "Вс"),
    ]

    private var expenseReminderSettings: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Напоминание о расходах")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Text("Это напоминание, а не Live Activity: карточка на «Сегодня» и опциональные локальные уведомления в выбранные дни и время.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineSpacing(2)

                Toggle("Включить напоминание", isOn: Binding(
                    get: { expenseReminder.prefs.enabled },
                    set: { var p = expenseReminder.prefs; p.enabled = $0; expenseReminder.update(p) }
                ))

                if expenseReminder.prefs.enabled {
                    DatePicker(
                        "Время",
                        selection: Binding(
                            get: {
                                Calendar.current.date(
                                    from: DateComponents(hour: expenseReminder.prefs.hour, minute: expenseReminder.prefs.minute)
                                ) ?? Date()
                            },
                            set: {
                                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                                var p = expenseReminder.prefs
                                p.hour = c.hour ?? 20
                                p.minute = c.minute ?? 0
                                expenseReminder.update(p)
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )

                    HStack(spacing: 6) {
                        ForEach(Self.weekdayLabels, id: \.day) { entry in
                            let on = expenseReminder.prefs.weekdays.contains(entry.day)
                            Button(entry.label) {
                                var p = expenseReminder.prefs
                                if on { p.weekdays.remove(entry.day) } else { p.weekdays.insert(entry.day) }
                                expenseReminder.update(p)
                            }
                            .font(.caption.weight(.semibold))
                            .frame(width: 34, height: 34)
                            .background((on ? AppTheme.Colors.accent : AppTheme.Colors.accent.opacity(0.12)))
                            .foregroundStyle(on ? .white : AppTheme.Colors.accent)
                            .clipShape(Circle())
                        }
                    }
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
