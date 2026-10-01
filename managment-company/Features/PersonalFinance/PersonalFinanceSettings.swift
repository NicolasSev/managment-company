import Foundation

/// Настройки подключения к portfolio-dashboard: base URL — в UserDefaults,
/// bearer-токен — только в Keychain. Плюс локальный кэш справочников
/// (единственный допустимый локальный стейт личных финансов на этом клиенте).
enum PersonalFinanceSettings {
    private static let baseURLKey = "personal_finance_base_url"
    private static let accountsCacheKey = "personal_finance_accounts_cache"
    private static let categoriesCacheKey = "personal_finance_categories_cache"

    static var baseURL: String {
        get { UserDefaults.standard.string(forKey: baseURLKey) ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            // POST на "…/api/transactions" собирается конкатенацией — хвостовой слэш даёт "//".
            let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
            UserDefaults.standard.set(normalized, forKey: baseURLKey)
        }
    }

    static var token: String? {
        KeychainManager.shared.getPersonalFinanceToken()
    }

    static func storeToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return KeychainManager.shared.clearPersonalFinanceToken() }
        return KeychainManager.shared.storePersonalFinanceToken(trimmed)
    }

    static var isConfigured: Bool {
        !baseURL.isEmpty && !(token ?? "").isEmpty
    }

    // MARK: - Установка шорткатов в один тап

    enum ShortcutKind: String, CaseIterable {
        case auto
        case manual

        var title: String {
            self == .auto ? "Трата Freedom (авто)" : "Добавить трату"
        }
    }

    /// `shortcuts://import-shortcut?url=…` — Shortcuts сам скачивает подписанный
    /// файл с сервера (auth через query `key`: импорт-запрос не шлёт заголовки)
    /// и показывает превью с одной кнопкой «Добавить».
    static func shortcutInstallURL(kind: ShortcutKind) -> URL? {
        guard isConfigured, let token else { return nil }
        let downloadURL = "\(baseURL)/api/shortcuts/\(kind.rawValue)?key=\(token)"
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard
            let encodedURL = downloadURL.addingPercentEncoding(withAllowedCharacters: allowed),
            let encodedName = kind.title.addingPercentEncoding(withAllowedCharacters: allowed)
        else { return nil }
        return URL(string: "shortcuts://import-shortcut?url=\(encodedURL)&name=\(encodedName)")
    }

    // MARK: - Справочники (кэш на случай офлайна/недоступности сервера)

    static var cachedAccounts: [PFAccount] {
        get { decode([PFAccount].self, forKey: accountsCacheKey) ?? [] }
        set { encode(newValue, forKey: accountsCacheKey) }
    }

    static var cachedCategories: [PFCategory] {
        get { decode([PFCategory].self, forKey: categoriesCacheKey) ?? [] }
        set { encode(newValue, forKey: categoriesCacheKey) }
    }

    private static func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
