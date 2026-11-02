import Foundation

/// `GET /v1/tenants/:id/overview?months=N` (spec §9.5). Read-only, so `Decodable` only.
struct TenantOverview: Decodable, Hashable {
    var asOf: String
    var windowFrom: String
    var windowTo: String
    var tenant: TenantOverviewProfile
    var currentLease: LeaseCard?
    var leases: [LeaseCard]
    var totals: [TenantTotals]
    var months: [TenantMonth]

    enum CodingKeys: String, CodingKey {
        case window, tenant, leases, totals, months
        case asOf = "as_of"
        case currentLease = "current_lease"
    }

    enum WindowKeys: String, CodingKey {
        case from, to
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        asOf = try c.decode(String.self, forKey: .asOf)
        let window = try c.nestedContainer(keyedBy: WindowKeys.self, forKey: .window)
        windowFrom = try window.decode(String.self, forKey: .from)
        windowTo = try window.decode(String.self, forKey: .to)
        tenant = try c.decode(TenantOverviewProfile.self, forKey: .tenant)
        currentLease = try c.decodeIfPresent(LeaseCard.self, forKey: .currentLease)
        leases = try c.decode([LeaseCard].self, forKey: .leases)
        totals = try c.decode([TenantTotals].self, forKey: .totals)
        months = try c.decode([TenantMonth].self, forKey: .months)
    }
}

struct TenantOverviewProfile: Decodable, Hashable {
    var id: String
    var firstName: String?
    var lastName: String?
    var middleName: String?
    var fullName: String
    var phone: String?
    var email: String?
    var iin: String?
    var documentType: String?
    var documentNumber: String?
    var documentIssuedBy: String?
    var documentIssuedAt: String?
    var birthDate: String?
    var registrationAddress: String?
    var cohabitants: String?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case id, phone, email, iin, cohabitants, notes
        case firstName = "first_name"
        case lastName = "last_name"
        case middleName = "middle_name"
        case fullName = "full_name"
        case documentType = "document_type"
        case documentNumber = "document_number"
        case documentIssuedBy = "document_issued_by"
        case documentIssuedAt = "document_issued_at"
        case birthDate = "birth_date"
        case registrationAddress = "registration_address"
    }
}

/// Lease card of the tenant overview: the aggregate without charges, payments and events.
struct LeaseCard: Decodable, Hashable, Identifiable {
    struct Balance: Hashable {
        var currency: String
        var outstanding: Money
        var overdue: Money
        var tenantCredit: Money
        var nextCharge: LeaseNextCharge?
    }

    struct Deposit: Hashable {
        var amount: Money
        var held: Money
        var status: DepositStatus
    }

    var id: String
    var status: LeaseStatus
    var property: LeaseProperty
    /// Present on `GET /v1/leases` summaries (spec §9.4); the tenant overview omits it.
    var tenant: LeaseTenantCard?
    var startDate: String
    var endDate: String?
    var activationDate: String?
    var moveOutDate: String?
    var currentRentAmount: Money
    var dueDay: Int
    var prolongationCount: Int
    var endsInDays: Int?
    var isEndingSoon: Bool
    var balance: Balance
    var deposit: Deposit
    var availableActions: [LeaseAction]

    enum CodingKeys: String, CodingKey {
        case id, status, property, tenant, balance, deposit
        case startDate = "start_date"
        case endDate = "end_date"
        case activationDate = "activation_date"
        case moveOutDate = "move_out_date"
        case currentRentAmount = "current_rent_amount"
        case rentCurrency = "rent_currency"
        case dueDay = "due_day"
        case prolongationCount = "prolongation_count"
        case endsInDays = "ends_in_days"
        case isEndingSoon = "is_ending_soon"
        case availableActions = "available_actions"
    }

    private enum BalanceKeys: String, CodingKey {
        case currency, outstanding, overdue
        case tenantCredit = "tenant_credit"
        case nextCharge = "next_charge"
    }

    private enum DepositKeys: String, CodingKey {
        case amount, held, status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let currency = try c.decode(String.self, forKey: .rentCurrency)
        id = try c.decode(String.self, forKey: .id)
        status = try c.decode(LeaseStatus.self, forKey: .status)
        property = try c.decode(LeaseProperty.self, forKey: .property)
        tenant = try c.decodeIfPresent(LeaseTenantCard.self, forKey: .tenant)
        startDate = try c.decode(String.self, forKey: .startDate)
        endDate = try c.decodeIfPresent(String.self, forKey: .endDate)
        activationDate = try c.decodeIfPresent(String.self, forKey: .activationDate)
        moveOutDate = try c.decodeIfPresent(String.self, forKey: .moveOutDate)
        currentRentAmount = try c.decodeMoney(.currentRentAmount, currency: currency)
        dueDay = try c.decode(Int.self, forKey: .dueDay)
        prolongationCount = try c.decode(Int.self, forKey: .prolongationCount)
        endsInDays = try c.decodeIfPresent(Int.self, forKey: .endsInDays)
        isEndingSoon = try c.decode(Bool.self, forKey: .isEndingSoon)
        availableActions = try c.decode([LeaseAction].self, forKey: .availableActions)

