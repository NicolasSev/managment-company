import Foundation

struct AppTask: Identifiable, Codable, Hashable {
    let id: String
    let propertyId: String?
    let title: String
    let description: String?
    let priority: String
    let status: String
    let dueDate: String?
    let reminderAt: String?
    let completedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id, title, description, priority, status
        case propertyId = "property_id"
        case dueDate = "due_date"
        case reminderAt = "reminder_at"
        case completedAt = "completed_at"
    }
}
