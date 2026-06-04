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
    @EnvironmentObject private var rentPreviewRouter: RentPreviewRouter

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
        .sheet(isPresented: Binding(
            get: { rentPreviewRouter.pendingScheduleId != nil },
            set: { isPresented in if !isPresented { rentPreviewRouter.clear() } }
        )) {
            if let scheduleId = rentPreviewRouter.pendingScheduleId {
                RentPreviewSheet(
                    scheduleId: scheduleId,
                    onPaid: { rentPreviewRouter.markPaidRecorded() },
                    onClose: { rentPreviewRouter.clear() }
                )
                .environmentObject(authManager)
                .id(scheduleId)
            }
        }
        .onOpenURL { url in
            _ = rentPreviewRouter.handle(url: url)
        }
        .task(id: authManager.isAuthenticated) {
            if authManager.isAuthenticated {
                await requestNotificationAuthorizationAndRegister()
                PendingMutationQueue.shared.startMonitoring(authManager: authManager)
                await PendingMutationQueue.shared.processQueue(authManager: authManager)
                await pushRegistration.syncRegistration(with: authManager)
                await liveActivityCoordinator.syncLocalActivities()
            } else {
                PendingMutationQueue.shared.stopMonitoring()
                DashboardOverviewCache.clear()
                pushRegistration.resetForLogout()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, authManager.isAuthenticated else { return }
            Task {
                await PendingMutationQueue.shared.processQueue(authManager: authManager)
                await pushRegistration.syncRegistration(with: authManager)
                await liveActivityCoordinator.syncLocalActivities()
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
    @StateObject private var rentPreviewRouter = RentPreviewRouter()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(authManager)
                .environmentObject(pushRegistration)
                .environmentObject(notificationRouter)
                .environmentObject(liveActivityCoordinator)
                .environmentObject(rentPreviewRouter)
                .onAppear {
                    appDelegate.deepLinkRouter = notificationRouter
                    appDelegate.authManager = authManager
                    appDelegate.onDeviceToken = { hex in
                        Task { @MainActor in
                            pushRegistration.setDeviceToken(hex)
                            await pushRegistration.syncRegistration(with: authManager)
                        }
                    }
                    RentReminderActions.authManager = authManager
                    liveActivityCoordinator.start(with: authManager)
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
    }
}
