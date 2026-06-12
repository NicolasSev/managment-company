import Foundation

enum DashboardRecentTransactionsAction: Equatable {
    case expand
    case openTransactions
}

struct DashboardRecentTransactionRow: Identifiable {
    let id: String
    let propertyName: String
    let type: String
    let amount: Double
    let currency: String
    let transactionDate: String
    let description: String?

    var isIncome: Bool {
        type.lowercased() == "income"
    }

    var amountSign: String {
        isIncome ? "+" : "-"
    }
}

enum DashboardRecentTransactionsLogic {
    static let previewCount = 5
    static let expandedCount = 10

    static func rows(
        transactions: [Transaction],
        propertyNames: [String: String]
    ) -> [DashboardRecentTransactionRow] {
        transactions
            .sorted {
                ($0.transactionDate, $0.id) > ($1.transactionDate, $1.id)
            }
            .prefix(expandedCount)
            .map {
                DashboardRecentTransactionRow(
                    id: $0.id,
                    propertyName: propertyNames[$0.propertyId] ?? "Объект не найден",
                    type: $0.type,
                    amount: $0.amount,
                    currency: $0.currency,
                    transactionDate: $0.transactionDate,
                    description: $0.description
                )
            }
    }

    static func visibleRows(
        _ rows: [DashboardRecentTransactionRow],
        expanded: Bool
    ) -> [DashboardRecentTransactionRow] {
        Array(rows.prefix(expanded ? expandedCount : previewCount))
    }

    static func action(
        rowCount: Int,
        expanded: Bool
    ) -> DashboardRecentTransactionsAction? {
        guard rowCount > 0 else { return nil }
        if !expanded, rowCount > previewCount {
            return .expand
        }
        return .openTransactions
    }
}
