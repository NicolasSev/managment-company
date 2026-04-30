import Foundation

/// Matches the list JSON envelope: `{ "data", "page", "per_page", "total" }`.
struct APIListEnvelope<Element: Decodable>: Decodable {
    let data: [Element]
    let page: Int
    let perPage: Int
    let total: Int

    enum CodingKeys: String, CodingKey {
        case data, page, total
        case perPage = "per_page"
    }
}
