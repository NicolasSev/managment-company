import Combine
import Foundation

enum NotificationSettingsState: Equatable {
    case loading
    case loaded
    case error(String)
}

/// A row of the channel matrix: an event and its two switches.
struct NotificationEventRow: Equatable, Identifiable {
    let event: NotificationEventType
    let title: String
    let detail: String
    let pushEnabled: Bool
    let telegramEnabled: Bool

    var id: String { event.rawValue }
}

/// State and commands of `NotificationSettingsView`. Every change goes to the server at once as a
/// partial `PUT`; the answer is what the screen shows, so a refused change snaps back.
@MainActor
final class NotificationSettingsViewModel: ObservableObject {
    @Published private(set) var state: NotificationSettingsState = .loading
    @Published private(set) var settings: NotificationSettings?
    @Published private(set) var link: TelegramLink?
    @Published private(set) var isWorking = false
    @Published var message: String?
    @Published private(set) var successSignal = 0

    private let service: NotificationSettingsService
    private let reminderDays: ClosedRange<Int>

    /// 1...30 days is the range the API accepts for the repeat interval.
    static let repeatDays = 1...30

    init(service: NotificationSettingsService, reminderDays: ClosedRange<Int> = 1...28) {
        self.service = service
        self.reminderDays = reminderDays
    }

    var reminderDayRange: ClosedRange<Int> { reminderDays }
    var isTelegramLinked: Bool { settings?.telegram.linked == true }

    /// The three events in the order of the notification settings; the texts are the owner's words.
    var rows: [NotificationEventRow] {
        guard let settings else { return [] }
        let events: [(NotificationEventType, String, String)] = [
            (.utilityBillMissing, "Нет квитанции", "Напоминание, пока за месяц нет квитанции или отметки об оплате"),
            (.utilityBillNeedsReview, "Счёт ждёт проверки", "Квитанция распознана, её нужно проверить и подтвердить"),
            (.utilityUploadOther, "Файл не похож на счёт", "Загруженный файл не коммунальная квитанция: нужно решение"),
        ]
        return events.map { event, title, detail in
            NotificationEventRow(
                event: event, title: title, detail: detail,
                pushEnabled: settings.isEnabled(event, .push),
                telegramEnabled: settings.isEnabled(event, .telegram)
            )
        }
    }

    func load() async {
        if settings == nil { state = .loading }
        do {
            settings = try await service.settings()
            state = .loaded
        } catch let error as UtilityBillsError {
            if settings == nil { state = .error(error.userMessage) } else { message = error.userMessage }
        } catch {
            if settings == nil { state = .error(UtilityBillsError.unknown.userMessage) } else { message = UtilityBillsError.unknown.userMessage }
        }
    }

    // MARK: Changes

    func setChannel(_ event: NotificationEventType, _ channel: NotificationChannel, enabled: Bool) async {
        var update = NotificationSettingsUpdate()
        update.channels = [NotificationChannelSetting(eventType: event, channel: channel, enabled: enabled)]
        await send(update)
    }

    /// Quiet hours on or off; `from`/`to` are `HH:mm` of the owner's time zone.
    func setQuietHours(from: String?, to: String?) async {
        var update = NotificationSettingsUpdate()
        update.quiet = NotificationSettingsUpdate.QuietHours(from: from, to: to)
        await send(update)
    }

    func setReminderDay(_ day: Int) async {
        guard reminderDays.contains(day), day != settings?.utilityReminderDay else { return }
        var update = NotificationSettingsUpdate()
        update.utilityReminderDay = day
        await send(update)
    }

    func setRepeatDays(_ days: Int) async {
        guard Self.repeatDays.contains(days), days != settings?.utilityReminderRepeatDays else { return }
        var update = NotificationSettingsUpdate()
        update.utilityReminderRepeatDays = days
        await send(update)
    }

    private func send(_ update: NotificationSettingsUpdate) async {
        message = nil
        do {
            settings = try await service.update(update)
            successSignal += 1
        } catch let error as UtilityBillsError {
            message = error.userMessage
            await load()
        } catch {
            message = UtilityBillsError.unknown.userMessage
            await load()
        }
    }

    // MARK: Telegram

    /// «Привязать»: asks for a one-time code; the owner opens the bot with it.
    func startLinking() async {
        guard !isWorking else { return }
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            link = try await service.issueTelegramLink()
        } catch let error as UtilityBillsError {
            message = error.userMessage
        } catch {
            message = UtilityBillsError.unknown.userMessage
        }
    }

    /// The bot completes the link on the server; the app asks again when the owner comes back.
    func refreshLinkStatus() async {
        guard link != nil || !isTelegramLinked else { return }
        await load()
        if isTelegramLinked { link = nil }
    }

    func unlink() async {
        guard !isWorking else { return }
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            try await service.unlinkTelegram()
            link = nil
            await load()
        } catch let error as UtilityBillsError {
            message = error.userMessage
        } catch {
            message = UtilityBillsError.unknown.userMessage
        }
    }

    /// The private-chat deep link (`https://t.me/<bot>?start=<code>`), opened with `openURL`.
    var telegramURL: URL? {
        link?.deepLink.flatMap(URL.init(string:))
    }

    var telegramGroupURL: URL? {
        link?.groupDeepLink.flatMap(URL.init(string:))
    }

    /// The command to type when the deep link cannot be used.
    var startCommand: String? {
        link.map { "/start \($0.code)" }
    }
}
