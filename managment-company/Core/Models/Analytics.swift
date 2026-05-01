import Foundation

/// Mirrors `DashboardSummary` in `packages/api-contracts/openapi.canonical.yaml` (GET `/v1/analytics/dashboard`).
struct AnalyticsDashboard: Codable {
    let totalIncome: Double
    let totalExpense: Double
    let netCashflow: Double
    let expectedRent: Double
    let rentReceived: Double
    let rentOutstanding: Double
    let depositIncome: Double
    let periodYear: Int
    let periodMonth: Int
    /// Wire: `all` | `month` | `season` | `quarter` | `year`
    let period: String
    let periodLabel: String
    let periodFrom: String?
    let periodTo: String?

    enum CodingKeys: String, CodingKey {
        case periodYear = "period_year"
        case periodMonth = "period_month"
        case totalIncome = "total_income"
        case totalExpense = "total_expense"
        case netCashflow = "net_cashflow"
        case expectedRent = "expected_rent"
        case rentReceived = "rent_received"
        case rentOutstanding = "rent_outstanding"
        case depositIncome = "deposit_income"
        case period
        case periodLabel = "period_label"
        case periodFrom = "period_from"
        case periodTo = "period_to"
    }

    /// UI label: prefer backend `period_label`, else month/year fallback.
    var displayPeriodLabel: String {
        let trimmed = periodLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "MMMM yyyy"
        if let date = Calendar.current.date(from: DateComponents(year: periodYear, month: periodMonth, day: 1)) {
            return formatter.string(from: date)
        }
        return "\(periodMonth)/\(periodYear)"
    }
}

/// `OccupancyResponse` envelope body for GET `/v1/analytics/occupancy`.
struct OccupancyPayload: Codable {
    let occupied: Int
    let total: Int
    let ratePct: Int

    enum CodingKeys: String, CodingKey {
        case occupied, total
        case ratePct = "rate_pct"
    }
}

/// GET `/v1/analytics/overdue-payments` → `data`.
struct OverduePaymentsPayload: Codable {
    let overdueCount: Int

    enum CodingKeys: String, CodingKey {
        case overdueCount = "overdue_count"
    }
}

/// One month in GET `/v1/analytics/cashflow-trend`.
struct CashflowTrendMonth: Codable, Identifiable {
    var id: String { "\(year)-\(month)" }
    let year: Int
    let month: Int
    let totalIncome: Double
    let totalExpense: Double
    let netCashflow: Double

    enum CodingKeys: String, CodingKey {
        case year, month
        case totalIncome = "total_income"
        case totalExpense = "total_expense"
        case netCashflow = "net_cashflow"
    }
}

/// Body inside `data` for GET `/v1/analytics/cashflow-trend`.
struct CashflowTrendBody: Codable {
    let months: [CashflowTrendMonth]
}

/// GET `/v1/analytics/profitability` → `data`.
struct ProfitabilityPoint: Codable {
    let propertyId: String?
    let propertyName: String?
    let periodKey: String
    let periodLabel: String
    let periodYear: Int
    let periodMonth: Int?
    let periodQuarter: Int?
    let periodSeason: String?
    let totalIncome: Double
    let totalExpense: Double
    let utilityExpense: Double
    let operatingCost: Double
    let netCashflow: Double
    let profitMarginPct: Double

    enum CodingKeys: String, CodingKey {
        case periodKey = "period_key"
        case periodLabel = "period_label"
        case periodYear = "period_year"
        case periodMonth = "period_month"
        case periodQuarter = "period_quarter"
        case periodSeason = "period_season"
        case totalIncome = "total_income"
        case totalExpense = "total_expense"
        case utilityExpense = "utility_expense"
        case operatingCost = "operating_cost"
        case netCashflow = "net_cashflow"
        case profitMarginPct = "profit_margin_pct"
        case propertyId = "property_id"
        case propertyName = "property_name"
    }
}

struct ProfitabilityReport: Codable {
    let groupBy: String
    let from: String
    let to: String
    let points: [ProfitabilityPoint]
    let totals: [ProfitabilityPoint]

    enum CodingKeys: String, CodingKey {
        case points, totals, from, to
        case groupBy = "group_by"
    }
}
