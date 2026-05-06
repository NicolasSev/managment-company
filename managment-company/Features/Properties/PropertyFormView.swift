import SwiftUI

struct PropertyFormView: View {
    var property: Property?
    var onSave: () async -> Void
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var propertyType = "apartment"
    @State private var status = "vacant"
    @State private var address = ""
    @State private var city = ""
    @State private var utilityAccountNumber = ""
    @State private var purchaseDate = Date()
    @State private var purchasePrice = ""
    @State private var purchaseUSDEquivalent: ExchangeRateConversionDTO?
    @State private var purchaseRateMessage: String?
    @State private var isLoadingPurchaseRate = false
    @State private var currentValue = ""
    @State private var currentUSDEquivalent: ExchangeRateConversionDTO?
    @State private var isLoadingCurrentRate = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    private let propertyTypes = ["apartment", "house", "commercial", "land", "other"]
    private let statuses = ["vacant", "occupied", "renovation", "for_sale", "archived"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Основное") {
                    AppTextField(title: "Название", text: $name, placeholder: "Название объекта")
                    Picker("Тип", selection: $propertyType) {
                        ForEach(propertyTypes, id: \.self) { Text(propertyTypeLabel($0)) }
                    }
                    Picker("Статус", selection: $status) {
                        ForEach(statuses, id: \.self) { Text(statusLabel($0)) }
                    }
                }
                Section("Адрес") {
                    AppTextField(title: "Адрес", text: $address, placeholder: "Улица, дом")
                    AppTextField(title: "Город", text: $city, placeholder: "Город")
                }
                Section("Коммунальные платежи (OCR)") {
                    AppTextField(
                        title: "Лицевой счёт",
                        text: $utilityAccountNumber,
                        placeholder: "Как на квитанции, для автопривязки"
                    )
                    Text("Если указать номер совпадающий с квитанцией, объект подставится при загрузке квитанции на вкладке «Операции».")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                Section("Покупка") {
                    DatePicker("Дата покупки", selection: $purchaseDate, displayedComponents: .date)
                    AppTextField(
                        title: "Стоимость покупки (KZT)",
                        text: $purchasePrice,
                        placeholder: "0",
                        keyboardType: .decimalPad,
                        autocapitalization: .never
                    )
                    if isLoadingPurchaseRate {
                        Text("Считаем эквивалент в USD по курсу Нацбанка РК...")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    } else if let purchaseUSDEquivalent {
                        Text("≈ \(AppFormatting.compactAmount(purchaseUSDEquivalent.convertedAmount, currency: "USD")) по курсу на \(AppFormatting.dateString(from: purchaseUSDEquivalent.rateDate) ?? purchaseUSDEquivalent.rateDate)")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    } else if let purchaseRateMessage {
                        Text(purchaseRateMessage)
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.warning)
                    }
                }
                Section("Оценочная стоимость") {
                    AppTextField(
                        title: "Оценочная стоимость (KZT)",
                        text: $currentValue,
                        placeholder: "0",
                        keyboardType: .decimalPad,
                        autocapitalization: .never
                    )
                    if isLoadingCurrentRate {
                        Text("Считаем эквивалент в USD по курсу Нацбанка РК...")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    } else if let currentUSDEquivalent {
                        Text("≈ \(AppFormatting.compactAmount(currentUSDEquivalent.convertedAmount, currency: "USD")) по курсу на сегодня")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
                if let err = errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(AppTheme.Colors.danger)
                    }
                }
            }
            .navigationTitle(property == nil ? "Новый объект" : "Редактировать объект")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { Task { await save() } }
                        .disabled(name.isEmpty || isLoading)
                }
            }
            .onAppear { populateFromProperty() }
            .task(id: purchaseRateKey) { await loadPurchaseUSDEquivalent() }
            .task(id: currentRateKey) { await loadCurrentUSDEquivalent() }
        }
    }

    private var parsedCurrentValue: Double? {
        let normalized = currentValue
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }

    private var currentRateKey: String { "\(parsedCurrentValue ?? 0)-today" }

    private var parsedPurchasePrice: Double? {
        let normalized = purchasePrice
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }

    private var purchaseDateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: purchaseDate)
    }

    private var purchaseRateKey: String {
        "\(parsedPurchasePrice ?? 0)-\(purchaseDateString)"
    }
    
    private func populateFromProperty() {
        guard let p = property else { return }
        name = p.name
        propertyType = p.propertyType
        status = p.status
        address = p.address ?? ""
        city = p.city ?? ""
        utilityAccountNumber = p.utilityAccountNumber ?? ""
        if let date = p.purchaseDate, let parsed = AppFormatting.parsedDate(from: date) {
            purchaseDate = parsed
        }
        if let price = p.purchasePrice {
            purchasePrice = String(Int(price.rounded()))
        }
        if let val = p.currentValue {
            currentValue = String(Int(val.rounded()))
        }
    }
    
    private func save() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        let trimmedAccount = utilityAccountNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let price = parsedPurchasePrice
        let currVal = parsedCurrentValue
        let body = PropertyInput(
            name: name,
            propertyType: propertyType,
            status: status,
            address: address.isEmpty ? nil : address,
            city: city.isEmpty ? nil : city,
            purchaseDate: price == nil ? nil : purchaseDateString,
            purchasePrice: price,
            purchaseCurrency: price == nil ? nil : "KZT",
            currentValue: currVal,
            currentValueCurrency: currVal == nil ? nil : "KZT",
            utilityAccountNumber: trimmedAccount.isEmpty ? nil : trimmedAccount
        )
        
        do {
            if let id = property?.id {
                _ = try await APIClient.shared.requestData(
                    "/v1/properties/\(id)",
                    method: "PUT",
                    body: body,
                    tokenProvider: { await MainActor.run { authManager.accessToken } },
                    refreshAndRetry: { await authManager.refreshToken() }
                )
            } else {
                _ = try await APIClient.shared.requestData(
                    "/v1/properties",
                    method: "POST",
                    body: body,
                    tokenProvider: { await MainActor.run { authManager.accessToken } },
                    refreshAndRetry: { await authManager.refreshToken() }
                )
            }
            await onSave()
            dismiss()
        } catch {
            errorMessage = "Не удалось сохранить объект"
        }
    }

    private func loadCurrentUSDEquivalent() async {
        guard let amount = parsedCurrentValue else {
            currentUSDEquivalent = nil
            return
        }
        isLoadingCurrentRate = true
        defer { isLoadingCurrentRate = false }
        do {
            let path = "/v1/exchange-rates/convert?amount=\(amount)&base=KZT&target=USD"
            let data = try await APIClient.shared.requestData(
                path,
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            let decoded = try JSONDecoder().decode(APIResponse<ExchangeRateConversionDTO>.self, from: data)
            currentUSDEquivalent = decoded.data
        } catch {
            currentUSDEquivalent = nil
        }
    }

    private func loadPurchaseUSDEquivalent() async {
        guard let amount = parsedPurchasePrice else {
            purchaseUSDEquivalent = nil
            purchaseRateMessage = nil
            return
        }
        isLoadingPurchaseRate = true
        defer { isLoadingPurchaseRate = false }

        do {
            let path = "/v1/exchange-rates/convert?amount=\(amount)&base=KZT&target=USD&date=\(purchaseDateString)"
            let data = try await APIClient.shared.requestData(
                path,
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            let decoded = try JSONDecoder().decode(APIResponse<ExchangeRateConversionDTO>.self, from: data)
            purchaseUSDEquivalent = decoded.data
            purchaseRateMessage = nil
        } catch {
            purchaseUSDEquivalent = nil
            purchaseRateMessage = "Курс USD пока не загрузился"
        }
    }

    private func propertyTypeLabel(_ value: String) -> String {
        switch value {
        case "apartment": return "Квартира"
        case "house": return "Дом"
        case "commercial": return "Коммерция"
        case "land": return "Земля"
        case "other": return "Другое"
        default: return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func statusLabel(_ value: String) -> String {
        switch value {
        case "vacant": return "Свободно"
        case "occupied": return "Занято"
        case "renovation": return "Ремонт"
        case "for_sale": return "В продаже"
        case "archived": return "Архив"
        default: return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

private struct PropertyInput: Encodable {
    let name: String
    let propertyType: String
    let status: String
    let address: String?
    let city: String?
    let purchaseDate: String?
    let purchasePrice: Double?
    let purchaseCurrency: String?
    let currentValue: Double?
    let currentValueCurrency: String?
    let utilityAccountNumber: String?

    enum CodingKeys: String, CodingKey {
        case name, status, address, city
        case propertyType = "property_type"
        case purchaseDate = "purchase_date"
        case purchasePrice = "purchase_price"
        case purchaseCurrency = "purchase_currency"
        case currentValue = "current_value"
        case currentValueCurrency = "current_value_currency"
        case utilityAccountNumber = "utility_account_number"
    }
}

private struct ExchangeRateConversionDTO: Decodable {
    let convertedAmount: Double
    let rateDate: String

    enum CodingKeys: String, CodingKey {
        case convertedAmount = "converted_amount"
        case rateDate = "rate_date"
    }
}
