import SwiftUI

struct QuickTransactionSheet: View {
    /// Fixed property ID (used from PropertyDetailView). Pass `nil` when `properties` is provided.
    let propertyId: String?
    /// When non-nil, shows a property picker as the first field.
    var properties: [Property]? = nil
    var transaction: Transaction? = nil
    var onSave: () async -> Void
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPropertyId: String = ""
    @State private var amount = ""
    @State private var selectedCategoryId: String?
    @State private var date = Date()
    @State private var isIncome = true
    @State private var transactionDescription = ""
    @State private var categories: [Category] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didPopulate = false

    private var effectivePropertyId: String? {
        if let transaction { return transaction.propertyId }
        if let pid = propertyId, !pid.isEmpty { return pid }
        let s = selectedPropertyId.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
    
    var body: some View {
        NavigationStack {
            Form {
                if transaction == nil, let props = properties {
                    Section("Объект") {
                        Picker("Объект", selection: $selectedPropertyId) {
                            Text("Выберите объект").tag("")
                            ForEach(props) { p in
                                Text(p.name).tag(p.id)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                }
                Section("Сумма") {
                    HStack {
                        TextField("0", text: $amount)
                            .keyboardType(.decimalPad)
                        Picker("Тип", selection: $isIncome) {
                            Text("Доход").tag(true)
                            Text("Расход").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }
                }
                Section("Категория") {
                    Picker("Категория", selection: $selectedCategoryId) {
                        Text("Выбрать").tag(nil as String?)
                        ForEach(filteredCategories) { cat in
                            Text(cat.name).tag(cat.id as String?)
                        }
                    }
                    .onChange(of: isIncome) { _, _ in
                        if let id = selectedCategoryId,
                           !filteredCategories.contains(where: { $0.id == id }) {
                            selectedCategoryId = filteredCategories.first?.id
                        }
                    }
                }
                Section("Дата") {
                    DatePicker("Дата", selection: $date, displayedComponents: .date)
                }
                Section("Описание") {
                    AppTextField(title: "Описание", text: $transactionDescription, placeholder: "Необязательно")
                }
                if let err = errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(AppTheme.Colors.danger)
                    }
                }
            }
            .navigationTitle(transaction == nil ? "Новая операция" : "Редактировать операцию")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(transaction == nil ? "Сохранить" : "Готово") { Task { await save() } }
                        .disabled(!isValid || isLoading)
                }
            }
            .onAppear { populateFromTransactionIfNeeded() }
            .task { await loadCategories() }
        }
    }
    
    private var filteredCategories: [Category] {
        categories.filter { $0.type == (isIncome ? "income" : "expense") }
    }
    
    private var isValid: Bool {
        guard let a = parsedAmount, a > 0 else { return false }
        guard effectivePropertyId != nil else { return false }
        return selectedCategoryId != nil
    }

    private var parsedAmount: Double? {
        Double(
            amount
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: ",", with: ".")
        )
    }

    private func populateFromTransactionIfNeeded() {
        guard !didPopulate else { return }
        didPopulate = true

        if let transaction {
            selectedPropertyId = transaction.propertyId
            amount = String(transaction.amount)
            selectedCategoryId = transaction.categoryId
            isIncome = transaction.type == "income"
            transactionDescription = transaction.description ?? ""
            if let parsed = AppFormatting.parsedDate(from: transaction.transactionDate) {
                date = parsed
            }
            return
        }

        if selectedPropertyId.isEmpty, propertyId == nil, let first = properties?.first {
            selectedPropertyId = first.id
        }
    }
    
    private func loadCategories() async {
        do {
            categories = try await APIClient.shared.request(
                "/v1/categories",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            if selectedCategoryId == nil, let first = filteredCategories.first {
                selectedCategoryId = first.id
            }
        } catch {
            categories = []
        }
    }
    
    private func save() async {
        guard let catId = selectedCategoryId,
              let amt = parsedAmount, amt > 0,
              let pid = effectivePropertyId else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let trimmedDescription = transactionDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = TransactionInput(
            type: isIncome ? "income" : "expense",
            categoryId: catId,
            amount: amt,
            currency: authManager.user?.baseCurrency ?? "KZT",
            transactionDate: formatter.string(from: date),
            description: transaction == nil && trimmedDescription.isEmpty ? nil : trimmedDescription
        )

        do {
            let path: String
            let method: String
            if let transaction {
                path = "/v1/transactions/\(transaction.id)"
                method = "PUT"
            } else {
                path = "/v1/properties/\(pid)/transactions"
                method = "POST"
            }
            _ = try await APIClient.shared.requestData(
                path,
                method: method,
                body: body,
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            await onSave()
            dismiss()
        } catch {
            errorMessage = "Не удалось сохранить"
        }
    }
}

private struct TransactionInput: Encodable {
    let type: String
    let categoryId: String
    let amount: Double
    let currency: String
    let transactionDate: String
    let description: String?
    
    enum CodingKeys: String, CodingKey {
        case type, amount, currency, description
        case categoryId = "category_id"
        case transactionDate = "transaction_date"
    }
}
