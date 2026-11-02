import Foundation
import Network

// Seams of the move-in wizard that are not the lease, contract or recognition API: the lists the
// first two steps choose from, and the network state (the wizard does not work offline).

// MARK: - Directory

/// Properties and tenants of the owner, as the first two steps show them.
protocol SettleDirectory {
    func properties() async throws -> [Property]
    func tenants() async throws -> [Tenant]
}

struct LiveSettleDirectory: SettleDirectory {
    let authManager: AuthManager

    func properties() async throws -> [Property] {
        try await APIClient.shared.request(
            "/v1/properties",
            tokenProvider: { await MainActor.run { authManager.accessToken } },
            refreshAndRetry: { await authManager.refreshToken() }
        )
    }

    func tenants() async throws -> [Tenant] {
        try await APIClient.shared.request(
            "/v1/tenants?per_page=100",
            tokenProvider: { await MainActor.run { authManager.accessToken } },
            refreshAndRetry: { await authManager.refreshToken() }
        )
    }
}

/// Sample lists for the mock mode (`LEASE_V2_MOCKS=1`) and the tests.
struct MockSettleDirectory: SettleDirectory {
    var propertiesResult: Result<[Property], Error>
    var tenantsResult: Result<[Tenant], Error>

    init(
        properties: [Property]? = nil,
        tenants: [Tenant]? = nil
    ) {
        propertiesResult = .success(properties ?? Self.sampleProperties)
        tenantsResult = .success(tenants ?? Self.sampleTenants)
    }

    func properties() async throws -> [Property] { try propertiesResult.get() }
    func tenants() async throws -> [Tenant] { try tenantsResult.get() }

    static let sampleProperties: [Property] = (try? JSONDecoder().decode([Property].self, from: Data("""
    [
      {"id":"5b8e0f37-2c19-4d7a-b6e4-1f3a9c7d2e50","name":"ул. Байзакова, 280, кв. 12","property_type":"apartment","city":"Алматы","address":"ул. Байзакова, 280, кв. 12","status":"vacant"},
      {"id":"9d4c2a18-6e53-4f07-8b91-3a7e5c1d0f64","name":"Студия на Абая, 15","property_type":"apartment","city":"Алматы","address":"пр. Абая, 15","status":"vacant"},
      {"id":"3f9a1c22-8e47-4b6d-a0f3-6c2e9d7b5a10","name":"ЖК «Есентай Парк», кв. 47","property_type":"apartment","city":"Алматы","address":"пр. Аль-Фараби, 77/8, кв. 47","status":"occupied"}
    ]
    """.utf8))) ?? []

    static let sampleTenants: [Tenant] = (try? JSONDecoder().decode([Tenant].self, from: Data("""
    [
      {"id":"a52d7e19-0c64-4f1b-8e3a-9b7f2c6d4e21","first_name":"Айгерим","last_name":"Касымова","middle_name":"Нурлановна","phone":"+7 701 555 12 34","iin":"950312401236"},
      {"id":"b81f3c05-7a29-4d6e-9c40-1e5a8b2d7f93","first_name":"Данияр","last_name":"Сейтов","phone":"+7 702 300 41 18","iin":"880114300725"}
    ]
    """.utf8))) ?? []
}

// MARK: - Network state

/// Online or not. The wizard shows «нет сети» at once instead of failing at the last step, and
/// its settle never goes to `PendingMutationQueue` (a half-made move-in must not replay later).
@MainActor
protocol SettleNetworkMonitoring: AnyObject {
    var isOnline: Bool { get }
    func start(onChange: @escaping @MainActor (Bool) -> Void)
    func stop()
}

@MainActor
final class SettlePathMonitor: SettleNetworkMonitoring {
    private(set) var isOnline = true
    private var monitor: NWPathMonitor?

    func start(onChange: @escaping @MainActor (Bool) -> Void) {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                self?.isOnline = online
                onChange(online)
            }
        }
        monitor.start(queue: DispatchQueue(label: "settle.network.monitor"))
        self.monitor = monitor
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }
}

/// Mock mode and tests: always online unless a test flips it.
@MainActor
final class StaticNetworkMonitor: SettleNetworkMonitoring {
    var isOnline: Bool
    private var handler: (@MainActor (Bool) -> Void)?

    init(isOnline: Bool = true) {
        self.isOnline = isOnline
    }

    func start(onChange: @escaping @MainActor (Bool) -> Void) {
        handler = onChange
    }

    func stop() {
        handler = nil
    }

    /// Test hook: network came or went.
    func set(online: Bool) {
        isOnline = online
        handler?(online)
    }
}
