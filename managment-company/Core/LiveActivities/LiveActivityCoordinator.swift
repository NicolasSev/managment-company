#if os(iOS)
import ActivityKit
import Combine
import Foundation
import os.log

private let liveActivityLog = Logger(subsystem: "com.nicolascooper.rentfolio", category: "LiveActivity")

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
        guard let auth = authManager, auth.isAuthenticated else {
            liveActivityLog.notice("sync skipped: not authenticated")
            return
        }
        let authInfo = ActivityAuthorizationInfo()
        guard authInfo.areActivitiesEnabled else {
            liveActivityLog.error("sync skipped: areActivitiesEnabled=false (enable Live Activities in Settings → app → Live Activities)")
            return
        }

        let allReminders = await LiveActivityAPI.fetchActiveReminders(auth: auth)
        liveActivityLog.notice("fetched \(allReminders.count) active reminders")

        // Reap orphan activities — any Live Activity whose scheduleId is no
        // longer in the active-reminders list (paid, snoozed-away, or stuck
        // with a cached empty Archive). This frees slots so push-to-start /
        // sync can start fresh ones.
        let reminderIds = Set(allReminders.map { $0.schedule_id })
        for activity in Activity<RentPaymentAttributes>.activities where !reminderIds.contains(activity.attributes.scheduleId) {
            liveActivityLog.notice("ending orphan activity id=\(activity.id, privacy: .public) schedule=\(activity.attributes.scheduleId, privacy: .public)")
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        guard !allReminders.isEmpty else { return }

        // iOS limits one app to ~5 concurrent Live Activities. Leave one slot
        // free for a backend push-to-start so the worker can still spawn the
        // most recent reminder later if a paid one frees up a slot.
        let reminders = Array(allReminders.prefix(4))
        let existing = Set(Activity<RentPaymentAttributes>.activities.map { $0.attributes.scheduleId })
        liveActivityLog.notice("currently running activities: \(existing.count)")

        for reminder in reminders {
            if existing.contains(reminder.schedule_id) {
                liveActivityLog.notice("skip \(reminder.schedule_id): already running")
                continue
            }
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
                let staleDate = Date().addingTimeInterval(4 * 60 * 60) // 4h — matches worker rearm cadence
                let activity = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: staleDate),
                    pushType: .token
                )
                liveActivityLog.notice("STARTED activity id=\(activity.id, privacy: .public) schedule=\(reminder.schedule_id, privacy: .public)")
            } catch {
                liveActivityLog.error("FAILED to start activity for schedule=\(reminder.schedule_id, privacy: .public): \(error.localizedDescription, privacy: .public)")
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
