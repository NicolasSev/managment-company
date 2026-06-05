import Foundation

/// Элемент списка `GET /v1/notifications`.
struct AppNotification: Identifiable, Decodable, Hashable {
    let id: String
    let type: String
    let title: String
    let body: String?
    let data: [String: String]
    let readAt: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, type, title, body, data
        case readAt = "read_at"
        case createdAt = "created_at"
    }

    init(
        id: String,
        type: String,
        title: String,
        body: String?,
        data: [String: String] = [:],
        readAt: String?,
        createdAt: String
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.body = body
        self.data = data
        self.readAt = readAt
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        readAt = try container.decodeIfPresent(String.self, forKey: .readAt)
        createdAt = try container.decode(String.self, forKey: .createdAt)

        if let stringData = try? container.decode([String: String].self, forKey: .data) {
            data = stringData
        } else if let flexibleData = try? container.decode([String: NotificationDataValue].self, forKey: .data) {
            data = flexibleData.mapValues(\.stringValue)
        } else {
            data = [:]
        }
    }
}

private struct NotificationDataValue: Decodable {
    let stringValue: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            stringValue = value
        } else if let value = try? container.decode(Int.self) {
            stringValue = String(value)
        } else if let value = try? container.decode(Double.self) {
            stringValue = String(value)
        } else if let value = try? container.decode(Bool.self) {
            stringValue = value ? "true" : "false"
        } else {
            stringValue = ""
        }
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
