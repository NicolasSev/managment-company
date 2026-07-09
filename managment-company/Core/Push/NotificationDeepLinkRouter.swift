import Combine
import Foundation
import SwiftUI

struct NotificationRoute: Identifiable, Equatable {
    enum Kind: Equatable {
        case today
        case dashboard
        case transactions
        case transaction(String)
        case properties
        case property(String)
        case tenants
        case tasks
        case task(String)
    }

    let id = UUID()
    let kind: Kind

    var tab: AppTab {
        switch kind {
        case .today:
            return .today
        case .dashboard:
            return .dashboard
        case .transactions, .transaction:
            return .transactions
        case .properties, .property:
            return .properties
        case .tenants:
            return .tenants
        case .tasks, .task:
            return .tasks
        }
    }

    var opensNestedDestination: Bool {
        switch kind {
        case .transaction, .property, .task:
            return true
        default:
            return false
        }
    }

    init(kind: Kind) {
        self.kind = kind
    }

    init(notificationType: String?, data: [String: String]) {
        let entityType = data["entity_type"]
        let entityId = data["entity_id"]
        let propertyId = data["property_id"]
        let transactionId = data["transaction_id"]
        let taskId = data["task_id"]

        if let transactionId, !transactionId.isEmpty {
            self.init(kind: .transaction(transactionId))
            return
        }

        if let taskId, !taskId.isEmpty {
            self.init(kind: .task(taskId))
            return
        }

        if notificationType == "daily_summary" || entityType == "today" {
            self.init(kind: .today)
            return
        }

        if notificationType == "rent_payment_due" || notificationType?.contains("payment") == true {
            self.init(kind: .transactions)
            return
        }

        switch entityType {
        case "task":
            if let entityId, !entityId.isEmpty {
                self.init(kind: .task(entityId))
            } else {
                self.init(kind: .tasks)
            }
        case "property":
            if let entityId, !entityId.isEmpty {
                self.init(kind: .property(entityId))
            } else {
                self.init(kind: .properties)
            }
        case "lease", "maintenance", "utility", "utility_receipt":
            if let propertyId, !propertyId.isEmpty {
                self.init(kind: .property(propertyId))
            } else {
                self.init(kind: .properties)
            }
        case "tenant":
            self.init(kind: .tenants)
        default:
            self.init(kind: .dashboard)
        }
    }
}

/// Выбор вкладки и точечного route по полезной нагрузке push/list notification.
@MainActor
final class NotificationDeepLinkRouter: ObservableObject {
    @Published var selectTab: AppTab?
    @Published var presentNotificationsInbox = false
    @Published var pendingRoute: NotificationRoute?

    func handleNotificationOpen(userInfo: [AnyHashable: Any]) {
        var data: [String: String] = [:]
        for (key, value) in userInfo {
            guard let key = key as? String else { continue }
            if let string = value as? String, !string.isEmpty {
                data[key] = string
            } else if let number = value as? NSNumber {
                data[key] = number.stringValue
            }
        }

        let route = NotificationRoute(
            notificationType: data["notification_type"] ?? data["type"],
            data: data
        )
        open(route)
    }

    func handleNotificationOpen(_ notification: AppNotification) {
        open(NotificationRoute(notificationType: notification.type, data: notification.data))
    }

    func open(_ route: NotificationRoute) {
        pendingRoute = route
        selectTab = route.tab
        presentNotificationsInbox = false
        if !route.opensNestedDestination {
            clearRoute(route)
        }
    }

    func clearTabSelection() {
        selectTab = nil
    }

    func clearRoute(_ route: NotificationRoute) {
        guard pendingRoute?.id == route.id else { return }
        pendingRoute = nil
    }
}
