import SwiftUI

/// The «Договор» button of the action block of `LeaseDetailView`: opens the contract for printing.
/// The contract can be previewed in any lease status.
struct ContractLeaseButton: View {
    let lease: LeaseAggregate

    var body: some View {
        NavigationLink {
            ContractDocumentView(
                context: ContractLeaseContext(
                    leaseId: lease.id,
                    propertyId: lease.propertyId,
                    tenantId: lease.tenantId,
                    startDate: lease.startDate
                )
            )
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "printer")
                Text("Договор").fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right").font(.caption)
            }
            .foregroundStyle(AppTheme.Colors.accent)
            .padding(.vertical, AppTheme.Spacing.md)
            .padding(.horizontal, AppTheme.Spacing.md)
            .background(AppTheme.Colors.accent.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("contract.open")
    }
}
