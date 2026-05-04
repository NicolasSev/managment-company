import Combine
import Foundation
import SwiftUI

/// Выбор вкладки и показ inbox по полезной нагрузке push (ключи корня payload рядом с `aps`).
@MainActor
final class NotificationDeepLinkRouter: ObservableObject {
    @Published var selectTab: AppTab?
    @Published var presentNotificationsInbox = false

    func handleNotificationOpen(userInfo: [AnyHashable: Any]) {
        func str(_ key: String) -> String? {
            if let v = userInfo[key] as? String, !v.isEmpty { return v }
            return nil
        }

        let entityType = str("entity_type")
        let nType = str("notification_type") ?? str("type")

        switch entityType {
        case "task":
            selectTab = .tasks
        case "lease":
            selectTab = .properties
        default:
            if nType == "rent_payment_due" || nType?.contains("payment") == true {
                selectTab = .transactions
            } else {
                selectTab = .dashboard
            }
        }
        presentNotificationsInbox = true
    }

    func clearTabSelection() {
        selectTab = nil
    }
}
