#if os(iOS)
import Foundation

/// Stub copy of `RentReminderActions` for the widget extension target.
/// `LiveActivityIntent.perform()` runs in the app process, never in the
/// extension — but the extension's Swift compiler still needs to resolve the
/// symbols referenced from `RentPaymentIntents.swift`. This file gives it
/// no-op shims so the file compiles.
///
/// IMPORTANT: this file is part of the PropManagerActivitiesExtension target
/// only. Main app uses the real implementation in
/// `Core/LiveActivities/RentReminderActions.swift`.
@MainActor
enum RentReminderActions {
    static func markPaid(scheduleId: String, amount: Double, currency: String) async throws {}
    static func snooze(scheduleId: String) async throws {}
}
#endif
