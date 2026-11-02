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

    /// `POST /v1/workflows/settle` (spec §9.7): tenant, draft lease and the next step in one
    /// transaction. One `idempotencyKey` per wizard opening: a repeat after a network failure
    /// replays the first answer. Failures are `SettleError`.
    func settle(_ request: SettleRequest, idempotencyKey: String) async throws -> SettleResponse
}

/// Failures of the settle command the wizard answers one by one (spec §9.7 and §11).
enum SettleError: Error, Equatable {
    /// `409 TENANT_IIN_CONFLICT`: the owner has a tenant with this IIN under another name.
    case tenantIINConflict(stored: SettleTenant?, provided: SettleProvidedName?)
    /// `409 LEASE_OVERLAP`: the dates collide with another lease of the property.
    case leaseOverlap(conflictingLeaseId: String?, from: String?, to: String?)
    /// `422 TENANT_IDENTITY_INCOMPLETE`: `details.missing`, field names of the tenant.
    case identityIncomplete(missing: [String])
    /// `400 VALIDATION_ERROR`: `details[]` with body paths (`tenant.iin`, `lease.rent_amount`).
    case validation(fields: [SettleFieldError])
    /// `422 REPLACE_TARGET_INVALID`.
    case replaceTargetInvalid
    /// Anything else, in the vocabulary of the lease screens (`transport`, `unauthorized`, ...).
    case other(LeaseV2Error)

    var isTransport: Bool {
        if case .other(.transport) = self { return true }
        return false
    }
}

nonisolated struct SettleProvidedName: Equatable {
    var firstName: String?
    var lastName: String?
    var middleName: String?

    var fullName: String {
        [lastName, firstName, middleName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

nonisolated struct SettleFieldError: Equatable {
    var field: String
    var message: String
}

/// Picks the service the lease screens use: `LiveLeaseV2Service` by default. The fixture-backed
/// `MockLeaseV2Service` is for previews and tests only; it is selected by `LEASE_V2_MOCKS=1`
/// (environment) or the launch argument `-lease_v2_mocks 1`, or by setting `useMocks`.
@MainActor
enum LeaseV2ServiceProvider {
    /// Forces the mock service. Off unless the environment or launch argument asks for it.
    static var useMocks: Bool = {
        ProcessInfo.processInfo.environment["LEASE_V2_MOCKS"] == "1"
            || UserDefaults.standard.bool(forKey: "lease_v2_mocks")
    }()

    private static var sharedMock: MockLeaseV2Service?

    /// Fixture lease ids that `MockLeaseV2Service` serves (previews and tests).
    static let mockLeaseIds = MockLeaseV2Service.fixtureLeaseIds

    static func makeService(authManager: AuthManager) -> LeaseV2Service {
        if useMocks {
            return mock()
        }
        return LiveLeaseV2Service(authManager: authManager)
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
