#if os(iOS)
import Foundation

/// Bridge used by rent-payment App Intents to reach the live `AuthManager` and
/// API client. The same enum name has a stub copy in the widget extension
/// target so the Intent file compiles in both targets, but `perform()` always
/// runs in the main app process — that's where the real implementation lives.
///
/// IMPORTANT: this file is part of the main app target only.
/// The widget extension target has `RentReminderActions+Stub.swift` with empty
/// no-op implementations of the same enum.
@MainActor
enum RentReminderActions {
    static weak var authManager: AuthManager?

    static func markPaid(scheduleId: String, amount: Double, currency: String) async throws {
        guard let auth = authManager else { return }
        try await LiveActivityAPI.markPaid(
            scheduleId: scheduleId,
            amount: amount,
            currency: currency,
            auth: auth
        )
    }

    static func snooze(scheduleId: String) async throws {
        guard let auth = authManager else { return }
        try await LiveActivityAPI.snooze(scheduleId: scheduleId, auth: auth)
    }
}
#endif
