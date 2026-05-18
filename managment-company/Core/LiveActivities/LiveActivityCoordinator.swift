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
