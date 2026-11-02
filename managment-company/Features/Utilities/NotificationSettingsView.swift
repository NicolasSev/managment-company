import SwiftUI

/// Settings of the utility notifications: the channels per event, quiet hours, the day and the
/// interval of the reminders, and the Telegram link.
struct NotificationSettingsView: View {
    @StateObject private var viewModel: NotificationSettingsViewModel

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showUnlinkConfirm = false
    @State private var copied = false

    init(service: NotificationSettingsService) {
        _viewModel = StateObject(wrappedValue: NotificationSettingsViewModel(service: service))
    }

    var body: some View {
        ZStack {
            AppScreenBackground()
            content
        }
        .navigationTitle("Уведомления")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.refreshLinkStatus() } }
        }
        .sensoryFeedback(.success, trigger: viewModel.successSignal)
        .confirmationDialog("Отвязать Telegram?", isPresented: $showUnlinkConfirm, titleVisibility: .visible) {
            Button("Отвязать", role: .destructive) { Task { await viewModel.unlink() } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Напоминания в Telegram прекратятся. Push на телефон продолжат приходить.")
        }
        .accessibilityContainer("settings.notifications")
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("settings.notifications.loading")
        case .error(let text):
            EmptyStateView(
                title: "Не удалось загрузить настройки",
                message: text,
                actionName: "Повторить",
                action: { Task { await viewModel.load() } },
                icon: "wifi.exclamationmark"
            )
        case .loaded:
            if let settings = viewModel.settings {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        if let message = viewModel.message {
                            UtilityBanner(text: message, identifier: "settings.notifications.error")
                        }
                        channelsCard
                        remindersCard(settings)
                        quietHoursCard(settings)
                        telegramCard
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.md)
                }
            }
        }
    }

    // MARK: Channels

    private var channelsCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                UtilitySectionTitle(text: "Что присылать")
                ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider() }
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text(row.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Text(row.detail)
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                        Toggle("Push на телефон", isOn: channelBinding(row.event, .push, row.pushEnabled))
                            .accessibilityIdentifier("settings.notifications.\(row.event.rawValue).push")
                        Toggle("Telegram", isOn: channelBinding(row.event, .telegram, row.telegramEnabled))
                            .accessibilityIdentifier("settings.notifications.\(row.event.rawValue).telegram")
                    }
                }
                if !viewModel.isTelegramLinked {
                    Text("Telegram не привязан: сообщения туда не уйдут, пока вы не привяжете чат ниже.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
        }
    }

    private func channelBinding(_ event: NotificationEventType, _ channel: NotificationChannel, _ value: Bool) -> Binding<Bool> {
        Binding(
            get: { value },
            set: { enabled in Task { await viewModel.setChannel(event, channel, enabled: enabled) } }
        )
    }

    // MARK: Reminders

    private func remindersCard(_ settings: NotificationSettings) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                UtilitySectionTitle(text: "Напоминания о квитанции")
                Text("Если за прошлый месяц нет квитанции, напомним в выбранный день и будем повторять, пока не появится файл или отметка об оплате.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Stepper(
                    value: Binding(
                        get: { settings.utilityReminderDay },
                        set: { day in Task { await viewModel.setReminderDay(day) } }
                    ),
                    in: viewModel.reminderDayRange
                ) {
                    HStack {
                        Text("День месяца")
                        Spacer()
                        Text("\(settings.utilityReminderDay)-е число")
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(settings.utilityReminderDay)))
                            .animation(AppTheme.Motion.resolved(AppTheme.Motion.fast, reduceMotion: reduceMotion), value: settings.utilityReminderDay)
                    }
                }
                .accessibilityIdentifier("settings.notifications.reminder_day")
                Stepper(
                    value: Binding(
                        get: { settings.utilityReminderRepeatDays },
                        set: { days in Task { await viewModel.setRepeatDays(days) } }
                    ),
                    in: NotificationSettingsViewModel.repeatDays
                ) {
                    HStack {
                        Text("Повторять")
                        Spacer()
                        Text(Self.repeatText(settings.utilityReminderRepeatDays))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(settings.utilityReminderRepeatDays)))
                            .animation(AppTheme.Motion.resolved(AppTheme.Motion.fast, reduceMotion: reduceMotion), value: settings.utilityReminderRepeatDays)
                    }
                }
                .accessibilityIdentifier("settings.notifications.repeat_days")
            }
        }
    }

    /// «каждый день», «каждые 3 дня», «каждые 5 дней».
    static func repeatText(_ days: Int) -> String {
        if days == 1 { return "каждый день" }
        let last = days % 10
        let tens = days % 100
        let word = (last == 1 && tens != 11) ? "день" : ((2...4).contains(last) && !(12...14).contains(tens) ? "дня" : "дней")
        return "каждые \(days) \(word)"
    }

    // MARK: Quiet hours

    private func quietHoursCard(_ settings: NotificationSettings) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                UtilitySectionTitle(text: "Тихие часы")
                Toggle(
                    "Не беспокоить",
                    isOn: Binding(
                        get: { settings.hasQuietHours },
                        set: { enabled in
                            Task { await viewModel.setQuietHours(from: enabled ? "22:00" : nil, to: enabled ? "08:00" : nil) }
                        }
                    )
                )
                .accessibilityIdentifier("settings.notifications.quiet.toggle")
                if settings.hasQuietHours {
                    DatePicker(
                        "С",
                        selection: timeBinding(settings.quietFrom, other: settings.quietTo, isFrom: true),
                        displayedComponents: .hourAndMinute
                    )
                    .accessibilityIdentifier("settings.notifications.quiet.from")
                    DatePicker(
                        "До",
                        selection: timeBinding(settings.quietTo, other: settings.quietFrom, isFrom: false),
                        displayedComponents: .hourAndMinute
                    )
                    .accessibilityIdentifier("settings.notifications.quiet.to")
                    Text("В это время сообщения придут позже, после окончания тихих часов. Время — по вашему часовому поясу.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
        }
    }

    private func timeBinding(_ value: String?, other: String?, isFrom: Bool) -> Binding<Date> {
        Binding(
            get: { Self.date(fromTime: value) },
            set: { date in
                let text = Self.time(from: date)
                Task {
                    await viewModel.setQuietHours(from: isFrom ? text : other, to: isFrom ? other : text)
                }
            }
        )
    }

    static func date(fromTime text: String?) -> Date {
        let parts = (text ?? "00:00").split(separator: ":").compactMap { Int($0) }
        let hour = parts.first ?? 0
        let minute = parts.count > 1 ? parts[1] : 0
        return Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
    }

    static func time(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    // MARK: Telegram

    private var telegramCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                UtilitySectionTitle(text: "Telegram")
                if viewModel.isTelegramLinked {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.Colors.success)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Привязан")
                                .font(.subheadline.weight(.medium))
                            if let verified = viewModel.settings?.telegram.verifiedAt {
                                Text("с \(UtilityFormat.day(verified) ?? verified)")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("settings.notifications.telegram.linked")
                    Button { showUnlinkConfirm = true } label: {
                        Label("Отвязать", systemImage: "link.badge.minus")
                    }
                    .buttonStyle(UtilitySecondaryButtonStyle(tone: AppTheme.Colors.danger))
                    .disabled(viewModel.isWorking)
                    .accessibilityIdentifier("settings.notifications.telegram.unlink")
                } else if let link = viewModel.link {
                    linkSteps(link)
                } else {
                    Text("Привяжите чат или группу, где работает бот @RentfolioBot, чтобы получать напоминания и пересылать их дальше.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    PrimaryButton(
                        title: "Привязать Telegram",
                        action: { Task { await viewModel.startLinking() } },
                        isLoading: viewModel.isWorking,
                        systemImage: "paperplane"
                    )
                    .accessibilityIdentifier("settings.notifications.telegram.link")
                }
            }
        }
    }

    @ViewBuilder
    private func linkSteps(_ link: TelegramLink) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("Код привязки действует \(link.ttlSeconds / 60) минут")
                .font(.footnote)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Text(link.code)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .textSelection(.enabled)
                .accessibilityIdentifier("settings.notifications.telegram.code")
            if let url = viewModel.telegramURL {
                PrimaryButton(title: "Открыть Telegram", action: { openURL(url) }, systemImage: "paperplane")
                    .accessibilityIdentifier("settings.notifications.telegram.open")
            }
            if let group = viewModel.telegramGroupURL {
                Button { openURL(group) } label: {
                    Label("Добавить в группу", systemImage: "person.3")
                }
                .buttonStyle(UtilitySecondaryButtonStyle())
                .accessibilityIdentifier("settings.notifications.telegram.group")
            }
            if let command = viewModel.startCommand {
                Text("Если Telegram не открылся, отправьте боту команду \(command)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Button {
                    UIPasteboard.general.string = command
                    copied = true
                } label: {
                    Label(copied ? "Скопировано" : "Скопировать команду", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(UtilitySecondaryButtonStyle())
                .accessibilityIdentifier("settings.notifications.telegram.copy")
            }
            Button { Task { await viewModel.refreshLinkStatus() } } label: {
                Label("Проверить привязку", systemImage: "arrow.clockwise")
            }
            .buttonStyle(UtilitySecondaryButtonStyle())
            .accessibilityIdentifier("settings.notifications.telegram.check")
        }
    }
}

/// The block of `SettingsView` with the utility notifications and the Telegram link.
struct UtilitiesSettingsSection: View {
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Коммуналка")
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text("Напоминания о квитанциях, тихие часы и привязка Telegram.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                NavigationLink {
                    NotificationSettingsView(service: NotificationSettingsServiceProvider.makeService(authManager: authManager))
                } label: {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Image(systemName: "bell.badge")
                        Text("Уведомления и Telegram").fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .foregroundStyle(AppTheme.Colors.accent)
                    .padding(.vertical, AppTheme.Spacing.md)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .background(AppTheme.Colors.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.notifications.open")
            }
        }
    }
}
