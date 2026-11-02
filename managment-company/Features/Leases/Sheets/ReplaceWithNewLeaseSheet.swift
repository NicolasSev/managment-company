import SwiftUI

/// «Заменить новым договором» (spec §3.10): the move-in wizard for the tenant and property of the
/// current lease, with `replaces_lease_id` set. Nothing happens to the current lease until the new
/// one is activated. After the settle the lease behind reloads; «К договору» opens the new lease
/// inside the sheet.
struct ReplaceWithNewLeaseSheet: View {
    @ObservedObject var viewModel: LeaseDetailViewModel
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        Group {
            if let lease = viewModel.lease {
                SettleWizardView(
                    context: .replacing(lease),
                    authManager: authManager,
                    onSettled: { _ in Task { await viewModel.reload() } },
                    onOpenLease: nil
                )
            } else {
                ProgressView()
            }
        }
        .accessibilityIdentifier("lease.detail.sheet.replace_with_new")
    }
}
