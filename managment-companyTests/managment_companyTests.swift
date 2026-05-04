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

    private func loadFixtureJSON(_ name: String) throws -> Data {
        let bundle = Bundle(for: ManagmentCompanyTests.self)
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            struct MissingFixture: Error {}
            throw MissingFixture()
        }
        return try Data(contentsOf: url)
    }

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

    @Test func decodesAnalyticsOccupancyFixtureFromBundle() throws {
        let data = try loadFixtureJSON("analytics-occupancy")
        let decoded = try JSONDecoder().decode(APIResponse<OccupancyPayload>.self, from: data).data
        #expect(decoded.occupied == 2)
        #expect(decoded.total == 5)
        #expect(decoded.ratePct == 40)
    }

    @Test func decodesAnalyticsDashboardFixtureFromBundle() throws {
        let data = try loadFixtureJSON("analytics-dashboard")
        let decoded = try JSONDecoder().decode(APIResponse<AnalyticsDashboard>.self, from: data).data
        #expect(decoded.period == "all")
        #expect(decoded.rentOutstanding == 10)
        #expect(decoded.displayPeriodLabel == "За всё время")
    }

    @Test func decodesOverduePaymentsFixtureFromBundle() throws {
        let data = try loadFixtureJSON("analytics-overdue-payments")
        let decoded = try JSONDecoder().decode(APIResponse<OverduePaymentsPayload>.self, from: data).data
        #expect(decoded.overdueCount == 3)
    }

    @Test func decodesCashflowTrendFixtureFromBundle() throws {
        let data = try loadFixtureJSON("analytics-cashflow-trend")
        let decoded = try JSONDecoder().decode(APIResponse<CashflowTrendBody>.self, from: data).data
        #expect(decoded.months.count == 1)
        #expect(decoded.months[0].year == 2026)
        #expect(decoded.months[0].netCashflow == 6)
    }

    @Test func decodesLeasePaymentScheduleListFixtureFromBundle() throws {
        let data = try loadFixtureJSON("lease-payment-schedule-list")
        let decoded = try JSONDecoder().decode(APIListEnvelope<LeasePaymentSchedule>.self, from: data)
        #expect(decoded.data.count == 1)
        #expect(decoded.data[0].expectedAmount == 95000)
        #expect(decoded.data[0].leaseId == "00000000-0000-0000-0000-000000000002")
        #expect(decoded.total == 1)
    }

    @Test func decodesProfitabilityFixtureFromBundle() throws {
        let data = try loadFixtureJSON("analytics-profitability")
        let decoded = try JSONDecoder().decode(APIResponse<ProfitabilityReport>.self, from: data).data
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

    @Test func decodesPropertyWithUtilityAccountNumber() throws {
        let json = """
        {"data":{"id":"00000000-0000-0000-0000-000000000001","name":"Flat A","property_type":"apartment",
        "country":null,"city":"Almaty","address":"Street 1","district":null,"area_sqm":null,"rooms":null,"floor":null,
        "purchase_date":null,"purchase_price":null,"purchase_currency":"KZT","current_value":null,"current_value_currency":null,
        "status":"vacant","notes":null,"tags":null,"utility_account_number":"1194968"}}
        """
        let decoded = try JSONDecoder().decode(APIResponse<Property>.self, from: json.data(using: .utf8)!).data
        #expect(decoded.utilityAccountNumber == "1194968")
    }

    /// Same JSON as `packages/api-contracts/fixtures/notifications-list.json`; refresh with `make ios-contract-fixtures`.
    @Test func decodesNotificationsListFixtureFromBundle() throws {
        let data = try loadFixtureJSON("notifications-list")
        let page = try JSONDecoder().decode(NotificationsListResponse.self, from: data)
        #expect(page.data.count == 1)
        #expect(page.data[0].id == "550e8400-e29b-41d4-a716-446655440000")
        #expect(page.data[0].title == "Rent")
        #expect(page.perPage == 30)
        #expect(page.unreadCount == 1)
    }

    /// Same JSON as `packages/api-contracts/fixtures/notifications-unread-count.json`.
    @Test func decodesNotificationsUnreadCountFixtureFromBundle() throws {
        let data = try loadFixtureJSON("notifications-unread-count")
        let inner = try JSONDecoder().decode(APIResponse<UnreadCountData>.self, from: data).data
        #expect(inner.count == 3)
    }
}
