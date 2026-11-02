//
//  UtilityNotificationTests.swift
//  managment-companyTests
//
//  Utility pushes and settings (task U9): `utility_bill_needs_review`, `utility_bill_missing` (the
//  reminder) and `utility_upload_other` open the bill or the inbox like `lease.ending_soon` opens a
//  lease; the notification settings screen sends partial updates; the Telegram link flow; the
//  payer, account and expectation rule of the property form.
//

import Foundation
import Testing
@testable import managment_company

@MainActor
@Suite(.serialized)
struct UtilityNotificationTests {
    // MARK: Deep links

    /// The data of a push as `notification_outbox.go` builds it.
    private func data(_ extra: [String: String]) -> [String: String] {
        var base = [
            "event_type": "utility_bill_needs_review", "entity_type": "utility_bill",
            "entity_id": "b-1", "bill_id": "b-1", "property_id": "p-1", "period": "2026-03",
            "deep_link": "/utilities?property_id=p-1&bill_id=b-1",
        ]
        base.merge(extra) { $1 }
        return base
    }

    @Test func needsReviewPushOpensTheBill() {
        let route = NotificationRoute(notificationType: "utility_bill_needs_review", data: data([:]))
        #expect(route.kind == .utilityBill(billId: "b-1", propertyId: "p-1"))
        #expect(route.tab == .utilities)
        #expect(route.opensNestedDestination)
        #expect(MainTabView.target(for: route.tab) == .utilitiesSheet)
    }

    @Test func missingReceiptReminderOpensTheBillUnderBothNames() {
        let payload = data(["event_type": "utility_bill_missing", "utility_payer": "tenant"])
        for type in ["utility_bill_missing", "utility_missing_reminder"] {
            let route = NotificationRoute(notificationType: type, data: payload)
            #expect(route.kind == .utilityBill(billId: "b-1", propertyId: "p-1"), "type \(type)")
        }
    }

    @Test func theTypeCanComeFromTheEventTypeKey() {
        let route = NotificationRoute(notificationType: nil, data: data(["event_type": "utility_bill_missing"]))
        #expect(route.kind == .utilityBill(billId: "b-1", propertyId: "p-1"))
    }

    @Test func uploadOtherPushOpensTheInbox() {
        let route = NotificationRoute(
            notificationType: "utility_upload_other",
            data: ["event_type": "utility_upload_other", "entity_type": "document_extraction", "entity_id": "e-1",
                   "extraction_id": "e-1", "deep_link": "/utilities?inbox=1"]
        )
        #expect(route.kind == .utilitiesInbox)
        #expect(route.tab == .utilities)
    }

    @Test func aBillPushWithoutABillIdFallsBackToTheInbox() {
        let route = NotificationRoute(notificationType: "utility_bill_needs_review", data: ["event_type": "utility_bill_needs_review"])
        #expect(route.kind == .utilitiesInbox)
    }

    @Test func theBillIdIsTakenFromTheEntityWhenTheKeyIsMissing() {
        let route = NotificationRoute(
            notificationType: "utility_bill_needs_review",
            data: ["entity_type": "utility_bill", "entity_id": "b-9"]
        )
        #expect(route.kind == .utilityBill(billId: "b-9", propertyId: nil))
    }

    @Test func otherRoutesAreUntouched() {
        #expect(NotificationRoute(notificationType: "rent_payment_due", data: [:]).kind == .transactions)
        #expect(NotificationRoute(notificationType: nil, data: ["entity_type": "lease", "property_id": "p-1"]).kind == .property("p-1"))
        #expect(NotificationRoute(notificationType: "daily_summary", data: [:]).kind == .today)
    }

    @Test func theRouterKeepsABillRouteUntilTheScreenTakesIt() {
        let router = NotificationDeepLinkRouter()
        router.handleNotificationOpen(userInfo: [
            "notification_type": "utility_bill_needs_review", "bill_id": "b-1", "entity_type": "utility_bill", "entity_id": "b-1",
        ])
        #expect(router.selectTab == .utilities)
        let route = router.pendingRoute
        #expect(route?.kind == .utilityBill(billId: "b-1", propertyId: nil))
        if let route { router.clearRoute(route) }
        #expect(router.pendingRoute == nil)
    }

