import SwiftUI

/// Terminate: move-out date, reason, and a preview of what happens (spec §3.7): voided
/// charges of later periods, the period of move-out stays whole, deposit forfeited on early
/// move-out, debt stays visible.
struct TerminateLeaseV2Sheet: View {
    @ObservedObject var viewModel: LeaseDetailViewModel
    let lease: LeaseAggregate

    @State private var moveOutDate: String
    @State private var reason = ""
    @State private var forfeitText = ""

    init(viewModel: LeaseDetailViewModel, lease: LeaseAggregate) {
        self.viewModel = viewModel
        self.lease = lease
        _moveOutDate = State(initialValue: viewModel.todayDay)
    }

    private var trimmedReason: String { reason.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var forfeitAmount: Money? {
        let trimmed = forfeitText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : Money.parse(trimmed, currency: lease.currency)
    }

    private var forfeitIsInvalid: Bool {
        let trimmed = forfeitText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let amount = forfeitAmount else { return true }
        return amount.minor < 0 || amount > lease.deposit.held
    }

    private var preview: LeaseTerminationPreview? {
        viewModel.terminationPreview(moveOutDate: moveOutDate, forfeitAmount: forfeitAmount)
    }

    var body: some View {
        LeaseSheetContainer(
            title: "Расторжение",
            name: "terminate",
            submitTitle: "Расторгнуть",
            canSubmit: !trimmedReason.isEmpty && !forfeitIsInvalid,
            isSubmitting: viewModel.isSubmitting,
            errorMessage: viewModel.sheetError,
            submitRole: .destructive,
            onCancel: { viewModel.dismissSheet() },
            onSubmit: {
                Task {
                    await viewModel.submitTerminate(
                        moveOutDate: moveOutDate,
                        reason: trimmedReason,
                        forfeitAmount: preview?.resultingStatus == .terminated ? forfeitAmount : nil
                    )
                }
            }
        ) {
            Section {
                DatePicker(
                    "Дата выезда",
                    selection: leaseDayBinding($moveOutDate),
                    in: (LeaseDay.pickerDate(lease.activationDate ?? lease.startDate) ?? Date.distantPast)...,
                    displayedComponents: .date
                )
                .accessibilityIdentifier("lease.detail.sheet.terminate.move_out_date")
                LeaseSheetField(
                    title: "Причина",
                    text: $reason,
                    placeholder: "Например, переезд в другой город",
                    identifier: "lease.detail.sheet.terminate.reason"
                )
            } footer: {
                Text("Последний день проживания. Не позже чем через 30 дней.")
            }

            if let preview {
                Section("Что произойдёт") {
                    LeaseKeyValueRow(label: "Итоговый статус", value: preview.resultingStatus.title)
                        .accessibilityIdentifier("lease.detail.sheet.terminate.preview.status")
                    if preview.voidedCharges.isEmpty {
                        Text("Начисления не аннулируются.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    } else {
                        LeaseKeyValueRow(
                            label: "Аннулируется начислений: \(preview.voidedCharges.count)",
                            value: preview.voidedTotal.formatted(),
                            identifier: "lease.detail.sheet.terminate.preview.void"
                        )
                    }
                    if let kept = preview.keptPeriodCharge {
                        Text("Период \(LeaseDay.period(kept.periodStart, kept.periodEnd)) остаётся полностью, без пересчёта.")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    if preview.debtStaysVisible.isPositive {
                        LeaseKeyValueRow(
                            label: "Долг до выезда остаётся",
                            value: preview.debtStaysVisible.formatted(),
                            valueColor: AppTheme.Colors.danger
                        )
                    }
                }

                if preview.resultingStatus == .terminated {
                    Section {
                        LeaseSheetField(
                            title: "Удержать депозит",
                            text: $forfeitText,
                            placeholder: "Пусто = весь депозит (\(lease.deposit.held.formatted()))",
                            keyboard: .decimalPad,
                            identifier: "lease.detail.sheet.terminate.forfeit"
                        )
                        LeaseKeyValueRow(
                            label: "Будет удержано",
                            value: preview.forfeitedDeposit.formatted(),
                            valueColor: AppTheme.Colors.warning,
                            identifier: "lease.detail.sheet.terminate.preview.forfeited"
                        )
                        if preview.remainingHeld.isPositive {
                            LeaseKeyValueRow(label: "Останется у вас до возврата", value: preview.remainingHeld.formatted())
                        }
                        if forfeitIsInvalid {
                            Text("Сумма не может быть больше удерживаемого депозита (\(lease.deposit.held.formatted())).")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.Colors.danger)
                        }
                    } header: {
                        Text("Депозит")
                    } footer: {
                        Text("Выезд раньше срока: депозит остаётся у владельца.")
                    }
                }
            }
        }
    }
}
