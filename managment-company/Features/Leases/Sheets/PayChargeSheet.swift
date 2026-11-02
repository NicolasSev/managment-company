import SwiftUI

/// Pay one charge: amount (default outstanding), date, method. The `Idempotency-Key` is made
/// when the sheet opens (`LeaseDetailViewModel.present`) and survives retries; a network
/// failure parks the request in `PendingMutationQueue`.
struct PayChargeSheet: View {
    @ObservedObject var viewModel: LeaseDetailViewModel
    let lease: LeaseAggregate
    let chargeId: String

    @State private var amountText: String
    @State private var receivedOn: String
    @State private var method: LeasePaymentMethod = .kaspi
    @State private var notes = ""

    init(viewModel: LeaseDetailViewModel, lease: LeaseAggregate, chargeId: String) {
        self.viewModel = viewModel
        self.lease = lease
        self.chargeId = chargeId
        let charge = lease.charge(id: chargeId)
        _amountText = State(initialValue: charge?.outstanding.editableText ?? "")
        _receivedOn = State(initialValue: viewModel.todayDay)
    }

    private var charge: LeaseCharge? { lease.charge(id: chargeId) }
    private var amount: Money? { Money.parse(amountText, currency: lease.currency) }
    private var canSubmit: Bool { charge != nil && (amount?.isPositive ?? false) }
    private var isOverpayment: Bool {
        guard let amount, let charge else { return false }
        return amount > charge.outstanding
    }

    var body: some View {
        LeaseSheetContainer(
            title: "Оплата",
            name: "pay_charge",
            submitTitle: "Провести",
            canSubmit: canSubmit,
            isSubmitting: viewModel.isSubmitting,
            errorMessage: viewModel.sheetError,
            onCancel: { viewModel.dismissSheet() },
            onSubmit: {
                let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                Task {
                    await viewModel.submitPayCharge(
                        chargeId: chargeId,
                        amount: amount,
                        receivedOn: receivedOn,
                        method: method,
                        notes: trimmed.isEmpty ? nil : trimmed
                    )
                }
            }
        ) {
            if let charge {
                Section {
                    Text(charge.description ?? "\(charge.kind.title) \(LeaseDay.period(charge.periodStart, charge.periodEnd))")
                        .font(.subheadline.weight(.semibold))
                    LeaseKeyValueRow(label: "Срок", value: LeaseDay.display(charge.dueDate))
                    LeaseKeyValueRow(label: "Начислено", value: charge.amount.formatted())
                    if charge.allocated.isPositive {
                        LeaseKeyValueRow(label: "Уже оплачено", value: charge.allocated.formatted())
                    }
                    LeaseKeyValueRow(
                        label: "К оплате",
                        value: charge.outstanding.formatted(),
                        valueColor: charge.isOverdue ? AppTheme.Colors.danger : AppTheme.Colors.textPrimary,
                        identifier: "lease.detail.sheet.pay_charge.outstanding"
                    )
                }
            }

            Section {
                LeaseSheetField(
                    title: "Сумма (\(lease.currency))",
                    text: $amountText,
                    keyboard: .decimalPad,
                    identifier: "lease.detail.sheet.pay_charge.amount"
                )
                DatePicker(
                    "Дата оплаты",
                    selection: leaseDayBinding($receivedOn),
                    in: ...Date(),
                    displayedComponents: .date
                )
                .accessibilityIdentifier("lease.detail.sheet.pay_charge.received_on")
                Picker("Способ", selection: $method) {
                    ForEach(LeasePaymentMethod.allCases) { method in
                        Text(method.title).tag(method)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("lease.detail.sheet.pay_charge.method")
                LeaseSheetField(
                    title: "Комментарий",
                    text: $notes,
                    placeholder: "Необязательно",
                    identifier: "lease.detail.sheet.pay_charge.notes"
                )
            } footer: {
                if isOverpayment {
                    Text("Сумма больше начисления: излишек закроет следующие начисления, остаток станет кредитом арендатора.")
                } else {
                    Text("Меньшая сумма запишется как частичный платёж.")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
