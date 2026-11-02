import SwiftUI

/// Block of `SettingsView` with the two contract settings screens.
struct ContractSettingsSection: View {
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Договор аренды")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Text("Данные арендодателя и шаблоны, из которых собирается договор для печати.")
                    .font(.body)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineSpacing(3)

                NavigationLink {
                    LandlordProfileView(service: ContractServiceProvider.makeService(authManager: authManager))
                } label: {
                    row(title: "Профиль арендодателя", systemImage: "person.text.rectangle")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.landlord.open")

                NavigationLink {
                    ContractTemplatesView(service: ContractServiceProvider.makeService(authManager: authManager))
                } label: {
                    row(title: "Шаблоны договора", systemImage: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.templates.open")
            }
        }
    }

    private func row(title: String, systemImage: String) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: systemImage)
            Text(title).fontWeight(.semibold)
            Spacer()
            Image(systemName: "chevron.right").font(.caption)
        }
        .foregroundStyle(AppTheme.Colors.accent)
        .padding(.vertical, AppTheme.Spacing.md)
        .padding(.horizontal, AppTheme.Spacing.md)
        .background(AppTheme.Colors.accent.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
