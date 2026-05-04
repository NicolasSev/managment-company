import SwiftUI

/// Форма для `POST /v1/payment-schedules/:id/mark-paid`: сумма по умолчанию из графика, дату можно сменить.
struct MarkSchedulePaidSheet: View {
    let schedule: LeasePaymentSchedule
    let onSuccess: () async -> Void

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String
    @State private var paymentDate: Date
    @State private var currency: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(schedule: LeasePaymentSchedule, onSuccess: @escaping () async -> Void) {
        self.schedule = schedule
        self.onSuccess = onSuccess
        _amountText = State(initialValue: MarkSchedulePaidSheet.defaultAmountLabel(schedule.expectedAmount))
        _paymentDate = State(initialValue: MarkSchedulePaidSheet.dueAnchorDate(schedule.dueDate))
        _currency = State(initialValue: schedule.currency)
        _notes = State(initialValue: "")
    }

    private static let apiDayFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Срок платежа \(AppFormatting.dateString(from: schedule.dueDate) ?? schedule.dueDate)")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)

                    Text("По умолчанию подставлена сумма из графика. Оставьте сумму пустой — сервер возьмёт ожидаемую.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Оплата") {
                    AppTextField(
                        title: "Сумма",
                        text: $amountText,
                        placeholder: "Из графика",
                        keyboardType: .decimalPad,
                        autocapitalization: .never
                    )
                    AppTextField(
                        title: "Валюта",
                        text: $currency,
                        placeholder: schedule.currency,
                        autocapitalization: .characters
                    )
                    DatePicker(
                        "Дата оплаты",
                        selection: $paymentDate,
                        displayedComponents: .date
                    )
                }

                Section("Заметки") {
                    AppTextField(title: "Комментарий", text: $notes, placeholder: "Необязательно")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(AppTheme.Colors.danger)
                    }
                }
            }
            .navigationTitle("Отметить оплату")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Провести") { Task { await save() } }
                        .disabled(!canSubmit || isSaving)
                }
            }
        }
    }

    private var canSubmit: Bool {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        guard let v = parsedAmount(trimmed) else { return false }
        return v > 0
    }

    private func parsedAmount(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private static func dueAnchorDate(_ due: String) -> Date {
        Self.apiDayFormatter.date(from: due) ?? Date()
    }

    private static func defaultAmountLabel(_ value: Double) -> String {
        let n = NSNumber(value: value)
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f.string(from: n) ?? String(value)
    }

    private func queueAndDismiss(payload: MarkSchedulePaidRequest, idempotencyKey: String) {
        do {
            try PendingMutationQueue.shared.enqueueMarkPaid(
                scheduleId: schedule.id,
                leaseId: schedule.leaseId,
                body: payload,
                idempotencyKey: idempotencyKey
            )
            Task { await PendingMutationQueue.shared.processQueue(authManager: authManager) }
            dismiss()
        } catch {
            errorMessage = "Не удалось сохранить операцию в очередь."
        }
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let trimmedAmount = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        let amountPayload: Double?
        if trimmedAmount.isEmpty {
            amountPayload = nil
        } else if let v = parsedAmount(trimmedAmount), v > 0 {
            amountPayload = v
        } else {
            await MainActor.run {
                errorMessage = "Введите положительную сумму или оставьте поле пустым."
            }
            return
        }

        let trimmedCurrency = currency.trimmingCharacters(in: .whitespacesAndNewlines)
        let payDay = Self.apiDayFormatter.string(from: paymentDate)

        let noteTrimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let idempotencyKey = UUID().uuidString
        let payload = MarkSchedulePaidRequest(
            amount: amountPayload,
            currency: trimmedCurrency.isEmpty ? nil : trimmedCurrency.uppercased(),
            paymentDate: payDay,
            notes: noteTrimmed.isEmpty ? nil : noteTrimmed
        )

        do {
            _ = try await APIClient.shared.request(
                "/v1/payment-schedules/\(schedule.id)/mark-paid",
                method: "POST",
                body: payload,
                idempotencyKey: idempotencyKey,
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            ) as SchedulePaymentResult
            await onSuccess()
            await MainActor.run { dismiss() }
        } catch let api as APIError {
            await MainActor.run {
                switch api {
                case .httpStatus(409):
                    errorMessage = "Этот платёж уже отмечен оплаченным."
                case .httpStatus(422):
                    errorMessage = "Не удалось провести оплату: проверьте категорию дохода по аренде или курс валюты."
                case .httpStatus(let code):
                    if PendingMutationQueue.isRetryableTransportError(api) {
                        queueAndDismiss(payload: payload, idempotencyKey: idempotencyKey)
                        return
                    }
                    errorMessage = "Не удалось отметить оплату (код \(code))."
                default:
                    if PendingMutationQueue.isRetryableTransportError(api) {
                        queueAndDismiss(payload: payload, idempotencyKey: idempotencyKey)
                        return
                    }
                    errorMessage = "Не удалось отметить оплату."
                }
            }
        } catch {
            await MainActor.run {
                if PendingMutationQueue.isRetryableTransportError(error) {
                    queueAndDismiss(payload: payload, idempotencyKey: idempotencyKey)
                } else {
                    errorMessage = "Не удалось отметить оплату."
                }
            }
        }
    }
}