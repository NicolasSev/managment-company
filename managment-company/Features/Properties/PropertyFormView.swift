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
        }
    }
    
    private func populateFromProperty() {
        guard let p = property else { return }
        name = p.name
        propertyType = p.propertyType
        status = p.status
        address = p.address ?? ""
        city = p.city ?? ""
        utilityAccountNumber = p.utilityAccountNumber ?? ""
    }
    
    private func save() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        let trimmedAccount = utilityAccountNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = PropertyInput(
            name: name,
            propertyType: propertyType,
            status: status,
            address: address.isEmpty ? nil : address,
            city: city.isEmpty ? nil : city,
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
    let utilityAccountNumber: String?

    enum CodingKeys: String, CodingKey {
        case name, status, address, city
        case propertyType = "property_type"
        case utilityAccountNumber = "utility_account_number"
    }
}
