import Foundation

/// Lease aggregate, `GET /v1/leases/:id` and the response of every lease command (spec §9.3).
///
/// The screen reads everything about a lease from this one object. The deprecated v1-compat
/// aliases (`property_name`, `move_in_date`, `payment_day`, `payment_due_day`,
/// `payment_window_*`, top-level `terminated_at`, `auto_renew`) are intentionally not decoded:
/// the flat v2 fields carry the same data.
struct LeaseAggregate: Codable, Hashable, Identifiable {
    var id: String
    var status: LeaseStatus
    /// Optimistic-concurrency counter; sent back as `If-Match: "<version>"`.
    var version: Int
    var origin: String
    var propertyId: String
    var tenantId: String
    var renewedFromLeaseId: String?
    var replacedByLeaseId: String?
    var startDate: String
    var endDate: String?
    var activationDate: String?
    var moveOutDate: String?
    /// `rent_amount`: rent at `start_date` (later values live in `amendments`).
    var rentAmount: Money
    /// `current_rent_amount`: rent in force today.
    var currentRentAmount: Money
    var depositAmount: Money?
    var dueDay: Int
    var remindDaysBefore: Int
    var utilitiesPaidBy: UtilitiesPaidBy
    var renewalReminderDays: Int
    var prolongationCount: Int
    var nextPeriodStart: String?
    var endsInDays: Int?
    var isEndingSoon: Bool
    var notes: String?
    var terminationReason: String?
    var property: LeaseProperty
    var tenant: LeaseTenantCard
    var tenantSnapshot: LeaseTenantSnapshot?
    var propertySnapshot: LeasePropertySnapshot?
    var lifecycle: LeaseLifecycle
    var amendments: [LeaseAmendment]
    var documents: LeaseDocuments
    var balance: LeaseBalance
    var charges: [LeaseCharge]
    /// Draft/pending only: what activation would create (`id == nil`).
    var chargesPreview: [LeaseCharge]
    var payments: [LeasePayment]
    var deposit: LeaseDeposit
    var checklists: [LeaseChecklistSummary]
    var events: [LeaseEvent]
    var availableActions: [LeaseAction]

    var currency: String { rentAmount.currency }

    func can(_ action: LeaseAction) -> Bool {
        availableActions.contains(action)
    }

    /// Charges that can be paid right now, in queue order.
    var payableCharges: [LeaseCharge] {
        charges.filter { $0.canPay }
    }

    func charge(id: String) -> LeaseCharge? {
        charges.first { $0.id == id }
    }

    enum CodingKeys: String, CodingKey {
        case id, status, version, origin, notes, property, tenant, lifecycle, amendments, documents
        case balance, charges, payments, deposit, checklists, events
        case propertyId = "property_id"
        case tenantId = "tenant_id"
        case renewedFromLeaseId = "renewed_from_lease_id"
        case replacedByLeaseId = "replaced_by_lease_id"
        case startDate = "start_date"
        case endDate = "end_date"
        case activationDate = "activation_date"
        case moveOutDate = "move_out_date"
        case rentAmount = "rent_amount"
        case rentCurrency = "rent_currency"
        case currentRentAmount = "current_rent_amount"
        case depositAmount = "deposit_amount"
        case depositCurrency = "deposit_currency"
        case dueDay = "due_day"
        case remindDaysBefore = "remind_days_before"
        case utilitiesPaidBy = "utilities_paid_by"
        case renewalReminderDays = "renewal_reminder_days"
        case prolongationCount = "prolongation_count"
        case nextPeriodStart = "next_period_start"
        case endsInDays = "ends_in_days"
        case isEndingSoon = "is_ending_soon"
        case terminationReason = "termination_reason"
        case tenantSnapshot = "tenant_snapshot"
        case propertySnapshot = "property_snapshot"
        case chargesPreview = "charges_preview"
        case availableActions = "available_actions"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rentCurrency = try c.decode(String.self, forKey: .rentCurrency)
        id = try c.decode(String.self, forKey: .id)
        status = try c.decode(LeaseStatus.self, forKey: .status)
        version = try c.decode(Int.self, forKey: .version)
        origin = try c.decodeIfPresent(String.self, forKey: .origin) ?? "v2"
        propertyId = try c.decode(String.self, forKey: .propertyId)
        tenantId = try c.decode(String.self, forKey: .tenantId)
        renewedFromLeaseId = try c.decodeIfPresent(String.self, forKey: .renewedFromLeaseId)
        replacedByLeaseId = try c.decodeIfPresent(String.self, forKey: .replacedByLeaseId)
        startDate = try c.decode(String.self, forKey: .startDate)
        endDate = try c.decodeIfPresent(String.self, forKey: .endDate)
        activationDate = try c.decodeIfPresent(String.self, forKey: .activationDate)
        moveOutDate = try c.decodeIfPresent(String.self, forKey: .moveOutDate)
        rentAmount = try c.decodeMoney(.rentAmount, currency: rentCurrency)
        currentRentAmount = try c.decodeMoney(.currentRentAmount, currency: rentCurrency)
        let depositCurrency = try c.decodeIfPresent(String.self, forKey: .depositCurrency) ?? rentCurrency
        depositAmount = try c.decodeMoneyIfPresent(.depositAmount, currency: depositCurrency)
        dueDay = try c.decode(Int.self, forKey: .dueDay)
        remindDaysBefore = try c.decode(Int.self, forKey: .remindDaysBefore)
        utilitiesPaidBy = try c.decode(UtilitiesPaidBy.self, forKey: .utilitiesPaidBy)
        renewalReminderDays = try c.decode(Int.self, forKey: .renewalReminderDays)
        prolongationCount = try c.decode(Int.self, forKey: .prolongationCount)
        nextPeriodStart = try c.decodeIfPresent(String.self, forKey: .nextPeriodStart)
        endsInDays = try c.decodeIfPresent(Int.self, forKey: .endsInDays)
        isEndingSoon = try c.decode(Bool.self, forKey: .isEndingSoon)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        terminationReason = try c.decodeIfPresent(String.self, forKey: .terminationReason)
        property = try c.decode(LeaseProperty.self, forKey: .property)
        tenant = try c.decode(LeaseTenantCard.self, forKey: .tenant)
        tenantSnapshot = try c.decodeIfPresent(LeaseTenantSnapshot.self, forKey: .tenantSnapshot)
        propertySnapshot = try c.decodeIfPresent(LeasePropertySnapshot.self, forKey: .propertySnapshot)
        lifecycle = try c.decode(LeaseLifecycle.self, forKey: .lifecycle)

