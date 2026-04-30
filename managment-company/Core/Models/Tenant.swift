import Foundation

struct Tenant: Identifiable, Codable {
    let id: String
    let firstName: String
    let lastName: String?
    let phone: String?
    let email: String?
    let cohabitants: String?
    let notes: String?
    
    enum CodingKeys: String, CodingKey {
        case id, phone, email, cohabitants, notes
        case firstName = "first_name"
        case lastName = "last_name"
    }
    
    var displayName: String {
        [firstName, lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}