        let b = try c.nestedContainer(keyedBy: BalanceKeys.self, forKey: .balance)
        let balanceCurrency = try b.decode(String.self, forKey: .currency)
        var next: LeaseNextCharge?
        if b.contains(.nextCharge), try !b.decodeNil(forKey: .nextCharge) {
            next = try LeaseNextCharge(from: b.superDecoder(forKey: .nextCharge), currency: balanceCurrency)
        }
        balance = Balance(
            currency: balanceCurrency,
            outstanding: try b.decodeMoney(.outstanding, currency: balanceCurrency),
            overdue: try b.decodeMoney(.overdue, currency: balanceCurrency),
            tenantCredit: try b.decodeMoney(.tenantCredit, currency: balanceCurrency),
            nextCharge: next
        )

        let d = try c.nestedContainer(keyedBy: DepositKeys.self, forKey: .deposit)
        deposit = Deposit(
            amount: try d.decodeMoney(.amount, currency: currency),
            held: try d.decodeMoney(.held, currency: currency),
            status: try d.decode(DepositStatus.self, forKey: .status)
        )
    }
}

/// Per-currency totals (`totals[]`).
struct TenantTotals: Decodable, Hashable {
    var currency: String
    var chargedToDate: Money
    var waivedToDate: Money
    var paidToDate: Money
    var outstanding: Money
    var overdue: Money
    var upcoming: Money
    var prepaid: Money
    var tenantCredit: Money
    var receivedTotal: Money
    var depositHeld: Money

    enum CodingKeys: String, CodingKey {
        case currency, outstanding, overdue, upcoming, prepaid
        case chargedToDate = "charged_to_date"
        case waivedToDate = "waived_to_date"
        case paidToDate = "paid_to_date"
        case tenantCredit = "tenant_credit"
        case receivedTotal = "received_total"
        case depositHeld = "deposit_held"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let cur = try c.decode(String.self, forKey: .currency)
        currency = cur
        chargedToDate = try c.decodeMoney(.chargedToDate, currency: cur)
        waivedToDate = try c.decodeMoney(.waivedToDate, currency: cur)
        paidToDate = try c.decodeMoney(.paidToDate, currency: cur)
        outstanding = try c.decodeMoney(.outstanding, currency: cur)
        overdue = try c.decodeMoney(.overdue, currency: cur)
        upcoming = try c.decodeMoney(.upcoming, currency: cur)
        prepaid = try c.decodeMoney(.prepaid, currency: cur)
        tenantCredit = try c.decodeMoney(.tenantCredit, currency: cur)
        receivedTotal = try c.decodeMoney(.receivedTotal, currency: cur)
        depositHeld = try c.decodeMoney(.depositHeld, currency: cur)
    }
}

enum TenantMonthStatus: FallbackStringEnum {
    case paid
    case waived
    case overdue
    case due
    case partial
    case upcoming
    case noCharges
    case unknown(String)

    static var knownMapping: [(TenantMonthStatus, String)] {
        [
            (.paid, "paid"), (.waived, "waived"), (.overdue, "overdue"), (.due, "due"),
            (.partial, "partial"), (.upcoming, "upcoming"), (.noCharges, "none"),
        ]
    }

    static func makeUnknown(_ raw: String) -> TenantMonthStatus { .unknown(raw) }

    var unknownRaw: String? {
        if case .unknown(let raw) = self { return raw }
        return nil
    }

    var rawValue: String {
        switch self {
        case .paid: return "paid"
        case .waived: return "waived"
        case .overdue: return "overdue"
        case .due: return "due"
        case .partial: return "partial"
        case .upcoming: return "upcoming"
        case .noCharges: return "none"
        case .unknown(let raw): return raw
        }
    }
}

/// One calendar month of one lease (`months[]`); months without charges have
/// `status == .noCharges`, zeros and `lease_id == nil`.
struct TenantMonth: Decodable, Hashable {
    var period: String
    var leaseId: String?
    var propertyId: String?
    var charged: Money
    var paid: Money
    var waived: Money
    var outstanding: Money
    var dueDate: String?
    var kinds: [ChargeKind]
    var status: TenantMonthStatus

    enum CodingKeys: String, CodingKey {
        case period, currency, charged, paid, waived, outstanding, kinds, status
        case leaseId = "lease_id"
        case propertyId = "property_id"
        case dueDate = "due_date"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let cur = try c.decode(String.self, forKey: .currency)
        period = try c.decode(String.self, forKey: .period)
        leaseId = try c.decodeIfPresent(String.self, forKey: .leaseId)
        propertyId = try c.decodeIfPresent(String.self, forKey: .propertyId)
        charged = try c.decodeMoney(.charged, currency: cur)
        paid = try c.decodeMoney(.paid, currency: cur)
        waived = try c.decodeMoney(.waived, currency: cur)
        outstanding = try c.decodeMoney(.outstanding, currency: cur)
        dueDate = try c.decodeIfPresent(String.self, forKey: .dueDate)
        kinds = try c.decode([ChargeKind].self, forKey: .kinds)
        status = try c.decode(TenantMonthStatus.self, forKey: .status)
    }
}
