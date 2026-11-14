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
    @Namespace private var zoomNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .accessibilityIdentifier("tenants.list.screen")
            .searchable(text: $searchText, prompt: "Имя, телефон, email или заметка")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                    .accessibilityLabel("Добавить арендатора")
                    .accessibilityIdentifier("tenants.list.add")
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
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    summarySection
                    ForEach(0..<3, id: \.self) { _ in
                        SurfaceCard(padding: AppTheme.Spacing.md) {
                            HStack(spacing: AppTheme.Spacing.md) {
                                RoundedRectangle(cornerRadius: 6).fill(AppTheme.Colors.backgroundSecondary)
                                    .frame(width: 44, height: 44)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Имя арендатора").font(.headline)
                                    Text("Телефон и почта").font(.caption)
                                }
                            }
                        }
                    }
                }
                .shimmerPlaceholder(true)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.top, AppTheme.Spacing.sm)
            }
            .accessibilityLabel("Загружаем арендаторов")
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
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    summarySection

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
                .padding(.top, AppTheme.Spacing.sm)
                .padding(.bottom, AppTheme.Spacing.xxl + AppTheme.Spacing.xl)
                .animation(
                    AppTheme.Motion.resolved(AppTheme.Motion.normal, reduceMotion: reduceMotion),
                    value: filteredTenants.map(\.id)
                )
            }
        }
    }

    private var summarySection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Директория")
                    .sectionLabelStyle()

                HStack(spacing: 0) {
                    MetricTile(title: "Всего", value: "\(tenants.count)")
                    MetricTile(
                        title: "Заселены",
                        value: "\(Set(leases.filter { $0.status.lowercased() == "active" }.map(\.tenantId)).count)",
                        tint: AppTheme.Colors.accent
                    )
                    MetricTile(title: "Контакты", value: "\(contactCoverage)%")
                }
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
                        property: group.property,
                        cards: group.cards
                    )
                }
            }

            if !unassignedCards.isEmpty {
                tenantGroupSection(
                    title: "Не заселены",
                    subtitle: "\(unassignedCards.count) арендат.",
                    property: nil,
                    cards: unassignedCards
                )
            }
        }
    }

    private func tenantGroupSection(
        title: String,
        subtitle: String,
        property: Property?,
        cards: [TenantLeaseCard]
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(alignment: .bottom, spacing: AppTheme.Spacing.sm) {
                if let property {
                    PropertyGlyph(property: property, height: 36)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .sectionLabelStyle()
                }
                Spacer()
            }
            .padding(.horizontal, AppTheme.Spacing.xs)

            LazyVStack(spacing: AppTheme.Spacing.sm) {
                ForEach(cards) { card in
                    NavigationLink {
                        TenantDetailView(tenantId: card.tenant.id, authManager: authManager) {
                            await loadData()
                        }
                        .environmentObject(authManager)
                        .navigationTransition(.zoom(sourceID: card.id, in: zoomNamespace))
                    } label: {
                        tenantCard(card)
                    }
                    .buttonStyle(.plain)
                    .matchedTransitionSource(id: card.id, in: zoomNamespace)
                    .accessibilityIdentifier("tenants.row.\(card.tenant.id)")
                }
            }
        }
    }

    private func tenantCard(_ card: TenantLeaseCard) -> some View {
        let contacts = [card.tenant.phone, card.tenant.email]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return SurfaceCard(padding: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                    Text(Self.initials(of: card.tenant.displayName))
                        .font(.system(.subheadline, weight: .medium).width(.expanded))
                        .foregroundStyle(AppTheme.Colors.accent)
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.stamp, style: .continuous)
                                .strokeBorder(AppTheme.Colors.accent.opacity(0.45), lineWidth: 1)
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.tenant.displayName.isEmpty ? "Без имени" : card.tenant.displayName)
                            .font(.headline)
                            .foregroundStyle(AppTheme.Colors.textPrimary)

                        Text(contacts.isEmpty ? "Контакты не указаны" : contacts.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .lineLimit(1)

                        if let cohabitants = card.tenant.cohabitants, !cohabitants.isEmpty {
                            Label(cohabitants, systemImage: "person.2")
                                .font(.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                                .lineLimit(1)
                        }
                        if let notes = card.tenant.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(AppTheme.Colors.textTertiary)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 0)

                    if let lease = card.lease {
                        StatusBadge(status: lease.status)
                    } else {
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.accent)
                    }
                }

                if let lease = card.lease {
                    HStack(spacing: 0) {
                        MetricTile(
                            title: "Аренда",
                            value: AppFormatting.currency(lease.rentAmount, currency: lease.rentCurrency)
                        )
                        MetricTile(
                            title: "Заезд",
                            value: AppFormatting.dateString(from: lease.moveInDate ?? lease.startDate) ?? lease.startDate
                        )
                        MetricTile(
                            title: "Оплата",
                            value: paymentWindow(lease)
                        )
                    }

                    if isLeaseEarlyMoveOut(lease) {
                        Label("Выехал раньше срока", systemImage: "exclamationmark.triangle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.warning)
                    }
                } else {
                    Text("Этот арендатор пока не привязан к объекту.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private static func initials(of name: String) -> String {
        let letters = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map { String($0).uppercased() }
        return letters.isEmpty ? "—" : letters.joined()
    }

    private func statusBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.footnote.weight(.medium))
            .foregroundStyle(AppTheme.Colors.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.Spacing.md)
            .background(AppTheme.Colors.warning.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.inner, style: .continuous))
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
        return start == end ? "\(start) числа" : "\(start)–\(end)"
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
