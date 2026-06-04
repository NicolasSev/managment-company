import SwiftUI

struct PropertiesListView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var properties: [Property] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showPropertyForm = false
    @State private var searchText = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground()

                content
            }
            .navigationTitle("Объекты")
            .searchable(text: $searchText, prompt: "Поиск объектов")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showPropertyForm = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .refreshable {
                await loadProperties()
            }
            .task {
                await loadProperties()
            }
            .navigationDestination(for: Property.self) { prop in
                PropertyDetailView(property: prop)
                    .environmentObject(authManager)
            }
            .sheet(isPresented: $showPropertyForm) {
                PropertyFormView(property: nil) { await loadProperties() }
                    .environmentObject(authManager)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, properties.isEmpty {
            EmptyStateView(
                title: "Не удалось загрузить объекты",
                message: errorMessage,
                actionName: "Повторить",
                action: { Task { await loadProperties() } },
                icon: "wifi.exclamationmark"
            )
        } else if filteredProperties.isEmpty {
            EmptyStateView(
                title: searchText.isEmpty ? "Объектов пока нет" : "Нет подходящих объектов",
                message: searchText.isEmpty
                    ? "Добавьте первый объект, чтобы начать вести портфель."
                    : "Попробуйте другое название, адрес или город.",
                actionName: searchText.isEmpty ? "Добавить объект" : "Сбросить поиск",
                action: {
                    if searchText.isEmpty {
                        showPropertyForm = true
                    } else {
                        searchText = ""
                    }
                },
                icon: searchText.isEmpty ? "building.2" : "magnifyingglass"
            )
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: AppTheme.Spacing.lg) {
                    portfolioSummary
                    filterSummary
                    if let errorMessage, !properties.isEmpty {
                        statusBanner(errorMessage, color: AppTheme.Colors.warning)
                    }

                    LazyVStack(spacing: AppTheme.Spacing.md) {
                        ForEach(filteredProperties) { property in
                            NavigationLink(value: property) {
                                PropertyRowView(property: property)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.lg)
            }
        }
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

                Text("Чистый обзор всех объектов.")
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
            return "Showing \(count) tracked propert\(count == 1 ? "y" : "ies") in the mobile portfolio."
        }

        return "Showing \(count) propert\(count == 1 ? "y" : "ies") matching “\(query)”."
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
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            properties = try await APIClient.shared.request(
                "/v1/properties",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
        } catch {
            errorMessage = "Не удалось загрузить"
            properties = []
        }
    }
}

struct PropertyRowView: View {
    let property: Property
    
    var body: some View {
        SurfaceCard(padding: AppTheme.Spacing.md) {
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

                    StatusBadge(status: property.status)
                }

                HStack(spacing: AppTheme.Spacing.sm) {
                    propertyFact(icon: "ruler", text: areaText)
                    propertyFact(icon: "bed.double", text: roomsText)
                    propertyFact(icon: "square.3.layers.3d", text: floorText)
                }
            }
        }
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
