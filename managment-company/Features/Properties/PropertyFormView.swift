import SwiftUI

struct PropertyFormView: View {
    var property: Property?
    var onSave: () async -> Void
    var onDelete: (() async -> Void)? = nil
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var propertyType = "apartment"
    @State private var status = "vacant"
    @State private var address = ""
    @State private var city = ""
    /// The payer, the default account and the expected months (U9); the account number is also
    /// written to the property record, where the welcome text and the old matching read it.
    @StateObject private var utilityModel = UtilityPropertySettingsModel()
    @State private var utilityAccountNumber = ""
    @State private var wifiLogin = ""
    @State private var wifiPassword = ""
    @State private var ownershipDocument = ""
    @State private var areaSqm = ""
    @State private var floor = ""
    @State private var purchaseDate = Date()
    @State private var purchasePrice = ""
    @State private var purchaseUSDEquivalent: ExchangeRateConversionDTO?
    @State private var purchaseRateMessage: String?
    @State private var isLoadingPurchaseRate = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var deleteConfirmationName = ""
    @State private var isDeleting = false

    private let propertyTypes = ["apartment", "house", "commercial", "land", "other"]
    private let statuses = ["vacant", "occupied", "renovation", "for_sale"]
    
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
                Section("Параметры объекта") {
                    AppTextField(
                        title: "Площадь, м²",
                        text: $areaSqm,
                        placeholder: "54,5",
                        keyboardType: .decimalPad,
                        autocapitalization: .never
                    )
                    .accessibilityIdentifier("property.form.area_sqm")
                    AppTextField(
                        title: "Этаж",
                        text: $floor,
                        placeholder: "5",
                        keyboardType: .numberPad,
                        autocapitalization: .never
                    )
                    .accessibilityIdentifier("property.form.floor")
                    Text("Площадь и этаж печатаются в договоре аренды.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                Section("Документы на объект") {
                    AppTextField(
                        title: "Правоустанавливающий документ",
                        text: $ownershipDocument,
                        placeholder: "Договор купли-продажи от 12.03.2019, рег. № …"
                    )
                    .accessibilityIdentifier("property.form.ownership_document")
                    Text("Печатается в договоре аренды (п. 1.1). Одной строкой: вид документа, дата, номер.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                UtilityPropertySettingsSection(model: utilityModel, isNewProperty: property == nil)
                Section("Wi-Fi для арендатора") {
                    AppTextField(
                        title: "Логин / сеть Wi-Fi",
                        text: $wifiLogin,
                        placeholder: "Например: Home_278_8",
                        autocapitalization: .never
                    )
                    AppTextField(
                        title: "Пароль Wi-Fi",
                        text: $wifiPassword,
                        placeholder: "Пароль от Wi-Fi",
                        autocapitalization: .never
                    )
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
                if let err = errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(AppTheme.Colors.danger)
                    }
                }
                if let property {
                    deleteSection(for: property)
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
                        .disabled(name.isEmpty || isLoading || isDeleting)
                }
            }
            .onAppear { populateFromProperty() }
            .task(id: purchaseRateKey) { await loadPurchaseUSDEquivalent() }
            .task {
                guard let property else { return }
                await utilityModel.load(
                    property: property,
                    service: UtilityBillsServiceProvider.makeService(authManager: authManager)
                )
            }
        }
    }

    private static func formatArea(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value).replacingOccurrences(of: ".", with: ",")
    }

    private var parsedArea: Double? {
        let normalized = areaSqm
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }

    private var parsedFloor: Int? {
        Int(floor.trimmingCharacters(in: .whitespacesAndNewlines))
    }

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
        wifiLogin = p.wifiLogin ?? ""
        wifiPassword = p.wifiPassword ?? ""
        ownershipDocument = p.ownershipDocument ?? ""
        areaSqm = p.areaSqm.map { Self.formatArea($0) } ?? ""
        floor = p.floor.map(String.init) ?? ""
        if let date = p.purchaseDate, let parsed = AppFormatting.parsedDate(from: date) {
            purchaseDate = parsed
        }
        if let price = p.purchasePrice {
            purchasePrice = String(Int(price.rounded()))
        }
    }
    
    @ViewBuilder
    private func deleteSection(for property: Property) -> some View {
        Section("Опасная зона") {
            if showDeleteConfirmation {
                Text("Введите название «\(property.name)», чтобы подтвердить. Объект и связанные с ним записи будут удалены без возможности восстановления.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                AppTextField(
                    title: "Название для подтверждения",
                    text: $deleteConfirmationName,
                    placeholder: property.name,
                    autocapitalization: .never
                )
                Button(role: .destructive) {
                    Task { await deleteProperty(property) }
                } label: {
                    if isDeleting {
                        ProgressView()
                    } else {
                        Text("Удалить объект")
                    }
                }
                .disabled(!deleteConfirmationMatches(property) || isDeleting)
            } else {
                Button("Удалить объект из портфеля", role: .destructive) {
                    showDeleteConfirmation = true
                }
                .disabled(isLoading)
            }
        }
    }

    private func deleteConfirmationMatches(_ property: Property) -> Bool {
        deleteConfirmationName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == property.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func deleteProperty(_ property: Property) async {
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }

        do {
            _ = try await APIClient.shared.requestData(
                "/v1/properties/\(property.id)",
                method: "DELETE",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            NotificationCenter.default.post(
                name: .propertyDeleted,
                object: nil,
                userInfo: ["propertyId": property.id]
            )
            AppHaptics.success()
            await onDelete?()
            dismiss()
        } catch {
            AppHaptics.warning()
            errorMessage = "Не удалось удалить объект. Возможно, есть связанные записи (аренды, операции)."
        }
    }

    private func save() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        let modelAccount = utilityModel.accountNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAccount = utilityModel.isLoaded
            ? modelAccount
            : utilityAccountNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWifiLogin = wifiLogin.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWifiPassword = wifiPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let price = parsedPurchasePrice
        let trimmedOwnership = ownershipDocument.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = PropertyInput(
            name: name,
            propertyType: propertyType,
            status: status,
            address: address.isEmpty ? nil : address,
            city: city.isEmpty ? nil : city,
            purchaseDate: price == nil ? nil : purchaseDateString,
            purchasePrice: price,
            purchaseCurrency: price == nil ? nil : "KZT",
            utilityAccountNumber: trimmedAccount.isEmpty ? nil : trimmedAccount,
            wifiLogin: trimmedWifiLogin.isEmpty ? nil : trimmedWifiLogin,
            wifiPassword: trimmedWifiPassword.isEmpty ? nil : trimmedWifiPassword,
            // PUT replaces the record: what the form does not edit goes back unchanged, or the
            // server clears it (area and floor are needed by the contract).
            country: property?.country,
            district: property?.district,
            areaSqm: parsedArea,
            rooms: property?.rooms,
            floor: parsedFloor,
            currentValue: property?.currentValue,
            currentValueCurrency: property?.currentValueCurrency,
            notes: property?.notes,
            tags: property?.tags,
            // PUT: absent keeps the stored value, an empty string clears it. A new object has nothing to clear.
            ownershipDocument: property == nil && trimmedOwnership.isEmpty ? nil : trimmedOwnership,
            utilityPayer: utilityModel.payer.rawValue
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
        } catch {
            errorMessage = "Не удалось сохранить объект"
            return
        }

        // The property is saved; the account and the expectation rule have their own endpoints.
        do {
            try await utilityModel.apply()
        } catch let error as UtilityBillsError {
            await onSave()
            errorMessage = "Объект сохранён, но коммунальные настройки нет. " + error.userMessage
            return
        } catch {
            await onSave()
            errorMessage = "Объект сохранён, но коммунальные настройки нет. Повторите."
            return
        }
        await onSave()
        dismiss()
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
    let utilityAccountNumber: String?
    let wifiLogin: String?
    let wifiPassword: String?
    let country: String?
    let district: String?
    let areaSqm: Double?
    let rooms: Int?
    let floor: Int?
    let currentValue: Double?
    let currentValueCurrency: String?
    let notes: String?
    let tags: [String]?
    let ownershipDocument: String?
    let utilityPayer: String?

    enum CodingKeys: String, CodingKey {
        case name, status, address, city, country, district, rooms, floor, notes, tags
        case areaSqm = "area_sqm"
        case currentValue = "current_value"
        case currentValueCurrency = "current_value_currency"
        case propertyType = "property_type"
        case purchaseDate = "purchase_date"
        case purchasePrice = "purchase_price"
        case purchaseCurrency = "purchase_currency"
        case utilityAccountNumber = "utility_account_number"
        case wifiLogin = "wifi_login"
        case wifiPassword = "wifi_password"
        case ownershipDocument = "ownership_document"
        case utilityPayer = "utility_payer"
    }
}

extension Notification.Name {
    /// После успешного удаления объекта. `userInfo["propertyId"]` — `String`.
    static let propertyDeleted = Notification.Name("app.propmanager.propertyDeleted")
    /// После архивирования или восстановления объекта.
    static let propertyArchiveChanged = Notification.Name("app.propmanager.propertyArchiveChanged")
}

private struct ExchangeRateConversionDTO: Decodable {
    let convertedAmount: Double
    let rateDate: String

    enum CodingKeys: String, CodingKey {
        case convertedAmount = "converted_amount"
        case rateDate = "rate_date"
    }
}
