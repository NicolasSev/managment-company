import Foundation

/// Модели внешнего portfolio-dashboard API (личные финансы, hub-and-spoke:
/// source of truth — таблица `transactions` в portfolio-dashboard; это приложение —
/// тонкий клиент и никогда не пишет личные транзакции в базу PropManager).
/// JSON — camelCase без обёртки `{ "data": … }`, суммы — decimal-строки.

struct PFAccount: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let accountType: String
    let baseCurrencyCode: String
    let institutionName: String?
}

struct PFCategory: Identifiable, Codable, Equatable {
    let id: String
    let slug: String
    let name: String
    let parentId: String?
    let sortOrder: Int
    let isActive: Bool
}

/// `GET /api/transactions/defaults` — префилл quick-add: последний счёт и топ категорий.
struct PFDefaults: Codable, Equatable {
    let lastAccountId: String?
    let lastCurrencyCode: String?
    let topCategoryIds: [String]
}

/// Тело `POST /api/transactions`. `currencyCode`/`occurredAt` не отправляем:
/// сервер берёт валюту счёта и текущий момент.
struct PFTransactionRequest: Encodable, Equatable {
    let accountId: String
    let transactionType: String
    let amount: String
    var categoryId: String?
    var merchant: String?
    var note: String?
    let source = "manual"
}

struct PFTransaction: Identifiable, Codable, Equatable {
    let id: String
    let accountId: String
    let transactionType: String
    let amount: String
    let currencyCode: String
    let categoryId: String?
    let note: String?
}

enum PFError: Error, LocalizedError, Equatable {
    /// Base URL или токен не заданы в настройках экрана.
    case notConfigured
    case invalidBaseURL
    case unauthorized
    case httpStatus(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Укажите адрес сервера и токен в настройках личных финансов."
        case .invalidBaseURL:
            return "Некорректный адрес сервера. Пример: http://185.146.3.87:18082"
        case .unauthorized:
            return "Токен не принят сервером. Проверьте токен в настройках."
        case .httpStatus(let code):
            return "Сервер личных финансов ответил ошибкой (\(code))."
        case .invalidResponse:
            return "Не удалось разобрать ответ сервера личных финансов."
        }
    }
}

/// Нормализация суммы из текстового поля: RU-локаль даёт `4 590,5`,
/// API принимает только десятичную точку без разделителей групп.
enum PFAmount {
    static func normalize(_ raw: String) -> String {
        raw.replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Валидная положительная сумма или nil. Полный матч обязателен:
    /// Decimal(string:) парсит валидный префикс и молча игнорирует хвост
    /// («12.5.0» → 12.5), поэтому одного его недостаточно.
    static func validated(_ raw: String) -> String? {
        let normalized = normalize(raw)
        guard normalized.wholeMatch(of: /[0-9]+(\.[0-9]+)?/) != nil,
              let value = Decimal(string: normalized), value > 0 else { return nil }
        return normalized
    }
}
