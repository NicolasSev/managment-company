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
    @State private var rowsVisible = false
    /// List ↔ grid formation of the cards, remembered per device.
    @AppStorage("properties.layout.grid") private var isGridLayout = false
    @Namespace private var zoomNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        AppHaptics.selection()
                        isGridLayout.toggle()
                    } label: {
                        Image(systemName: isGridLayout ? "rectangle.grid.1x2" : "square.grid.2x2")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .accessibilityLabel(isGridLayout ? "Показать списком" : "Показать плиткой")
                    .accessibilityIdentifier("properties.layout.toggle")
                }
                if propertyScope == .active {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showPropertyForm = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Добавить объект")
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
                    .navigationTransition(.zoom(sourceID: prop.id, in: zoomNamespace))
            }
            .sheet(isPresented: $showPropertyForm) {
                PropertyFormView(property: nil) { await loadProperties() }
                    .environmentObject(authManager)
            }
            .sheet(item: $selectedTenant) { route in
                NavigationStack {
                    TenantDetailView(tenantId: route.id, authManager: authManager) {
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
                // The id of a v1 receipt is the id of its bill: the review sheet of U9 opens it.
                UtilityBillReviewSheet(
                    billId: route.id,
                    service: UtilityBillsServiceProvider.makeService(authManager: authManager),
                    timeZoneIdentifier: authManager.user?.timezone ?? "Asia/Almaty"
                )
                .environmentObject(authManager)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ScrollView(showsIndicators: false) {
                VStack(spacing: AppTheme.Spacing.md) {
                    portfolioSummary
                    ForEach(0..<3, id: \.self) { _ in
                        SurfaceCard(padding: AppTheme.Spacing.md) {
                            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                                RoundedRectangle(cornerRadius: 4).fill(AppTheme.Colors.backgroundSecondary)
                                    .frame(width: 48, height: 64)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Квартира").font(.caption2)
                                    Text("Название объекта").font(.title3)
                                    Text("Адрес объекта, город").font(.subheadline)
                                }
                            }
                        }
                    }
                }
                .shimmerPlaceholder(true)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.top, AppTheme.Spacing.sm)
            }
            .accessibilityLabel("Загружаем объекты")
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
                VStack(spacing: AppTheme.Spacing.md) {
                    portfolioSummary
                    if let errorMessage, !properties.isEmpty {
                        statusBanner(errorMessage, color: AppTheme.Colors.warning)
                    }
                    if let snippetWarning {
                        statusBanner(snippetWarning, color: AppTheme.Colors.warning)
                    }

                    HStack {
                        Text(filterSummaryText)
                            .sectionLabelStyle()
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                    }
                    .padding(.horizontal, AppTheme.Spacing.xs)
                    .padding(.top, AppTheme.Spacing.xs)

                    // One grid for both formations: changing the column count lets every
                    // card travel to its new slot on its own spring.
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.sm, alignment: .top),
                            count: isGridLayout ? 2 : 1
                        ),
                        spacing: isGridLayout ? AppTheme.Spacing.sm : AppTheme.Spacing.md
                    ) {
                        ForEach(Array(filteredProperties.enumerated()), id: \.element.id) { index, property in
                            PropertyRowView(
                                property: property,
                                summary: snippetSummaries[property.id],
                                isLoadingSummary: isLoadingSnippets
                                    && snippetSummaries[property.id] == nil,
                                isCompact: isGridLayout,
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
                            .matchedTransitionSource(id: property.id, in: zoomNamespace)
                            .appearStagger(index: index, isVisible: rowsVisible)
                        }
                    }
                    .animation(
                        AppTheme.Motion.resolved(.spring(response: 0.46, dampingFraction: 0.86), reduceMotion: reduceMotion),
                        value: isGridLayout
                    )
                    .onAppear { rowsVisible = true }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.top, AppTheme.Spacing.sm)
                .padding(.bottom, AppTheme.Spacing.xxl + AppTheme.Spacing.xl)
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
                property.typeTitle,
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

    /// Hero: the portfolio drawn as a street, with its three counts and the scope switch.
    private var portfolioSummary: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Портфель")
                        .sectionLabelStyle()
                    Spacer()
                    Text(propertyScope == .active ? "В расчётах" : "Вне расчётов")
                        .sectionLabelStyle(AppTheme.Colors.accent)
                }

                if !properties.isEmpty {
                    IsometricStreet(
                        buildings: properties.map(IsometricBuildingSpec.init(property:)),
                        height: 92
                    )
                    .id(propertyScope)
                }

                HStack(spacing: 0) {
                    MetricTile(title: "Всего", value: "\(properties.count)")
                    MetricTile(
                        title: "Занято",
                        value: "\(properties.filter { $0.status == "occupied" }.count)",
                        tint: AppTheme.Colors.accent
                    )
                    MetricTile(
                        title: "Свободно",
                        value: "\(properties.filter { $0.status == "vacant" }.count)"
                    )
                }

                scopePicker
            }
        }
    }

    private var filterSummaryText: String {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = filteredProperties.count

        if query.isEmpty {
            return propertyScope == .active
                ? "Активные · \(count)"
                : "Архив · \(count)"
        }

        return "По запросу «\(query)» · \(count)"
    }

    private func statusBanner(_ message: String, color: Color) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.footnote.weight(.medium))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.inner, style: .continuous))
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
    /// Grid formation: glyph, name and status only.
    var isCompact: Bool = false
    let onOpenProperty: () -> Void
    let onOpenTenant: (String) -> Void
    let onOpenTransaction: (String) -> Void
    let onOpenReceipt: (String) -> Void
    
    var body: some View {
        SurfaceCard(padding: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Button(action: onOpenProperty) {
                    if isCompact { compactOverview } else { propertyOverview }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("properties.row.\(property.id)")

                if !isCompact {
                    if isLoadingSummary {
                        snippetSkeleton
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
    }

    private var compactOverview: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(alignment: .bottom) {
                PropertyGlyph(property: property, height: 72)
                Spacer(minLength: 0)
            }
            DimensionRule(ticks: 3)
            Text(property.typeTitle)
                .sectionLabelStyle()
            Text(property.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
            StatusBadge(status: property.status)
        }
        .contentShape(Rectangle())
    }

    private var propertyOverview: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            PropertyGlyph(property: property, height: 72)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
                    Text(property.typeTitle)
                        .sectionLabelStyle()
                    if property.isArchived {
                        Text("Архив")
                            .sectionLabelStyle(AppTheme.Colors.warning)
                    }
                    Spacer(minLength: 0)
                    StatusBadge(status: property.status)
                }

                Text(property.name)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let addr = property.displayAddress {
                    Text(addr)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                HStack(spacing: AppTheme.Spacing.xs) {
                    Text(factsText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.accent)
                }
                .padding(.top, 2)
            }
        }
        .contentShape(Rectangle())
    }

    private var snippetSkeleton: some View {
        VStack(spacing: 0) {
            ForEach(["Арендатор", "Последняя оплата", "Коммуналка"], id: \.self) { title in
                snippetMetricContent(
                    icon: "circle",
                    title: title,
                    value: "Загружаем данные",
                    detail: "",
                    status: nil,
                    statusColor: nil,
                    showsChevron: false
                )
            }
        }
        .shimmerPlaceholder(true)
        .accessibilityLabel("Загружаем краткую сводку")
    }

    private func snippetSection(_ summary: PropertyListSnippetSummary) -> some View {
        VStack(spacing: 0) {
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
            statusColor = AppTheme.Colors.accent
        case .former:
            title = property.status.lowercased() == "vacant"
                ? "Последний арендатор"
                : "Арендатор"
            detail = tenant.relevantDate.flatMap {
                AppFormatting.dateString(from: $0)
            }.map { "выехал \($0)" } ?? "дата выезда не указана"
            status = "Выехал"
            statusColor = AppTheme.Colors.textSecondary
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
                icon: "banknote",
                title: "Последняя оплата",
                value: "Нет оплат",
                detail: "Доходы не записаны",
                status: nil,
                statusColor: nil,
                action: nil
            )
        }
        return snippetMetric(
            icon: "banknote",
            title: "Последняя оплата",
            value: AppFormatting.currency(payment.amount, currency: payment.currency),
            detail: AppFormatting.dateString(from: payment.transactionDate)
                ?? payment.transactionDate,
            status: nil,
            statusColor: nil,
            action: { onOpenTransaction(payment.id) }
        )
    }

    private func utilitySnippet(_ utility: PropertyUtilitySnippet?) -> some View {
        guard let utility else {
            return snippetMetric(
                icon: "bolt",
                title: "Коммуналка",
                value: "Нет начислений",
                detail: "Коммуналка не записана",
                status: nil,
                statusColor: nil,
                action: nil
            )
        }

        return snippetMetric(
            icon: "bolt",
            title: "Коммуналка",
            value: AppFormatting.currency(utility.amount, currency: utility.currency),
            detail: utility.detail,
            status: nil,
            statusColor: nil,
            action: utility.receiptId.map { id in { onOpenReceipt(id) } }
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

    /// One line of the card's fact table: hairline on top, label left, value right.
    private func snippetMetricContent(
        icon: String,
        title: String,
        value: String,
        detail: String,
        status: String?,
        statusColor: Color?,
        showsChevron: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.footnote.weight(.medium))
                .foregroundStyle(showsChevron ? AppTheme.Colors.accent : AppTheme.Colors.textTertiary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(showsChevron ? AppTheme.Colors.textPrimary : AppTheme.Colors.textSecondary)
                    .lineLimit(1)
                if let status, let statusColor {
                    Text(status)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(statusColor)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textTertiary)
                .opacity(showsChevron ? 1 : 0)
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(AppTheme.Colors.border).frame(height: 1)
        }
        .contentShape(Rectangle())
    }

    /// Known facts only, in one line: "64 м² · 2 комн. · 6 этаж".
    private var factsText: String {
        var parts: [String] = []
        if let area = property.areaSqm { parts.append("\(Int(area.rounded())) м²") }
        if let rooms = property.rooms { parts.append("\(rooms) комн.") }
        if let floor = property.floor { parts.append("\(floor) этаж") }
        return parts.isEmpty ? "Параметры не указаны" : parts.joined(separator: " · ")
    }
}

private extension String {
    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}
