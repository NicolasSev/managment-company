//
//  ExpenseReminderTests.swift
//  managment-companyTests
//
//  Mirrored tests for GAP-038 (opt-in daily expense reminder): Today-card
//  gating (enabled, weekday, time, expense-today, dismissed) and notification
//  trigger components.
//

import Foundation
import Testing
@testable import managment_company

@Suite(.serialized)
struct ExpenseReminderTests {

    private let tz = "Asia/Almaty"

    // 2026-06-17 is a Wednesday (Calendar weekday 4). 16:00Z = 21:00 Asia/Almaty.
    private func instant(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    @Test func disabledNeverShowsCard() throws {
        var prefs = ExpenseReminderPreferences.default
        prefs.enabled = false
        let now = try instant("2026-06-17T16:00:00Z")
        #expect(!ExpenseReminderController.shouldShowCard(
            now: now, prefs: prefs, expenseRecordedDayKey: nil, dismissedDayKey: nil, timeZoneIdentifier: tz
        ))
    }

    @Test func showsAfterTimeOnSelectedWeekdayWhenClear() throws {
        var prefs = ExpenseReminderPreferences.default
        prefs.enabled = true
        prefs.hour = 20; prefs.minute = 0
        let now = try instant("2026-06-17T16:00:00Z") // 21:00 local Wed
        #expect(ExpenseReminderController.shouldShowCard(
            now: now, prefs: prefs, expenseRecordedDayKey: nil, dismissedDayKey: nil, timeZoneIdentifier: tz
        ))
    }

    @Test func expenseRecordedTodaySuppressesCard() throws {
        var prefs = ExpenseReminderPreferences.default
        prefs.enabled = true
        let now = try instant("2026-06-17T16:00:00Z")
        #expect(!ExpenseReminderController.shouldShowCard(
            now: now, prefs: prefs, expenseRecordedDayKey: "2026-06-17", dismissedDayKey: nil, timeZoneIdentifier: tz
        ))
    }

    @Test func dismissedTodaySuppressesCard() throws {
        var prefs = ExpenseReminderPreferences.default
        prefs.enabled = true
        let now = try instant("2026-06-17T16:00:00Z")
        #expect(!ExpenseReminderController.shouldShowCard(
            now: now, prefs: prefs, expenseRecordedDayKey: nil, dismissedDayKey: "2026-06-17", timeZoneIdentifier: tz
        ))
    }

    @Test func beforeConfiguredTimeHidesCard() throws {
        var prefs = ExpenseReminderPreferences.default
        prefs.enabled = true
        prefs.hour = 20; prefs.minute = 0
        let now = try instant("2026-06-17T10:00:00Z") // 15:00 local Wed < 20:00
        #expect(!ExpenseReminderController.shouldShowCard(
            now: now, prefs: prefs, expenseRecordedDayKey: nil, dismissedDayKey: nil, timeZoneIdentifier: tz
        ))
    }

    @Test func unselectedWeekdayHidesCard() throws {
        var prefs = ExpenseReminderPreferences.default
        prefs.enabled = true
        prefs.weekdays = [1] // Sunday only; 2026-06-17 is Wednesday
        let now = try instant("2026-06-17T16:00:00Z")
        #expect(!ExpenseReminderController.shouldShowCard(
            now: now, prefs: prefs, expenseRecordedDayKey: nil, dismissedDayKey: nil, timeZoneIdentifier: tz
        ))
    }

    @Test func triggerComponentsOnePerWeekdayAtConfiguredTime() {
        var prefs = ExpenseReminderPreferences.default
        prefs.weekdays = [2, 4, 6]
        prefs.hour = 19; prefs.minute = 30
        let components = ExpenseReminderController.triggerComponents(prefs: prefs)
        #expect(components.count == 3)
        #expect(components.map { $0.weekday } == [2, 4, 6])
        #expect(components.allSatisfy { $0.hour == 19 && $0.minute == 30 })
    }
}
