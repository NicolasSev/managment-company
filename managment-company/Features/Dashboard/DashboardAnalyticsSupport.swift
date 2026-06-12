import Foundation

enum DashboardAnalyticsRange: String, CaseIterable, Identifiable {
    case all
    case twelveMonths
    case sixMonths
    case threeMonths

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Все"
        case .twelveMonths: return "12 мес."
        case .sixMonths: return "6 мес."
        case .threeMonths: return "3 мес."
        }
    }

    func dateRange(now: Date = Date(), calendar: Calendar = .current) -> (from: String, to: String) {
        let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) ?? calendar.startOfDay(for: now)
        let from: Date
        switch self {
        case .all:
            from = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? monthStart
        case .twelveMonths:
            from = calendar.date(byAdding: .month, value: -11, to: monthStart) ?? monthStart
        case .sixMonths:
            from = calendar.date(byAdding: .month, value: -5, to: monthStart) ?? monthStart
        case .threeMonths:
            from = calendar.date(byAdding: .month, value: -2, to: monthStart) ?? monthStart
        }
        return (DashboardAnalyticsLogic.isoDate(from), DashboardAnalyticsLogic.isoDate(now))
    }
}

enum DashboardAnalyticsGroup: String, CaseIterable, Identifiable {
    case month
    case quarter
    case season
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: return "Месяцы"
        case .quarter: return "Кварталы"
        case .season: return "Сезоны"
        case .year: return "Годы"
        }
    }
}

struct DashboardPropertyComparisonRow: Identifiable, Equatable {
    let propertyId: String
    let propertyName: String
    let income: Double
    let operatingCost: Double
    let utilityExpense: Double
    let netCashflow: Double

    var id: String { propertyId }
}

enum DashboardCoverageState: String, Equatable {
    case noLease
    case unpaid
    case partial
    case paid
}

struct DashboardCalendarDay: Identifiable, Equatable {
    let date: Date
    let day: Int
    let activeLeaseCount: Int
    let paidLeaseCount: Int
    let dueScheduleCount: Int
    let isToday: Bool
    let state: DashboardCoverageState

    var id: String { DashboardAnalyticsLogic.isoDate(date) }
}

struct DashboardCoverageSummary: Equatable {
    let rentDays: Int
    let paidDays: Int

    var unpaidDays: Int { max(0, rentDays - paidDays) }
    var coveragePct: Int {
        guard rentDays > 0 else { return 0 }
        return Int((Double(paidDays) / Double(rentDays) * 100).rounded())
    }
}

enum DashboardAnalyticsLogic {
    static func comparisonRows(
        points: [ProfitabilityPoint],
        propertyNames: [String: String],
        selectedPropertyIds: Set<String>
    ) -> [DashboardPropertyComparisonRow] {
        var rows: [String: DashboardPropertyComparisonRow] = [:]
        for point in points {
            guard let propertyId = point.propertyId else { continue }
            if !selectedPropertyIds.isEmpty && !selectedPropertyIds.contains(propertyId) {
                continue
            }
            let current = rows[propertyId]
            rows[propertyId] = DashboardPropertyComparisonRow(
                propertyId: propertyId,
                propertyName: point.propertyName ?? propertyNames[propertyId] ?? "Объект",
                income: (current?.income ?? 0) + point.totalIncome,
                operatingCost: (current?.operatingCost ?? 0) + point.operatingCost,
                utilityExpense: (current?.utilityExpense ?? 0) + point.utilityExpense,
                netCashflow: (current?.netCashflow ?? 0) + point.netCashflow
            )
        }
        return rows.values.sorted {
            if $0.netCashflow == $1.netCashflow {
                return $0.propertyName.localizedCaseInsensitiveCompare($1.propertyName) == .orderedAscending
            }
            return $0.netCashflow > $1.netCashflow
        }
    }

