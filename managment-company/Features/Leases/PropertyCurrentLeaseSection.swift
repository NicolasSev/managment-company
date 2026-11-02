import Combine
import SwiftUI

/// Reads the open leases of a property (`GET /v1/leases?property_id=&status=...`, spec §9.4).
protocol PropertyLeasesClient {
    func fetchOpenLeases(propertyId: String) async throws -> [LeaseCard]
}

struct LivePropertyLeasesClient: PropertyLeasesClient {
    let authManager: AuthManager

    func fetchOpenLeases(propertyId: String) async throws -> [LeaseCard] {
        let envelope: APIListEnvelope<LeaseCard> = try await APIClient.shared.requestRoot(
            "/v1/leases?property_id=\(propertyId)&status=active,pending_signature,draft&per_page=50",
            tokenProvider: { await MainActor.run { authManager.accessToken } },
            refreshAndRetry: { await authManager.refreshToken() }
        )
        return envelope.data
    }
}

/// State of the «Текущий договор» block on the property screen.
@MainActor
final class PropertyCurrentLeaseViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded(LeaseCard?)
        case error
    }

    @Published private(set) var state: State = .loading

    let propertyId: String
    private let client: PropertyLeasesClient

    init(propertyId: String, client: PropertyLeasesClient) {
        self.propertyId = propertyId
        self.client = client
    }

    var lease: LeaseCard? {
        if case .loaded(let lease) = state { return lease }
        return nil
    }

    func load() async {
        do {
            state = .loaded(Self.current(from: try await client.fetchOpenLeases(propertyId: propertyId)))
        } catch {
            // Keep a card that is already on screen; only a first load shows the error.
            if case .loaded = state { return }
            state = .error
        }
    }

    /// The lease the owner works with: the active one, else one waiting for signature, else a
    /// draft; the latest start date wins inside a status.
    static func current(from leases: [LeaseCard]) -> LeaseCard? {
        func rank(_ status: LeaseStatus) -> Int? {
            switch status {
            case .active: return 0
            case .pendingSignature: return 1
            case .draft: return 2
            default: return nil
            }
        }
        return leases
            .compactMap { lease in rank(lease.status).map { (rank: $0, lease: lease) } }
            .sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.lease.startDate > $1.lease.startDate }
            .first?.lease
    }
}

/// «Текущий договор» at the top of the property card: tenant, status, next payment and debt, a
/// tap opens `LeaseDetailView`. Without an open lease it offers «Заселить», which opens the
/// move-in wizard (`SettleWizardView`); after it the card reloads and «К договору» pushes the lease.
struct PropertyCurrentLeaseSection: View {
    @State private var settleContext: SettleWizardContext?
    @StateObject private var viewModel: PropertyCurrentLeaseViewModel
    private let canSettle: Bool

    init(propertyId: String, canSettle: Bool, authManager: AuthManager) {
        self.canSettle = canSettle
        _viewModel = StateObject(wrappedValue: PropertyCurrentLeaseViewModel(
            propertyId: propertyId,
            client: LivePropertyLeasesClient(authManager: authManager)
        ))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                SurfaceCard {
                    HStack {
                        ProgressView()
                        Text("Загружаем договор...")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
            case .error:
                SurfaceCard {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text("Текущий договор")
                            .font(.headline)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Text("Не удалось загрузить договор.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                        Button("Повторить") { Task { await viewModel.load() } }
                            .font(.subheadline.weight(.semibold))
                    }
                }
            case .loaded(let lease?):
                LeaseNavigationLink(leaseId: lease.id, identifier: "property.currentLease") {
                    CurrentLeaseCard(lease: lease, subject: .tenant, identifier: "property.currentLease")
                }
            case .loaded(nil):
                emptyCard
            }
        }
        // First appearance loads; coming back from the lease screen (a payment, a status change)
        // refreshes the card.
        .onAppear {
            Task { await viewModel.load() }
        }
        .settleWizard(context: $settleContext) { await viewModel.load() }
        .onReceive(NotificationCenter.default.publisher(for: .pendingMarkPaidQueueLeaseAffected)) { _ in
            Task { await viewModel.load() }
        }
    }

    private var emptyCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Текущий договор")
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text("Сейчас в объекте нет действующего договора.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                if canSettle {
                    PrimaryButton(title: "Заселить", action: { settleContext = .property(viewModel.propertyId) }, systemImage: "person.badge.plus")
                        .accessibilityIdentifier("property.currentLease.settle")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("property.currentLease.empty")
    }
}
