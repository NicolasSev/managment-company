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
        Lease(
            id: id,
            propertyId: "property-\(id)",
            propertyName: nil,
            tenantId: "tenant-\(id)",
            startDate: start,
            endDate: end,
            moveInDate: nil,
            rentAmount: 100,
            rentCurrency: "KZT",
            depositAmount: nil,
            depositCurrency: nil,
            paymentDay: 5,
            paymentWindowStartDay: nil,
            paymentWindowEndDay: nil,
            paymentDueDay: 5,
            status: "active",
            terminatedAt: nil,
            terminationReason: nil,
            notes: nil,
            renewalReminderDays: nil,
            autoRenew: nil,
            utilitiesPaidBy: nil
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