        var amendmentList: [LeaseAmendment] = []
        var amendmentContainer = try c.nestedUnkeyedContainer(forKey: .amendments)
        while !amendmentContainer.isAtEnd {
            amendmentList.append(try LeaseAmendment(from: amendmentContainer.superDecoder(), currency: rentCurrency))
        }
        amendments = amendmentList

        documents = try c.decode(LeaseDocuments.self, forKey: .documents)
        balance = try c.decode(LeaseBalance.self, forKey: .balance)
        charges = try c.decode([LeaseCharge].self, forKey: .charges)
        chargesPreview = try c.decodeIfPresent([LeaseCharge].self, forKey: .chargesPreview) ?? []
        payments = try c.decode([LeasePayment].self, forKey: .payments)
        deposit = try c.decode(LeaseDeposit.self, forKey: .deposit)
        checklists = try c.decodeIfPresent([LeaseChecklistSummary].self, forKey: .checklists) ?? []
        events = try c.decode([LeaseEvent].self, forKey: .events)
        availableActions = try c.decode([LeaseAction].self, forKey: .availableActions)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(status, forKey: .status)
        try c.encode(version, forKey: .version)
        try c.encode(origin, forKey: .origin)
        try c.encode(propertyId, forKey: .propertyId)
        try c.encode(tenantId, forKey: .tenantId)
        try c.encode(renewedFromLeaseId, forKey: .renewedFromLeaseId)
        try c.encode(replacedByLeaseId, forKey: .replacedByLeaseId)
        try c.encode(startDate, forKey: .startDate)
        try c.encode(endDate, forKey: .endDate)
        try c.encode(activationDate, forKey: .activationDate)
        try c.encode(moveOutDate, forKey: .moveOutDate)
        try c.encodeMoney(rentAmount, forKey: .rentAmount)
        try c.encode(rentAmount.currency, forKey: .rentCurrency)
        try c.encodeMoney(currentRentAmount, forKey: .currentRentAmount)
        try c.encodeMoneyIfPresent(depositAmount, forKey: .depositAmount)
        try c.encodeIfPresent(depositAmount?.currency, forKey: .depositCurrency)
        try c.encode(dueDay, forKey: .dueDay)
        try c.encode(remindDaysBefore, forKey: .remindDaysBefore)
        try c.encode(utilitiesPaidBy, forKey: .utilitiesPaidBy)
        try c.encode(renewalReminderDays, forKey: .renewalReminderDays)
        try c.encode(prolongationCount, forKey: .prolongationCount)
        try c.encode(nextPeriodStart, forKey: .nextPeriodStart)
        try c.encode(endsInDays, forKey: .endsInDays)
        try c.encode(isEndingSoon, forKey: .isEndingSoon)
        try c.encode(notes, forKey: .notes)
        try c.encode(terminationReason, forKey: .terminationReason)
        try c.encode(property, forKey: .property)
        try c.encode(tenant, forKey: .tenant)
        try c.encode(tenantSnapshot, forKey: .tenantSnapshot)
        try c.encode(propertySnapshot, forKey: .propertySnapshot)
        try c.encode(lifecycle, forKey: .lifecycle)
        try c.encode(amendments, forKey: .amendments)
        try c.encode(documents, forKey: .documents)
        try c.encode(balance, forKey: .balance)
        try c.encode(charges, forKey: .charges)
        try c.encode(chargesPreview, forKey: .chargesPreview)
        try c.encode(payments, forKey: .payments)
        try c.encode(deposit, forKey: .deposit)
        try c.encode(checklists, forKey: .checklists)
        try c.encode(events, forKey: .events)
        try c.encode(availableActions, forKey: .availableActions)
    }
}
