import SwiftUI

struct QuickTransactionSheet: View {
    /// Fixed property ID (used from PropertyDetailView). Pass `nil` when `properties` is provided.
    let propertyId: String?
    /// When non-nil, shows a property picker as the first field.
    var properties: [Property]? = nil
    var onSave: () async -> Void
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPropertyId: String = ""
    @State private var amount = ""
    @State private var selectedCategoryId: String?
    @State private var date = Date()
    @State private var isIncome = true
    @State private var categories: [Category] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var effectivePropertyId: String? {
        if let pid = propertyId, !pid.isEmpty { return pid }
        let s = selectedPropertyId.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
    
    var body: some View {
        NavigationStack {
            Form {
                if let props = properties {
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
                if let err = errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(AppTheme.Colors.danger)
                    }
                }
            }
            .navigationTitle("Быстрая операция")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { Task { await save() } }
                        .disabled(!isValid || isLoading)
                }
            }
            .task { await loadCategories() }
        }
    }
    
    private var filteredCategories: [Category] {
        categories.filter { $0.type == (isIncome ? "income" : "expense") }
    }
    
    private var isValid: Bool {
        guard let a = Double(amount), a > 0 else { return false }
        guard effectivePropertyId != nil else { return false }
        return selectedCategoryId != nil
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
              let amt = Double(amount), amt > 0,
              let pid = effectivePropertyId else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let body = TransactionInput(
            type: isIncome ? "income" : "expense",
            categoryId: catId,
            amount: amt,
            currency: authManager.user?.baseCurrency ?? "KZT",
            transactionDate: formatter.string(from: date)
        )

        do {
            _ = try await APIClient.shared.requestData(
                "/v1/properties/\(pid)/transactions",
                method: "POST",
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
    
    enum CodingKeys: String, CodingKey {
        case type, amount, currency
        case categoryId = "category_id"
        case transactionDate = "transaction_date"
    }
}