    static func calendarDays(
        year: Int,
        month: Int,
        leases: [Lease],
        schedules: [LeasePaymentSchedule],
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> [DashboardCalendarDay] {
        guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let nextMonth = calendar.date(byAdding: .month, value: 1, to: start) else {
            return []
        }

        var days: [DashboardCalendarDay] = []
        var date = start
        while date < nextMonth {
            let activeLeases = leases.filter { leaseIsActive($0, on: date, calendar: calendar) }
            let activeIds = Set(activeLeases.map(\.id))
            let paidIds = Set(schedules.compactMap { schedule -> String? in
                guard activeIds.contains(schedule.leaseId),
                      scheduleCovers(schedule, date: date, calendar: calendar),
                      scheduleIsPaid(schedule) else {
                    return nil
                }
                return schedule.leaseId
            })
            let dueCount = schedules.filter { schedule in
                guard activeIds.contains(schedule.leaseId),
                      let dueDate = parseDate(schedule.dueDate, calendar: calendar) else {
                    return false
                }
                return calendar.isDate(dueDate, inSameDayAs: date)
            }.count
            let state: DashboardCoverageState
            if activeIds.isEmpty {
                state = .noLease
            } else if paidIds.count >= activeIds.count {
                state = .paid
            } else if paidIds.isEmpty {
                state = .unpaid
            } else {
                state = .partial
            }

            days.append(
                DashboardCalendarDay(
                    date: date,
                    day: calendar.component(.day, from: date),
                    activeLeaseCount: activeIds.count,
                    paidLeaseCount: paidIds.count,
                    dueScheduleCount: dueCount,
                    isToday: calendar.isDate(date, inSameDayAs: today),
                    state: state
                )
            )
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? nextMonth
        }
        return days
    }

    static func coverageSummary(days: [DashboardCalendarDay]) -> DashboardCoverageSummary {
        DashboardCoverageSummary(
            rentDays: days.reduce(0) { $0 + $1.activeLeaseCount },
            paidDays: days.reduce(0) { $0 + min($1.paidLeaseCount, $1.activeLeaseCount) }
        )
    }

    static func leadingWeekdaySlots(
        year: Int,
        month: Int,
        calendar: Calendar = .current
    ) -> Int {
        guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else {
            return 0
        }
        // Calendar weekday is Sunday=1; the UI starts with Monday.
        return (calendar.component(.weekday, from: start) + 5) % 7
    }

    static func availableYears(
        leases: [Lease],
        currentYear: Int = Calendar.current.component(.year, from: Date()),
        calendar: Calendar = .current
    ) -> [Int] {
        var years = Set([currentYear])
        for lease in leases {
            if let start = parseDate(lease.moveInDate ?? lease.startDate, calendar: calendar) {
                years.insert(calendar.component(.year, from: start))
            }
            if let rawEnd = lease.terminatedAt ?? lease.endDate,
               let end = parseDate(rawEnd, calendar: calendar) {
                years.insert(calendar.component(.year, from: end))
            }
        }
        return years.sorted(by: >)
    }

    static func csv(report: ProfitabilityReport) -> String {
        let headers = [
            "period",
            "total_income",
            "owner_operating_cost",
            "tenant_utilities",
            "net_cashflow",
            "profit_margin_pct",
        ]
        let rows = report.totals.map { row in
            [
                row.periodLabel.isEmpty ? row.periodKey : row.periodLabel,
                String(row.totalIncome),
                String(row.operatingCost),
                String(row.utilityExpense),
                String(row.netCashflow),
                String(row.profitMarginPct),
            ]
        }
        return ([headers] + rows)
            .map { $0.map(csvEscape).joined(separator: ",") }
            .joined(separator: "\n")
    }

    static func monthTitle(year: Int, month: Int, calendar: Calendar = .current) -> String {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else {
            return "\(month).\(year)"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date).capitalized
    }

    static func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func parseDate(_ raw: String, calendar: Calendar) -> Date? {
        let parts = String(raw.prefix(10)).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func leaseIsActive(_ lease: Lease, on date: Date, calendar: Calendar) -> Bool {
        guard let start = parseDate(lease.moveInDate ?? lease.startDate, calendar: calendar) else {
            return false
        }
        let end = (lease.terminatedAt ?? lease.endDate).flatMap { parseDate($0, calendar: calendar) }
        let day = calendar.startOfDay(for: date)
        if day < calendar.startOfDay(for: start) { return false }
        if let end, day > calendar.startOfDay(for: end) { return false }
        return true
    }

    private static func scheduleCovers(
        _ schedule: LeasePaymentSchedule,
        date: Date,
        calendar: Calendar
    ) -> Bool {
        guard let start = parseDate(
            schedule.periodStartDate ?? schedule.dueDate,
            calendar: calendar
        ) else {
            return false
        }
        let end = parseDate(
            schedule.periodEndDate ?? schedule.periodStartDate ?? schedule.dueDate,
            calendar: calendar
        ) ?? start
        let day = calendar.startOfDay(for: date)
        return day >= calendar.startOfDay(for: start) && day <= calendar.startOfDay(for: end)
    }

    private static func scheduleIsPaid(_ schedule: LeasePaymentSchedule) -> Bool {
        let status = schedule.status.lowercased()
        return status == "paid"
            || status == "matched"
            || schedule.actualPaymentId != nil
            || schedule.transactionId != nil
            || schedule.paidAt != nil
    }

    nonisolated private static func csvEscape(_ raw: String) -> String {
        let escaped = raw.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\n") || escaped.contains("\"") {
            return "\"\(escaped)\""
        }
        return escaped
    }
}
