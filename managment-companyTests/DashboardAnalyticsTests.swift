import Foundation
import Testing
@testable import managment_company

@MainActor
@Suite(.serialized)
struct DashboardAnalyticsTests {
    @Test func threeMonthRangeStartsAtFirstDayTwoMonthsEarlier() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 12,
            hour: 12
        ))!

        let range = DashboardAnalyticsRange.threeMonths.dateRange(
            now: now,
            calendar: calendar
        )

        #expect(range.from == "2026-04-01")
        #expect(range.to == "2026-06-12")
    }

    @Test func comparisonAggregatesSelectedPropertyPoints() {
        let points = [
            point(propertyId: "a", propertyName: "Alpha", income: 100, cost: 20, utilities: 5),
            point(propertyId: "a", propertyName: "Alpha", income: 50, cost: 10, utilities: 2),
            point(propertyId: "b", propertyName: "Beta", income: 500, cost: 40, utilities: 8),
        ]

        let rows = DashboardAnalyticsLogic.comparisonRows(
            points: points,
            propertyNames: [:],
            selectedPropertyIds: ["a"]
        )

        #expect(rows.count == 1)
        #expect(rows[0].propertyName == "Alpha")
        #expect(rows[0].income == 150)
        #expect(rows[0].operatingCost == 30)
        #expect(rows[0].utilityExpense == 7)
        #expect(rows[0].netCashflow == 113)
    }

    @Test func monthlyCalendarDistinguishesPaidPartialAndNoLeaseDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let leases = [
            lease(id: "lease-a", start: "2026-06-01", end: "2026-06-20"),
            lease(id: "lease-b", start: "2026-06-10", end: "2026-06-20"),
        ]
        let schedules = [
            schedule(
                id: "schedule-a",
                leaseId: "lease-a",
                dueDate: "2026-06-05",
                start: "2026-06-01",
                end: "2026-06-20",
                status: "paid"
            ),
            schedule(
                id: "schedule-b",
                leaseId: "lease-b",
                dueDate: "2026-06-15",
                start: "2026-06-10",
                end: "2026-06-20",
                status: "pending"
            ),
        ]

        let days = DashboardAnalyticsLogic.calendarDays(
            year: 2026,
            month: 6,
            leases: leases,
            schedules: schedules,
            today: calendar.date(from: DateComponents(year: 2026, month: 6, day: 12))!,
            calendar: calendar
        )

        #expect(days.count == 30)
        #expect(days[4].state == .paid)
        #expect(days[14].state == .partial)
        #expect(days[14].dueScheduleCount == 1)
        #expect(days[24].state == .noLease)

        let summary = DashboardAnalyticsLogic.coverageSummary(days: days)
        #expect(summary.rentDays == 31)
        #expect(summary.paidDays == 20)
        #expect(summary.unpaidDays == 11)
        #expect(summary.coveragePct == 65)
    }

    @Test func csvEscapesCommaAndQuotes() {
        let report = ProfitabilityReport(
            groupBy: "month",
            from: "2026-06-01",
            to: "2026-06-30",
            points: [],
            totals: [
                point(
                    propertyId: nil,
                    propertyName: nil,
                    periodLabel: "Июнь, \"план\"",
                    income: 100,
                    cost: 20,
                    utilities: 5
                ),
            ]
        )

        let csv = DashboardAnalyticsLogic.csv(report: report)

        #expect(csv.hasPrefix("period,total_income,owner_operating_cost"))
        #expect(csv.contains("\"Июнь, \"\"план\"\"\""))
        #expect(csv.contains(",100.0,20.0,5.0,75.0,75.0"))
    }

    @Test func calendarDayDetailMatchesPaidAndUnpaidLeaseCoverage() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(
            from: DateComponents(year: 2026, month: 6, day: 12)
        )!
        let alpha = lease(
            id: "lease-a",
            propertyId: "property-a",
            tenantId: "tenant-a",
            start: "2026-06-01",
            end: nil,
            rentAmount: 250_000
        )
        let beta = lease(
            id: "lease-b",
            propertyId: "property-b",
            tenantId: "tenant-b",
            start: "2026-05-01",
            end: "2026-12-31",
            rentAmount: 350_000
        )
        let detail = DashboardAnalyticsLogic.calendarDayDetail(
            date: date,
            properties: [
                property(id: "property-a", name: "Демо"),
                property(id: "property-b", name: "Назарбаева"),
            ],
            leases: [beta, alpha],
            schedules: [
                schedule(
                    id: "schedule-a",
                    leaseId: alpha.id,
                    dueDate: "2026-06-12",
                    start: "2026-06-01",
                    end: "2026-06-30",
                    status: "paid"
                ),
                schedule(
                    id: "schedule-b",
                    leaseId: beta.id,
                    dueDate: "2026-06-15",
                    start: "2026-06-01",
                    end: "2026-06-30",
                    status: "pending"
                ),
            ],
            tenants: [
                tenant(id: "tenant-a", name: "Демо Демоев"),
                tenant(id: "tenant-b", name: "Екатерина Ким"),
            ],
            calendar: calendar
        )

        #expect(detail.activeLeaseCount == 2)
        #expect(detail.paidLeaseCount == 1)
        #expect(detail.coveragePct == 50)
        #expect(detail.entries.map(\.propertyName) == ["Демо", "Назарбаева"])
        #expect(detail.entries[0].tenantName == "Демо Демоев")
        #expect(detail.entries[0].payment?.amount == 100)
        #expect(detail.entries[0].payment?.periodStartDate == "2026-06-01")
        #expect(detail.entries[0].payment?.periodEndDate == "2026-06-30")
        #expect(detail.entries[0].isPaymentDue)
        #expect(detail.entries[1].payment == nil)
    }

    @Test func calendarDayDetailIsEmptyOutsideLeaseDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 1)
        )!

        let detail = DashboardAnalyticsLogic.calendarDayDetail(
            date: date,
            properties: [property(id: "property-a", name: "Демо")],
            leases: [
                lease(
                    id: "lease-a",
                    propertyId: "property-a",
                    tenantId: "tenant-a",
                    start: "2026-06-01",
                    end: "2026-06-30",
                    rentAmount: 250_000
                ),
            ],
            schedules: [],
            tenants: [],
            calendar: calendar
        )

        #expect(detail.entries.isEmpty)
        #expect(detail.coveragePct == 0)
    }

    @Test func calendarUsesAttributedRentTransactionWhenScheduleIsMissing() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let lease = lease(
            id: "lease-a",
            propertyId: "property-a",
            tenantId: "tenant-a",
            start: "2025-11-01",
            end: "2026-11-01",
            rentAmount: 400_000,
            paymentDay: 1
        )
        let transaction = transaction(
            id: "transaction-a",
            propertyId: lease.propertyId,
            categoryId: "rent",
            amount: 400_000,
            date: "2026-05-01",
            periodYear: 2026,
            periodMonth: 5,
            tenantId: lease.tenantId,
            leaseId: lease.id
        )

        let days = DashboardAnalyticsLogic.calendarDays(
            year: 2026,
            month: 5,
            leases: [lease],
            schedules: [],
            transactions: [transaction],
            categories: [category(id: "rent", name: "Аренда")],
            today: calendar.date(
                from: DateComponents(year: 2026, month: 6, day: 12)
            )!,
            calendar: calendar
        )
        let detail = DashboardAnalyticsLogic.calendarDayDetail(
            date: calendar.date(
                from: DateComponents(year: 2026, month: 5, day: 15)
            )!,
            properties: [property(id: lease.propertyId, name: "Назарбаева 278")],
            leases: [lease],
            schedules: [],
            tenants: [tenant(id: lease.tenantId, name: "Данил Назарбаев")],
            transactions: [transaction],
            categories: [category(id: "rent", name: "Аренда")],
            calendar: calendar
        )

        #expect(days[14].state == .paid)
        #expect(days[14].paidLeaseCount == 1)
        #expect(detail.paidLeaseCount == 1)
        #expect(detail.coveragePct == 100)
        #expect(detail.entries[0].payment?.amount == 400_000)
        #expect(detail.entries[0].payment?.periodStartDate == "2026-05-01")
        #expect(detail.entries[0].payment?.periodEndDate == "2026-06-01")
    }

    @Test func calendarIgnoresNonRentIncomeTransaction() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let lease = lease(
            id: "lease-a",
            propertyId: "property-a",
            tenantId: "tenant-a",
            start: "2026-05-01",
            end: nil,
            rentAmount: 400_000
        )
        let transaction = transaction(
            id: "transaction-a",
            propertyId: lease.propertyId,
            categoryId: "deposit",
            amount: 400_000,
            date: "2026-05-01",
            periodYear: 2026,
            periodMonth: 5,
            tenantId: lease.tenantId,
            leaseId: lease.id
        )

        let detail = DashboardAnalyticsLogic.calendarDayDetail(
            date: calendar.date(
                from: DateComponents(year: 2026, month: 5, day: 15)
            )!,
            properties: [property(id: lease.propertyId, name: "Назарбаева 278")],
            leases: [lease],
            schedules: [],
            tenants: [],
            transactions: [transaction],
            categories: [
                category(id: "rent", name: "Аренда"),
                category(id: "deposit", name: "Депозит"),
            ],
            calendar: calendar
        )

        #expect(detail.paidLeaseCount == 0)
        #expect(detail.entries[0].payment == nil)
    }

    private func point(
        propertyId: String?,
        propertyName: String?,
        periodLabel: String = "Июнь 2026",
        income: Double,
        cost: Double,
        utilities: Double
    ) -> ProfitabilityPoint {
        let net = income - cost - utilities
        return ProfitabilityPoint(
            propertyId: propertyId,
            propertyName: propertyName,
            periodKey: "2026-06",
            periodLabel: periodLabel,
            periodYear: 2026,
            periodMonth: 6,
            periodQuarter: nil,
            periodSeason: nil,
            totalIncome: income,
            totalExpense: cost + utilities,
            utilityExpense: utilities,
            operatingCost: cost,
            netCashflow: net,
            profitMarginPct: income == 0 ? 0 : net / income * 100
        )
    }

    private func lease(id: String, start: String, end: String) -> Lease {
        lease(
            id: id,
            propertyId: "property-\(id)",
            tenantId: "tenant-\(id)",
            start: start,
            end: end,
            rentAmount: 100
        )
    }

    private func lease(
        id: String,
        propertyId: String,
        tenantId: String,
        start: String,
        end: String?,
        rentAmount: Double,
        paymentDay: Int = 5
    ) -> Lease {
        Lease(
            id: id,
            propertyId: propertyId,
            propertyName: nil,
            tenantId: tenantId,
            startDate: start,
            endDate: end,
            moveInDate: nil,
            rentAmount: rentAmount,
            rentCurrency: "KZT",
            depositAmount: nil,
            depositCurrency: nil,
            paymentDay: paymentDay,
            paymentWindowStartDay: nil,
            paymentWindowEndDay: nil,
            paymentDueDay: paymentDay,
            status: "active",
            terminatedAt: nil,
            terminationReason: nil,
            notes: nil,
            renewalReminderDays: nil,
            autoRenew: nil,
            utilitiesPaidBy: nil
        )
    }

    private func property(id: String, name: String) -> Property {
        Property(
            id: id,
            name: name,
            propertyType: "apartment",
            country: "KZ",
            city: "Almaty",
            address: nil,
            district: nil,
            areaSqm: nil,
            rooms: nil,
            floor: nil,
            purchaseDate: nil,
            purchasePrice: nil,
            purchaseCurrency: nil,
            currentValue: nil,
            currentValueCurrency: nil,
            status: "occupied",
            notes: nil,
            tags: nil,
            utilityAccountNumber: nil,
            wifiLogin: nil,
            wifiPassword: nil
        )
    }

    private func tenant(id: String, name: String) -> Tenant {
        let parts = name.split(separator: " ", maxSplits: 1).map(String.init)
        return Tenant(
            id: id,
            firstName: parts[0],
            lastName: parts.count > 1 ? parts[1] : nil,
            phone: nil,
            email: nil,
            cohabitants: nil,
            notes: nil
        )
    }

    private func category(
        id: String,
        name: String
    ) -> managment_company.Category {
        managment_company.Category(
            id: id,
            name: name,
            type: "income",
            isSystem: true,
            icon: nil,
            sortOrder: 0
        )
    }

    private func transaction(
        id: String,
        propertyId: String,
        categoryId: String,
        amount: Double,
        date: String,
        periodYear: Int,
        periodMonth: Int,
        tenantId: String?,
        leaseId: String?
    ) -> Transaction {
        Transaction(
            id: id,
            propertyId: propertyId,
            type: "income",
            categoryId: categoryId,
            amount: amount,
            currency: "KZT",
            amountBase: amount,
            exchangeRate: nil,
            transactionDate: date,
            periodYear: periodYear,
            periodMonth: periodMonth,
            description: nil,
            tenantId: tenantId,
            leaseId: leaseId
        )
    }

    private func schedule(
        id: String,
        leaseId: String,
        dueDate: String,
        start: String,
        end: String,
        status: String
    ) -> LeasePaymentSchedule {
        LeasePaymentSchedule(
            id: id,
            leaseId: leaseId,
            dueDate: dueDate,
            periodStartDate: start,
            periodEndDate: end,
            notificationDueDate: nil,
            notificationSentAt: nil,
            expectedAmount: 100,
            currency: "KZT",
            actualPaymentId: status == "paid" ? "payment-\(id)" : nil,
            actualAmount: status == "paid" ? 100 : nil,
            paidAt: status == "paid" ? dueDate : nil,
            transactionId: nil,
            status: status,
            isOverdue: false,
            daysOverdue: 0
        )
    }
}
