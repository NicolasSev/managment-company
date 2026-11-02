import SwiftUI

/// The sheet behind "fill in" of a missing contract value: landlord profile, property form or
/// tenant card. The contract screen refreshes its preview when the sheet closes.
struct ContractFixSheet: View {
    let target: ContractFixTarget
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch target {
            case .landlordProfile:
                NavigationStack {
                    LandlordProfileView(service: ContractServiceProvider.makeService(authManager: authManager))
                        .toolbar { closeButton }
                }
            case .property(let id):
                // PropertyFormView brings its own NavigationStack and Cancel button.
                ContractPropertyFix(propertyId: id)
            case .tenant(let id):
                NavigationStack {
                    TenantDetailView(tenantId: id, authManager: authManager, onChanged: {})
                        .toolbar { closeButton }
                }
            }
        }
        .accessibilityIdentifier("contract.fix.\(target.id)")
    }

    @ToolbarContentBuilder
    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Закрыть") { dismiss() }
                .accessibilityIdentifier("contract.fix.close")
        }
    }
}

/// Loads the property by id and opens the regular property form (which carries the
/// «Правоустанавливающий документ» field).
private struct ContractPropertyFix: View {
    let propertyId: String
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var property: Property?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let property {
                PropertyFormView(property: property, onSave: {})
            } else if let errorMessage {
                EmptyStateView(
                    title: "Объект недоступен",
                    message: errorMessage,
                    actionName: "Закрыть",
                    action: { dismiss() },
                    icon: "building.2"
                )
            } else {
                ProgressView()
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            let data = try await APIClient.shared.requestData(
                "/v1/properties/\(propertyId)",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            property = try JSONDecoder().decode(APIResponse<Property>.self, from: data).data
        } catch {
            errorMessage = "Не удалось загрузить объект."
        }
    }
}
