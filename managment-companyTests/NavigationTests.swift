//
//  NavigationTests.swift
//  managment-companyTests
//
//  Navigation after L13: four primary tabs (Сегодня, Деньги, Объекты, Арендаторы); Tasks,
//  Dashboard and Settings open as secondary sheets from the «Ещё» menu; money routes land on
//  the «Деньги» hub.
//

import Foundation
import Testing
@testable import managment_company

@Suite(.serialized)
struct NavigationTests {

    @MainActor
    @Test func primaryTabsResolveToThemselves() {
        #expect(MainTabView.target(for: .today) == .tab(.today))
        #expect(MainTabView.target(for: .money) == .tab(.money))
        #expect(MainTabView.target(for: .properties) == .tab(.properties))
        #expect(MainTabView.target(for: .tenants) == .tab(.tenants))
    }

    @MainActor
    @Test func moneyRoutesLandOnTheHub() {
        #expect(MainTabView.target(for: .payments) == .tab(.money))
        #expect(MainTabView.target(for: .transactions) == .tab(.money))
    }

    @MainActor
    @Test func secondaryRoutesOpenSheets() {
        #expect(MainTabView.target(for: .dashboard) == .dashboardSheet)
        #expect(MainTabView.target(for: .tasks) == .tasksSheet)
        #expect(MainTabView.target(for: .settings) == .settingsSheet)
    }

    @MainActor
    @Test func tenantNotificationRouteSelectsTheTab() {
        #expect(NotificationRoute(kind: .tenants).tab == .tenants)
        #expect(MainTabView.target(for: NotificationRoute(kind: .task("t1")).tab) == .tasksSheet)
    }
}
