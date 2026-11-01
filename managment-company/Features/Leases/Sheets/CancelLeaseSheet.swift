import SwiftUI

/// Cancels a draft or pending-signature lease.
struct CancelLeaseSheet: View {
    @ObservedObject var viewModel: LeaseDetailViewModel

    @State private var reason = ""

    private var trimmedReason: String { reason.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        LeaseSheetContainer(
            title: "Отмена договора",
            name: "cancel",
            submitTitle: "Отменить договор",
            canSubmit: !trimmedReason.isEmpty,
            isSubmitting: viewModel.isSubmitting,
            errorMessage: viewModel.sheetError,
            submitRole: .destructive,
            onCancel: { viewModel.dismissSheet() },
            onSubmit: { Task { await viewModel.submitCancel(reason: trimmedReason) } }
        ) {
            Section {
                LeaseSheetField(
                    title: "Причина",
                    text: $reason,
                    placeholder: "Например, арендатор передумал",
                    identifier: "lease.detail.sheet.cancel.reason"
                )
            } footer: {
                Text("Договор получит статус «Отменён». Начислений по нему не будет.")
            }
        }
    }
}
