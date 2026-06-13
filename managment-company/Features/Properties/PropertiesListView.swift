import SwiftUI

private struct PropertyTenantDetailRoute: Identifiable {
    let id: String
}

private struct PropertyTransactionDetailRoute: Identifiable {
    let id: String
    let propertyName: String
}

private struct PropertyReceiptDetailRoute: Identifiable {
    let id: String
}

struct PropertiesListView: View {
    private enum PropertyScope: String, CaseIterable, Identifiable {
        case active
        case archived

        var id: String { rawValue }
        var title: String { self == .active ? "Активные" : "Архив" }
    }

    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject private var notificationRouter: NotificationDeepLinkRouter
    @State private var properties: [Property] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showPropertyForm = false
    @State private var searchText = ""
    @State private var navigationPath = NavigationPath()
    @State private var snippetSummaries: [String: PropertyListSnippetSummary] = [:]
    @State private var isLoadingSnippets = false
    @State private var snippetWarning: String?
    @State private var selectedTenant: PropertyTenantDetailRoute?
    @State private var selectedTransaction: PropertyTransactionDetailRoute?
    @State private var selectedReceipt: PropertyReceiptDetailRoute?
    @State private var propertyScope: PropertyScope = .active
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                AppScreenBackground()

                content
            }
            .navigationTitle("Объекты")
            .searchable(text: $searchText, prompt: "Поиск объектов")
            .onChange(of: propertyScope) { _, _ in
                Task { await loadProperties() }
            }
            .toolbar {
                if propertyScope == .active {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showPropertyForm = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                }
            }
            .refreshable {
                await loadProperties()
            }
            .task {
                await loadProperties()
            }
            .onChange(of: notificationRouter.pendingRoute) { _, _ in
                Task { await handlePendingNotificationRoute() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .propertyDeleted)) { _ in
                Task { await loadProperties() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .propertyArchiveChanged)) { _ in
                Task { await loadProperties() }
            }
            .navigationDestination(for: Property.self) { prop in
                PropertyDetailView(property: prop)
                    .environmentObject(authManager)
            }
            .sheet(isPresented: $showPropertyForm) {
                PropertyFormView(property: nil) { await loadProperties() }
                    .environmentObject(authManager)
            }
            .sheet(item: $selectedTenant) { route in
                NavigationStack {
                    TenantDetailView(tenantId: route.id) {
                        await loadProperties()
                    }
                    .environmentObject(authManager)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Закрыть") { selectedTenant = nil }
                        }
                    }
                }
            }
            .sheet(item: $selectedTransaction) { route in
                TransactionDetailSheet(
                    transactionId: route.id,
                    propertyName: route.propertyName,
                    baseCurrency: authManager.user?.baseCurrency ?? "KZT"
                )
                .environmentObject(authManager)
            }
            .sheet(item: $selectedReceipt) { route in
                UtilityReceiptDetailSheet(receiptId: route.id)
                    .environmentObject(authManager)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: AppTheme.Spacing.md) {
                scopePicker
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
        } else if let errorMessage, properties.isEmpty {
            VStack(spacing: AppTheme.Spacing.md) {
                scopePicker
                EmptyStateView(
                    title: "Не удалось загрузить объекты",
                    message: errorMessage,
                    actionName: "Повторить",
                    action: { Task { await loadProperties() } },
                    icon: "wifi.exclamationmark"
                )
            }
            .padding(.horizontal, AppTheme.Spacing.md)
        } else if filteredProperties.isEmpty {
            VStack(spacing: AppTheme.Spacing.md) {
                scopePicker
                EmptyStateView(
                    title: searchText.isEmpty ? "Объектов пока нет" : "Нет подходящих объектов",
                    message: searchText.isEmpty
                        ? propertyScope == .archived
                            ? "Архивированные объекты появятся здесь и будут доступны для восстановления."
                            : "Добавьте первый объект, чтобы начать вести портфель."
                        : "Попробуйте другое название, адрес или город.",
                    actionName: searchText.isEmpty
                        ? propertyScope == .active ? "Добавить объект" : "К активным"
                        : "Сбросить поиск",
                    action: {
                        if searchText.isEmpty {
                            if propertyScope == .active {
                                showPropertyForm = true
                            } else {
                                propertyScope = .active
                            }
                        } else {
                            searchText = ""
                        }
                    },
                    icon: searchText.isEmpty ? "building.2" : "magnifyingglass"
                )
            }
            .padding(.horizontal, AppTheme.Spacing.md)
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: AppTheme.Spacing.lg) {
                    scopePicker
                    portfolioSummary
                    filterSummary
                    if let errorMessage, !properties.isEmpty {
                        statusBanner(errorMessage, color: AppTheme.Colors.warning)
                    }
                    if let snippetWarning {
                        statusBanner(snippetWarning, color: AppTheme.Colors.warning)
                    }

                    LazyVStack(spacing: AppTheme.Spacing.md) {
                        ForEach(filteredProperties) { property in
                            PropertyRowView(
                                property: property,
                                summary: snippetSummaries[property.id],
                                isLoadingSummary: isLoadingSnippets
                                    && snippetSummaries[property.id] == nil,
                                onOpenProperty: { navigationPath.append(property) },
                                onOpenTenant: { tenantId in
                                    selectedTenant = PropertyTenantDetailRoute(id: tenantId)
                                },
                                onOpenTransaction: { transactionId in
                                    selectedTransaction = PropertyTransactionDetailRoute(
                                        id: transactionId,
                                        propertyName: property.name
                                    )
                                },
                                onOpenReceipt: { receiptId in
                                    selectedReceipt = PropertyReceiptDetailRoute(id: receiptId)
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.lg)
            }
        }
    }

    private var scopePicker: some View {
        Picker("Состав портфеля", selection: $propertyScope) {
            ForEach(PropertyScope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .pickerStyle(.segmented)
    }

    private var filteredProperties: [Property] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return properties }

        return properties.filter { property in
            let haystack = [
                property.name,
                property.propertyType,
                property.address,
                property.city,
                property.country,
                property.district,
            ]
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()

            return haystack.contains(query)
        }
    }

    private var portfolioSummary: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Портфель")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Text(propertyScope == .active
                    ? "Чистый обзор активных объектов."
                    : "Объекты вне расчётов и напоминаний.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                HStack(spacing: AppTheme.Spacing.sm) {
                    portfolioMetric(title: "Всего", value: "\(properties.count)")
                    portfolioMetric(
                        title: "Занято",
                        value: "\(properties.filter { $0.status == "occupied" }.count)"
                    )
                    portfolioMetric(
                        title: "Свободно",
                        value: "\(properties.filter { $0.status == "vacant" }.count)"
                    )
                }
            }
        }
    }

    private var filterSummary: some View {
        SurfaceCard(padding: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Текущий вид")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Text(filterSummaryText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Поиск идет по названию, типу, адресу, району, городу и стране.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
        }
    }

    private func portfolioMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var filterSummaryText: String {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = filteredProperties.count

        if query.isEmpty {
            return propertyScope == .active
                ? "Показано активных объектов: \(count)."
                : "Показано объектов в архиве: \(count)."
        }

        return "По запросу «\(query)» найдено объектов: \(count)."
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
    
    private func loadProperties() async {
        if properties.isEmpty { isLoading = true }
        errorMessage = nil
        snippetWarning = nil
        
        do {
            let path = propertyScope == .active
                ? "/v1/properties"
                : "/v1/properties?scope=archived"
            let loaded: [Property] = try await APIClient.shared.request(
                path,
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            properties = loaded
            isLoading = false
            await handlePendingNotificationRoute()
            await loadPropertySnippets()
        } catch {
            isLoading = false
            errorMessage = "Не удалось загрузить"
            if properties.isEmpty { properties = [] }
        }
    }

    private func loadPropertySnippets() async {
        isLoadingSnippets = true
        defer { isLoadingSnippets = false }

        var partialFailure = false
        let tenants: [Tenant]
        do {
            tenants = try await APIClient.shared.request(
                "/v1/tenants?per_page=100",
                tokenProvider: tokenProvider,
                refreshAndRetry: refreshProvider
            )
        } catch {
            tenants = []
            partialFailure = true
        }
        let tenantsById = Dictionary(uniqueKeysWithValues: tenants.map { ($0.id, $0) })

        var next = snippetSummaries
        for property in properties {
            let propertyLeases: [Lease]
            do {
                propertyLeases = try await APIClient.shared.request(
                    "/v1/properties/\(property.id)/leases",
                    tokenProvider: tokenProvider,
                    refreshAndRetry: refreshProvider
                )
            } catch {
                propertyLeases = []
                partialFailure = true
            }

            let transactions: [Transaction]
            do {
                let data = try await APIClient.shared.requestData(
                    "/v1/properties/\(property.id)/transactions?per_page=100",
                    tokenProvider: tokenProvider,
                    refreshAndRetry: refreshProvider
                )
                transactions = try JSONDecoder()
                    .decode(APIResponse<[Transaction]>.self, from: data)
                    .data
            } catch {
                transactions = []
                partialFailure = true
            }

            let utilities: [PropertyUtility]
            do {
                let data = try await APIClient.shared.requestData(
                    "/v1/properties/\(property.id)/utilities?per_page=60",
                    tokenProvider: tokenProvider,
                    refreshAndRetry: refreshProvider
                )
                utilities = try JSONDecoder()
                    .decode(APIListEnvelope<PropertyUtility>.self, from: data)
                    .data
            } catch {
                utilities = []
                partialFailure = true
            }

            next[property.id] = PropertyListSnippetLogic.summary(
                property: property,
                leases: propertyLeases,
                tenantsById: tenantsById,
                transactions: transactions,
                utilities: utilities
            )
            snippetSummaries = next
        }

        snippetWarning = partialFailure
            ? "Часть кратких сводок не загрузилась. Объекты по-прежнему доступны."
            : nil
    }

    private func tokenProvider() async -> String? {
        await MainActor.run { authManager.accessToken }
    }

    private func refreshProvider() async -> Bool {
        await authManager.refreshToken()
    }

    private func handlePendingNotificationRoute() async {
        guard let route = notificationRouter.pendingRoute,
              case .property(let propertyId) = route.kind else { return }

        if isLoading && properties.isEmpty { return }

        searchText = ""
        if let property = properties.first(where: { $0.id == propertyId }) {
            navigationPath.append(property)
        } else {
            errorMessage = "Объект из уведомления не найден в текущем портфеле."
        }
        notificationRouter.clearRoute(route)
    }
}

struct PropertyRowView: View {
    let property: Property
    let summary: PropertyListSnippetSummary?
    let isLoadingSummary: Bool
    let onOpenProperty: () -> Void
    let onOpenTenant: (String) -> Void
    let onOpenTransaction: (String) -> Void
    let onOpenReceipt: (String) -> Void
    
    var body: some View {
        SurfaceCard(padding: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Button(action: onOpenProperty) {
                    propertyOverview
                }
                .buttonStyle(.plain)

                Divider()

                if isLoadingSummary {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ProgressView().controlSize(.small)
                        Text("Загружаем краткую сводку...")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if let summary {
                    snippetSection(summary)
                } else {
                    Text("Краткая сводка пока недоступна.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
        }
    }

    private var propertyOverview: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(propertyTypeText)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .textCase(.uppercase)
                        .tracking(1.2)
                        .foregroundStyle(AppTheme.Colors.textSecondary)

                    Text(property.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)

                    if let addr = property.displayAddress {
                        Label(addr, systemImage: "mappin.and.ellipse")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    if property.isArchived {
                        Text("Архив")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.warning)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.Colors.warning.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    StatusBadge(status: property.status)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                }
            }

            HStack(spacing: AppTheme.Spacing.sm) {
                propertyFact(icon: "ruler", text: areaText)
                propertyFact(icon: "bed.double", text: roomsText)
                propertyFact(icon: "square.3.layers.3d", text: floorText)
            }
        }
        .contentShape(Rectangle())
    }

    private func snippetSection(_ summary: PropertyListSnippetSummary) -> some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            tenantSnippet(summary.tenant)
            paymentSnippet(summary.payment)
            utilitySnippet(summary.utility)
        }
    }

    private func tenantSnippet(_ tenant: PropertyTenantSnippet) -> some View {
        let title: String
        let detail: String
        let status: String?
        let statusColor: Color?

        switch tenant.relationship {
        case .current:
            title = "Текущий арендатор"
            detail = tenant.relevantDate.flatMap {
                AppFormatting.dateString(from: $0)
            }.map { "с \($0)" } ?? "активная аренда"
            status = "Проживает"
            statusColor = AppTheme.Colors.success
        case .former:
            title = property.status.lowercased() == "vacant"
                ? "Последний арендатор"
                : "Арендатор"
            detail = tenant.relevantDate.flatMap {
                AppFormatting.dateString(from: $0)
            }.map { "выехал \($0)" } ?? "дата выезда не указана"
            status = "Выехал"
            statusColor = AppTheme.Colors.danger
        case .none:
            title = property.status.lowercased() == "vacant" ? "Свободен" : "Арендатор"
            detail = "Аренда не создавалась"
            status = nil
            statusColor = nil
        }

        return snippetMetric(
            icon: "person",
            title: title,
            value: tenant.tenantName,
            detail: detail,
            status: status,
            statusColor: statusColor,
            action: tenant.tenantId.map { id in { onOpenTenant(id) } }
        )
    }

    private func paymentSnippet(_ payment: Transaction?) -> some View {
        guard let payment else {
            return snippetMetric(
                icon: "wallet.pass",
                title: "Последняя оплата",
                value: "Нет оплат",
                detail: "Доходы не записаны",
                status: nil,
                statusColor: nil,
                action: nil
            )
        }
        return snippetMetric(
            icon: "wallet.pass",
            title: "Последняя оплата",
            value: AppFormatting.compactAmount(payment.amount, currency: payment.currency),
            detail: AppFormatting.dateString(from: payment.transactionDate)
                ?? payment.transactionDate,
            status: nil,
            statusColor: nil,
            action: { onOpenTransaction(payment.id) }
        )
    }

    private func utilitySnippet(_ utility: PropertyUtility?) -> some View {
        guard let utility else {
            return snippetMetric(
                icon: "doc.text",
                title: "Коммуналка",
                value: "Нет начислений",
                detail: "Коммуналка не записана",
                status: nil,
                statusColor: nil,
                action: nil
            )
        }

        let type = PropertyListSnippetLogic.utilityTypeLabel(utility.utilityType)
        let period = PropertyListSnippetLogic.utilityPeriodLabel(
            year: utility.periodYear,
            month: utility.periodMonth
        )
        let provider = utility.provider?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = provider?.isEmpty == false
            ? "\(type) · \(provider!) · \(period)"
            : "\(type) · \(period)"
        let receiptId = utility.sourceReceiptId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank

        return snippetMetric(
            icon: "doc.text",
            title: "Коммуналка",
            value: AppFormatting.compactAmount(utility.amount, currency: utility.currency),
            detail: detail,
            status: nil,
            statusColor: nil,
            action: receiptId.map { id in { onOpenReceipt(id) } }
        )
    }

    private func snippetMetric(
        icon: String,
        title: String,
        value: String,
        detail: String,
        status: String?,
        statusColor: Color?,
        action: (() -> Void)?
    ) -> some View {
        Group {
            if let action {
                Button(action: action) {
                    snippetMetricContent(
                        icon: icon,
                        title: title,
                        value: value,
                        detail: detail,
                        status: status,
                        statusColor: statusColor,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            } else {
                snippetMetricContent(
                    icon: icon,
                    title: title,
                    value: value,
                    detail: detail,
                    status: status,
                    statusColor: statusColor,
                    showsChevron: false
                )
            }
        }
    }

    private func snippetMetricContent(
        icon: String,
        title: String,
        value: String,
        detail: String,
        status: String?,
        statusColor: Color?,
        showsChevron: Bool
    ) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(AppTheme.Colors.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(AppTheme.Colors.textTertiary)
                HStack(spacing: 8) {
                    Text(value)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                    if let status, let statusColor {
                        Text(status)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(statusColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(statusColor.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
    }

    private var propertyTypeText: String {
        property.propertyType.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var areaText: String {
        guard let area = property.areaSqm else { return "Площадь не указана" }
        return "\(Int(area.rounded())) m²"
    }

    private var roomsText: String {
        guard let rooms = property.rooms else { return "Комнаты не указаны" }
        return "\(rooms) rooms"
    }

    private var floorText: String {
        guard let floor = property.floor else { return "Этаж не указан" }
        return "Floor \(floor)"
    }

    private func propertyFact(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(AppTheme.Colors.accent)

            Text(text)
                .font(.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private extension String {
    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}
