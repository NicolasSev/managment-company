#if os(iOS)
import Foundation

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
