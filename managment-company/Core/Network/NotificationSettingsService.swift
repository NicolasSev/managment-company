import Foundation

/// `GET/PUT /v1/me/notification-settings` and the Telegram link (`POST/DELETE /v1/me/telegram-link`).
/// Live over `APIClient`, Mock over the contract fixtures.
protocol NotificationSettingsService {
    func settings() async throws -> NotificationSettings
    func update(_ update: NotificationSettingsUpdate) async throws -> NotificationSettings
    /// A one-time code (15 minutes) and the deep links that open the bot.
    func issueTelegramLink() async throws -> TelegramLink
    func unlinkTelegram() async throws
}

final class LiveNotificationSettingsService: NotificationSettingsService {
    private let authManager: AuthManager

    init(authManager: AuthManager) {
        self.authManager = authManager
    }

    func settings() async throws -> NotificationSettings {
        try await send("/v1/me/notification-settings")
    }

    func update(_ update: NotificationSettingsUpdate) async throws -> NotificationSettings {
        try await send("/v1/me/notification-settings", method: "PUT", body: update)
    }

    func issueTelegramLink() async throws -> TelegramLink {
        try await send("/v1/me/telegram-link", method: "POST", body: EmptyJSONBody())
    }

    func unlinkTelegram() async throws {
        let auth = authManager
        do {
            _ = try await APIClient.shared.requestData(
                "/v1/me/telegram-link",
                method: "DELETE",
                typedErrors: true,
                tokenProvider: { await MainActor.run { auth.accessToken } },
                refreshAndRetry: { await auth.refreshToken() }
            )
        } catch {
            throw LiveUtilityBillsService.map(error)
        }
    }

    private func send<T: Decodable>(_ path: String, method: String = "GET", body: Encodable? = nil) async throws -> T {
        let auth = authManager
        do {
            return try await APIClient.shared.request(
                path,
                method: method,
                body: body,
                typedErrors: true,
                tokenProvider: { await MainActor.run { auth.accessToken } },
                refreshAndRetry: { await auth.refreshToken() }
            )
        } catch {
            throw LiveUtilityBillsService.map(error)
        }
    }
}

/// Settings kept in memory over the fixtures (`settings`, `telegram-link`): linking is simulated, the
/// «привязан» state flips when `completeLink` is called (the bot does that on the server).
final class MockNotificationSettingsService: NotificationSettingsService {
    var latency: Duration
    var failure: UtilityBillsError?
    private(set) var current: NotificationSettings
    private(set) var updates: [NotificationSettingsUpdate] = []
    private(set) var unlinkCalls = 0
    private let link: TelegramLink

    init(latency: Duration = .zero, linked: Bool = false) throws {
        self.latency = latency
        var base = try UtilityFixtures.decode(NotificationSettings.self, named: "settings")
        if !linked { base.telegram = NotificationTelegramStatus(linked: false, verifiedAt: nil) }
        current = base
        link = try UtilityFixtures.decode(TelegramLink.self, named: "telegram-link")
    }

    static func fromFixtures(latency: Duration = .zero, linked: Bool = false) -> MockNotificationSettingsService {
        if let mock = try? MockNotificationSettingsService(latency: latency, linked: linked) { return mock }
        return MockNotificationSettingsService(fallback: latency)
    }

    private init(fallback latency: Duration) {
        self.latency = latency
        current = NotificationSettings(
            channels: [], quietFrom: nil, quietTo: nil, utilityReminderDay: 10, utilityReminderRepeatDays: 3,
            telegram: NotificationTelegramStatus(linked: false, verifiedAt: nil)
        )
        link = TelegramLink(code: "K7M2Q9XW4HPD", expiresAt: "2026-11-02T10:05:00Z", ttlSeconds: 900, deepLink: nil, groupDeepLink: nil, botUsername: nil)
    }

    func settings() async throws -> NotificationSettings {
        try await pause()
        return current
    }

    func update(_ update: NotificationSettingsUpdate) async throws -> NotificationSettings {
        try await pause()
        updates.append(update)
        if let channels = update.channels {
            for item in channels {
                if let index = current.channels.firstIndex(where: { $0.eventType == item.eventType && $0.channel == item.channel }) {
                    current.channels[index].enabled = item.enabled
                } else {
                    current.channels.append(item)
                }
            }
        }
        if let quiet = update.quiet {
            current.quietFrom = quiet.from
            current.quietTo = quiet.to
        }
        if let day = update.utilityReminderDay { current.utilityReminderDay = day }
        if let repeatDays = update.utilityReminderRepeatDays { current.utilityReminderRepeatDays = repeatDays }
        return current
    }

    func issueTelegramLink() async throws -> TelegramLink {
        try await pause()
        return link
    }

    func unlinkTelegram() async throws {
        try await pause()
        unlinkCalls += 1
        current.telegram = NotificationTelegramStatus(linked: false, verifiedAt: nil)
    }

    /// What the bot does on the server after `/start <code>`.
    func completeLink() {
        current.telegram = NotificationTelegramStatus(linked: true, verifiedAt: "2026-11-02T09:55:12Z")
    }

    private func pause() async throws {
        if latency > .zero { try await Task.sleep(for: latency) }
        if let failure {
            self.failure = nil
            throw failure
        }
    }
}

@MainActor
enum NotificationSettingsServiceProvider {
    private static var sharedMock: MockNotificationSettingsService?

    static func makeService(authManager: AuthManager) -> NotificationSettingsService {
        if UtilityBillsServiceProvider.isMocked { return mock() }
        return LiveNotificationSettingsService(authManager: authManager)
    }

    static func mock() -> MockNotificationSettingsService {
        if let sharedMock { return sharedMock }
        let mock = MockNotificationSettingsService.fromFixtures(latency: .milliseconds(200))
        sharedMock = mock
        return mock
    }
}
