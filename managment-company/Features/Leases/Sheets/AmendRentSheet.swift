import SwiftUI

/// Rent and/or due-day change effective from a date, without a signature cycle (spec §3.6).
struct AmendRentSheet: View {
    @ObservedObject var viewModel: LeaseDetailViewModel
    let lease: LeaseAggregate

    @State private var effectiveFrom: String
    @State private var rentText: String
    @State private var changeDueDay = false
    @State private var dueDay: Int
    @State private var note = ""

    init(viewModel: LeaseDetailViewModel, lease: LeaseAggregate) {
        self.viewModel = viewModel
        self.lease = lease
        _effectiveFrom = State(initialValue: lease.nextPeriodStart ?? viewModel.todayDay)
        _rentText = State(initialValue: lease.currentRentAmount.editableText)
        _dueDay = State(initialValue: lease.dueDay)
    }

    private var newRent: Money? { Money.parse(rentText, currency: lease.currency) }
    private var rentChanged: Bool {
        guard let newRent else { return false }
        return newRent != lease.currentRentAmount
    }
    private var dueDayChanged: Bool { changeDueDay && dueDay != lease.dueDay }
    private var rentIsValid: Bool { (newRent?.isPositive ?? false) }
    private var canSubmit: Bool {
        rentIsValid && (rentChanged || dueDayChanged) && effectiveFrom >= lease.startDate
    }

    private var affectedRentCharges: [LeaseCharge] {
        lease.charges.filter { $0.kind == .rent && !$0.isVoid && $0.periodStart >= effectiveFrom }
    }

    var body: some View {
        LeaseSheetContainer(
            title: "Изменение аренды",
            name: "amend_rent",
            submitTitle: "Применить",
            canSubmit: canSubmit,
            isSubmitting: viewModel.isSubmitting,
            errorMessage: viewModel.sheetError,
            onCancel: { viewModel.dismissSheet() },
            onSubmit: {
                Task {
                    await viewModel.submitAmendRent(
                        effectiveFrom: effectiveFrom,
                        rent: rentChanged ? newRent : nil,
                        dueDay: dueDayChanged ? dueDay : nil,
                        note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
            }
        ) {
            Section {
                DatePicker(
                    "Действует с",
                    selection: leaseDayBinding($effectiveFrom),
                    in: (LeaseDay.pickerDate(lease.startDate) ?? Date.distantPast)...,
                    displayedComponents: .date
                )
                .accessibilityIdentifier("lease.detail.sheet.amend_rent.effective_from")
                LeaseSheetField(
                    title: "Новая аренда (\(lease.currency))",
                    text: $rentText,
                    keyboard: .decimalPad,
                    identifier: "lease.detail.sheet.amend_rent.rent"
                )
                Toggle("Изменить день оплаты", isOn: $changeDueDay)
                    .accessibilityIdentifier("lease.detail.sheet.amend_rent.change_due_day")
                if changeDueDay {
                    Stepper("День оплаты: \(dueDay)", value: $dueDay, in: 1...31)
                        .accessibilityIdentifier("lease.detail.sheet.amend_rent.due_day")
                }
                LeaseSheetField(
                    title: "Комментарий",
                    text: $note,
                    placeholder: "Например, индексация по допсоглашению",
                    identifier: "lease.detail.sheet.amend_rent.note"
                )
            } footer: {
                Text("Подпись не нужна: изменение применяется сразу. Текущая аренда — \(lease.currentRentAmount.formatted()).")
            }

            if rentChanged || dueDayChanged {
                Section("Затронутые начисления") {
                    let repriced = affectedRentCharges.filter { !$0.allocated.isPositive }.count
                    let kept = affectedRentCharges.count - repriced
                    Text("Будет пересоздано неоплаченных начислений: \(repriced)")
                        .font(.subheadline)
                    if kept > 0 {
                        Text("Оплаченные и частично оплаченные остаются без изменений: \(kept)")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
            }
        }
    }
}
