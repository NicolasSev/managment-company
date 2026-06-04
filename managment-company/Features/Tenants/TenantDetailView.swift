import SwiftUI

struct TenantDetailView: View {
    let tenantId: String
    let onChanged: () async -> Void

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var tenant: Tenant?
    @State private var leases: [Lease] = []
    @State private var properties: [Property] = []
    @State private var showEditSheet = false
    @State private var showDeleteConfirmation = false
    @State private var isLoading = true
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private var activeLeaseCount: Int {
        leases.filter { $0.status.lowercased() == "active" }.count
    }

    private var propertiesById: [String: Property] {
        Dictionary(uniqueKeysWithValues: properties.map { ($0.id, $0) })
    }

    var body: some View {
        ZStack {
            AppScreenBackground()
            content
        }
        .navigationTitle(tenant?.displayName.isEmpty == false ? tenant!.displayName : "Арендатор")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Редактировать") { showEditSheet = true }
                    .disabled(tenant == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(tenant == nil)
                .accessibilityLabel("Удалить арендатора")
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if let tenant {
                TenantFormSheet(tenant: tenant) {
                    await loadData()
                    await onChanged()
                }
                .environmentObject(authManager)
            }
        }
        .confirmationDialog(
            "Удалить арендатора?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                Task { await deleteTenant() }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            if activeLeaseCount > 0 {
                Text("У арендатора есть активная аренда. Перед удалением лучше отметить выезд или прекратить договор.")
            } else {
                Text("Карточка арендатора исчезнет из списка. История договоров и операций останется в системе.")
            }
        }
        .task(id: tenantId) { await loadData() }
        .refreshable { await loadData() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && tenant == nil {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, tenant == nil {
            EmptyStateView(
                title: "Арендатор недоступен",
                message: errorMessage,
                actionName: "Повторить",
                action: { Task { await loadData() } },
                icon: "person.crop.circle.badge.exclamationmark"
            )
        } else if let tenant {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    if let errorMessage {
                        statusBanner(errorMessage)
                    }

                    profileSection(tenant)

                    EntityFilesSection(
                        entityType: "tenant",
                        entityId: tenant.id,
                        title: "Документы арендатора",
                        fileTypes: [
                            EntityFileType(value: "passport", label: "Паспорт"),
                            EntityFileType(value: "id_card", label: "Удостоверение"),
                            EntityFileType(value: "document", label: "Документ"),
                            EntityFileType(value: "photo", label: "Фото")
                        ]
                    )
                    .environmentObject(authManager)

                    leaseHistorySection
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.lg)
            }
        }
    }

    private func profileSection(_ tenant: Tenant) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tenant.displayName.isEmpty ? "Без имени" : tenant.displayName)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.textPrimary)

                        Text(tenant.notes?.isEmpty == false ? tenant.notes! : "Заметок пока нет.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }

                    Spacer()

                    StatusBadge(status: activeLeaseCount > 0 ? "active" : "archived")
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    contactRow(icon: "phone", title: "Телефон", value: tenant.phone)
                    contactRow(icon: "envelope", title: "Почта", value: tenant.email)
                    contactRow(icon: "person.2", title: "Проживают", value: tenant.cohabitants)
                }

                HStack(spacing: AppTheme.Spacing.sm) {
                    metricCard(title: "Договоров", value: "\(leases.count)")
                    metricCard(title: "Активных", value: "\(activeLeaseCount)")
                    metricCard(title: "Документы", value: "Ниже")
                }
            }
        }
    }

    private var leaseHistorySection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("История проживания")
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                if leases.isEmpty {
                    Text("Этот арендатор пока не привязан к объекту.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                } else {
                    LazyVStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(sortedLeases) { lease in
                            leaseHistoryRow(lease)
                        }
                    }
                }
            }
        }
    }

    private var sortedLeases: [Lease] {
        leases.sorted {
            let leftActive = $0.status.lowercased() == "active"
            let rightActive = $1.status.lowercased() == "active"
            if leftActive != rightActive { return leftActive }
            return ($0.moveInDate ?? $0.startDate) > ($1.moveInDate ?? $1.startDate)
        }
    }

    private func leaseHistoryRow(_ lease: Lease) -> some View {
        let content = VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lease.propertyName ?? propertiesById[lease.propertyId]?.name ?? "Объект")
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)

                    Text("Заезд \(AppFormatting.dateString(from: lease.moveInDate ?? lease.startDate) ?? (lease.moveInDate ?? lease.startDate)) · договор \(leasePeriod(lease))")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                StatusBadge(status: lease.status)
            }

            HStack(spacing: AppTheme.Spacing.sm) {
                metricCard(title: "Аренда", value: AppFormatting.compactAmount(lease.rentAmount, currency: lease.rentCurrency))
                metricCard(title: "Оплата", value: paymentWindow(lease))
                metricCard(title: "Выезд", value: lease.terminatedAt.flatMap { AppFormatting.dateString(from: $0) } ?? "-")
            }

            if let reason = lease.terminationReason, !reason.isEmpty {
                Text("Причина: \(reason)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            if isLeaseEarlyMoveOut(lease) {
                Label("Выехал раньше срока", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.warning)
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

        if let property = propertiesById[lease.propertyId] {
            return AnyView(
                NavigationLink {
                    PropertyDetailView(property: property)
                        .environmentObject(authManager)
                } label: {
                    content
                }
                .buttonStyle(.plain)
            )
        }

        return AnyView(content)
    }

    private func contactRow(icon: String, title: String, value: String?) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.Colors.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Text(value?.isEmpty == false ? value! : "Не указано")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            Spacer()
        }
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
        if tenant == nil { isLoading = true }
        defer { isLoading = false }

        do {
            async let tenantRequest: Tenant = APIClient.shared.request(
                "/v1/tenants/\(tenantId)",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            async let leasesRequest: [Lease] = APIClient.shared.request(
                "/v1/tenants/\(tenantId)/leases",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            async let propertiesRequest: [Property] = APIClient.shared.request(
                "/v1/properties",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )

            let (loadedTenant, loadedLeases, loadedProperties) = try await (tenantRequest, leasesRequest, propertiesRequest)
            tenant = loadedTenant
            leases = loadedLeases
            properties = loadedProperties
        } catch {
            errorMessage = "Не удалось загрузить арендатора."
        }
    }

    private func deleteTenant() async {
        guard !isDeleting else { return }
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }

        do {
            _ = try await APIClient.shared.requestData(
                "/v1/tenants/\(tenantId)",
                method: "DELETE",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            await onChanged()
            await MainActor.run { dismiss() }
        } catch {
            errorMessage = "Не удалось удалить арендатора."
        }
    }

    private func leasePeriod(_ lease: Lease) -> String {
        let from = AppFormatting.dateString(from: lease.startDate) ?? lease.startDate
        let to = lease.endDate.flatMap { AppFormatting.dateString(from: $0) } ?? "без даты окончания"
        return "\(from) - \(to)"
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
