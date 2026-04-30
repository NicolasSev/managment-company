import SwiftUI

struct PropertyDetailView: View {
    let property: Property
    @EnvironmentObject var authManager: AuthManager
    @State private var transactions: [Transaction] = []
    @State private var tenants: [Tenant] = []
    @State private var leases: [Lease] = []
    @State private var utilities: [PropertyUtility] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showTransactionSheet = false
    @State private var showEditForm = false
    @State private var showUtilityForm = false
    @State private var editingUtility: PropertyUtility?

    var body: some View {
        ZStack {
            AppScreenBackground()

            content
        }
        .navigationTitle(property.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Редактировать") { showEditForm = true }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Добавить операцию") { showTransactionSheet = true }
            }
        }
        .task { await loadData() }
        .refreshable { await loadData() }
        .sheet(isPresented: $showTransactionSheet) {
            QuickTransactionSheet(propertyId: property.id) { await loadData() }
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showEditForm) {
            PropertyFormView(property: property) { await loadData() }
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showUtilityForm) {
            UtilityFormView(propertyId: property.id, utility: editingUtility) {
                await loadUtilities()
            }
            .environmentObject(authManager)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, transactions.isEmpty, leases.isEmpty, utilities.isEmpty {
            EmptyStateView(
                title: "Не удалось загрузить активность объекта",
                message: errorMessage,
                actionName: "Повторить",
                action: { Task { await loadData() } },
                icon: "wifi.exclamationmark"
            )
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    heroSection

                    if let errorMessage {
                        statusBanner(errorMessage, color: AppTheme.Colors.warning)
                    }

                    factsSection

                    PropertyFilesSection(propertyId: property.id)
                        .environmentObject(authManager)

                    transactionsSection
                    tenantsSection
                    utilitiesSection
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.lg)
            }
        }
    }

    private var heroSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(propertyTypeLabel(property.propertyType))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .textCase(.uppercase)
                            .tracking(1.2)
                            .foregroundStyle(AppTheme.Colors.textSecondary)

                        Text(property.name)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.textPrimary)

                        if let addr = property.displayAddress {
                            Label(addr, systemImage: "mappin.and.ellipse")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        } else {
                            Text("Адрес объекта пока не указан.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    }

                    Spacer()

                    StatusBadge(status: property.status)
                }

                HStack(spacing: AppTheme.Spacing.sm) {
                    metricCard(
                        title: "Оценка",
                        value: AppFormatting.currency(
                            property.currentValue ?? property.purchasePrice ?? 0,
                            currency: property.currentValueCurrency ?? property.purchaseCurrency ?? "KZT"
                        ),
                        fallback: property.currentValue == nil && property.purchasePrice == nil
                    )
                    metricCard(
                        title: "Комнаты",
                        value: property.rooms.map(String.init) ?? "N/A",
                        fallback: property.rooms == nil
                    )
                    metricCard(
                        title: "Площадь",
                        value: property.areaSqm.map { "\(Int($0.rounded())) m²" } ?? "N/A",
                        fallback: property.areaSqm == nil
                    )
                }
            }
        }
    }

    private var factsSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Детали объекта")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                VStack(spacing: AppTheme.Spacing.sm) {
                    detailRow("Дата покупки", value: AppFormatting.dateString(from: property.purchaseDate) ?? "Не указано")
                    detailRow("Цена покупки", value: property.purchasePrice.map {
                        AppFormatting.currency($0, currency: property.purchaseCurrency ?? "KZT")
                    } ?? "Не указано")
                    detailRow("Район", value: property.district ?? "Не указано")
                    detailRow("Этаж", value: property.floor.map { "Этаж \($0)" } ?? "Не указано")
                    detailRow("Заметки", value: property.notes ?? "Заметок по объекту пока нет")
                }
            }
        }
    }

    private var transactionsSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                sectionHeader(
                    title: "Операции",
                    subtitle: "Последнее движение денег по объекту."
                )

                if transactions.isEmpty {
                    sectionPlaceholder(
                        title: "Операций пока нет",
                        message: "Добавьте первый доход или расход, чтобы журнал объекта стал полезным на мобильном.",
                        icon: "banknote"
                    )
                } else {
                    ForEach(transactions.prefix(10)) { transaction in
                        TransactionRow(
                            transaction: transaction,
                            baseCurrency: authManager.user?.baseCurrency ?? "KZT"
                        )
                    }
                }
            }
        }
    }

    private var tenantsSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                sectionHeader(
                    title: "Арендаторы",
                    subtitle: "Аренда и контакты в одном месте."
                )

                if leases.isEmpty {
                    sectionPlaceholder(
                        title: "Арендаторы пока не привязаны",
                        message: "Записи аренды появятся здесь, когда у объекта будет активный арендатор.",
                        icon: "person.2"
                    )
                } else {
                    ForEach(leases) { lease in
                        let tenant = tenants.first(where: { $0.id == lease.tenantId })

                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(tenant?.displayName ?? "Неизвестный арендатор")
                                        .font(.headline)
                                        .foregroundStyle(AppTheme.Colors.textPrimary)

                                    if let email = tenant?.email, !email.isEmpty {
                                        Label(email, systemImage: "envelope")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.Colors.textSecondary)
                                    } else if let phone = tenant?.phone, !phone.isEmpty {
                                        Label(phone, systemImage: "phone")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.Colors.textSecondary)
                                    } else {
                                        Text("Контакты не указаны")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.Colors.textSecondary)
                                    }

                                    if let cohabitants = tenant?.cohabitants, !cohabitants.isEmpty {
                                        Label(cohabitants, systemImage: "person.2")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.Colors.textSecondary)
                                    }
                                }

                                Spacer()

                                StatusBadge(status: lease.status)
                            }

                            HStack(spacing: AppTheme.Spacing.sm) {
                                metricCard(
                                    title: "Аренда",
                                    value: AppFormatting.currency(lease.rentAmount, currency: lease.rentCurrency)
                                )
                                metricCard(
                                    title: "Заезд",
                                    value: AppFormatting.dateString(from: lease.moveInDate ?? lease.startDate) ?? lease.startDate
                                )
                                metricCard(
                                    title: "Окно оплаты",
                                    value: leasePaymentWindow(lease)
                                )
                            }

                            if let terminatedAt = lease.terminatedAt {
                                Text("Прекращено \(AppFormatting.dateString(from: terminatedAt) ?? terminatedAt)")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.Colors.warning)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var utilitiesSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(alignment: .top) {
                    sectionHeader(
                        title: "Коммуналка",
                        subtitle: "Ежемесячные коммунальные расходы и квитанции по объекту."
                    )

                    Spacer()

                    Button {
                        editingUtility = nil
                        showUtilityForm = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(AppTheme.Colors.accent)
                    .accessibilityLabel("Добавить коммуналку")
                }

                if utilities.isEmpty {
                    sectionPlaceholder(
                        title: "Коммуналка пока не добавлена",
                        message: "Добавляйте ежемесячную коммуналку здесь; загрузка квитанций доступна в вебе.",
                        icon: "receipt"
                    )
                } else {
                    ForEach(utilities.prefix(12)) { utility in
                        Button {
                            editingUtility = utility
                            showUtilityForm = true
                        } label: {
                            utilityRow(utility)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func metricCard(title: String, value: String, fallback: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(fallback ? AppTheme.Colors.textSecondary : AppTheme.Colors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .frame(width: 110, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
    }

    private func sectionPlaceholder(title: String, message: String, icon: String) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AppTheme.Colors.accent)
                .frame(width: 36, height: 36)
                .background(AppTheme.Colors.accent.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineSpacing(2)
            }

            Spacer()
        }
        .padding(.vertical, AppTheme.Spacing.sm)
    }

    private func utilityRow(_ utility: PropertyUtility) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                Text(utilityPeriodLabel(utility))
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Text(utilityTypeLabel(utility.utilityType))
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text(utility.provider?.isEmpty == false ? utility.provider! : "Поставщик не указан")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(AppFormatting.compactAmount(utility.amount, currency: utility.currency))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                StatusBadge(status: utility.status)

                if let due = utility.dueDate {
                    Text("Срок: \(AppFormatting.dateString(from: due) ?? due)")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func statusBanner(_ message: String, color: Color) -> some View {
        Text(message)
            .font(.footnote.weight(.medium))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await loadTransactions() }
            group.addTask { await loadLeases() }
            group.addTask { await loadUtilities() }
        }

        await loadTenants()
    }

    private func loadTransactions() async {
        do {
            let data = try await APIClient.shared.requestData(
                "/v1/properties/\(property.id)/transactions",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            let decoded = try JSONDecoder().decode(APIResponse<[Transaction]>.self, from: data)
            transactions = decoded.data
        } catch {
            transactions = []
            errorMessage = "Часть активности объекта не загрузилась. Потяните для обновления и попробуйте еще раз."
        }
    }

    private func loadLeases() async {
        do {
            let data = try await APIClient.shared.requestData(
                "/v1/properties/\(property.id)/leases",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            let decoded = try JSONDecoder().decode(APIResponse<[Lease]>.self, from: data)
            leases = decoded.data
        } catch {
            leases = []
            errorMessage = "Часть активности объекта не загрузилась. Потяните для обновления и попробуйте еще раз."
        }
    }

    private func loadTenants() async {
        guard !leases.isEmpty else { return }

        do {
            let data = try await APIClient.shared.requestData(
                "/v1/tenants",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            let decoded = try JSONDecoder().decode(APIResponse<[Tenant]>.self, from: data)
            let ids = Set(leases.map(\.tenantId))
            tenants = decoded.data.filter { ids.contains($0.id) }
        } catch {
            tenants = []
            errorMessage = "Контакты арендатора не загрузились. Потяните для обновления и попробуйте еще раз."
        }
    }

    private func loadUtilities() async {
        do {
            let data = try await APIClient.shared.requestData(
                "/v1/properties/\(property.id)/utilities?per_page=60",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            let decoded = try JSONDecoder().decode(APIResponse<[PropertyUtility]>.self, from: data)
            utilities = decoded.data.sorted {
                if $0.periodYear == $1.periodYear {
                    return $0.periodMonth > $1.periodMonth
                }
                return $0.periodYear > $1.periodYear
            }
        } catch {
            utilities = []
            errorMessage = "История коммуналки не загрузилась. Потяните для обновления и попробуйте еще раз."
        }
    }

    private func leasePaymentWindow(_ lease: Lease) -> String {
        let start = lease.paymentWindowStartDay ?? lease.paymentDay ?? 1
        let end = lease.paymentWindowEndDay ?? lease.paymentDueDay ?? lease.paymentDay ?? start
        return "\(start)-\(end)"
    }

    private func utilityPeriodLabel(_ utility: PropertyUtility) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "MMMM yyyy"
        let components = DateComponents(year: utility.periodYear, month: utility.periodMonth, day: 1)
        guard let date = Calendar.current.date(from: components) else {
            return "\(utility.periodMonth)/\(utility.periodYear)"
        }
        return formatter.string(from: date)
    }

    private func utilityTypeLabel(_ value: String) -> String {
        switch value {
        case "utilities": return "Коммунальные услуги"
        case "electricity": return "Электричество"
        case "water": return "Вода"
        case "gas": return "Газ"
        case "heating": return "Отопление"
        case "internet": return "Интернет"
        case "maintenance": return "Обслуживание"
        case "other": return "Другое"
        default: return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func propertyTypeLabel(_ value: String) -> String {
        switch value {
        case "apartment": return "Квартира"
        case "house": return "Дом"
        case "commercial": return "Коммерция"
        case "land": return "Земля"
        case "other": return "Другое"
        default: return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

struct TransactionRow: View {
    let transaction: Transaction
    let baseCurrency: String

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppFormatting.dateString(from: transaction.transactionDate) ?? transaction.transactionDate)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                HStack(spacing: 8) {
                    StatusBadge(status: transaction.type)

                    if let description = transaction.description, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .lineLimit(2)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(AppFormatting.compactAmount(transaction.amount, currency: transaction.currency))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(transaction.type == "income" ? AppTheme.Colors.success : AppTheme.Colors.danger)

                Text("База \(AppFormatting.currency(transaction.amountBase, currency: baseCurrency))")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
