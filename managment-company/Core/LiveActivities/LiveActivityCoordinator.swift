#if os(iOS)
import ActivityKit
import BackgroundTasks
import Combine
import Foundation
import os.log

private let liveActivityLog = Logger(subsystem: "com.nicolascooper.rentfolio", category: "LiveActivity")

/// Daily best-effort refresh of the push-to-start token for a rarely-opened app.
///
/// Push-to-start tokens are handed to the app only while it runs; a mostly-closed
/// app would otherwise never re-send a rotated token and the server's copy would
/// silently go stale. This schedules a `BGAppRefreshTask` roughly once a day that
/// grabs the current token and re-registers it. Best-effort by nature: iOS picks
/// the actual moment and will not run it at all while the app is force-quit — the
/// foreground path in `LiveActivityCoordinator` remains the primary refresh.
enum LiveActivityBackgroundRefresh {
    static let taskIdentifier = "com.nicolascooper.rentfolio.refresh-live-activity-token"

    /// Ask the system to run our refresh in ~24h. Registration is handled by the
    /// SwiftUI `.backgroundTask(.appRefresh:)` modifier; here we only submit the
    /// request. Call on entering background and again after each run.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(24 * 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            liveActivityLog.error("schedule token refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// One-shot body invoked from the app's `.backgroundTask` handler: restore the
    /// session from Keychain, take the current push-to-start token that ActivityKit
    /// emits on subscription, and re-register it. Respects task cancellation (the
    /// background budget) so it never hangs when no token is available.
    @available(iOS 17.2, *)
    static func run() async {
        let auth = await MainActor.run { AuthManager() }
        guard await MainActor.run(body: { auth.isAuthenticated }) else {
            liveActivityLog.notice("bg token refresh skipped: not authenticated")
            return
        }
        for await tokenData in Activity<RentPaymentAttributes>.pushToStartTokenUpdates {
            let hex = tokenData.map { String(format: "%02x", $0) }.joined()
            await LiveActivityAPI.registerStartToken(hex, auth: auth)
            liveActivityLog.notice("bg token refresh: re-registered push-to-start token")
            return
        }
    }
}

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
        // App Intents launched from a Live Activity execute in the app process,
        // but they do not receive SwiftUI environment objects. Keep the shared
        // intent bridge wired to the live auth session; without this, tapping
        // "Оплачено" returns successfully but never calls the mark-paid API.
        RentReminderActions.authManager = authManager
        startPushToStartListener()
        startActivityListener()
    }

    func stop() {
        RentReminderActions.authManager = nil
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

        guard let allReminders = await LiveActivityAPI.fetchActiveReminders(auth: auth) else {
            // Transient backend error: leave running activities alone so the
            // user does not lose the Lock Screen card while the network /
            // token recovers. The next sync will reconcile.
            liveActivityLog.notice("sync skipped: /active-reminders fetch failed")
            return
        }
        liveActivityLog.notice("fetched \(allReminders.count) active reminders")

        // iOS limits one app to ~5 concurrent Live Activities. Leave one slot
        // free for a backend push-to-start so the worker can still spawn the
        // most recent reminder later if a paid one frees up a slot.
        let reminders = Array(allReminders.prefix(4))
        let wantedIds = Set(reminders.map { $0.schedule_id })

        // End activities the backend no longer wants (paid / snoozed away).
        // For ones still in the wanted set we ALSO end them here and respawn
        // below — that drops any "orphan" duplicate iOS may be holding with a
        // cached empty WidgetRenderer Archive (created when the extension was
        // missing from an earlier build), so the Lock Screen UI re-renders
        // from the current widget binary. Either way: we only reach this loop
        // after a successful fetch, so we never wipe activities on a network
        // blip.
        for activity in Activity<RentPaymentAttributes>.activities {
            let scheduleId = activity.attributes.scheduleId
            let reason = wantedIds.contains(scheduleId) ? "respawning" : "orphan"
            liveActivityLog.notice("ending \(reason, privacy: .public) activity id=\(activity.id, privacy: .public) schedule=\(scheduleId, privacy: .public)")
            await activity.end(nil, dismissalPolicy: .immediate)
            // Report the end so the backend frees the update-token slot instead of
            // leaving it 'active' forever (stranded tokens otherwise saturate the
            // per-user cap and block backend push-to-start).
            await LiveActivityAPI.endActivity(activityId: activity.id, auth: auth)
        }

        for reminder in reminders {
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