    // MARK: Notification settings

    private func settingsModel(linked: Bool = false) throws -> (NotificationSettingsViewModel, MockNotificationSettingsService) {
        let service = try MockNotificationSettingsService(linked: linked)
        return (NotificationSettingsViewModel(service: service), service)
    }

    @Test func settingsListTheThreeEventsWithBothChannels() async throws {
        let (model, _) = try settingsModel(linked: true)
        await model.load()
        #expect(model.state == .loaded)
        #expect(model.rows.map(\.event) == [.utilityBillMissing, .utilityBillNeedsReview, .utilityUploadOther])
        #expect(model.rows[0].pushEnabled && model.rows[0].telegramEnabled)
        #expect(model.rows[1].pushEnabled && !model.rows[1].telegramEnabled)
        #expect(model.isTelegramLinked)
    }

    @Test func aSwitchSendsOnlyThatChannel() async throws {
        let (model, service) = try settingsModel()
        await model.load()
        await model.setChannel(.utilityBillNeedsReview, .telegram, enabled: true)
        let sent = try #require(service.updates.last)
        #expect(sent.channels == [NotificationChannelSetting(eventType: .utilityBillNeedsReview, channel: .telegram, enabled: true)])
        #expect(sent.quiet == nil && sent.utilityReminderDay == nil && sent.utilityReminderRepeatDays == nil)
        #expect(model.rows[1].telegramEnabled)
    }

    @Test func quietHoursAreSetAndClearedAsAPair() async throws {
        let (model, service) = try settingsModel()
        await model.load()
        await model.setQuietHours(from: nil, to: nil)
        #expect(model.settings?.hasQuietHours == false)
        await model.setQuietHours(from: "21:30", to: "07:00")
        #expect(model.settings?.quietFrom == "21:30" && model.settings?.quietTo == "07:00")
        #expect(service.updates.last?.quiet == .init(from: "21:30", to: "07:00"))
    }

    @Test func reminderDayAndIntervalStayInTheirRanges() async throws {
        let (model, service) = try settingsModel()
        await model.load()
        await model.setReminderDay(15)
        await model.setRepeatDays(5)
        #expect(model.settings?.utilityReminderDay == 15 && model.settings?.utilityReminderRepeatDays == 5)
        let sends = service.updates.count
        await model.setReminderDay(29)
        await model.setReminderDay(0)
        await model.setRepeatDays(31)
        await model.setRepeatDays(5)    // unchanged: nothing to send
        #expect(service.updates.count == sends)
        #expect(NotificationSettingsView.repeatText(1) == "каждый день")
        #expect(NotificationSettingsView.repeatText(3) == "каждые 3 дня")
        #expect(NotificationSettingsView.repeatText(5) == "каждые 5 дней")
        #expect(NotificationSettingsView.repeatText(21) == "каждые 21 день")
        #expect(NotificationSettingsView.repeatText(12) == "каждые 12 дней")
    }

    @Test func aRefusedChangeSnapsBackToTheServersValue() async throws {
        let (model, service) = try settingsModel()
        await model.load()
        service.failure = .validation(fields: [UtilityFieldError(field: "utility_reminder_day", message: "out_of_range")])
        await model.setReminderDay(20)
        #expect(model.message != nil)
        #expect(model.settings?.utilityReminderDay == 10)
    }

    @Test func linkingIssuesACodeAndTheOwnerOpensTelegram() async throws {
        let (model, service) = try settingsModel()
        await model.load()
        #expect(!model.isTelegramLinked && model.link == nil)
        await model.startLinking()
        #expect(model.link?.code == "K7M2Q9XW4HPD")
        #expect(model.telegramURL?.absoluteString == "https://t.me/RentfolioBot?start=K7M2Q9XW4HPD")
        #expect(model.telegramGroupURL?.absoluteString.contains("startgroup=") == true)
        #expect(model.startCommand == "/start K7M2Q9XW4HPD")
        // The bot completes the link on the server; coming back to the app refreshes the state.
        service.completeLink()
        await model.refreshLinkStatus()
        #expect(model.isTelegramLinked && model.link == nil)
    }

