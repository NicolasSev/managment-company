#if os(iOS)
import Foundation
import os.log

private let liveActivityAPILog = Logger(subsystem: "com.nicolascooper.rentfolio", category: "LiveActivity")

/// Lightweight helpers that wrap the rent-payment endpoints used by Live Activity
/// intents and the coordinator. They use the shared `APIClient` so JWT
/// refresh / retry behaviour is identical to the rest of the app.
@MainActor
enum LiveActivityAPI {
    struct EmptyResponse: Decodable {}

    struct RegisterStartTokenBody: Encodable {
        let token: String
    }

    struct RegisterActivityBody: Encodable {
        let activity_id: String
        let push_token: String
    }

    struct MarkPaidBody: Encodable {
        let amount: Double?
        let currency: String?
        let payment_date: String?
        let notes: String?
    }

    static func registerStartToken(_ token: String, auth: AuthManager) async {
        guard auth.isAuthenticated else { return }
        do {
            _ = try await APIClient.shared.requestData(
                "/v1/live-activities/start-token",
                method: "POST",
                body: RegisterStartTokenBody(token: token),
                tokenProvider: { auth.accessToken },
                refreshAndRetry: { await auth.refreshToken() }
            )
        } catch {
            // Best-effort: next foreground will retry from the coordinator.
        }
    }

    static func registerActivityToken(scheduleId: String, activityId: String, pushToken: String, auth: AuthManager) async {
        guard auth.isAuthenticated else { return }
        do {
            _ = try await APIClient.shared.requestData(
                "/v1/live-activities/\(scheduleId)/register",
                method: "POST",
                body: RegisterActivityBody(activity_id: activityId, push_token: pushToken),
                tokenProvider: { auth.accessToken },
                refreshAndRetry: { await auth.refreshToken() }
            )
        } catch {
            // best-effort
        }
    }

    static func markPaid(scheduleId: String, amount: Double, currency: String, auth: AuthManager) async throws {
        let today = ISO8601DateFormatter.dayString(from: Date())
        let idempotency = "live-activity-\(scheduleId)-\(today)"
        _ = try await APIClient.shared.requestData(
            "/v1/payment-schedules/\(scheduleId)/mark-paid",
            method: "POST",
            body: MarkPaidBody(amount: amount, currency: currency, payment_date: today, notes: "Live Activity"),
            idempotencyKey: idempotency,
            tokenProvider: { auth.accessToken },
            refreshAndRetry: { await auth.refreshToken() }
        )
    }

    static func snooze(scheduleId: String, auth: AuthManager) async throws {
        _ = try await APIClient.shared.requestData(
            "/v1/payment-schedules/\(scheduleId)/snooze",
            method: "POST",
            body: Optional<String>.none as Encodable?,
            tokenProvider: { auth.accessToken },
            refreshAndRetry: { await auth.refreshToken() }
        )
    }

    /// One row from `GET /v1/payment-schedules/active-reminders`.
    struct ActiveReminder: Decodable {
        let schedule_id: String
        let lease_id: String
        let property_name: String
        let tenant_name: String
        let due_date: String
        let period_start: String
        let expected_amount: Double
        let currency: String
    }

    private struct ActiveRemindersEnvelope: Decodable {
        let data: [ActiveReminder]
    }

    /// Returns `nil` when the backend call genuinely failed (network/auth/decode)
    /// so the coordinator can distinguish "empty success" from "we don't know"
    /// and avoid tearing down running Live Activities on a transient error.
    static func fetchActiveReminders(auth: AuthManager) async -> [ActiveReminder]? {
        guard auth.isAuthenticated else {
            liveActivityAPILog.notice("fetchActiveReminders: not authenticated")
            return nil
        }
        do {
            let data = try await APIClient.shared.requestData(
                "/v1/payment-schedules/active-reminders",
                method: "GET",
                tokenProvider: { auth.accessToken },
                refreshAndRetry: { await auth.refreshToken() }
            )
            let envelope = try JSONDecoder().decode(ActiveRemindersEnvelope.self, from: data)
            liveActivityAPILog.notice("/active-reminders returned \(envelope.data.count, privacy: .public) row(s)")
            return envelope.data
        } catch {
            liveActivityAPILog.error("/active-reminders FAILED: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

private extension ISO8601DateFormatter {
    static func dayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(identifier: "Asia/Almaty")
        return formatter.string(from: date)
    }
}
#endif
