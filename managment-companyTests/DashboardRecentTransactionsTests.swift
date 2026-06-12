import Foundation
import Testing
@testable import managment_company

@MainActor
@Suite(.serialized)
struct DashboardRecentTransactionsTests {
    @Test func rowsSortNewestFirstAndKeepTen() {
        let transactions = (1...12).map { index in
            transaction(
                id: String(format: "%02d", index),
                propertyId: index.isMultiple(of: 2) ? "a" : "b",
                type: index.isMultiple(of: 2) ? "income" : "expense",
                amount: Double(index),
                date: String(format: "2026-06-%02d", index)
            )
        }

        let rows = DashboardRecentTransactionsLogic.rows(
            transactions: transactions,
            propertyNames: ["a": "Alpha", "b": "Beta"]
        )

        #expect(rows.count == 10)
        #expect(rows.first?.id == "12")
        #expect(rows.last?.id == "03")
        #expect(rows.first?.propertyName == "Alpha")
    }

    @Test func presentationUsesSignedIncomeAndExpenseAmounts() {
        let rows = DashboardRecentTransactionsLogic.rows(
            transactions: [
                transaction(
                    id: "income",
                    propertyId: "known",
                    type: "income",
                    amount: 100,
                    date: "2026-06-12"
                ),
                transaction(
                    id: "expense",
                    propertyId: "missing",
                    type: "expense",
                    amount: 40,
                    date: "2026-06-11"
                ),
            ],
            propertyNames: ["known": "Alpha"]
        )

        #expect(rows[0].amountSign == "+")
        #expect(rows[0].isIncome)
        #expect(rows[1].amountSign == "-")
        #expect(!rows[1].isIncome)
        #expect(rows[1].propertyName == "Объект не найден")
    }

    @Test func actionExpandsFiveToTenThenOpensTransactions() {
        #expect(
            DashboardRecentTransactionsLogic.action(rowCount: 6, expanded: false)
                == .expand
        )
        #expect(
            DashboardRecentTransactionsLogic.action(rowCount: 6, expanded: true)
                == .openTransactions
        )
        #expect(
            DashboardRecentTransactionsLogic.action(rowCount: 5, expanded: false)
                == .openTransactions
        )
        #expect(
            DashboardRecentTransactionsLogic.action(rowCount: 0, expanded: false)
                == nil
        )
    }

    @Test func visibleRowsUsePreviewAndExpandedLimits() {
        let transactions = (1...12).map { index in
            transaction(
                id: "\(index)",
                propertyId: "a",
                type: "income",
                amount: Double(index),
                date: String(format: "2026-06-%02d", index)
            )
        }
        let rows = DashboardRecentTransactionsLogic.rows(
            transactions: transactions,
            propertyNames: ["a": "Alpha"]
        )

        #expect(
            DashboardRecentTransactionsLogic.visibleRows(rows, expanded: false).count == 5
        )
        #expect(
            DashboardRecentTransactionsLogic.visibleRows(rows, expanded: true).count == 10
        )
    }

    private func transaction(
        id: String,
        propertyId: String,
        type: String,
        amount: Double,
        date: String
    ) -> Transaction {
        Transaction(
            id: id,
            propertyId: propertyId,
            type: type,
            categoryId: "category",
            amount: amount,
            currency: "KZT",
            amountBase: amount,
            exchangeRate: nil,
            transactionDate: date,
            periodYear: 2026,
            periodMonth: 6,
            description: nil,
            tenantId: nil,
            leaseId: nil
        )
    }
}
