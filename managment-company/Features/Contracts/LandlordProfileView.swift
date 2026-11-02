import SwiftUI

/// `Settings → Профиль арендодателя`: the landlord side of the contract, one per account.
/// Fields the contract still needs (`missing_fields`) are highlighted.
/// Accessibility identifiers: `settings.landlord.*`.
struct LandlordProfileView: View {
    @StateObject private var viewModel: LandlordProfileViewModel

    init(service: ContractService) {
        _viewModel = StateObject(wrappedValue: LandlordProfileViewModel(service: service))
    }

    var body: some View {
        ZStack {
            AppScreenBackground()
            content
        }
        .navigationTitle("Профиль арендодателя")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings.landlord.screen")
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("settings.landlord.loading")
        case .error(let message):
            EmptyStateView(
                title: "Профиль недоступен",
                message: message,
                actionName: "Повторить",
                action: { Task { await viewModel.load() } },
                icon: "person.text.rectangle"
            )
            .accessibilityIdentifier("settings.landlord.error")
        case .loaded:
            form
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                if viewModel.highlightedCount > 0 {
                    Label("Для договора не хватает полей: \(viewModel.highlightedCount)", systemImage: "exclamationmark.circle")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppTheme.Spacing.md)
                        .background(AppTheme.Colors.warning.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityIdentifier("settings.landlord.missing_banner")
                }

                SurfaceCard {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        Text("Арендодатель в договоре")
                            .font(.headline)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Text("Эти данные подставляются в каждый договор. Заполните один раз.")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.Colors.textSecondary)

                        ForEach(LandlordField.allCases) { field in
                            fieldView(field)
                        }
                        genderView
                    }
                }

                if let message = viewModel.message {
                    statusLine(message, color: AppTheme.Colors.success, identifier: "settings.landlord.message")
                }
                if let error = viewModel.errorMessage {
                    statusLine(error, color: AppTheme.Colors.danger, identifier: "settings.landlord.error_message")
                }

                PrimaryButton(
                    title: viewModel.isSaving ? "Сохраняем..." : "Сохранить",
                    action: { Task { await viewModel.save() } },
                    isLoading: viewModel.isSaving,
                    isDisabled: viewModel.isSaving || !viewModel.isDirty,
                    systemImage: "square.and.arrow.down"
                )
                .accessibilityIdentifier("settings.landlord.save")
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func fieldView(_ field: LandlordField) -> some View {
        let highlighted = viewModel.isHighlighted(field)
        return VStack(alignment: .leading, spacing: 4) {
            AppTextField(
                title: field.title,
                text: Binding(
                    get: { viewModel.form[keyPath: field.keyPath] },
                    set: { viewModel.form[keyPath: field.keyPath] = $0 }
                ),
                placeholder: field.placeholder,
                keyboardType: keyboard(for: field),
                autocapitalization: autocapitalization(for: field)
            )
            .accessibilityIdentifier("settings.landlord.field.\(field.rawValue)")
            if highlighted {
                Text("Нужно для договора")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.danger)
                    .accessibilityIdentifier("settings.landlord.field.\(field.rawValue).missing")
            }
        }
        .padding(highlighted ? AppTheme.Spacing.sm : 0)
        .background(highlighted ? AppTheme.Colors.danger.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var genderView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Пол (для «именуемый/именуемая»)")
                .font(.caption)
                .fontWeight(.semibold)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Picker("Пол", selection: $viewModel.form.gender) {
                Text("По отчеству").tag(LandlordGender?.none)
                Text("Женский").tag(Optional(LandlordGender.female))
                Text("Мужской").tag(Optional(LandlordGender.male))
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.landlord.gender")
            if viewModel.isGenderHighlighted {
                Text("Нужно для договора")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.danger)
            }
        }
    }

    private func statusLine(_ text: String, color: Color, identifier: String) -> some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.Spacing.md)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityIdentifier(identifier)
    }

    private func keyboard(for field: LandlordField) -> UIKeyboardType {
        switch field {
        case .iin: return .numberPad
        case .phone, .phone2: return .phonePad
        default: return .default
        }
    }

    private func autocapitalization(for field: LandlordField) -> TextInputAutocapitalization {
        switch field {
        case .iin, .phone, .phone2: return .never
        default: return .sentences
        }
    }
}
