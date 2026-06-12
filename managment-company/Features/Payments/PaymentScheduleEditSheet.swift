import SwiftUI

/// Edit one queue row: payment day and/or amount. Both edits are contract-level —
/// `PATCH /v1/payment-schedules/:id` rewrites the tenant's lease
/// (`payment_day`/`payment_due_day` or `rent_amount`) and regenerates all future
/// installments, mirroring the web `/payments` edit dialog.
struct PaymentScheduleEditSheet: View {
    let item: PaymentQueueItem
    /// Returns true on success; the sheet dismisses itself.
    let onApply: (_ day: Int?, _ amount: Double?) async -> Bool

    @Environment(\.dismiss) private var dismiss

    @State private var day: Int
    @State private var amountText: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// Same 1–28 day window as web: every month has these days.
    private static let dayOptions = Array(1...28)

    init(item: PaymentQueueItem, onApply: @escaping (_ day: Int?, _ amount: Double?) async -> Bool) {
        self.item = item
        self.onApply = onApply
        let seededDay = PaymentsQueueViewModel.dueDay(fromISODate: item.dueDate) ?? item.paymentDay ?? 1
        _day = State(initialValue: min(max(seededDay, 1), 28))
        _amountText = State(initialValue: PaymentScheduleEditSheet.amountLabel(item.expectedAmount))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.propertyName)
                            .font(.headline)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Text(item.tenantName.isEmpty ? "—" : item.tenantName)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }

                Section("Платёж") {
                    Picker("День оплаты (число месяца)", selection: $day) {
                        ForEach(Self.dayOptions, id: \.self) { d in
                            Text("\(d) число").tag(d)
                        }
                    }

                    AppTextField(
                        title: "Сумма платежа (\(item.currency))",
                        text: $amountText,
                        placeholder: PaymentScheduleEditSheet.amountLabel(item.expectedAmount),
                        keyboardType: .decimalPad,
                        autocapitalization: .never
                    )
                }

                if hasChanges {
                    Section {
                        Label {
                            Text("Изменение применится к договору арендатора и ко всем будущим платежам по этому объекту.")
                                .font(.footnote)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                        .foregroundStyle(AppTheme.Colors.warning)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(AppTheme.Colors.danger)
                    }
                }
            }
            .navigationTitle("Изменить платёж")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { Task { await save() } }
                        .disabled(!hasChanges || !amountIsValid || isSaving)
                }
            }
        }
    }

    private var currentDay: Int? {
        PaymentsQueueViewModel.dueDay(fromISODate: item.dueDate)
    }

    private var dayChanged: Bool { day != currentDay }

    private var parsedAmount: Double? {
        Double(amountText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }

    private var amountChanged: Bool {
        guard let value = parsedAmount, value > 0 else { return false }
        return value != item.expectedAmount
    }

    private var amountIsValid: Bool {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return dayChanged }
        guard let value = parsedAmount else { return false }
        return value > 0
    }

    private var hasChanges: Bool { dayChanged || amountChanged }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let success = await onApply(
            dayChanged ? day : nil,
            amountChanged ? parsedAmount : nil
        )
        if success {
            dismiss()
        } else {
            errorMessage = "Не удалось сохранить изменения."
        }
    }

    private static func amountLabel(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
