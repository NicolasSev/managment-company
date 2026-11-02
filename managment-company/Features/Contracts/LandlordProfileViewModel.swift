import Combine
import Foundation

/// Text fields of the landlord profile, in screen order.
enum LandlordField: String, CaseIterable, Identifiable {
    case fullName = "full_name"
    case fullNameShortGen = "full_name_short_gen"
    case iin
    case document
    case address
    case phone
    case phone2
    case bankDetails = "bank_details"

    var id: String { rawValue }

    var keyPath: WritableKeyPath<LandlordProfileInput, String> {
        switch self {
        case .fullName: return \.fullName
        case .fullNameShortGen: return \.fullNameShortGen
        case .iin: return \.iin
        case .document: return \.document
        case .address: return \.address
        case .phone: return \.phone
        case .phone2: return \.phone2
        case .bankDetails: return \.bankDetails
        }
    }

    var title: String {
        switch self {
        case .fullName: return "ФИО полностью"
        case .fullNameShortGen: return "ФИО в родительном падеже"
        case .iin: return "ИИН"
        case .document: return "Документ, удостоверяющий личность"
        case .address: return "Адрес"
        case .phone: return "Телефон"
        case .phone2: return "Телефон 2"
        case .bankDetails: return "Банковские реквизиты"
        }
    }

    var placeholder: String {
        switch self {
        case .fullName: return "Карцева Татьяна Викторовна"
        case .fullNameShortGen: return "Карцевой Т.В."
        case .iin: return "12 цифр"
        case .document: return "удостоверение личности РК № …, выдано …"
        case .address: return "г. Алматы, ул. …"
        case .phone: return "+7 …"
        case .phone2: return "Необязательно"
        case .bankDetails: return "Необязательно"
        }
    }

    /// Fields the contract does not need (never highlighted).
    var isRequired: Bool { self != .phone2 && self != .bankDetails }
}

/// State of the landlord profile screen (`GET/PUT /v1/landlord-profile`).
@MainActor
final class LandlordProfileViewModel: ObservableObject {
    enum LoadState: Equatable {
        case loading
        case loaded
        case error(String)
    }

    @Published private(set) var loadState: LoadState = .loading
    @Published var form = LandlordProfileInput()
    /// `missing_fields` of the last answer.
    @Published private(set) var missing: Set<String> = []
    @Published private(set) var isSaving = false
    @Published private(set) var message: String?
    @Published private(set) var errorMessage: String?

    private let service: ContractService
    private var saved = LandlordProfileInput()

    init(service: ContractService) {
        self.service = service
    }

    var isDirty: Bool { form != saved }

    /// Highlighted while the server still lists the field and the user has not typed into it.
    func isHighlighted(_ field: LandlordField) -> Bool {
        field.isRequired
            && missing.contains(field.rawValue)
            && form[keyPath: field.keyPath].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isGenderHighlighted: Bool { missing.contains("gender") && form.gender == nil }

    var highlightedCount: Int {
        LandlordField.allCases.filter(isHighlighted).count + (isGenderHighlighted ? 1 : 0)
    }

    /// Message in Russian when the form cannot be sent, else nil.
    var validationMessage: String? {
        let iin = form.iin.trimmingCharacters(in: .whitespacesAndNewlines)
        if !iin.isEmpty, iin.count != 12 || !iin.allSatisfy(\.isNumber) {
            return "ИИН: ровно 12 цифр."
        }
        return nil
    }

    func load() async {
        loadState = .loading
        do {
            apply(try await service.landlordProfile())
            loadState = .loaded
        } catch let error as ContractServiceError {
            loadState = .error(error.userMessage)
        } catch {
            loadState = .error(ContractServiceError.unknown.userMessage)
        }
    }

    func save() async {
        guard !isSaving else { return }
        if let validationMessage {
            errorMessage = validationMessage
            return
        }
        isSaving = true
        errorMessage = nil
        message = nil
        defer { isSaving = false }
        do {
            let profile = try await service.saveLandlordProfile(form)
            apply(profile)
            message = profile.missingFields.isEmpty
                ? "Профиль сохранён."
                : "Профиль сохранён. Для договора ещё не хватает полей: \(profile.missingFields.count)."
        } catch let error as ContractServiceError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = ContractServiceError.unknown.userMessage
        }
    }

    private func apply(_ profile: LandlordProfile) {
        let input = LandlordProfileInput(profile)
        form = input
        saved = input
        missing = Set(profile.missingFields)
    }
}
