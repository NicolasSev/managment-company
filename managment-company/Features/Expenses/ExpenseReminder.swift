import Combine
import Foundation
#if os(iOS)
import UserNotifications
#endif

/// User preferences for the opt-in daily expense reminder (GAP-038). Disabled by
/// default; weekdays use `Calendar` numbering (1 = Sunday … 7 = Saturday).
struct ExpenseReminderPreferences: Codable, Equatable {
    var enabled: Bool
    var weekdays: Set<Int>
    var hour: Int
    var minute: Int

    static let `default` = ExpenseReminderPreferences(
        enabled: false,
        weekdays: [2, 3, 4, 5, 6], // Mon–Fri
        hour: 20,
        minute: 0
    )
}

/// Drives the opt-in daily expense reminder: a dismissible Today card plus
/// optional local notifications, suppressed once an owner expense is recorded
/// that local day (GAP-038). Shared so the compact-expense flow and Today screen
/// observe the same state.
@MainActor
final class ExpenseReminderController: ObservableObject {
    static let shared = ExpenseReminderController()

    @Published private(set) var prefs: ExpenseReminderPreferences
    @Published private(set) var lastExpenseDayKey: String?
    @Published private(set) var dismissedDayKey: String?

    private let defaults: UserDefaults
    private let timeZoneIdentifier: () -> String

    private enum Key {
        static let prefs = "expenseReminder.prefs"
        static let lastExpense = "expenseReminder.lastExpenseDay"
        static let dismissed = "expenseReminder.dismissedDay"
    }

    init(
        defaults: UserDefaults = .standard,
        timeZoneIdentifier: @escaping () -> String = { "Asia/Almaty" }
    ) {
        self.defaults = defaults
        self.timeZoneIdentifier = timeZoneIdentifier
        if let data = defaults.data(forKey: Key.prefs),
           let decoded = try? JSONDecoder().decode(ExpenseReminderPreferences.self, from: data) {
            self.prefs = decoded
        } else {
            self.prefs = .default
        }
        self.lastExpenseDayKey = defaults.string(forKey: Key.lastExpense)
        self.dismissedDayKey = defaults.string(forKey: Key.dismissed)
    }

    var shouldShowCard: Bool {
        Self.shouldShowCard(
            now: Date(),
            prefs: prefs,
            expenseRecordedDayKey: lastExpenseDayKey,
            dismissedDayKey: dismissedDayKey,
            timeZoneIdentifier: timeZoneIdentifier()
        )
    }

    func update(_ newPrefs: ExpenseReminderPreferences) {
        prefs = newPrefs
        if let data = try? JSONEncoder().encode(newPrefs) {
            defaults.set(data, forKey: Key.prefs)
        }
        reschedule()
    }

    func markExpenseRecorded(now: Date = Date()) {
        let key = AppFormatting.dayKey(for: now, timeZoneIdentifier: timeZoneIdentifier())
        lastExpenseDayKey = key
        defaults.set(key, forKey: Key.lastExpense)
    }

    func dismissForToday(now: Date = Date()) {
        let key = AppFormatting.dayKey(for: now, timeZoneIdentifier: timeZoneIdentifier())
        dismissedDayKey = key
        defaults.set(key, forKey: Key.dismissed)
    }

    /// Re-arms local notifications to match the current preferences.
    func reschedule() {
        #if os(iOS)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: Self.scheduledIdentifiers)
        guard prefs.enabled else { return }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            for components in Self.triggerComponents(prefs: self.prefs) {
                let content = UNMutableNotificationContent()
                content.title = "Расходы за день"
                content.body = "Записать сегодняшние расходы по объектам?"
                content.sound = .default
                content.userInfo = ["reminder": "expense"]
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                let id = "expense-reminder-\(components.weekday ?? 0)"
                center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        }
        #endif
    }

    static let scheduledIdentifiers = (1...7).map { "expense-reminder-\($0)" }

    // MARK: - Pure logic (unit-tested)

    /// The Today card shows only when enabled, on a selected weekday, after the
    /// configured local time, when no owner expense was recorded today and the
    /// card was not dismissed for today.
    nonisolated static func shouldShowCard(
        now: Date,
        prefs: ExpenseReminderPreferences,
        expenseRecordedDayKey: String?,
        dismissedDayKey: String?,
        timeZoneIdentifier: String
    ) -> Bool {
        guard prefs.enabled else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let today = AppFormatting.dayKey(for: now, timeZoneIdentifier: timeZoneIdentifier)
        if expenseRecordedDayKey == today { return false }
        if dismissedDayKey == today { return false }
        let comps = calendar.dateComponents([.weekday, .hour, .minute], from: now)
        guard let weekday = comps.weekday, prefs.weekdays.contains(weekday) else { return false }
        let nowMinutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let targetMinutes = prefs.hour * 60 + prefs.minute
        return nowMinutes >= targetMinutes
    }

    /// One `DateComponents` per selected weekday at the configured time.
    nonisolated static func triggerComponents(prefs: ExpenseReminderPreferences) -> [DateComponents] {
        prefs.weekdays.sorted().map { weekday in
            var components = DateComponents()
            components.weekday = weekday
            components.hour = prefs.hour
            components.minute = prefs.minute
            return components
        }
    }
}