    @Test func unlinkingForgetsTheChat() async throws {
        let (model, service) = try settingsModel(linked: true)
        await model.load()
        await model.unlink()
        #expect(service.unlinkCalls == 1)
        #expect(!model.isTelegramLinked)
    }

    // MARK: The property form

    private func propertyAndService() throws -> (Property, MockUtilityBillsService) {
        let json = """
        {"id":"7c1e4a52-3b1f-4d1c-9a55-0a1f6c1d2b01","name":"Примерная 1, кв. 1","property_type":"apartment","status":"occupied","utility_payer":"owner"}
        """
        return (try JSONDecoder().decode(Property.self, from: Data(json.utf8)), try MockUtilityBillsService())
    }

    @Test func propertyKeepsItsPayerFromTheRecord() throws {
        let (property, _) = try propertyAndService()
        #expect(property.utilityPayer == .owner)
        let bare = """
        {"id":"p","name":"n","property_type":"apartment","status":"vacant"}
        """
        #expect(try JSONDecoder().decode(Property.self, from: Data(bare.utf8)).utilityPayer == nil)
    }

    @Test func formLoadsThePayerTheAccountAndTheOpenRule() async throws {
        let (property, service) = try propertyAndService()
        let model = UtilityPropertySettingsModel(today: { Date(timeIntervalSince1970: 1_793_620_800) })
        await model.load(property: property, service: service)
        #expect(model.isLoaded && model.payer == .owner)
        #expect(model.accountNumber == "1100000" && model.providerName == "АлСеКо")
        #expect(model.expectsBills && model.months == Set(1...12))
        #expect(!model.hasChanges)
    }

    @Test func changingTheAccountSavesItAndAnEmptyNumberRemovesIt() async throws {
        let (property, service) = try propertyAndService()
        let model = UtilityPropertySettingsModel()
        await model.load(property: property, service: service)
        model.accountNumber = "2200123"
        #expect(model.hasChanges)
        try await model.apply()
        #expect(try await service.account(propertyId: property.id)?.accountNumber == "2200123")
        #expect(!model.hasChanges)
        model.accountNumber = ""
        try await model.apply()
        #expect(try await service.account(propertyId: property.id) == nil)
    }

    @Test func monthsOfTheRuleAreUpdatedAndTheRuleCanBeClosed() async throws {
        let (property, service) = try propertyAndService()
        let model = UtilityPropertySettingsModel(today: { Date(timeIntervalSince1970: 1_793_620_800) })
        await model.load(property: property, service: service)
        model.toggle(month: 7)
        model.toggle(month: 8)
        #expect(model.hasChanges)
        try await model.apply()
        let rules = try await service.expectations(propertyId: property.id)
        #expect(rules.count == 1 && !rules[0].months.contains(7) && !rules[0].months.contains(8) && rules[0].isOpen)

        model.expectsBills = false
        try await model.apply()
        let closed = try await service.expectations(propertyId: property.id)
        #expect(closed.first?.activeTo == "2026-11-02" && closed.first?.isOpen == false)
        // Switched on again later: a new rule starts on the first day of the month.
        model.expectsBills = true
        try await model.apply()
        let reopened = try await service.expectations(propertyId: property.id)
        #expect(reopened.contains { $0.isOpen && $0.activeFrom == "2026-11-01" })
    }

    @Test func atLeastOneMonthStaysSelected() async throws {
        let model = UtilityPropertySettingsModel()
        for month in 1...11 { model.toggle(month: month) }
        #expect(model.months == [12])
        model.toggle(month: 12)
        #expect(model.months == [12])
    }
}
