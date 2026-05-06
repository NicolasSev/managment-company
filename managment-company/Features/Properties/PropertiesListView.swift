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
                VStack(spacing: AppTheme.Spacing.md) {
                    portfolioSummary
                    if let errorMessage, !properties.isEmpty {
                        statusBanner(errorMessage, color: AppTheme.Colors.warning)
                    }

                    LazyVStack(spacing: AppTheme.Spacing.md) {
                        ForEach(filteredProperties) { property in
                            NavigationLink(value: property) {
                                PropertyRowView(property: property)
                                    .environmentObject(authManager)
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
        HStack(spacing: AppTheme.Spacing.sm) {
            portfolioMetric(title: "Всего", value: "\(properties.count)")
            portfolioMetric(
                title: "Занято",
                value: "\(properties.filter { $0.status == "occupied" }.count)",
                valueColor: AppTheme.Colors.success
            )
            portfolioMetric(
                title: "Свободно",
                value: "\(properties.filter { $0.status == "vacant" }.count)",
                valueColor: AppTheme.Colors.danger
            )
        }
    }

    private func portfolioMetric(title: String, value: String, valueColor: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(valueColor ?? AppTheme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct CoverPhotoRow: Decodable {
    let id: String
    let fileType: String
    let downloadURL: String?
    enum CodingKeys: String, CodingKey {
        case id
        case fileType = "file_type"
        case downloadURL = "download_url"
    }
}
private struct CoverPhotoPayload: Decodable {
    let data: [CoverPhotoRow]
}

struct PropertyRowView: View {
    let property: Property
    @EnvironmentObject var authManager: AuthManager

    @State private var coverPhotoURL: URL?

    private var statusColor: Color {
        switch property.status {
        case "occupied":    return AppTheme.Colors.success
        case "vacant":      return AppTheme.Colors.danger
        default:            return AppTheme.Colors.textTertiary.opacity(0.5)
        }
    }

    var body: some View {
        SurfaceCard(padding: .zero) {
            HStack(spacing: 0) {
                // Status stripe
                Rectangle()
                    .fill(statusColor)
                    .frame(width: 4)
                    .clipShape(
                        .rect(topLeadingRadius: 20, bottomLeadingRadius: 20)
                    )

                // Cover photo
                Group {
                    if let url = coverPhotoURL {
                        AsyncImage(url: url) { phase in
                            if case .success(let img) = phase {
                                img.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                photoPlaceholder
                            }
                        }
                    } else {
                        photoPlaceholder
                    }
                }
                .frame(width: 72)
                .clipped()

                // Content
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(propertyTypeText)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .textCase(.uppercase)
                                .tracking(1.1)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                            Text(property.name)
                                .font(.headline)
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        StatusBadge(status: property.status)
                    }

                    if let city = property.city, !city.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.caption2)
                                .foregroundStyle(AppTheme.Colors.accent)
                            Text(city)
                                .font(.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                            if let addr = property.address, !addr.isEmpty {
                                Text("· \(addr)")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.Colors.textTertiary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    HStack(spacing: AppTheme.Spacing.sm) {
                        if let area = property.areaSqm {
                            propertyFact(icon: "ruler", text: "\(Int(area.rounded())) м²")
                        }
                        if let rooms = property.rooms {
                            propertyFact(icon: "bed.double", text: "\(rooms) комн.")
                        }
                        if let floor = property.floor {
                            propertyFact(icon: "square.3.layers.3d", text: "\(floor) эт.")
                        }
                    }

                    if let price = property.purchasePrice, price > 0 {
                        HStack(spacing: 12) {
                            valuationChip(
                                label: "Покупка",
                                amount: price,
                                currency: property.purchaseCurrency ?? "KZT"
                            )
                            if let curr = property.currentValue, curr > 0 {
                                valuationChip(
                                    label: "Оценка",
                                    amount: curr,
                                    currency: property.currentValueCurrency ?? "KZT"
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.md)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textTertiary)
                    .padding(.trailing, AppTheme.Spacing.md)
            }
        }
        .task { await loadCoverPhoto() }
    }

    private var photoPlaceholder: some View {
        Rectangle()
            .fill(AppTheme.Colors.backgroundSecondary.opacity(0.8))
            .overlay(
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(AppTheme.Colors.textTertiary.opacity(0.5))
            )
    }

    private var propertyTypeText: String {
        property.propertyType.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func propertyFact(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(AppTheme.Colors.accent)
            Text(text)
                .font(.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 9)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func valuationChip(label: String, amount: Double, currency: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppTheme.Colors.textTertiary)
            Text(AppFormatting.compactAmount(amount, currency: currency))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
    }

    private func loadCoverPhoto() async {
        let path = "/v1/files?entity_type=property&entity_id=\(property.id)&per_page=10"
        do {
            let payload: CoverPhotoPayload = try await APIClient.shared.requestRoot(
                path,
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            if let first = payload.data.first(where: { $0.fileType == "photo" }),
               let urlString = first.downloadURL,
               let url = APIURLBuilder.absoluteDownloadURL(base: AppEnvironment.apiBaseURL, downloadPath: urlString) {
                coverPhotoURL = url
            }
        } catch {
            // no cover photo available — show placeholder
        }
    }
}
