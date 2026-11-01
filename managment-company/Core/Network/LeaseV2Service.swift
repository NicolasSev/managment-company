import Foundation

/// Failures of the lease-v2 commands. `Live` maps HTTP statuses here; `Mock` throws them to
/// imitate the server rules of `docs/product/lease-v2-spec.md` §2.1 and §11.
enum LeaseV2Error: Error, Equatable {
    case notFound
    /// `412 VERSION_MISMATCH`: the lease changed since it was loaded.
    case versionMismatch(currentVersion: Int?)
    /// `422 INVALID_STATE_TRANSITION`.
    case invalidStateTransition(command: String)
    /// `400/422` field validation. `message` is Russian, ready for the UI.
    case validation(message: String)
    /// `409 LEASE_OVERLAP` and other conflicts.
    case conflict(message: String)
    /// `422 AMOUNT_EXCEEDS_OUTSTANDING`, `CHARGE_NOT_OPEN`.
    case chargeNotPayable
    /// `422 DEPOSIT_BALANCE_EXCEEDED`.
    case depositBalanceExceeded(held: Money?)
    /// `422 IDEMPOTENCY_KEY_REUSED`.
    case idempotencyKeyReused
    /// Transport or 5xx failure; the money commands may be queued for retry.
    case transport
    case unauthorized
    case unknown

    /// Message for the sheet footer or the screen banner.
    @MainActor
    var userMessage: String {
        switch self {
        case .notFound: return "Договор не найден."
        case .versionMismatch: return "Договор изменился. Обновите экран и повторите."
        case .invalidStateTransition: return "Это действие недоступно в текущем статусе договора."
        case .validation(let message): return message
        case .conflict(let message): return message
        case .chargeNotPayable: return "Начисление уже закрыто или не подлежит оплате."
        case .depositBalanceExceeded(let held):
            if let held { return "Сумма больше удерживаемого депозита (\(held.formatted()))." }
            return "Сумма больше удерживаемого депозита."
        case .idempotencyKeyReused: return "Операция уже выполнялась с другими данными. Закройте окно и повторите."
        case .transport: return "Нет связи с сервером."
        case .unauthorized: return "Сессия истекла. Войдите снова."
        case .unknown: return "Не удалось выполнить действие."
        }
    }

    /// Money commands may be parked in `PendingMutationQueue` only for these.
    var isRetryable: Bool {
        if case .transport = self { return true }
        return false
    }
}

/// Everything the lease screen needs from the API (spec §9). Each command returns the full
/// refreshed aggregate (`Every lease command response is the full aggregate`), so the view
/// model replaces its state and never refetches.
///
/// `version` is the aggregate version the user saw; it goes out as `If-Match: "<version>"`.
/// Money-creating commands take an `idempotencyKey` generated once per user intent.
protocol LeaseV2Service {
    func fetchLease(id: String) async throws -> LeaseAggregate

    func markSigned(leaseId: String, version: Int, request: MarkSignedRequest, scan: LeaseScanAttachment?) async throws -> LeaseAggregate
    func activate(leaseId: String, version: Int, request: ActivateLeaseRequest) async throws -> LeaseAggregate
    func cancel(leaseId: String, version: Int, request: CancelLeaseRequest) async throws -> LeaseAggregate
    func terminate(leaseId: String, version: Int, request: TerminateLeaseRequest) async throws -> LeaseAggregate
    func amendRent(leaseId: String, version: Int, request: AmendRentRequest) async throws -> LeaseAggregate

    func addExtraCharge(leaseId: String, version: Int, request: AddExtraChargeRequest, idempotencyKey: String) async throws -> LeaseAggregate
    func payCharge(leaseId: String, chargeId: String, request: PayChargeRequest, idempotencyKey: String) async throws -> LeaseAggregate
    func returnDeposit(leaseId: String, version: Int, request: ReturnDepositRequest, idempotencyKey: String) async throws -> LeaseAggregate
}

/// Picks the service the lease screens use. Until L8 connects the real API the app runs on
/// the fixture-backed mock; flipping `useLiveAPI` (or launching with
/// `LEASE_V2_LIVE=1`) switches every lease screen to `LiveLeaseV2Service`.
@MainActor
enum LeaseV2ServiceProvider {
    /// Switch for L8. `false` keeps the screens on `MockLeaseV2Service`.
    static var useLiveAPI: Bool = ProcessInfo.processInfo.environment["LEASE_V2_LIVE"] == "1"

    /// Temporary entry point (task L12) into the lease screen from the tenant card. Visible in
    /// DEBUG builds and when launched with `LEASE_V2_MOCKS=1` or `-lease_v2_mocks 1`. The
    /// final navigation (tenants tab, property card) replaces it in L13.
    static var isMockEntryVisible: Bool {
        #if DEBUG
        return true
        #else
        return ProcessInfo.processInfo.environment["LEASE_V2_MOCKS"] == "1"
            || UserDefaults.standard.bool(forKey: "lease_v2_mocks")
        #endif
    }

    private static var sharedMock: MockLeaseV2Service?

    /// Fixture lease ids that `MockLeaseV2Service` serves (for the temporary entry point).
    static let mockLeaseIds = MockLeaseV2Service.fixtureLeaseIds

    static func makeService(authManager: AuthManager) -> LeaseV2Service {
        if useLiveAPI {
            return LiveLeaseV2Service(authManager: authManager)
        }
        return mock()
    }

    /// One mock for the whole process, so edits made on the screen survive navigating away.
    static func mock() -> MockLeaseV2Service {
        if let sharedMock { return sharedMock }
        let mock = (try? MockLeaseV2Service.fromFixtures(latency: .milliseconds(250))) ?? MockLeaseV2Service(leases: [])
        sharedMock = mock
        return mock
    }

    /// Drops the in-memory mock state (back to the fixtures).
    static func resetMock() {
        sharedMock = nil
    }
}
