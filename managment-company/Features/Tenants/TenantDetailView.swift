import SwiftUI

/// Tenant screen on `GET /v1/tenants/:id/overview`: profile and identity, the current lease as a
/// card that opens `LeaseDetailView`, balance and debt, months of the last year, lease history,
/// documents. Accessibility identifiers `tenants.detail.*`.
struct TenantDetailView: View {
    let tenantId: String
    let onChanged: () async -> Void

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: TenantDetailViewModel
    @State private var editingTenant: Tenant?
    @State private var showDeleteConfirmation = false
    @State private var hasAppeared = false
    @State private var settleContext: SettleWizardContext?

    init(tenantId: String, authManager: AuthManager, onChanged: @escaping () async -> Void) {
        self.tenantId = tenantId
        self.onChanged = onChanged
        _viewModel = StateObject(wrappedValue: TenantDetailViewModel(
            tenantId: tenantId,
            client: LiveTenantClient(authManager: authManager)
        ))
    }

    var body: some View {
        ZStack {
            AppScreenBackground()
            content
        }
        .navigationTitle(viewModel.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("tenants.detail.screen")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Редактировать") {
                    Task { editingTenant = await viewModel.tenantForEditing() }
                }
                .disabled(viewModel.overview == nil)
                .accessibilityIdentifier("tenants.detail.edit")
            }
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(viewModel.overview == nil)
                .accessibilityLabel("Удалить арендатора")
                .accessibilityIdentifier("tenants.detail.delete")
            }
        }
        .sheet(item: $editingTenant) { tenant in
            TenantFormSheet(tenant: tenant) {
                await viewModel.load()
                await onChanged()
            }
            .environmentObject(authManager)
        }
        // «Заселить» (a tenant without a current lease) opens the wizard with this tenant chosen.
        .settleWizard(context: $settleContext) {
            await viewModel.load()
            await onChanged()
        }
        .confirmationDialog(
            "Удалить арендатора?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                Task {
                    if await viewModel.delete() {
                        await onChanged()
                        dismiss()
                    }
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            if viewModel.activeLeaseCount > 0 {
                Text("У арендатора есть действующий договор. Перед удалением лучше расторгнуть договор.")
            } else {
                Text("Карточка арендатора исчезнет из списка. История договоров и операций останется в системе.")
            }
        }
        .task(id: tenantId) { await viewModel.load() }
        // Back from the lease screen (a payment changes balance and months): reload quietly.
        .onAppear {
            if hasAppeared { Task { await viewModel.load() } }
            hasAppeared = true
        }
        .refreshable { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("tenants.detail.loading")
        case .error(let message):
            EmptyStateView(
                title: "Арендатор недоступен",
                message: message,
                actionName: "Повторить",
                action: { Task { await viewModel.load() } },
                icon: "person.crop.circle.badge.exclamationmark"
            )
            .accessibilityIdentifier("tenants.detail.error")
        case .loaded(let overview):
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    if let banner = viewModel.banner {
                        statusBanner(banner)
                    }
                    profileSection(overview.tenant)
                    currentLeaseSection(overview)
                    if let totals = viewModel.primaryTotals {
                        balanceSection(totals)
                    }
                    monthsSection
                    identitySection(overview.tenant)

                    EntityFilesSection(
                        entityType: "tenant",
                        entityId: overview.tenant.id,
                        title: "Документы арендатора",
                        fileTypes: [
                            EntityFileType(value: "passport", label: "Паспорт"),
                            EntityFileType(value: "id_card", label: "Удостоверение"),
                            EntityFileType(value: "document", label: "Документ"),
                            EntityFileType(value: "photo", label: "Фото")
                        ]
                    )
                    .environmentObject(authManager)

                    historySection
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.lg)
            }
        }
    }

    // MARK: Sections

    private func profileSection(_ profile: TenantOverviewProfile) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(profile.fullName.isEmpty ? "Без имени" : profile.fullName)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .accessibilityIdentifier("tenants.detail.name")

                        Text(Self.nonEmpty(profile.notes) ?? "Заметок пока нет.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }

                    Spacer()

                    StatusBadge(status: viewModel.activeLeaseCount > 0 ? "active" : "archived")
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    infoRow(icon: "phone", title: "Телефон", value: profile.phone)
                    infoRow(icon: "envelope", title: "Почта", value: profile.email)
                    infoRow(icon: "person.2", title: "Проживают", value: profile.cohabitants)
                }
            }
        }
    }

    @ViewBuilder
    private func currentLeaseSection(_ overview: TenantOverview) -> some View {
        if let lease = overview.currentLease {
            LeaseNavigationLink(leaseId: lease.id, identifier: "tenants.detail.currentLease") {
                CurrentLeaseCard(lease: lease, subject: .property, identifier: "tenants.detail.currentLease")
            }
        } else {
            SurfaceCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text("Текущий договор")
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text("Сейчас у арендатора нет действующего договора.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    PrimaryButton(
                        title: "Заселить",
                        action: { settleContext = .tenant(tenantId) },
                        systemImage: "person.badge.plus"
                    )
                    .accessibilityIdentifier("tenants.detail.settle")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("tenants.detail.noLease")
        }
    }

    private func balanceSection(_ totals: TenantTotals) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Баланс")
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                HStack(spacing: AppTheme.Spacing.sm) {
                    LeaseMetricTile(
                        title: "К оплате",
                        value: totals.outstanding.formatted(),
                        identifier: "tenants.detail.outstanding"
                    )
                    LeaseMetricTile(
                        title: "Просрочено",
                        value: totals.overdue.formatted(),
                        color: totals.overdue.isPositive ? AppTheme.Colors.danger : AppTheme.Colors.textPrimary,
                        identifier: "tenants.detail.overdue"
                    )
                }
                HStack(spacing: AppTheme.Spacing.sm) {
                    LeaseMetricTile(title: "Оплачено", value: totals.paidToDate.formatted())
                    LeaseMetricTile(title: "Переплата", value: totals.tenantCredit.formatted())
                    LeaseMetricTile(title: "Депозит", value: totals.depositHeld.formatted())
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tenants.detail.balance")
    }

    @ViewBuilder
    private var monthsSection: some View {
        let rows = viewModel.monthRows
        if !rows.isEmpty {
            SurfaceCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    Text("Месяцы")
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    LazyVStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(rows) { row in
                            monthRow(row.month)
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("tenants.detail.months")
        }
    }

    @ViewBuilder
    private func monthRow(_ month: TenantMonth) -> some View {
        let line = HStack(spacing: AppTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.monthTitle(month.period))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text("Начислено \(month.charged.formatted()) · оплачено \(month.paid.formatted())")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            Spacer(minLength: AppTheme.Spacing.sm)
            VStack(alignment: .trailing, spacing: 4) {
                monthStatusPill(month.status)
                if month.outstanding.isPositive {
                    Text(month.outstanding.formatted())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

        if let leaseId = month.leaseId {
            LeaseNavigationLink(leaseId: leaseId, identifier: "tenants.detail.month.\(month.period)") { line }
        } else {
            line
        }
    }

    private func monthStatusPill(_ status: TenantMonthStatus) -> some View {
        let (title, color) = Self.monthStatusStyle(status)
        return Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func identitySection(_ profile: TenantOverviewProfile) -> some View {
        let issuedBy = viewModel.tenant?.documentIssuedBy
        let issuedAt = viewModel.tenant?.documentIssuedAt
        return SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack {
                    Text("Удостоверение")
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Spacer()
                    Button("Изменить") {
                        Task { editingTenant = await viewModel.tenantForEditing() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("tenants.detail.identity.edit")
                }
                infoRow(icon: "number", title: "ИИН", value: profile.iin, identifier: "tenants.detail.iin")
                infoRow(
                    icon: "doc.text",
                    title: "Документ",
                    value: Self.documentLine(
                        type: profile.documentType,
                        number: profile.documentNumber,
                        issuedBy: issuedBy,
                        issuedAt: issuedAt
                    ),
                    identifier: "tenants.detail.document"
                )
                infoRow(
                    icon: "birthday.cake",
                    title: "Дата рождения",
                    value: profile.birthDate.map { LeaseDay.display($0) },
                    identifier: "tenants.detail.birthDate"
                )
                infoRow(
                    icon: "house",
                    title: "Адрес регистрации",
                    value: profile.registrationAddress,
                    identifier: "tenants.detail.address"
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tenants.detail.identity")
    }

    @ViewBuilder
    private var historySection: some View {
        let leases = viewModel.historyLeases
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("История проживания")
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                if leases.isEmpty {
                    Text(viewModel.overview?.currentLease == nil
                         ? "Этот арендатор пока не привязан к объекту."
                         : "Других договоров нет.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                } else {
                    LazyVStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(leases) { lease in
                            LeaseNavigationLink(leaseId: lease.id, identifier: "tenants.detail.history.\(lease.id)") {
                                historyRow(lease)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tenants.detail.history")
    }

    private func historyRow(_ lease: LeaseCard) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lease.property.name)
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text("Договор \(LeaseDay.display(lease.startDate)) - \(lease.endDate.map { LeaseDay.display($0) } ?? "без даты окончания")")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                LeaseStatusBadge(status: lease.status)
            }
            HStack(spacing: AppTheme.Spacing.sm) {
                LeaseMetricTile(title: "Аренда", value: lease.currentRentAmount.formatted())
                LeaseMetricTile(title: "Выезд", value: lease.moveOutDate.map { LeaseDay.display($0) } ?? "-")
                LeaseMetricTile(
                    title: "Долг",
                    value: lease.balance.overdue.formatted(),
                    color: lease.balance.overdue.isPositive ? AppTheme.Colors.danger : AppTheme.Colors.textPrimary
                )
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: Pieces

    private func infoRow(icon: String, title: String, value: String?, identifier: String? = nil) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.Colors.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Text(Self.nonEmpty(value) ?? "Не указано")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .leaseIdentifier(identifier)
            }
            Spacer()
        }
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

    // MARK: Formatting

    /// The text when it has content, else `nil`.
    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private static let monthNames = [
        "Январь", "Февраль", "Март", "Апрель", "Май", "Июнь",
        "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь",
    ]

    /// `2026-10` -> `Октябрь 2026`.
    static func monthTitle(_ period: String) -> String {
        let parts = period.split(separator: "-").compactMap { Int($0) }
        guard parts.count >= 2, (1...12).contains(parts[1]) else { return period }
        return "\(monthNames[parts[1] - 1]) \(parts[0])"
    }

    static func monthStatusStyle(_ status: TenantMonthStatus) -> (String, Color) {
        switch status {
        case .paid: return ("Оплачено", AppTheme.Colors.success)
        case .waived: return ("Прощено", AppTheme.Colors.textSecondary)
        case .overdue: return ("Просрочено", AppTheme.Colors.danger)
        case .due: return ("К оплате", AppTheme.Colors.warning)
        case .partial: return ("Частично", AppTheme.Colors.warning)
        case .upcoming: return ("Впереди", AppTheme.Colors.info)
        case .noCharges: return ("Нет начислений", AppTheme.Colors.textSecondary)
        case .unknown(let raw): return (raw, AppTheme.Colors.textSecondary)
        }
    }

    /// `Паспорт N123456, выдан МВД, 10 янв. 2020`; `nil` when nothing is stored.
    static func documentLine(type: String?, number: String?, issuedBy: String?, issuedAt: String?) -> String? {
        var parts: [String] = []
        let kind = TenantDocumentType.title(for: type)
        let numberText = number.flatMap { $0.isEmpty ? nil : $0 }
        switch (kind, numberText) {
        case let (kind?, number?): parts.append("\(kind) \(number)")
        case let (kind?, nil): parts.append(kind)
        case let (nil, number?): parts.append("№ \(number)")
        case (nil, nil): break
        }
        if let issuedBy, !issuedBy.isEmpty { parts.append("выдан \(issuedBy)") }
        if let issuedAt, !issuedAt.isEmpty { parts.append(LeaseDay.display(issuedAt)) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
