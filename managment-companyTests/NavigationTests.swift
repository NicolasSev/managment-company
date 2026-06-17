//
//  NavigationTests.swift
//  managment-companyTests
//
//  Mirrored tests for GAP-037 (five-position navigation): routes moved out of
//  the primary bar resolve to secondary sheets; money routes land on the hub;
//  primary tabs resolve to themselves.
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
        #expect(MainTabView.target(for: .tasks) == .tab(.tasks))
    }

    @MainActor
    @Test func moneyRoutesLandOnTheHub() {
        #expect(MainTabView.target(for: .payments) == .tab(.money))
        #expect(MainTabView.target(for: .transactions) == .tab(.money))
    }

    @MainActor
    @Test func secondaryRoutesOpenSheets() {
        #expect(MainTabView.target(for: .dashboard) == .dashboardSheet)
        #expect(MainTabView.target(for: .tenants) == .tenantsSheet)
        #expect(MainTabView.target(for: .settings) == .settingsSheet)
    }
}
