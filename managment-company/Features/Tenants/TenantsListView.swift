import SwiftUI

private struct TenantLeaseCard: Identifiable {
    var id: String { lease?.id ?? tenant.id }
    let tenant: Tenant
    let lease: Lease?
    let property: Property?
}

struct TenantsListView: View {
    @EnvironmentObject private var authManager: AuthManager

    @State private var tenants: [Tenant] = []
    @State private var properties: [Property] = []
    @State private var leases: [Lease] = []
    @State private var searchText = ""
    @State private var showCreateSheet = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var filteredTenants: [Tenant] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return tenants }
        return tenants.filter { tenant in
            [
                tenant.firstName,
                tenant.lastName,
                tenant.phone,
                tenant.email,
                tenant.cohabitants,
                tenant.notes
            ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
            .contains(query)
        }
    }

    private var tenantsById: [String: Tenant] {
        Dictionary(uniqueKeysWithValues: tenants.map { ($0.id, $0) })
    }

    private var filteredTenantIds: Set<String> {
        Set(filteredTenants.map(\.id))
    }

    private var propertyGroups: [(property: Property, cards: [TenantLeaseCard])] {
        properties.map { property in
            let cards = leases
                .filter { $0.propertyId == property.id && filteredTenantIds.contains($0.tenantId) }
                .compactMap { lease -> TenantLeaseCard? in
                    guard let tenant = tenantsById[lease.tenantId] else { return nil }
                    return TenantLeaseCard(tenant: tenant, lease: lease, property: property)
                }
                .sorted { left, right in
                    let leftActive = left.lease?.status.lowercased() == "active"
                    let rightActive = right.lease?.status.lowercased() == "active"
                    if leftActive != rightActive { return leftActive }
                    return (left.lease?.moveInDate ?? left.lease?.startDate ?? "") > (right.lease?.moveInDate ?? right.lease?.startDate ?? "")
                }
            return (property, cards)
        }
    }

    private var unassignedCards: [TenantLeaseCard] {
        let tenantIdsWithLeases = Set(leases.map(\.tenantId))
        return filteredTenants
            .filter { !tenantIdsWithLeases.contains($0.id) }
            .sorted { $0.displayName < $1.displayName }
            .map { TenantLeaseCard(tenant: $0, lease: nil, property: nil) }
    }

    private var contactCoverage: Int {
        guard !tenants.isEmpty else { return 0 }
        let filled = tenants.filter { $0.email?.isEmpty == false || $0.phone?.isEmpty == false }.count
        return Int((Double(filled) / Double(tenants.count) * 100).rounded())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground()
                content
            }
            .navigationTitle("Арендаторы")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                    .accessibilityLabel("Добавить арендатора")
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                TenantFormSheet {
                    await loadData()
                }
                .environmentObject(authManager)
            }
            .task { await loadData() }
            .refreshable { await loadData() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && tenants.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, tenants.isEmpty {
            EmptyStateView(
                title: "Арендаторы недоступны",
                message: errorMessage,
                actionName: "Повторить",
                action: { Task { await loadData() } },
                icon: "person.2"
            )
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    summarySection
                    searchSection

                    if let errorMessage {
                        statusBanner(errorMessage)
                    }

                    if tenants.isEmpty {
                        EmptyStateView(
                            title: "Арендаторов пока нет",
                            message: "Создайте арендатора, затем заселите его в нужный объект.",
                            actionName: "Добавить арендатора",
                            action: { showCreateSheet = true },
                            icon: "person.badge.plus"
                        )
                    } else if filteredTenants.isEmpty {
                        SurfaceCard {
                            Text("По этому поиску арендаторы не найдены.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    } else {
                        tenantGroups
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.lg)
            }
        }
    }

    private var summarySection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Директория арендаторов")
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                HStack(spacing: AppTheme.Spacing.sm) {
                    metricCard(title: "Всего", value: "\(tenants.count)")
                    metricCard(title: "С почтой", value: "\(tenants.filter { $0.email?.isEmpty == false }.count)")
                    metricCard(title: "Контакты", value: "\(contactCoverage)%")
                }

                PrimaryButton(
                    title: "Добавить арендатора",
                    action: { showCreateSheet = true },
                    systemImage: "plus"
                )
            }
        }
    }

    private var searchSection: some View {
        SurfaceCard(padding: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                TextField("Поиск по имени, email, телефону или заметкам", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            }
        }
    }

    private var tenantGroups: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            ForEach(propertyGroups, id: \.property.id) { group in
                if !group.cards.isEmpty {
                    tenantGroupSection(
                        title: group.property.name,
                        subtitle: "\(group.cards.count) арендат.",
                        cards: group.cards
                    )
                }
            }

            if !unassignedCards.isEmpty {
                tenantGroupSection(
                    title: "Не заселены",
                    subtitle: "\(unassignedCards.count) арендат.",
                    cards: unassignedCards
                )
            }
        }
    }

    private func tenantGroupSection(title: String, subtitle: String, cards: [TenantLeaseCard]) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    Spacer()
                }

                LazyVStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(cards) { card in
                        NavigationLink {
                            TenantDetailView(tenantId: card.tenant.id) {
                                await loadData()
                            }
                            .environmentObject(authManager)
                        } label: {
                            tenantCard(card)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func tenantCard(_ card: TenantLeaseCard) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.tenant.displayName.isEmpty ? "Без имени" : card.tenant.displayName)
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)

                    Text(card.tenant.notes?.isEmpty == false ? card.tenant.notes! : "Заметок пока нет")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                if let lease = card.lease {
                    StatusBadge(status: lease.status)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Label(card.tenant.phone?.isEmpty == false ? card.tenant.phone! : "Телефон не указан", systemImage: "phone")
                Label(card.tenant.email?.isEmpty == false ? card.tenant.email! : "Почта не указана", systemImage: "envelope")
                Label(card.tenant.cohabitants?.isEmpty == false ? card.tenant.cohabitants! : "Состав проживающих не указан", systemImage: "person.2")
            }
            .font(.caption)
            .foregroundStyle(AppTheme.Colors.textSecondary)

            if let lease = card.lease {
                HStack(spacing: AppTheme.Spacing.sm) {
                    metricCard(
                        title: "Аренда",
                        value: AppFormatting.compactAmount(lease.rentAmount, currency: lease.rentCurrency)
                    )
                    metricCard(
                        title: "Заезд",
                        value: AppFormatting.dateString(from: lease.moveInDate ?? lease.startDate) ?? lease.startDate
                    )
                    metricCard(
                        title: "Оплата",
                        value: paymentWindow(lease)
                    )
                }

                if isLeaseEarlyMoveOut(lease) {
                    Label("Выехал раньше срока", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.warning)
                }
            } else {
                Text("Этот арендатор пока не привязан к объекту.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func metricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.sm)
        .background(Color.white.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func statusBanner(_ message: String) -> some View {
        Text(message)
            .font(.footnote.weight(.medium))
            .foregroundStyle(AppTheme.Colors.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.Spacing.md)
            .background(AppTheme.Colors.warning.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @MainActor
    private func loadData() async {
        errorMessage = nil
        if tenants.isEmpty { isLoading = true }
        defer { isLoading = false }

        do {
            async let tenantsRequest: [Tenant] = APIClient.shared.request(
                "/v1/tenants?per_page=100",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            async let propertiesRequest: [Property] = APIClient.shared.request(
                "/v1/properties",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )

            let (loadedTenants, loadedProperties) = try await (tenantsRequest, propertiesRequest)
            tenants = loadedTenants.sorted { $0.displayName < $1.displayName }
            properties = loadedProperties.sorted { $0.name < $1.name }

            var loadedLeases: [Lease] = []
            for property in loadedProperties {
                let propertyLeases: [Lease] = try await APIClient.shared.request(
                    "/v1/properties/\(property.id)/leases",
                    tokenProvider: { await MainActor.run { authManager.accessToken } },
                    refreshAndRetry: { await authManager.refreshToken() }
                )
                loadedLeases.append(contentsOf: propertyLeases)
            }
            leases = loadedLeases
        } catch {
            if tenants.isEmpty {
                tenants = []
                properties = []
                leases = []
            }
            errorMessage = "Не удалось загрузить арендаторов."
        }
    }

    private func paymentWindow(_ lease: Lease) -> String {
        let start = lease.paymentWindowStartDay ?? lease.paymentDay ?? 1
        let end = lease.paymentWindowEndDay ?? lease.paymentDueDay ?? lease.paymentDay ?? start
        return "\(start)-\(end)"
    }

    private func isLeaseEarlyMoveOut(_ lease: Lease) -> Bool {
        if lease.terminationReason?.trimmingCharacters(in: .whitespacesAndNewlines) == "Выехал раньше срока" {
            return true
        }
        guard let terminatedAt = lease.terminatedAt,
              let endDate = lease.endDate else {
            return false
        }
        return terminatedAt < endDate
    }
}
