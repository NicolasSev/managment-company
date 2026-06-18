//
//  DocumentHubTests.swift
//  managment-companyTests
//
//  Mirrored tests for GAP-044/GAP-047 (cross-portfolio document hub): list-path
//  building with filters, entity-type labels, pagination/load-more, delete + reload,
//  and property/tenant/date filter path construction.
//

import Foundation
import Testing
@testable import managment_company

private func file(_ id: String, entityType: String = "property", name: String = "doc.pdf") -> DocumentFile {
    DocumentFile(
        id: id, entityType: entityType, entityId: "e1", fileType: "document", originalName: name,
        mimeType: "application/pdf", sizeBytes: 100, downloadURL: "/v1/files/\(id)/download",
        contextName: "Контекст", propertyId: "p1", propertyName: "Алматы", createdAt: "2026-06-01"
    )
}

@MainActor
private final class MockDocumentHubClient: DocumentHubClient {
    var pages: [[DocumentFile]] = []
    var total = 0
    var fetchedPaths: [String] = []
    var deleted: [String] = []

    func fetch(search: String, entityType: String, fileType: String,
               propertyId: String, tenantId: String, dateFrom: String, dateTo: String,
               page: Int, perPage: Int) async throws -> (files: [DocumentFile], total: Int) {
        fetchedPaths.append(DocumentHubViewModel.listPath(
            search: search, entityType: entityType, fileType: fileType,
            propertyId: propertyId, tenantId: tenantId, dateFrom: dateFrom, dateTo: dateTo,
            page: page, perPage: perPage
        ))
        let idx = page - 1
        return (idx < pages.count ? pages[idx] : [], total)
    }

    func fetchProperties() async throws -> [Property] { [] }
    func fetchTenants() async throws -> [Tenant] { [] }
    func delete(id: String) async throws { deleted.append(id) }
}

@Suite(.serialized)
struct DocumentHubTests {

    @Test func listPathIncludesOnlySetFilters() {
        #expect(DocumentHubViewModel.listPath(search: "", entityType: "", fileType: "", page: 1, perPage: 50) == "/v1/files?page=1&per_page=50")
        let withFilters = DocumentHubViewModel.listPath(search: "договор", entityType: "lease", fileType: "contract", page: 2, perPage: 50)
        #expect(withFilters.contains("page=2&per_page=50"))
        #expect(withFilters.contains("entity_type=lease"))
        #expect(withFilters.contains("file_type=contract"))
        #expect(withFilters.contains("search="))
    }

    @Test func listPathIncludesPropertyAndTenantFilters() {
        let path = DocumentHubViewModel.listPath(
            search: "", entityType: "", fileType: "",
            propertyId: "prop-uuid", tenantId: "tenant-uuid",
            page: 1, perPage: 50
        )
        #expect(path.contains("property_id=prop-uuid"))
        #expect(path.contains("tenant_id=tenant-uuid"))
        #expect(!path.contains("date_from"))
        #expect(!path.contains("date_to"))
    }

    @Test func listPathIncludesDateFilters() {
        let path = DocumentHubViewModel.listPath(
            search: "", entityType: "", fileType: "",
            dateFrom: "2026-01-01", dateTo: "2026-06-30",
            page: 1, perPage: 50
        )
        #expect(path.contains("date_from=2026-01-01"))
        #expect(path.contains("date_to=2026-06-30"))
    }

    @Test func listPathOmitsEmptyFilters() {
        let path = DocumentHubViewModel.listPath(
            search: "", entityType: "", fileType: "",
            propertyId: "", tenantId: "", dateFrom: "", dateTo: "",
            page: 1, perPage: 50
        )
        #expect(path == "/v1/files?page=1&per_page=50")
    }

    @Test func entityTypeLabelMapsKnownTypes() {
        #expect(DocumentHubViewModel.entityTypeLabel("property") == "Объект")
        #expect(DocumentHubViewModel.entityTypeLabel("lease") == "Договор")
        #expect(DocumentHubViewModel.entityTypeLabel("") == "Все")
    }

    @MainActor
    @Test func reloadThenLoadMoreAppendsAndPaginates() async {
        let client = MockDocumentHubClient()
        client.total = 3
        client.pages = [[file("a"), file("b")], [file("c")]]
        let vm = DocumentHubViewModel(client: client)

        await vm.reload()
        #expect(vm.files.map(\.id) == ["a", "b"])
        #expect(vm.canLoadMore)

        await vm.loadMore()
        #expect(vm.files.map(\.id) == ["a", "b", "c"])
        #expect(!vm.canLoadMore)
        #expect(client.fetchedPaths.count == 2)
    }

    @MainActor
    @Test func deleteCallsClientAndReloads() async {
        let client = MockDocumentHubClient()
        client.total = 1
        client.pages = [[file("a")]]
        let vm = DocumentHubViewModel(client: client)
        await vm.reload()

        let ok = await vm.delete(file("a"))
        #expect(ok)
        #expect(client.deleted == ["a"])
    }

    @MainActor
    @Test func hasActiveFiltersReflectsFilterState() {
        let client = MockDocumentHubClient()
        let vm = DocumentHubViewModel(client: client)
        #expect(!vm.hasActiveFilters)

        vm.propertyIdFilter = "some-id"
        #expect(vm.hasActiveFilters)

        vm.clearFilters()
        #expect(!vm.hasActiveFilters)
        #expect(vm.propertyIdFilter == "")
        #expect(vm.tenantIdFilter == "")
        #expect(vm.dateFromFilter == nil)
        #expect(vm.dateToFilter == nil)
    }
}
