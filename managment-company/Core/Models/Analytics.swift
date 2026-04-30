import Foundation

struct AnalyticsDashboard: Codable {
    let totalIncome: Double
    let totalExpense: Double
    let netCashflow: Double
    let periodYear: Int
    let periodMonth: Int
    
    enum CodingKeys: String, CodingKey {
        case periodYear = "period_year"
        case periodMonth = "period_month"
        case totalIncome = "total_income"
        case totalExpense = "total_expense"
        case netCashflow = "net_cashflow"
    }
}
