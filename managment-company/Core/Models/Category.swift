import Foundation

struct Category: Identifiable, Codable {
    let id: String
    let name: String
    let type: String
    let isSystem: Bool
    let icon: String?
    let sortOrder: Int
    
    enum CodingKeys: String, CodingKey {
        case id, name, type, icon
        case isSystem = "is_system"
        case sortOrder = "sort_order"
    }
}
