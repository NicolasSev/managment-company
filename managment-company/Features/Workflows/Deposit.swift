import Combine
import Foundation

/// One deposit ledger event (GAP-041): received / deduction / refunded.
struct LeaseDepositEvent: Identifiable, Decodable, Equatable {
    let id: String
    let leaseId: String
    let eventType: String
    let amount: Double
    let currency: String
    let eventDate: String
    let reason: String?
    let transactionId: String?
    let reversedAt: String?

    var isReversed: Bool { reversedAt != nil }

    enum CodingKeys: String, CodingKey {
        case id, amount, currency, reason
        case leaseId = "lease_id"
        case eventType = "event_type"
        case eventDate = "event_date"
        case transactionId = "transaction_id"
        case reversedAt = "reversed_at"
    }
}

/// Canonical deposit balance for a lease.
struct DepositSummary: Decodable, Equatable {
    let leaseId: String
    let expected: Double
    let received: Double
    let deductions: Double
    let refunded: Double
    let held: Double
    let outstanding: Double
    let currency: String
    let status: String
    let events: [LeaseDepositEvent]

    enum CodingKeys: String, CodingKey {
        case expected, received, deductions, refunded, held, outstanding, currency, status, events
        case leaseId = "lease_id"
    }
}

struct DepositEventInput: Encodable {
    let eventType: String
    let amount: Double
    let currency: String
    let eventDate: String
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case amount, currency, reason
        case eventType = "event_type"
        case eventDate = "event_date"
    }
}

@MainActor
protocol DepositClient {
    func summary(leaseId: String) async throws -> DepositSummary
    func createEvent(leaseId: String, input: DepositEventInput) async throws
    func reverseEvent(eventId: String) async throws
}

@MainActor
struct LiveDepositClient: DepositClient {
    let authManager: AuthManager
    private var token: () async -> String? { { await MainActor.run { authManager.accessToken } } }
    private var refresh: () async -> Bool { { await authManager.refreshToken() } }

    private struct Envelope: Decodable { let data: DepositSummary }

    func summary(leaseId: String) async throws -> DepositSummary {
        let data = try await APIClient.shared.requestData("/v1/leases/\(leaseId)/deposit", tokenProvider: token, refreshAndRetry: refresh)
        if let env = try? JSONDecoder().decode(Envelope.self, from: data) { return env.data }
        return try JSONDecoder().decode(DepositSummary.self, from: data)
    }
    func createEvent(leaseId: String, input: DepositEventInput) async throws {
        _ = try await APIClient.shared.requestData("/v1/leases/\(leaseId)/deposit-events", method: "POST", body: input, tokenProvider: token, refreshAndRetry: refresh)
    }
    func reverseEvent(eventId: String) async throws {
        _ = try await APIClient.shared.requestData("/v1/deposit-events/\(eventId)/reverse", method: "POST", tokenProvider: token, refreshAndRetry: refresh)
    }
}

/// Security-deposit lifecycle (GAP-041): summary + received/deduction/refunded
/// events with reversal, against the canonical per-lease deposit API.
@MainActor
final class DepositViewModel: ObservableObject {
    @Published private(set) var summary: DepositSummary?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client: DepositClient
    let leaseId: String
    let baseCurrency: String

    init(client: DepositClient, leaseId: String, baseCurrency: String) {
        self.client = client
        self.leaseId = leaseId
        self.baseCurrency = baseCurrency
    }

    var activeEvents: [LeaseDepositEvent] {
        (summary?.events ?? []).filter { !$0.isReversed }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            summary = try await client.summary(leaseId: leaseId)
        } catch {
            errorMessage = "Не удалось загрузить депозит."
        }
    }

    func addEvent(type: String, amount: Double, reason: String?, now: Date, timeZoneIdentifier: String) async -> Bool {
        let input = DepositEventInput(
            eventType: type,
            amount: amount,
            currency: summary?.currency ?? baseCurrency,
            eventDate: AppFormatting.dayKey(for: now, timeZoneIdentifier: timeZoneIdentifier),
            reason: reason
        )
        return await act { try await self.client.createEvent(leaseId: self.leaseId, input: input) }
    }

    func reverse(_ event: LeaseDepositEvent) async -> Bool {
        await act { try await self.client.reverseEvent(eventId: event.id) }
    }

    private func act(_ work: @escaping () async throws -> Void) async -> Bool {
        errorMessage = nil
        do { try await work(); await load(); return true }
        catch { errorMessage = "Не удалось выполнить операцию."; return false }
    }

    // MARK: - Pure logic (unit-tested)

    static func eventTypeLabel(_ type: String) -> String {
        switch type {
        case "received": return "Получен"
        case "deduction": return "Удержание"
        case "refunded": return "Возврат"
        default: return type
        }
    }

    /// Whether a deduction/refund of `amount` is allowed against currently held.
    nonisolated static func canApply(eventType: String, amount: Double, held: Double) -> Bool {
        guard amount > 0 else { return false }
        if eventType == "deduction" || eventType == "refunded" {
            return amount <= held
        }
        return eventType == "received"
    }
}
