#if os(iOS)
import ActivityKit
import AppIntents
import Foundation

/// App Intent invoked when the user taps "Оплачено" inside the Live Activity.
/// `LiveActivityIntent.perform()` always runs in the main app process — the
/// widget extension just compiles the type declaration so it can wire up the
/// SwiftUI Button. The shared `RentReminderActions` enum has a stub copy in
/// the extension target with empty implementations.
struct MarkRentPaidIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Записать оплату"
    static var description = IntentDescription("Записывает оплату аренды и закрывает напоминание.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "scheduleId") var scheduleId: String
    @Parameter(title: "amount") var amount: Double
    @Parameter(title: "currency") var currency: String

    init() {}

    init(scheduleId: String, amount: Double, currency: String) {
        self.scheduleId = scheduleId
        self.amount = amount
        self.currency = currency
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await RentReminderActions.markPaid(scheduleId: scheduleId, amount: amount, currency: currency)
        // Best-effort local end; the backend will also push an `end` update.
        for activity in Activity<RentPaymentAttributes>.activities where activity.attributes.scheduleId == scheduleId {
            await activity.end(
                ActivityContent(state: .init(status: "paid", paidAt: Date()), staleDate: nil),
                dismissalPolicy: .after(.now + 30)
            )
        }
        return .result()
    }
}

/// App Intent invoked when the user taps "Не оплачено". Snoozes the reminder
/// for 4 hours and closes the running activity.
struct MarkRentNotPaidIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Отложить напоминание"
    static var description = IntentDescription("Откладывает напоминание о платеже на 4 часа.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "scheduleId") var scheduleId: String

    init() {}

    init(scheduleId: String) {
        self.scheduleId = scheduleId
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await RentReminderActions.snooze(scheduleId: scheduleId)
        for activity in Activity<RentPaymentAttributes>.activities where activity.attributes.scheduleId == scheduleId {
            await activity.end(
                ActivityContent(state: .init(status: "snoozed"), staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
        return .result()
    }
}
#endif
