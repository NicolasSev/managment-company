import SwiftUI

/// Placeholder for «заменить новым договором» (spec §3.10). The flow that creates the
/// replacing lease belongs to the tenants/lease creation work; this sheet only explains it.
struct ReplaceWithNewLeaseSheet: View {
    @ObservedObject var viewModel: LeaseDetailViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: AppTheme.Spacing.lg) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.accent)
                Text("Замена договора новым")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text("Новый договор с другой ставкой и сроком вместо продления появится в одном из ближайших обновлений. Текущий договор при этом не изменяется.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .accessibilityIdentifier("lease.detail.sheet.replace_with_new.message")
                PrimaryButton(title: "Понятно") { viewModel.dismissSheet() }
                    .accessibilityIdentifier("lease.detail.sheet.replace_with_new.close")
            }
            .padding(AppTheme.Spacing.lg)
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationTitle("Новый договор")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("lease.detail.sheet.replace_with_new")
        .presentationDetents([.medium])
    }
}
