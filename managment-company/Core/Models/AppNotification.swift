import Foundation

/// Элемент списка `GET /v1/notifications` (поле `data` в теле уведомления с сервера не декодируем — достаточно заголовка для списка).
struct AppNotification: Identifiable, Decodable, Hashable {
    let id: String
    let type: String
    let title: String
    let body: String?
    let readAt: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, type, title, body
        case readAt = "read_at"
        case createdAt = "created_at"
    }
}

struct NotificationsListResponse: Decodable {
    let data: [AppNotification]
    let page: Int
    let perPage: Int
    let total: Int
    let unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case data, page, total
        case perPage = "per_page"
        case unreadCount = "unread_count"
    }
}

struct UnreadCountData: Decodable {
    let count: Int
}

struct RegisterDeviceBody: Encodable {
    let platform: String
    let token: String
}

/// Ответ `POST /v1/devices/register`: `{ "data": { … } }`.
struct DeviceRegisterData: Decodable {
    let id: String
    let platform: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, platform
        case createdAt = "created_at"
    }
}

/// Тело `PUT` с пустым JSON-объектом `{}`.
struct EmptyJSONBody: Encodable {}

/// `{ "data": { "ok": true } }` при отметке уведомления прочитанным.
struct APIJsonOk: Decodable {
    let ok: Bool
}
