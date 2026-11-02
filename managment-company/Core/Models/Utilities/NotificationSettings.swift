import Foundation

// `GET/PUT /v1/me/notification-settings`, `POST/DELETE /v1/me/telegram-link`.

enum NotificationChannel: FallbackStringEnum {
    case push
    case telegram
    case unknown(String)

    static var knownMapping: [(NotificationChannel, String)] { [(.push, "push"), (.telegram, "telegram")] }

    var rawValue: String {
        switch self {
        case .push: return "push"
        case .telegram: return "telegram"
        case .unknown(let raw): return raw
        }
    }

    static func makeUnknown(_ raw: String) -> NotificationChannel { .unknown(raw) }

    var unknownRaw: String? {
        if case .unknown(let raw) = self { return raw }
        return nil
    }
}

/// The events an owner can switch per channel.
enum NotificationEventType: FallbackStringEnum {
    case utilityBillMissing
    case utilityBillNeedsReview
    case utilityUploadOther
    case unknown(String)

    static var knownMapping: [(NotificationEventType, String)] {
        [
            (.utilityBillMissing, "utility_bill_missing"),
            (.utilityBillNeedsReview, "utility_bill_needs_review"),
            (.utilityUploadOther, "utility_upload_other"),
        ]
    }

    var rawValue: String {
        switch self {
        case .utilityBillMissing: return "utility_bill_missing"
        case .utilityBillNeedsReview: return "utility_bill_needs_review"
        case .utilityUploadOther: return "utility_upload_other"
        case .unknown(let raw): return raw
        }
    }

    static func makeUnknown(_ raw: String) -> NotificationEventType { .unknown(raw) }

    var unknownRaw: String? {
        if case .unknown(let raw) = self { return raw }
        return nil
    }
}

struct NotificationChannelSetting: Codable, Hashable {
    let eventType: NotificationEventType
    let channel: NotificationChannel
    var enabled: Bool

    enum CodingKeys: String, CodingKey {
        case channel, enabled
        case eventType = "event_type"
    }
}

struct NotificationTelegramStatus: Codable, Hashable {
    let linked: Bool
    let verifiedAt: String?

    enum CodingKeys: String, CodingKey {
        case linked
        case verifiedAt = "verified_at"
    }
}

struct NotificationSettings: Codable, Hashable {
    var channels: [NotificationChannelSetting]
    /// `HH:mm` of the owner's time zone; both `nil` = no quiet hours.
    var quietFrom: String?
    var quietTo: String?
    var utilityReminderDay: Int
    var utilityReminderRepeatDays: Int
    var telegram: NotificationTelegramStatus

    enum CodingKeys: String, CodingKey {
        case channels, telegram
        case quietFrom = "quiet_from"
        case quietTo = "quiet_to"
        case utilityReminderDay = "utility_reminder_day"
        case utilityReminderRepeatDays = "utility_reminder_repeat_days"
    }

    func isEnabled(_ event: NotificationEventType, _ channel: NotificationChannel) -> Bool {
        channels.first(where: { $0.eventType == event && $0.channel == channel })?.enabled ?? true
    }

    var hasQuietHours: Bool { quietFrom != nil && quietTo != nil }
}

/// `PUT` body: only what changed. `quiet_from`/`quiet_to` are sent together (both `null` clears).
struct NotificationSettingsUpdate: Encodable, Equatable {
    var channels: [NotificationChannelSetting]?
    var quiet: QuietHours?
    var utilityReminderDay: Int?
    var utilityReminderRepeatDays: Int?

    struct QuietHours: Equatable {
        var from: String?
        var to: String?
    }

    enum CodingKeys: String, CodingKey {
        case channels
        case quietFrom = "quiet_from"
        case quietTo = "quiet_to"
        case utilityReminderDay = "utility_reminder_day"
        case utilityReminderRepeatDays = "utility_reminder_repeat_days"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(channels, forKey: .channels)
        if let quiet {
            if let from = quiet.from { try c.encode(from, forKey: .quietFrom) } else { try c.encodeNil(forKey: .quietFrom) }
            if let to = quiet.to { try c.encode(to, forKey: .quietTo) } else { try c.encodeNil(forKey: .quietTo) }
        }
        try c.encodeIfPresent(utilityReminderDay, forKey: .utilityReminderDay)
        try c.encodeIfPresent(utilityReminderRepeatDays, forKey: .utilityReminderRepeatDays)
    }

    init() {}

    /// Full snapshot of the screen.
    init(settings: NotificationSettings) {
        channels = settings.channels
        quiet = QuietHours(from: settings.quietFrom, to: settings.quietTo)
        utilityReminderDay = settings.utilityReminderDay
        utilityReminderRepeatDays = settings.utilityReminderRepeatDays
    }
}

/// `POST /v1/me/telegram-link`: a one-time code for the bot.
struct TelegramLink: Codable, Hashable {
    let code: String
    let expiresAt: String
    let ttlSeconds: Int
    let deepLink: String?
    let groupDeepLink: String?
    let botUsername: String?

    enum CodingKeys: String, CodingKey {
        case code
        case expiresAt = "expires_at"
        case ttlSeconds = "ttl_seconds"
        case deepLink = "deep_link"
        case groupDeepLink = "group_deep_link"
        case botUsername = "bot_username"
    }
}
