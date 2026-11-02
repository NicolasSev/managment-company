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
        /// A utility bill from a push (`utility_bill_needs_review`, `utility_bill_missing`).
        case utilityBill(billId: String, propertyId: String?)
        /// The review inbox of the utilities (`utility_upload_other`, or a push without a bill).
        case utilitiesInbox
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
        case .utilityBill, .utilitiesInbox:
            return .utilities
        }
    }

    var opensNestedDestination: Bool {
        switch kind {
        case .transaction, .property, .task, .utilityBill, .utilitiesInbox:
            return true
        default:
            return false
        }
    }

    init(kind: Kind) {
        self.kind = kind
    }

    /// Push types of the utility bills. The reminder for a missing receipt is sent as
    /// `utility_bill_missing`; `utility_missing_reminder` is accepted as its alias.
    private static let utilityBillTypes: Set<String> = [
        "utility_bill_needs_review", "utility_bill_missing", "utility_missing_reminder",
    ]

    /// Where a utility push leads: the bill when the payload names one, else the inbox.
    static func utilityKind(notificationType: String?, data: [String: String]) -> Kind? {
        let type = notificationType ?? data["event_type"]
        let entityType = data["entity_type"]
        let isBill = type.map(utilityBillTypes.contains) == true || entityType == "utility_bill"
        let isInbox = type == "utility_upload_other" || entityType == "document_extraction"
        guard isBill || isInbox else { return nil }
        if isBill {
            let billId = data["bill_id"] ?? (entityType == "utility_bill" ? data["entity_id"] : nil)
            if let billId, !billId.isEmpty {
                let propertyId = data["property_id"].flatMap { $0.isEmpty ? nil : $0 }
                return .utilityBill(billId: billId, propertyId: propertyId)
            }
        }
        return .utilitiesInbox
    }

    init(notificationType: String?, data: [String: String]) {
        let entityType = data["entity_type"]
        let entityId = data["entity_id"]
        let propertyId = data["property_id"]
        let transactionId = data["transaction_id"]
        let taskId = data["task_id"]

        if let utility = Self.utilityKind(notificationType: notificationType, data: data) {
            self.init(kind: utility)
            return
        }

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
