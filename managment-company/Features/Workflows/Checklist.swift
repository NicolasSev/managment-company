import Combine
import Foundation

/// One lease lifecycle checklist item (GAP-043).
struct LeaseChecklistItem: Identifiable, Decodable, Equatable {
    let id: String
    let code: String
    let label: String
    let status: String
    let notes: String?
    let linkedPath: String?
    let completedAt: String?

    var isDone: Bool { status == "done" }

    enum CodingKeys: String, CodingKey {
        case id, code, label, status, notes
        case linkedPath = "linked_path"
        case completedAt = "completed_at"
    }
}

/// A move-in or move-out checklist bound to a lease.
struct LeaseChecklist: Decodable, Equatable {
    let id: String
    let leaseId: String
    let kind: String
    let status: String
    let dueDate: String?
    let items: [LeaseChecklistItem]

    enum CodingKeys: String, CodingKey {
        case id, kind, status, items
        case leaseId = "lease_id"
        case dueDate = "due_date"
    }
}

enum ChecklistKind: String, CaseIterable, Identifiable {
    case moveIn = "move_in"
    case moveOut = "move_out"
    var id: String { rawValue }
    var title: String { self == .moveIn ? "Заезд" : "Выезд" }
}

@MainActor
protocol ChecklistClient {
    func get(leaseId: String, kind: String) async throws -> LeaseChecklist?
    func start(leaseId: String, kind: String) async throws
    func updateItem(itemId: String, status: String, notes: String?) async throws
}

@MainActor
struct LiveChecklistClient: ChecklistClient {
    let authManager: AuthManager
    private var token: () async -> String? { { await MainActor.run { authManager.accessToken } } }
    private var refresh: () async -> Bool { { await authManager.refreshToken() } }

    private struct Envelope: Decodable { let data: LeaseChecklist? }

    func get(leaseId: String, kind: String) async throws -> LeaseChecklist? {
        let data = try await APIClient.shared.requestData("/v1/leases/\(leaseId)/checklists/\(kind)", tokenProvider: token, refreshAndRetry: refresh)
        if let env = try? JSONDecoder().decode(Envelope.self, from: data) { return env.data }
        return try? JSONDecoder().decode(LeaseChecklist.self, from: data)
    }
    func start(leaseId: String, kind: String) async throws {
        _ = try await APIClient.shared.requestData("/v1/leases/\(leaseId)/checklists/\(kind)", method: "POST", tokenProvider: token, refreshAndRetry: refresh)
    }
    func updateItem(itemId: String, status: String, notes: String?) async throws {
        struct Body: Encodable { let status: String; let notes: String? }
        _ = try await APIClient.shared.requestData("/v1/checklist-items/\(itemId)", method: "PATCH", body: Body(status: status, notes: notes), tokenProvider: token, refreshAndRetry: refresh)
    }
}

/// Move-in / move-out checklist workspace (GAP-043). Toggling presentation items
/// never mutates lease status by itself.
@MainActor
final class ChecklistViewModel: ObservableObject {
    @Published var kind: ChecklistKind = .moveIn {
        didSet { if kind != oldValue { Task { await load() } } }
    }
    @Published private(set) var checklist: LeaseChecklist?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client: ChecklistClient
    let leaseId: String

    init(client: ChecklistClient, leaseId: String) {
        self.client = client
        self.leaseId = leaseId
    }

    var isStarted: Bool { checklist != nil }
    var items: [LeaseChecklistItem] { checklist?.items ?? [] }
    var progress: (done: Int, total: Int) { Self.progress(items) }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            checklist = try await client.get(leaseId: leaseId, kind: kind.rawValue)
        } catch {
            errorMessage = "Не удалось загрузить чек-лист."
        }
    }

    func start() async -> Bool {
        await act { try await self.client.start(leaseId: self.leaseId, kind: self.kind.rawValue) }
    }

    func toggle(_ item: LeaseChecklistItem) async -> Bool {
        await act { try await self.client.updateItem(itemId: item.id, status: Self.nextStatus(item.status), notes: item.notes) }
    }

    private func act(_ work: @escaping () async throws -> Void) async -> Bool {
        errorMessage = nil
        do { try await work(); await load(); return true }
        catch { errorMessage = "Не удалось выполнить действие."; return false }
    }

    // MARK: - Pure logic (unit-tested)

    nonisolated static func progress(_ items: [LeaseChecklistItem]) -> (done: Int, total: Int) {
        (items.filter { $0.isDone }.count, items.count)
    }

    nonisolated static func nextStatus(_ status: String) -> String {
        status == "done" ? "pending" : "done"
    }

    nonisolated static func isComplete(_ items: [LeaseChecklistItem]) -> Bool {
        !items.isEmpty && items.allSatisfy { $0.isDone }
    }
}
