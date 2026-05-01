//
//  managment_companyTests.swift
//  managment-companyTests
//

import Foundation
import Testing
@testable import managment_company

/// Shared `KeychainManager` + parallel default execution can race; serialize this suite.
@Suite(.serialized)
struct ManagmentCompanyTests {

    @Test func apiURLBuilderJoinsRelativeDownloadPath() {
        let url = APIURLBuilder.absoluteDownloadURL(
            base: "http://127.0.0.1:8080",
            downloadPath: "/v1/files/abc/download?user=x&истекает=1&signature=y"
        )
        // Foundation percent-encodes non-ASCII in query (e.g. Cyrillic param names).
        #expect(url?.absoluteString == "http://127.0.0.1:8080/v1/files/abc/download?user=x&%D0%B8%D1%81%D1%82%D0%B5%D0%BA%D0%B0%D0%B5%D1%82=1&signature=y")
    }

    @Test func apiURLBuilderPassesThroughAbsoluteHttpURL() {
        let full = "https://cdn.example.com/file.pdf"
        let url = APIURLBuilder.absoluteDownloadURL(base: "http://127.0.0.1:8080", downloadPath: full)
        #expect(url?.absoluteString == full)
    }

    @Test func keychainRoundTripForTokens() {
        let keychain = KeychainManager.shared
        _ = keychain.clearTokens()
        #expect(keychain.storeTokens(access: "test-access", refresh: "test-refresh"))
        #expect(keychain.getAccessToken() == "test-access")
        #expect(keychain.getRefreshToken() == "test-refresh")
        _ = keychain.clearTokens()
        #expect(keychain.getAccessToken() == nil)
        #expect(keychain.getRefreshToken() == nil)
    }

    @Test func decodesOccupancyEnvelopeBody() throws {
        let raw = #"{"data":{"occupied":2,"total":5,"rate_pct":40}}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(APIResponse<OccupancyPayload>.self, from: raw).data
        #expect(decoded.occupied == 2)
        #expect(decoded.total == 5)
        #expect(decoded.ratePct == 40)
    }

    @Test func decodesAnalyticsDashboardEnvelopeBody() throws {
        let json = """
        {"data":{
          "total_income":100,"total_expense":40,"net_cashflow":60,
          "expected_rent":80,"rent_received":70,"rent_outstanding":10,"deposit_income":0,
          "period_year":2026,"period_month":4,"period":"all","period_label":"За всё время",
          "period_from":null,"period_to":null
        }}
        """
        let decoded = try JSONDecoder().decode(APIResponse<AnalyticsDashboard>.self, from: json.data(using: .utf8)!).data
        #expect(decoded.period == "all")
        #expect(decoded.rentOutstanding == 10)
        #expect(decoded.displayPeriodLabel == "За всё время")
    }

    @Test func decodesOverduePaymentsEnvelopeBody() throws {
        let raw = #"{"data":{"overdue_count":3}}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(APIResponse<OverduePaymentsPayload>.self, from: raw).data
        #expect(decoded.overdueCount == 3)
    }

    @Test func decodesCashflowTrendEnvelopeBody() throws {
        let json = #"{"data":{"months":[{"year":2026,"month":3,"total_income":10,"total_expense":4,"net_cashflow":6}]}}"#
        let decoded = try JSONDecoder().decode(APIResponse<CashflowTrendBody>.self, from: json.data(using: .utf8)!).data
        #expect(decoded.months.count == 1)
        #expect(decoded.months[0].year == 2026)
        #expect(decoded.months[0].netCashflow == 6)
    }

    @Test func decodesLeasePaymentScheduleListEnvelopeBody() throws {
        let json = """
        {"data":[{"id":"00000000-0000-0000-0000-000000000001","lease_id":"00000000-0000-0000-0000-000000000002",
        "due_date":"2026-04-05","period_start_date":null,"period_end_date":null,
        "notification_due_date":null,"notification_sent_at":null,
        "expected_amount":95000,"currency":"KZT",
        "actual_payment_id":null,"actual_amount":null,"paid_at":null,"transaction_id":null,
        "status":"pending","is_overdue":false,"days_overdue":0}],"page":1,"per_page":1,"total":1}
        """
        let decoded = try JSONDecoder().decode(APIListEnvelope<LeasePaymentSchedule>.self, from: json.data(using: .utf8)!)
        #expect(decoded.data.count == 1)
        #expect(decoded.data[0].expectedAmount == 95000)
        #expect(decoded.data[0].leaseId == "00000000-0000-0000-0000-000000000002")
        #expect(decoded.total == 1)
    }

    @Test func decodesProfitabilityEnvelopeBody() throws {
        let json = """
        {"data":{"group_by":"month","from":"2025-05-01","to":"2026-05-01",
        "points":[],
        "totals":[{"period_key":"2026-03","period_label":"март 2026","period_year":2026,"period_month":3,
        "total_income":900,"total_expense":400,"utility_expense":50,"operating_cost":350,
        "net_cashflow":500,"profit_margin_pct":55.5}]}}
        """
        let decoded = try JSONDecoder().decode(APIResponse<ProfitabilityReport>.self, from: json.data(using: .utf8)!).data
        #expect(decoded.totals.count == 1)
        #expect(decoded.totals[0].netCashflow == 500)
        #expect(abs(decoded.totals[0].profitMarginPct - 55.5) < 0.01)
        #expect(decoded.totals[0].propertyId == nil)
    }

    @Test func decodesSchedulePaymentMutationEnvelopeBody() throws {
        let json = """
        {"data":{
          "schedule":{"id":"00000000-0000-0000-0000-000000000001","lease_id":"00000000-0000-0000-0000-000000000002",
          "due_date":"2026-04-05","period_start_date":null,"period_end_date":null,
          "notification_due_date":null,"notification_sent_at":null,
          "expected_amount":95000,"currency":"KZT",
          "actual_payment_id":"00000000-0000-0000-0000-000000000003","actual_amount":95000,"paid_at":"2026-04-10","transaction_id":null,
          "status":"paid","is_overdue":false,"days_overdue":0},
          "payment":{"id":"00000000-0000-0000-0000-000000000003","lease_id":"00000000-0000-0000-0000-000000000002",
          "amount":95000,"currency":"KZT","payment_date":"2026-04-10","period_year":2026,"period_month":4,
          "status":"paid","transaction_id":"00000000-0000-0000-0000-000000000099","notes":null}
        }}
        """
        let decoded = try JSONDecoder().decode(APIResponse<SchedulePaymentResult>.self, from: json.data(using: .utf8)!).data
        #expect(decoded.payment.amount == decoded.schedule.expectedAmount)
        #expect(decoded.schedule.status == "paid")
        #expect(decoded.payment.periodMonth == 4)
    }
}
