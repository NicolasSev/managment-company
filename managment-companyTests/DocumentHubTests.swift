//
//  DocumentHubTests.swift
//  managment-companyTests
//
//  Mirrored tests for GAP-044 (cross-portfolio document hub): list-path building
//  with filters, entity-type labels, pagination/load-more, and delete + reload.
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

    func fetch(search: String, entityType: String, fileType: String, page: Int, perPage: Int) async throws -> (files: [DocumentFile], total: Int) {
        fetchedPaths.append(DocumentHubViewModel.listPath(search: search, entityType: entityType, fileType: fileType, page: page, perPage: perPage))
        let idx = page - 1
        return (idx < pages.count ? pages[idx] : [], total)
    }
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
}
