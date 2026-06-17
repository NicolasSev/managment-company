//
//  ChecklistTests.swift
//  managment-companyTests
//
//  Mirrored tests for GAP-043 (move-in/move-out checklists): progress, status
//  toggle, completion, decoding, and start/toggle flow.
//

import Foundation
import Testing
@testable import managment_company

private func item(_ id: String, status: String) -> LeaseChecklistItem {
    LeaseChecklistItem(id: id, code: id, label: "Пункт \(id)", status: status, notes: nil, linkedPath: nil, completedAt: nil)
}

@MainActor
private final class MockChecklistClient: ChecklistClient {
    var checklists: [String: LeaseChecklist] = [:] // kind -> checklist
    var started: [String] = []
    var updated: [(id: String, status: String)] = []

    func get(leaseId: String, kind: String) async throws -> LeaseChecklist? { checklists[kind] }
    func start(leaseId: String, kind: String) async throws {
        started.append(kind)
        checklists[kind] = LeaseChecklist(id: "cl", leaseId: leaseId, kind: kind, status: "in_progress", dueDate: nil,
                                          items: [item("a", status: "pending")])
    }
    func updateItem(itemId: String, status: String, notes: String?) async throws {
        updated.append((itemId, status))
    }
}

@Suite(.serialized)
struct ChecklistTests {

    @Test func progressCountsDone() {
        let items = [item("a", status: "done"), item("b", status: "pending"), item("c", status: "done")]
        let p = ChecklistViewModel.progress(items)
        #expect(p.done == 2)
        #expect(p.total == 3)
    }

    @Test func nextStatusTogglesAndCompletion() {
        #expect(ChecklistViewModel.nextStatus("pending") == "done")
        #expect(ChecklistViewModel.nextStatus("done") == "pending")
        #expect(!ChecklistViewModel.isComplete([]))
        #expect(!ChecklistViewModel.isComplete([item("a", status: "pending")]))
        #expect(ChecklistViewModel.isComplete([item("a", status: "done")]))
    }

    @Test func decodesChecklistEnvelopeItems() throws {
        let json = """
        {"id":"cl","lease_id":"l1","kind":"move_in","status":"in_progress","due_date":null,
        "items":[{"id":"i1","code":"keys","label":"Ключи","status":"done","notes":"2 шт","linked_path":null,"completed_at":"2026-06-01"}]}
        """
        let cl = try JSONDecoder().decode(LeaseChecklist.self, from: json.data(using: .utf8)!)
        #expect(cl.kind == "move_in")
        #expect(cl.items.count == 1)
        #expect(cl.items[0].isDone)
        #expect(cl.items[0].notes == "2 шт")
    }

    @MainActor
    @Test func startThenToggleCallClient() async {
        let client = MockChecklistClient()
        let vm = ChecklistViewModel(client: client, leaseId: "l1")
        await vm.load()
        #expect(!vm.isStarted)

        let started = await vm.start()
        #expect(started)
        #expect(client.started == ["move_in"])
        #expect(vm.isStarted)
        #expect(vm.progress.total == 1)

        let toggled = await vm.toggle(item("a", status: "pending"))
        #expect(toggled)
        #expect(client.updated.last?.status == "done")
    }
}
