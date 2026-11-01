import SwiftUI

/// «Депозит возвращён»: how much goes back to the tenant and, only if the owner chooses, how
/// much is set off against the current debt. The set-off is offered, never applied by itself.
struct ReturnDepositSheet: View {
    @ObservedObject var viewModel: LeaseDetailViewModel
    let lease: LeaseAggregate

    @State private var amountText: String
    @State private var applyText = ""
    @State private var returnedOn: String
    @State private var method: LeasePaymentMethod = .kaspi
    @State private var notes = ""

    init(viewModel: LeaseDetailViewModel, lease: LeaseAggregate) {
        self.viewModel = viewModel
        self.lease = lease
        _amountText = State(initialValue: lease.deposit.held.editableText)
        _returnedOn = State(initialValue: viewModel.todayDay)
    }

    private var held: Money { lease.deposit.held }
    private var amount: Money? {
        amountText.trimmingCharacters(in: .whitespaces).isEmpty ? .zero(lease.currency) : Money.parse(amountText, currency: lease.currency)
    }
    private var applied: Money? {
        applyText.trimmingCharacters(in: .whitespaces).isEmpty ? .zero(lease.currency) : Money.parse(applyText, currency: lease.currency)
    }
    private var total: Money? {
        guard let amount, let applied else { return nil }
        return amount + applied
    }
    private var canSubmit: Bool {
        guard let amount, let applied, let total else { return false }
        return amount.minor >= 0 && applied.minor >= 0 && total.isPositive && total <= held
    }
    private var suggestion: Money { lease.deposit.suggestedApplyToDebt }

    var body: some View {
        LeaseSheetContainer(
            title: "Возврат депозита",
            name: "return_deposit",
            submitTitle: "Подтвердить",
            canSubmit: canSubmit,
            isSubmitting: viewModel.isSubmitting,
            errorMessage: viewModel.sheetError,
            onCancel: { viewModel.dismissSheet() },
            onSubmit: {
                let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                Task {
                    await viewModel.submitReturnDeposit(
                        amount: amount,
                        returnedOn: returnedOn,
                        method: method,
                        applyToDebt: applied,
                        notes: trimmed.isEmpty ? nil : trimmed
                    )
                }
            }
        ) {
            Section {
                LeaseKeyValueRow(label: "Удерживается", value: held.formatted(), identifier: "lease.detail.sheet.return_deposit.held")
                if lease.balance.outstanding.isPositive {
                    LeaseKeyValueRow(label: "Долг арендатора", value: lease.balance.outstanding.formatted(), valueColor: AppTheme.Colors.danger)
                }
            }

            Section {
                LeaseSheetField(
                    title: "Вернуть арендатору (\(lease.currency))",
                    text: $amountText,
                    keyboard: .decimalPad,
                    identifier: "lease.detail.sheet.return_deposit.amount"
                )
                LeaseSheetField(
                    title: "Зачесть в долг (\(lease.currency))",
                    text: $applyText,
                    placeholder: "0",
                    keyboard: .decimalPad,
                    identifier: "lease.detail.sheet.return_deposit.apply_to_debt"
                )
                if suggestion.isPositive {
                    Button {
                        applyText = suggestion.editableText
                        let remainder = Money(minor: max(0, held.minor - suggestion.minor), currency: lease.currency)
                        amountText = remainder.editableText
                    } label: {
                        Label("Предложить зачёт \(suggestion.formatted())", systemImage: "arrow.left.arrow.right")
                    }
                    .accessibilityIdentifier("lease.detail.sheet.return_deposit.suggest")
                }
                if let total, total > held {
                    Text("Вместе больше удерживаемого депозита (\(held.formatted())).")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.Colors.danger)
                }
            } footer: {
                Text("Зачёт в долг применяется только по вашему решению. Ущерб оформляется доп. начислением.")
            }

            Section {
                DatePicker(
                    "Дата возврата",
                    selection: leaseDayBinding($returnedOn),
                    in: ...Date(),
                    displayedComponents: .date
                )
                .accessibilityIdentifier("lease.detail.sheet.return_deposit.returned_on")
                Picker("Способ", selection: $method) {
                    ForEach(LeasePaymentMethod.allCases) { method in
                        Text(method.title).tag(method)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("lease.detail.sheet.return_deposit.method")
                LeaseSheetField(
                    title: "Комментарий",
                    text: $notes,
                    placeholder: "Необязательно",
                    identifier: "lease.detail.sheet.return_deposit.notes"
                )
            }
        }
    }
}
