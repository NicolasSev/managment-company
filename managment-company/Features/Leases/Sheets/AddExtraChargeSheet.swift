import SwiftUI

/// Extra charge (damage, cleaning, utilities re-billing): goes through the normal queue.
struct AddExtraChargeSheet: View {
    @ObservedObject var viewModel: LeaseDetailViewModel
    let lease: LeaseAggregate

    @State private var amountText = ""
    @State private var descriptionText = ""
    @State private var chargedOn: String
    @State private var customDueDate = false
    @State private var dueDate: String

    init(viewModel: LeaseDetailViewModel, lease: LeaseAggregate) {
        self.viewModel = viewModel
        self.lease = lease
        _chargedOn = State(initialValue: viewModel.todayDay)
        _dueDate = State(initialValue: viewModel.todayDay)
    }

    private var amount: Money? { Money.parse(amountText, currency: lease.currency) }
    private var trimmedDescription: String { descriptionText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSubmit: Bool { (amount?.isPositive ?? false) && !trimmedDescription.isEmpty }

    var body: some View {
        LeaseSheetContainer(
            title: "Доп. начисление",
            name: "add_extra_charge",
            submitTitle: "Начислить",
            canSubmit: canSubmit,
            isSubmitting: viewModel.isSubmitting,
            errorMessage: viewModel.sheetError,
            onCancel: { viewModel.dismissSheet() },
            onSubmit: {
                guard let amount else { return }
                Task {
                    await viewModel.submitAddExtraCharge(
                        amount: amount,
                        chargedOn: chargedOn,
                        dueDate: customDueDate ? dueDate : nil,
                        description: trimmedDescription
                    )
                }
            }
        ) {
            Section {
                LeaseSheetField(
                    title: "Сумма (\(lease.currency))",
                    text: $amountText,
                    keyboard: .decimalPad,
                    identifier: "lease.detail.sheet.add_extra_charge.amount"
                )
                LeaseSheetField(
                    title: "За что",
                    text: $descriptionText,
                    placeholder: "Например, порванные обои в спальне",
                    identifier: "lease.detail.sheet.add_extra_charge.description"
                )
                DatePicker("Дата начисления", selection: leaseDayBinding($chargedOn), displayedComponents: .date)
                    .accessibilityIdentifier("lease.detail.sheet.add_extra_charge.charged_on")
                Toggle("Другой срок оплаты", isOn: $customDueDate)
                    .accessibilityIdentifier("lease.detail.sheet.add_extra_charge.custom_due")
                if customDueDate {
                    DatePicker("Оплатить до", selection: leaseDayBinding($dueDate), displayedComponents: .date)
                        .accessibilityIdentifier("lease.detail.sheet.add_extra_charge.due_date")
                }
            } footer: {
                Text("Ущерб — это начисление, а не списание с депозита. Попадёт в очередь и закроется обычной оплатой.")
            }
        }
    }
}
