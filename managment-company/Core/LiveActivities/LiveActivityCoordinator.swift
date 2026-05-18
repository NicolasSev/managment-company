#if os(iOS)
import ActivityKit
import Combine
import Foundation

/// Subscribes to ActivityKit token streams and reports them back to the API so
/// the backend can deliver push-to-start and update pushes for rent payment
/// Live Activities.
///
/// Lifecycle:
///   1. On launch / login, this coordinator observes
///      `Activity<RentPaymentAttributes>.pushToStartTokenUpdates` and POSTs
///      every new token to `/v1/live-activities/start-token`.
///   2. When the OS starts a new activity (via push-to-start), the coordinator
///      grabs `activityUpdates`, then for each activity observes
///      `pushTokenUpdates` and POSTs them to
///      `/v1/live-activities/:scheduleId/register`.
@MainActor
final class LiveActivityCoordinator: ObservableObject {
    private weak var authManager: AuthManager?
    private var pushToStartTask: Task<Void, Never>?
    private var activityListenerTask: Task<Void, Never>?

    func start(with authManager: AuthManager) {
        self.authManager = authManager
        startPushToStartListener()
        startActivityListener()
    }

    func stop() {
        pushToStartTask?.cancel()
        activityListenerTask?.cancel()
        pushToStartTask = nil
        activityListenerTask = nil
    }

    /// Asks the backend for currently-due rent reminders and starts a local
    /// Live Activity for each one that does not already have a running
    /// activity. This is the fallback path that bootstraps Live Activities on
    /// first use — once iOS has seen `RentPaymentAttributes` once, push-to-start
    /// payloads from the backend will also work for future cycles.
    func syncLocalActivities() async {
        guard let auth = authManager, auth.isAuthenticated else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let reminders = await LiveActivityAPI.fetchActiveReminders(auth: auth)
        guard !reminders.isEmpty else { return }

        let existing = Set(Activity<RentPaymentAttributes>.activities.map { $0.attributes.scheduleId })

        for reminder in reminders {
            if existing.contains(reminder.schedule_id) { continue }
            let attributes = RentPaymentAttributes(
                scheduleId: reminder.schedule_id,
                leaseId: reminder.lease_id,
                propertyName: reminder.property_name,
                tenantName: reminder.tenant_name,
                periodLabel: Self.periodLabel(from: reminder.period_start),
                dueDate: reminder.due_date,
                amount: reminder.expected_amount,
                currency: reminder.currency
            )
            let state = RentPaymentAttributes.ContentState(status: "awaiting")
            do {
                _ = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: .token
                )
            } catch {
                // Typically thrown when the user has disabled Live Activities
                // in Settings or the concurrent cap is reached.
            }
        }
    }

    private static func periodLabel(from periodStartISO: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        guard let date = formatter.date(from: periodStartISO) else { return periodStartISO }
        let months = ["январь", "февраль", "март", "апрель", "май", "июнь",
                      "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь"]
        let cal = Calendar(identifier: .gregorian)
        let month = cal.component(.month, from: date)
        let year = cal.component(.year, from: date)
        let name = (1...12).contains(month) ? months[month - 1] : ""
        return "\(name) \(year)".trimmingCharacters(in: .whitespaces)
    }

    private func startPushToStartListener() {
        pushToStartTask?.cancel()
        pushToStartTask = Task { [weak self] in
            guard #available(iOS 17.2, *) else { return }
            for await tokenData in Activity<RentPaymentAttributes>.pushToStartTokenUpdates {
                guard let self else { return }
                let hex = tokenData.map { String(format: "%02x", $0) }.joined()
                guard let auth = self.authManager else { continue }
                await LiveActivityAPI.registerStartToken(hex, auth: auth)
            }
        }
    }

    private func startActivityListener() {
        activityListenerTask?.cancel()
        activityListenerTask = Task { [weak self] in
            guard let self else { return }
            // Already-running activities (e.g. relaunched app).
            for activity in Activity<RentPaymentAttributes>.activities {
                observe(activity: activity)
            }
            for await activity in Activity<RentPaymentAttributes>.activityUpdates {
                self.observe(activity: activity)
            }
        }
    }

    private func observe(activity: Activity<RentPaymentAttributes>) {
        Task { [weak self] in
            for await tokenData in activity.pushTokenUpdates {
                guard let self, let auth = self.authManager else { return }
                let hex = tokenData.map { String(format: "%02x", $0) }.joined()
                await LiveActivityAPI.registerActivityToken(
                    scheduleId: activity.attributes.scheduleId,
                    activityId: activity.id,
                    pushToken: hex,
                    auth: auth
                )
            }
        }
    }
}
#endif
