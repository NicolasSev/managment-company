import SwiftUI

/// Activation: the lease starts occupying the property from `activation_date` (default
/// `start_date`, editable) and the first period and the deposit go to the payment queue.
struct ActivateLeaseSheet: View {
    @ObservedObject var viewModel: LeaseDetailViewModel
    let lease: LeaseAggregate

    @State private var activationDate: String
    @State private var signedOn: String

    init(viewModel: LeaseDetailViewModel, lease: LeaseAggregate) {
        self.viewModel = viewModel
        self.lease = lease
        _activationDate = State(initialValue: lease.activationDate ?? lease.startDate)
        _signedOn = State(initialValue: lease.lifecycle.signedOn ?? viewModel.todayDay)
    }

    private var needsSignedOn: Bool { lease.lifecycle.signedOn == nil }

    var body: some View {
        LeaseSheetContainer(
            title: "Активация договора",
            name: "activate",
            submitTitle: "Активировать",
            isSubmitting: viewModel.isSubmitting,
            errorMessage: viewModel.sheetError,
            onCancel: { viewModel.dismissSheet() },
            onSubmit: {
                Task {
                    await viewModel.submitActivate(
                        activationDate: activationDate,
                        signedOn: needsSignedOn ? signedOn : nil
                    )
                }
            }
        ) {
            Section {
                DatePicker(
                    "Дата заселения",
                    selection: leaseDayBinding($activationDate),
                    displayedComponents: .date
                )
                .accessibilityIdentifier("lease.detail.sheet.activate.activation_date")
                if needsSignedOn {
                    DatePicker(
                        "Дата подписания",
                        selection: leaseDayBinding($signedOn),
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .accessibilityIdentifier("lease.detail.sheet.activate.signed_on")
                }
            } footer: {
                Text("С этой даты объект считается занятым. По умолчанию — начало договора (\(LeaseDay.display(lease.startDate))).")
            }

            if !lease.chargesPreview.isEmpty {
                Section("Сразу попадут в очередь") {
                    ForEach(lease.chargesPreview.prefix(2), id: \.rowKey) { charge in
                        HStack {
                            Text(charge.kind.title)
                            Spacer()
                            Text("\(charge.amount.formatted()) до \(LeaseDay.short(charge.dueDate))")
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
    }
}
