import SwiftUI

/// «Личные финансы» — quick-add личной траты/дохода в portfolio-dashboard.
/// Тонкий клиент внешнего API: домены не смешиваются, в базу PropManager
/// личные транзакции не пишутся (hub-and-spoke, см. product-manifest GAP-050).
struct PersonalFinanceView: View {
    var embedded = false
    @Environment(\.openURL) private var openURL
    @StateObject private var viewModel = PersonalFinanceViewModel()
    @State private var showSettings = false

    var body: some View {
        Group {
            if embedded {
                content
            } else {
                NavigationStack { content }
            }
        }
        .sheet(isPresented: $showSettings, onDismiss: {
            viewModel.refreshConfiguration()
            Task { await viewModel.load() }
        }) {
            PersonalFinanceSettingsSheet()
        }
        .task { await viewModel.load() }
    }

    private var content: some View {
        ZStack {
            AppScreenBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: AppTheme.Spacing.lg) {
                    if !viewModel.isConfigured {
                        setupPrompt
                    } else {
                        entryForm
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.lg)
            }
        }
        .navigationTitle("Личные финансы")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Настройки личных финансов")
            }
        }
    }

    private var setupPrompt: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Подключение")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Text("Личные траты и доходы записываются в отдельный сервис портфеля (portfolio-dashboard), не в базу PropManager. Укажите адрес сервера и токен доступа.")
                    .font(.body)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineSpacing(3)

                PrimaryButton(
                    title: "Настроить подключение",
                    action: { showSettings = true },
                    systemImage: "gearshape"
                )
            }
        }
    }

    /// Кнопки «в один тап»: Shortcuts открывается с готовым подписанным шорткатом
    /// с сервера, пользователю остаётся подтвердить добавление.
    private var shortcutsCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Шорткаты Apple Pay")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Text("Установите готовые шорткаты: авто-запись трат по Apple Pay с карты Freedom и ручное добавление с Siri или виджета.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineSpacing(2)

                ForEach(PersonalFinanceSettings.ShortcutKind.allCases, id: \.rawValue) { kind in
                    Button {
                        if let url = PersonalFinanceSettings.shortcutInstallURL(kind: kind) {
                            openURL(url)
                        }
                    } label: {
                        Label("Установить «\(kind.title)»", systemImage: "square.and.arrow.down")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, AppTheme.Spacing.md)
                            .padding(.vertical, AppTheme.Spacing.sm)
                            .background(AppTheme.Colors.accent.opacity(0.1))
                            .foregroundStyle(AppTheme.Colors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Text("После установки авто-шортката: Автоматизация → «Транзакция» → карта Freedom, «Запускать сразу» → действие «Выполнить шорткат: Трата Freedom (авто)».")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineSpacing(2)
            }
        }
    }

    private var entryForm: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            SurfaceCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    Picker("Тип записи", selection: $viewModel.entryType) {
                        ForEach(PersonalFinanceViewModel.EntryType.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)

                    AppTextField(
                        title: "Сумма",
                        text: $viewModel.amountText,
                        placeholder: "0",
                        keyboardType: .decimalPad
                    )

                    accountPicker

                    AppTextField(
                        title: "Комментарий",
                        text: $viewModel.note,
                        placeholder: "Необязательно"
                    )
                }
            }

            categoriesCard

            shortcutsCard

            if let successMessage = viewModel.successMessage {
                statusMessage(successMessage, color: AppTheme.Colors.success)
            }

            if let errorMessage = viewModel.errorMessage {
                statusMessage(errorMessage, color: AppTheme.Colors.danger)
            }

            PrimaryButton(
                title: viewModel.isSubmitting ? "Записываем..." : "Записать",
                action: { Task { await viewModel.submit() } },
                isLoading: viewModel.isSubmitting,
                isDisabled: !viewModel.canSubmit,
                systemImage: "plus.circle"
            )
        }
    }

    private var accountPicker: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text("Счёт")
                .font(.caption)
                .fontWeight(.semibold)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            Menu {
                ForEach(viewModel.accounts) { account in
                    Button {
                        viewModel.selectedAccountId = account.id
                    } label: {
                        if account.id == viewModel.selectedAccountId {
                            Label(accountTitle(account), systemImage: "checkmark")
                        } else {
                            Text(accountTitle(account))
                        }
                    }
                }
            } label: {
                HStack {
                    Text(viewModel.selectedAccount.map(accountTitle) ?? "Выберите счёт")
                        .foregroundStyle(
                            viewModel.selectedAccount == nil
                                ? AppTheme.Colors.textSecondary
                                : AppTheme.Colors.textPrimary
                        )
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.md)
                .background(Color.white.opacity(0.82))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.Colors.border, lineWidth: 1)
                )
            }
        }
    }

    private var categoriesCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Категория")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                if viewModel.isLoading && viewModel.categories.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, AppTheme.Spacing.md)
                } else if viewModel.categories.isEmpty {
                    Text("Категории появятся после подключения к серверу.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 104), spacing: AppTheme.Spacing.sm)],
                        spacing: AppTheme.Spacing.sm
                    ) {
                        ForEach(viewModel.categories) { category in
                            categoryTile(category)
                        }
                    }

                    Text("Категория необязательна — без неё запись попадёт в разбор.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
        }
    }

    private func categoryTile(_ category: PFCategory) -> some View {
        let isSelected = viewModel.selectedCategoryId == category.id
        return Button {
            viewModel.selectedCategoryId = isSelected ? nil : category.id
        } label: {
            Text(category.name)
                .font(.footnote.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, AppTheme.Spacing.xs)
                .background(isSelected ? AppTheme.Colors.accent : AppTheme.Colors.accent.opacity(0.1))
                .foregroundStyle(isSelected ? .white : AppTheme.Colors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func accountTitle(_ account: PFAccount) -> String {
        "\(account.name) · \(account.baseCurrencyCode)"
    }

    private func statusMessage(_ message: String, color: Color) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Настройки подключения: base URL — UserDefaults, токен — Keychain.
struct PersonalFinanceSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var baseURL = PersonalFinanceSettings.baseURL
    @State private var token = PersonalFinanceSettings.token ?? ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: AppTheme.Spacing.lg) {
                        SurfaceCard {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                                AppTextField(
                                    title: "Адрес сервера",
                                    text: $baseURL,
                                    placeholder: "http://185.146.3.87:18082",
                                    keyboardType: .URL,
                                    autocapitalization: .never
                                )

                                AppTextField(
                                    title: "Токен доступа",
                                    text: $token,
                                    placeholder: "Bearer-токен portfolio-dashboard",
                                    autocapitalization: .never
                                )

                                Text("Токен хранится в Keychain устройства и не покидает его, кроме запросов к указанному серверу.")
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                                    .lineSpacing(2)

                                if let errorMessage {
                                    Text(errorMessage)
                                        .font(.footnote)
                                        .foregroundStyle(AppTheme.Colors.danger)
                                }

                                PrimaryButton(
                                    title: "Сохранить",
                                    action: save,
                                    systemImage: "square.and.arrow.down"
                                )
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.lg)
                }
            }
            .navigationTitle("Подключение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }

    private func save() {
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedURL.isEmpty || URL(string: trimmedURL) != nil else {
            errorMessage = "Некорректный адрес сервера."
            return
        }
        PersonalFinanceSettings.baseURL = trimmedURL
        guard PersonalFinanceSettings.storeToken(token) else {
            errorMessage = "Не удалось сохранить токен в Keychain."
            return
        }
        dismiss()
    }
}
