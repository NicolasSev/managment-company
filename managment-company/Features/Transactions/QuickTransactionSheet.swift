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
    @State private var leases: [Lease] = []
    @State private var tenants: [Tenant] = []
    @State private var selectedLeaseId = ""
    @State private var periodYear = String(Calendar.current.component(.year, from: Date()))
    @State private var periodMonth = String(Calendar.current.component(.month, from: Date()))
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
                if rentCategorySelected {
                    Section("Аренда") {
                        Picker("Договор", selection: $selectedLeaseId) {
                            Text("Не связывать с арендатором").tag("")
                            ForEach(leases) { lease in
                                Text(leaseTitle(lease)).tag(lease.id)
                            }
                        }
                        .pickerStyle(.navigationLink)

                        HStack {
                            AppTextField(
                                title: "Год периода",
                                text: $periodYear,
                                placeholder: "2026",
                                keyboardType: .numberPad,
                                autocapitalization: .never
                            )
                            AppTextField(
                                title: "Месяц",
                                text: $periodMonth,
                                placeholder: "1",
                                keyboardType: .numberPad,
                                autocapitalization: .never
                            )
                        }

                        Text("Как и в вебе, связь с договором и периодом нужна календарю оплат аренды.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
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
            .task(id: effectivePropertyId ?? "") { await loadLeasesAndTenants() }
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

    private var selectedLease: Lease? {
        leases.first { $0.id == selectedLeaseId }
    }

    private var parsedPeriodYear: Int? {
        guard let value = Int(periodYear.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else {
            return nil
        }
        return value
    }

    private var parsedPeriodMonth: Int? {
        guard let value = Int(periodMonth.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...12).contains(value) else {
            return nil
        }
        return value
    }

    private var rentCategorySelected: Bool {
        guard isIncome, let selectedCategoryId else { return false }
        guard let category = categories.first(where: { $0.id == selectedCategoryId }) else { return false }
        return Self.isRentCategoryName(category.name)
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
            selectedLeaseId = transaction.leaseId ?? ""
            periodYear = String(transaction.periodYear)
            periodMonth = String(transaction.periodMonth)
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

    private func loadLeasesAndTenants() async {
        guard let pid = effectivePropertyId else {
            leases = []
            tenants = []
            selectedLeaseId = ""
            return
        }

        do {
            async let leasesRequest: [Lease] = APIClient.shared.request(
                "/v1/properties/\(pid)/leases",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            async let tenantsRequest: [Tenant] = APIClient.shared.request(
                "/v1/tenants?per_page=100",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            let (loadedLeases, loadedTenants) = try await (leasesRequest, tenantsRequest)
            leases = loadedLeases.sorted {
                ($0.moveInDate ?? $0.startDate) > ($1.moveInDate ?? $1.startDate)
            }
            tenants = loadedTenants
            if !selectedLeaseId.isEmpty, !loadedLeases.contains(where: { $0.id == selectedLeaseId }) {
                selectedLeaseId = ""
            }
        } catch {
            leases = []
            tenants = []
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
            description: transaction == nil && trimmedDescription.isEmpty ? nil : trimmedDescription,
            tenantId: rentCategorySelected ? selectedLease?.tenantId : nil,
            leaseId: rentCategorySelected ? selectedLease?.id : nil,
            periodYear: rentCategorySelected ? parsedPeriodYear : nil,
            periodMonth: rentCategorySelected ? parsedPeriodMonth : nil
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

    private func leaseTitle(_ lease: Lease) -> String {
        let tenant = tenants.first { $0.id == lease.tenantId }
        let tenantName = tenant?.displayName.isEmpty == false ? tenant!.displayName : "Арендатор"
        let from = AppFormatting.dateString(from: lease.moveInDate ?? lease.startDate) ?? (lease.moveInDate ?? lease.startDate)
        let toRaw = lease.terminatedAt ?? lease.endDate
        let to = toRaw.flatMap { AppFormatting.dateString(from: $0) } ?? "сейчас"
        return "\(tenantName) · \(from) - \(to)"
    }

    private static func isRentCategoryName(_ name: String) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "аренда" || normalized == "rent" || normalized.contains("арендная")
    }
}

private struct TransactionInput: Encodable {
    let type: String
    let categoryId: String
    let amount: Double
    let currency: String
    let transactionDate: String
    let description: String?
    let tenantId: String?
    let leaseId: String?
    let periodYear: Int?
    let periodMonth: Int?
    
    enum CodingKeys: String, CodingKey {
        case type, amount, currency, description
        case categoryId = "category_id"
        case transactionDate = "transaction_date"
        case tenantId = "tenant_id"
        case leaseId = "lease_id"
        case periodYear = "period_year"
        case periodMonth = "period_month"
    }
}
