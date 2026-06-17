//
//  QuickDocumentTests.swift
//  managment-companyTests
//
//  Mirrored tests for GAP-036 (quick document upload with target search): target
//  search filtering, entity-type mapping, target loading + context preselect,
//  and upload flow.
//

import Foundation
import Testing
@testable import managment_company

private func docProperty(_ id: String, _ name: String) -> Property {
    Property(
        id: id, name: name, propertyType: "apartment", country: nil, city: nil, address: "ул. \(name)",
        district: nil, areaSqm: nil, rooms: nil, floor: nil, purchaseDate: nil, purchasePrice: nil,
        purchaseCurrency: nil, currentValue: nil, currentValueCurrency: nil, status: "vacant",
        notes: nil, tags: nil, utilityAccountNumber: nil, wifiLogin: nil, wifiPassword: nil
    )
}

@MainActor
private final class MockQuickDocumentClient: QuickDocumentClient {
    var properties: [Property] = []
    var tenants: [Tenant] = []
    var transactions: [Transaction] = []
    var uploads: [(entityType: String, entityId: String, fileType: String)] = []
    var failUpload = false
    private struct Boom: Error {}

    func fetchProperties() async throws -> [Property] { properties }
    func fetchTenants() async throws -> [Tenant] { tenants }
    func fetchTransactions(propertyIds: [String]) async throws -> [Transaction] { transactions }
    func upload(entityType: String, entityId: String, fileType: String, fileData: Data, fileName: String, mimeType: String) async throws {
        if failUpload { throw Boom() }
        uploads.append((entityType, entityId, fileType))
    }
}

@Suite(.serialized)
struct QuickDocumentTests {

    @Test func targetTypeMapsToApiEntityType() {
        #expect(DocumentTargetType.property.apiEntityType == "property")
        #expect(DocumentTargetType.tenant.apiEntityType == "tenant")
        #expect(DocumentTargetType.transaction.apiEntityType == "transaction")
    }

    @Test func searchMatchesTitleAndSubtitleCaseInsensitively() {
        let items = [
            DocumentTargetItem(id: "1", title: "Алматы центр", subtitle: "ул. Абая"),
            DocumentTargetItem(id: "2", title: "Астана", subtitle: "пр. Кабанбай"),
        ]
        #expect(QuickDocumentViewModel.search(items, query: "").count == 2)
        #expect(QuickDocumentViewModel.search(items, query: "абая").map(\.id) == ["1"])
        #expect(QuickDocumentViewModel.search(items, query: "АСТАНА").map(\.id) == ["2"])
        #expect(QuickDocumentViewModel.search(items, query: "zzz").isEmpty)
    }

    @MainActor
    @Test func loadTargetsBuildsPropertyItemsAndKeepsContextSelection() async {
        let client = MockQuickDocumentClient()
        client.properties = [docProperty("p1", "Алматы"), docProperty("p2", "Астана")]
        let vm = QuickDocumentViewModel(client: client, contextPropertyId: "p2")

        await vm.loadTargets()

        #expect(vm.items.count == 2)
        #expect(vm.selectedEntityId == "p2")
        #expect(vm.canUpload)
    }

    @MainActor
    @Test func uploadRequiresSelectionThenSucceeds() async {
        let client = MockQuickDocumentClient()
        client.properties = [docProperty("p1", "Алматы")]
        let vm = QuickDocumentViewModel(client: client)
        await vm.loadTargets()

        // No selection yet.
        let blocked = await vm.upload(fileData: Data(), fileName: "f.pdf", mimeType: "application/pdf")
        #expect(!blocked)
        #expect(vm.errorMessage != nil)

        vm.selectedEntityId = "p1"
        vm.fileType = "contract"
        let ok = await vm.upload(fileData: Data([0x25]), fileName: "lease.pdf", mimeType: "application/pdf")

        #expect(ok)
        #expect(vm.didUpload)
        #expect(client.uploads.count == 1)
        #expect(client.uploads[0].entityType == "property")
        #expect(client.uploads[0].entityId == "p1")
        #expect(client.uploads[0].fileType == "contract")
    }
}
