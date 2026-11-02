import Combine
import SwiftUI

/// The utility settings of one property as the property form edits them: who pays, the default
/// account, and which months a receipt is expected. The payer travels with the property record
/// (`utility_payer`); the account and the expectation rule have endpoints of their own.
@MainActor
final class UtilityPropertySettingsModel: ObservableObject {
    @Published var payer: UtilityPayer = .tenant
    @Published var providerName = ""
    @Published var accountNumber = ""
    /// A receipt is expected for the chosen months.
    @Published var expectsBills = false
    @Published var months: Set<Int> = Set(1...12)
    @Published private(set) var isLoaded = false
    @Published private(set) var loadFailed = false

    private var service: UtilityBillsService?
    private var propertyId: String?
    private var account: UtilityAccount?
    private var rule: UtilityExpectation?
    private let today: () -> Date

    init(today: @escaping () -> Date = { Date() }) {
        self.today = today
    }

    /// The payer is on the property record; the rest comes from the utility endpoints.
    func load(property: Property, service: UtilityBillsService) async {
        guard propertyId != property.id || !isLoaded else { return }
        self.service = service
        propertyId = property.id
        payer = property.utilityPayer ?? .tenant
        do {
            async let accountTask = service.account(propertyId: property.id)
            async let rulesTask = service.expectations(propertyId: property.id)
            let loadedAccount = try await accountTask
            let rules = try await rulesTask
            account = loadedAccount
            providerName = loadedAccount?.providerName ?? ""
            accountNumber = loadedAccount?.accountNumber ?? ""
            // The rule that is still open produces expected bills; the closed ones are history.
            rule = rules.filter(\.isOpen).max(by: { $0.activeFrom < $1.activeFrom })
            expectsBills = rule != nil
            months = Set(rule?.months ?? Array(1...12))
            isLoaded = true
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    /// Whether the account or the rule differ from what the server has.
    var hasChanges: Bool {
        guard isLoaded else { return false }
        return accountChange() != .none || ruleChange() != .none
    }

    private enum AccountChange: Equatable {
        case none
        case save(UtilityAccountInput)
        case remove
    }

    private enum RuleChange: Equatable {
        case none
        case create(UtilityExpectationInput)
        case update(UtilityExpectationInput)
        case close(String)
    }

    private func accountChange() -> AccountChange {
        let number = accountNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = providerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if number.isEmpty { return account == nil ? .none : .remove }
        if let account, account.accountNumber == number, (account.providerName ?? "") == provider { return .none }
        return .save(UtilityAccountInput(providerName: provider.isEmpty ? nil : provider, accountNumber: number))
    }

    private func ruleChange() -> RuleChange {
        let chosen = months.sorted()
        if expectsBills {
            guard !chosen.isEmpty else { return .none }
            if let rule {
                return rule.months.sorted() == chosen
                    ? .none
                    : .update(UtilityExpectationInput(months: chosen, activeFrom: rule.activeFrom, activeTo: nil))
            }
            return .create(UtilityExpectationInput(months: chosen, activeFrom: Self.firstOfMonth(today()), activeTo: nil))
        }
        return rule == nil ? .none : .close(UtilityFormat.localDayKey(today()))
    }

    /// First day of the month of `date`, `YYYY-MM-01`.
    static func firstOfMonth(_ date: Date) -> String {
        String(UtilityFormat.localDayKey(date).prefix(8)) + "01"
    }

    /// Saves the account and the rule; throws the first failure (the property itself is saved by the form).
    func apply() async throws {
        guard isLoaded, let service, let propertyId else { return }
        switch accountChange() {
        case .none:
            break
        case .save(let input):
            account = try await service.saveAccount(propertyId: propertyId, existing: account, input: input)
        case .remove:
            if let account { try await service.deleteAccount(propertyId: propertyId, id: account.id) }
            account = nil
        }
        switch ruleChange() {
        case .none:
            break
        case .create(let input):
            rule = try await service.saveExpectation(propertyId: propertyId, existing: nil, input: input)
        case .update(let input):
            rule = try await service.saveExpectation(propertyId: propertyId, existing: rule, input: input)
        case .close(let day):
            if let rule {
                _ = try await service.saveExpectation(
                    propertyId: propertyId,
                    existing: rule,
                    input: UtilityExpectationInput(months: rule.months, activeFrom: rule.activeFrom, activeTo: day)
                )
            }
            rule = nil
        }
    }

    func toggle(month: Int) {
        if months.contains(month) {
            if months.count > 1 { months.remove(month) }
        } else {
            months.insert(month)
        }
    }
}

/// The «Коммунальные платежи» section of the property form.
struct UtilityPropertySettingsSection: View {
    @ObservedObject var model: UtilityPropertySettingsModel
    /// A new property has no id yet: the account and the rule wait until it is saved.
    let isNewProperty: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)

    var body: some View {
        Section {
            Picker("Платит за коммуналку", selection: $model.payer) {
                Text("Арендатор").tag(UtilityPayer.tenant)
                Text("Владелец").tag(UtilityPayer.owner)
            }
            .accessibilityIdentifier("property.form.utility_payer")
            if model.payer == .owner {
                Text("Платит владелец: арендатору пересылать нечего.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            if isNewProperty {
                Text("Лицевой счёт и месяцы, за которые ждать квитанцию, настраиваются после сохранения объекта.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            } else if model.loadFailed {
                Text("Не удалось загрузить лицевой счёт и правило ожидания. Закройте форму и откройте снова.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.warning)
                    .accessibilityIdentifier("property.form.utilities.error")
            } else if model.isLoaded {
                TextField("Поставщик, например АлСеКо", text: $model.providerName)
                    .accessibilityIdentifier("property.form.utility_provider")
                TextField("Лицевой счёт как на квитанции", text: $model.accountNumber)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("property.form.utility_account")
                Text("По номеру счёта загруженная квитанция сама находит объект.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Toggle("Ждать квитанции", isOn: $model.expectsBills)
                    .accessibilityIdentifier("property.form.utility_expect")
                if model.expectsBills {
                    Text("Месяцы, за которые нужна квитанция. Если её нет в день напоминания, придёт уведомление.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(1...12, id: \.self) { month in
                            monthChip(month)
                        }
                    }
                }
            } else {
                HStack(spacing: AppTheme.Spacing.sm) {
                    ProgressView()
                    Text("Загружаем настройки…")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
        } header: {
            Text("Коммунальные платежи")
        }
    }

    private func monthChip(_ month: Int) -> some View {
        let selected = model.months.contains(month)
        let title = UtilityFormat.monthShort(UtilityFormat.periodKey(year: 2000, month: month))
        return Button {
            model.toggle(month: month)
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(selected ? .white : AppTheme.Colors.accent)
                .background(selected ? AppTheme.Colors.accent : AppTheme.Colors.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(UtilityFormat.monthName(UtilityFormat.periodKey(year: 2000, month: month)))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("property.form.utility_month.\(month)")
    }
}
