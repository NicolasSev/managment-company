import SwiftUI
import UIKit
import UserNotifications

/// Обёртка с `scenePhase`, push-регистрацией и очередью мутаций после логина.
private struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var pushRegistration: PushDeviceRegistrationController
    @EnvironmentObject private var notificationRouter: NotificationDeepLinkRouter
    @EnvironmentObject private var liveActivityCoordinator: LiveActivityCoordinator

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .sheet(isPresented: $notificationRouter.presentNotificationsInbox) {
            NotificationsInboxView(onDataChanged: { })
                .environmentObject(authManager)
        }
        .task(id: authManager.isAuthenticated) {
            if authManager.isAuthenticated {
                await requestNotificationAuthorizationAndRegister()
                PendingMutationQueue.shared.startMonitoring(authManager: authManager)
                await PendingMutationQueue.shared.processQueue(authManager: authManager)
                await pushRegistration.syncRegistration(with: authManager)
                // Observe push-to-start / activity tokens and reconcile any due
                // rent Live Activities. This also re-registers a fresh
                // push-to-start token on every launch (Apple's guidance for
                // keeping the token live server-side).
                liveActivityCoordinator.start(with: authManager)
                await liveActivityCoordinator.syncLocalActivities()
            } else {
                PendingMutationQueue.shared.stopMonitoring()
                DashboardOverviewCache.clear()
                pushRegistration.resetForLogout()
                liveActivityCoordinator.stop()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                guard authManager.isAuthenticated else { return }
                Task {
                    await PendingMutationQueue.shared.processQueue(authManager: authManager)
                    await pushRegistration.syncRegistration(with: authManager)
                    await liveActivityCoordinator.syncLocalActivities()
                }
            case .background:
                // Arm the daily push-to-start token refresh so a mostly-closed
                // app keeps a live token server-side.
                LiveActivityBackgroundRefresh.schedule()
            default:
                break
            }
        }
    }

    private func requestNotificationAuthorizationAndRegister() async {
        let center = UNUserNotificationCenter.current()
        do {
            _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {}
    }
}

@main
struct managment_companyApp: App {
    @UIApplicationDelegateAdaptor(PushNotificationsAppDelegate.self) private var appDelegate
    @StateObject private var authManager = AuthManager()
    @StateObject private var pushRegistration = PushDeviceRegistrationController()
    @StateObject private var notificationRouter = NotificationDeepLinkRouter()
    @StateObject private var liveActivityCoordinator = LiveActivityCoordinator()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(authManager)
                .environmentObject(pushRegistration)
                .environmentObject(notificationRouter)
                .environmentObject(liveActivityCoordinator)
                .onAppear {
                    appDelegate.deepLinkRouter = notificationRouter
                    appDelegate.authManager = authManager
                    appDelegate.onDeviceToken = { hex in
                        Task { @MainActor in
                            pushRegistration.setDeviceToken(hex)
                            await pushRegistration.syncRegistration(with: authManager)
                        }
                    }
                }
                .onChange(of: authManager.isAuthenticated) { _, _ in
                    appDelegate.authManager = authManager
                }
                .alert(
                    "Сессия",
                    isPresented: Binding(
                        get: { authManager.sessionExpiredMessage != nil },
                        set: { if !$0 { authManager.acknowledgeSessionExpired() } }
                    )
                ) {
                    Button("OK", role: .cancel) {
                        authManager.acknowledgeSessionExpired()
                    }
                } message: {
                    Text(authManager.sessionExpiredMessage ?? "")
                }
        }
        .backgroundTask(.appRefresh(LiveActivityBackgroundRefresh.taskIdentifier)) {
            if #available(iOS 17.2, *) {
                await LiveActivityBackgroundRefresh.run()
            }
            // Re-arm for the next day at the end of every run.
            LiveActivityBackgroundRefresh.schedule()
        }
    }
}
