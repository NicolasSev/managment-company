//
//  QuickActionsTests.swift
//  managment-companyTests
//
//  Mirrored tests for GAP-032 (global quick-action launcher): fixed action
//  order, prerequisite/availability rules, and context preselection.
//

import Foundation
import Testing
@testable import managment_company

@Suite(.serialized)
struct QuickActionsTests {

    @Test func actionOrderMatchesWebLauncher() {
        #expect(QuickActionsController.orderedActions == [
            .payment, .expense, .receipt, .task, .document, .tenant,
        ])
    }

    @Test func expenseAndReceiptRequireAProperty() {
        #expect(QuickActionsController.prerequisite(for: .expense, hasProperties: false) != nil)
        #expect(QuickActionsController.prerequisite(for: .receipt, hasProperties: false) != nil)
        #expect(QuickActionsController.prerequisite(for: .expense, hasProperties: true) == nil)
        #expect(QuickActionsController.prerequisite(for: .receipt, hasProperties: true) == nil)
    }

    @Test func paymentTaskTenantAlwaysAvailable() {
        for kind in [QuickActionKind.payment, .task, .tenant, .document] {
            #expect(QuickActionsController.isAvailable(kind, hasProperties: false))
        }
    }

    @MainActor
    @Test func openSetsActiveActionAndClosesMenu() {
        let controller = QuickActionsController()
        controller.presentMenu()
        #expect(controller.isMenuPresented)

        controller.open(.expense)
        #expect(!controller.isMenuPresented)
        #expect(controller.activeAction == .expense)

        controller.close()
        #expect(controller.activeAction == nil)
    }

    @MainActor
    @Test func contextPreselectionIsStoredAndCleared() {
        let controller = QuickActionsController()
        controller.setContext(propertyId: "prop-1", tenantId: "ten-9")
        #expect(controller.contextPropertyId == "prop-1")
        #expect(controller.contextTenantId == "ten-9")

        controller.clearContext()
        #expect(controller.contextPropertyId == nil)
        #expect(controller.contextTenantId == nil)
    }

    @MainActor
    @Test func setContextOnlyOverwritesProvidedFields() {
        let controller = QuickActionsController()
        controller.setContext(propertyId: "prop-1")
        controller.setContext(tenantId: "ten-2")
        #expect(controller.contextPropertyId == "prop-1")
        #expect(controller.contextTenantId == "ten-2")
    }

    @Test func everyActionHasTitleAndIcon() {
        for kind in QuickActionKind.allCases {
            #expect(!kind.title.isEmpty)
            #expect(!kind.systemImage.isEmpty)
        }
    }
}
