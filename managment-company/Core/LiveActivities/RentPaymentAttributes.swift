#if os(iOS)
import ActivityKit
import Foundation

/// ActivityAttributes for the rent payment Live Activity.
///
/// The Swift type name must match the backend's `RentActivityAttributesType`
/// constant — APNs uses it as the `aps.attributes-type` key when delivering a
/// push-to-start payload.
///
/// IMPORTANT: this file is included in both the main app target and the
/// `PropManagerActivities` widget extension target via Xcode Target Membership.
struct RentPaymentAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// "awaiting" while the user has not yet confirmed payment, "paid" once
        /// the schedule is settled, "snoozed" if the user dismissed it.
        public var status: String
        public var paidAt: Date?

        public init(status: String, paidAt: Date? = nil) {
            self.status = status
            self.paidAt = paidAt
        }
    }

    public let scheduleId: String
    public let leaseId: String
    public let propertyName: String
    public let tenantName: String
    public let periodLabel: String
    public let dueDate: String
    public let amount: Double
    public let currency: String

    public init(
        scheduleId: String,
        leaseId: String,
        propertyName: String,
        tenantName: String,
        periodLabel: String,
        dueDate: String,
        amount: Double,
        currency: String
    ) {
        self.scheduleId = scheduleId
        self.leaseId = leaseId
        self.propertyName = propertyName
        self.tenantName = tenantName
        self.periodLabel = periodLabel
        self.dueDate = dueDate
        self.amount = amount
        self.currency = currency
    }
}
#endif
