import SwiftUI

struct UtilityFormView: View {
    let propertyId: String
    var utility: PropertyUtility?
    var onSave: () async -> Void

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var periodYear = Calendar.current.component(.year, from: Date())
    @State private var periodMonth = Calendar.current.component(.month, from: Date())
    @State private var utilityType = "utilities"
    @State private var provider = ""
    @State private var amount = ""
    @State private var currency = "KZT"
    @State private var dueDate = Date()
    @State private var hasDueDate = false
    @State private var paidAt = Date()
    @State private var hasPaidAt = false
    @State private var status = "pending"
    @State private var notes = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let utilityTypes = [
        "utilities",
        "electricity",
        "water",
        "gas",
        "heating",
        "internet",
        "maintenance",
        "other"
    ]
    private let statuses = ["pending", "paid", "cancelled"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Период") {
                    Stepper("Год \(periodYear)", value: $periodYear, in: 2000...2100)
                    Picker("Месяц", selection: $periodMonth) {
                        ForEach(1...12, id: \.self) { month in
                            Text(monthName(month)).tag(month)
                        }
                    }
                }

                Section("Коммуналка") {
                    Picker("Тип", selection: $utilityType) {
                        ForEach(utilityTypes, id: \.self) { value in
                            Text(displayValue(value)).tag(value)
                        }
                    }
                    AppTextField(title: "Поставщик", text: $provider, placeholder: "Поставщик или услуга")
                    AppTextField(
                        title: "Сумма",
                        text: $amount,
                        placeholder: "0",
                        keyboardType: .decimalPad,
                        autocapitalization: .never
                    )
                    AppTextField(
                        title: "Валюта",
                        text: $currency,
                        placeholder: "KZT",
                        autocapitalization: .characters
                    )
                }

                Section("Даты") {
                    Toggle("Указать срок оплаты", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Срок", selection: $dueDate, displayedComponents: .date)
                    }
                    Toggle("Указать дату оплаты", isOn: $hasPaidAt)
                    if hasPaidAt {
                        DatePicker("Оплачено", selection: $paidAt, displayedComponents: .date)
                    }
                }

                Section("Статус") {
                    Picker("Статус", selection: $status) {
                        ForEach(statuses, id: \.self) { value in
                            Text(displayValue(value)).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Заметки") {
                    AppTextField(title: "Заметки", text: $notes, placeholder: "Необязательно")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(AppTheme.Colors.danger)
                    }
                }
            }
            .navigationTitle(utility == nil ? "Новая коммуналка" : "Редактировать коммуналку")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { Task { await save() } }
                        .disabled(parsedAmount == nil || isLoading)
                }
            }
            .onAppear { populateFromUtility() }
        }
    }

    private var parsedAmount: Double? {
        Double(amount.replacingOccurrences(of: ",", with: "."))
    }

    private func populateFromUtility() {
        guard let utility else { return }
        periodYear = utility.periodYear
        periodMonth = utility.periodMonth
        utilityType = utility.utilityType
        provider = utility.provider ?? ""
        amount = String(utility.amount)
        currency = utility.currency
        status = utility.status
        notes = utility.notes ?? ""
        if let due = utility.dueDate, let parsed = AppFormatting.parsedDate(from: due) {
            dueDate = parsed
            hasDueDate = true
        }
        if let paid = utility.paidAt, let parsed = AppFormatting.parsedDate(from: paid) {
            paidAt = parsed
            hasPaidAt = true
        }
    }

    private func save() async {
        guard let parsedAmount else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let body = UtilityInput(
            periodYear: periodYear,
            periodMonth: periodMonth,
            utilityType: utilityType,
            provider: provider.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            amount: parsedAmount,
            currency: currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().nilIfBlank ?? "KZT",
            dueDate: hasDueDate ? dateString(dueDate) : nil,
            paidAt: hasPaidAt ? dateString(paidAt) : nil,
            status: status,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        )

        do {
            if let utility {
                _ = try await APIClient.shared.requestData(
                    "/v1/utilities/\(utility.id)",
                    method: "PUT",
                    body: body,
                    tokenProvider: { await MainActor.run { authManager.accessToken } },
                    refreshAndRetry: { await authManager.refreshToken() }
                )
            } else {
                _ = try await APIClient.shared.requestData(
                    "/v1/properties/\(propertyId)/utilities",
                    method: "POST",
                    body: body,
                    tokenProvider: { await MainActor.run { authManager.accessToken } },
                    refreshAndRetry: { await authManager.refreshToken() }
                )
            }
            AppHaptics.success()
            await onSave()
            dismiss()
        } catch {
            AppHaptics.warning()
            errorMessage = "Не удалось сохранить коммунальный платеж."
        }
    }

    private func monthName(_ month: Int) -> String {
        let formatter = DateFormatter()
        return formatter.monthSymbols[max(0, min(month - 1, 11))]
    }

    private func displayValue(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private struct UtilityInput: Encodable {
    let periodYear: Int
    let periodMonth: Int
    let utilityType: String
    let provider: String?
    let amount: Double
    let currency: String
    let dueDate: String?
    let paidAt: String?
    let status: String
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case provider, amount, currency, status, notes
        case periodYear = "period_year"
        case periodMonth = "period_month"
        case utilityType = "utility_type"
        case dueDate = "due_date"
        case paidAt = "paid_at"
    }
}

private extension String {
    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}
