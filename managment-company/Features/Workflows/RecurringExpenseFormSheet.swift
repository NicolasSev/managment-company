import SwiftUI

/// Create/edit a recurring expense template (GAP-039).
struct RecurringExpenseFormSheet: View {
    let template: RecurringExpenseTemplate?
    let onSave: (RecurringExpenseInput) async -> Bool

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var properties: [Property] = []
    @State private var categories: [Category] = []
    @State private var propertyId = ""
    @State private var categoryId = ""
    @State private var amountText = ""
    @State private var payee = ""
    @State private var description = ""
    @State private var cadence = "monthly"
    @State private var nextOccurrence = Date()
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let timeZoneIdentifier: String
    private let currency: String

    private let cadences = ["monthly", "weekly", "quarterly", "yearly"]

    init(authManager: AuthManager, template: RecurringExpenseTemplate?, onSave: @escaping (RecurringExpenseInput) async -> Bool) {
        self.template = template
        self.onSave = onSave
        self.timeZoneIdentifier = authManager.user?.timezone ?? "Asia/Almaty"
        self.currency = template?.currency ?? authManager.user?.baseCurrency ?? "KZT"
    }

    private var expenseCategories: [Category] {
        categories.filter { $0.type == "expense" }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var canSave: Bool {
        !propertyId.isEmpty && !categoryId.isEmpty && (Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Объект") {
                    Picker("Объект", selection: $propertyId) {
                        Text("Не выбрано").tag("")
                        ForEach(properties) { Text($0.name).tag($0.id) }
                    }
                }
                Section("Категория") {
                    Picker("Категория", selection: $categoryId) {
                        Text("Не выбрано").tag("")
                        ForEach(expenseCategories) { Text($0.name).tag($0.id) }
                    }
                }
                Section("Сумма") {
                    HStack {
                        TextField("0", text: $amountText).keyboardType(.decimalPad)
                        Text(currency).foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
                Section("Расписание") {
                    Picker("Периодичность", selection: $cadence) {
                        ForEach(cadences, id: \.self) { Text(cadenceLabel($0)).tag($0) }
                    }
                    DatePicker("Следующая дата", selection: $nextOccurrence, displayedComponents: .date)
                }
                Section("Дополнительно") {
                    AppTextField(title: "Получатель", text: $payee, placeholder: "Необязательно")
                    AppTextField(title: "Комментарий", text: $description, placeholder: "Необязательно")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(AppTheme.Colors.danger) }
                }
            }
            .navigationTitle(template == nil ? "Новый шаблон" : "Шаблон")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { Task { await save() } }
                        .disabled(!canSave || isSaving)
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        async let props: [Property]? = try? await APIClient.shared.request("/v1/properties", tokenProvider: { await MainActor.run { authManager.accessToken } }, refreshAndRetry: { await authManager.refreshToken() })
        async let cats: [Category]? = try? await APIClient.shared.request("/v1/categories", tokenProvider: { await MainActor.run { authManager.accessToken } }, refreshAndRetry: { await authManager.refreshToken() })
        properties = (await props) ?? []
        categories = (await cats) ?? []
        if let template {
            propertyId = template.propertyId
            categoryId = template.categoryId
            amountText = String(template.amount)
            payee = template.payee ?? ""
            description = template.description ?? ""
            cadence = template.cadence
            nextOccurrence = AppFormatting.parsedDate(from: template.nextOccurrence) ?? Date()
        } else {
            propertyId = properties.first?.id ?? ""
            categoryId = expenseCategories.first?.id ?? ""
        }
    }

    private func save() async {
        guard let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")), amount > 0 else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let trimmedPayee = payee.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = RecurringExpenseInput(
            propertyId: propertyId,
            categoryId: categoryId,
            amount: amount,
            currency: currency,
            payee: trimmedPayee.isEmpty ? nil : trimmedPayee,
            description: trimmedDescription.isEmpty ? nil : trimmedDescription,
            cadence: cadence,
            timezone: timeZoneIdentifier,
            nextOccurrence: AppFormatting.dayKey(for: nextOccurrence, timeZoneIdentifier: timeZoneIdentifier),
            status: template?.status ?? "active"
        )
        if await onSave(input) {
            dismiss()
        } else {
            errorMessage = "Не удалось сохранить шаблон."
        }
    }

    private func cadenceLabel(_ cadence: String) -> String {
        switch cadence {
        case "monthly": return "Ежемесячно"
        case "weekly": return "Еженедельно"
        case "quarterly": return "Ежеквартально"
        case "yearly": return "Ежегодно"
        default: return cadence
        }
    }
}
