import SwiftUI
import UIKit
import UserNotifications

/// UIKit-хуки для APNs (`deviceToken`) и тапов по локальному/remote-notification UI.
final class PushNotificationsAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var authManager: AuthManager?
    weak var deepLinkRouter: NotificationDeepLinkRouter?

    var onDeviceToken: ((String) -> Void)?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        Task { @MainActor in
            self.onDeviceToken?(hex)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Симулятор без capability часто не отдаёт токен — не считается ошибкой продукта.
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .badge, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor in
            guard self.authManager?.isAuthenticated == true else { return }
            self.deepLinkRouter?.handleNotificationOpen(userInfo: userInfo)
        }
        completionHandler()
    }
}
