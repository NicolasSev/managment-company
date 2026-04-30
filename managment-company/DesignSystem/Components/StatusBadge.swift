import SwiftUI

struct StatusBadge: View {
    let status: String
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(statusDisplay)
                .font(.caption2)
                .fontWeight(.semibold)
                .tracking(0.4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(statusColor.opacity(0.14))
        .foregroundStyle(statusColor)
        .overlay(
            Capsule()
                .stroke(statusColor.opacity(0.16), lineWidth: 1)
        )
        .clipShape(Capsule())
    }
    
    private var normalizedStatus: String {
        status.lowercased().replacingOccurrences(of: " ", with: "_")
    }
    
    private var statusDisplay: String {
        switch normalizedStatus {
        case "occupied": return "Занято"
        case "vacant": return "Свободно"
        case "renovation": return "Ремонт"
        case "for_sale": return "В продаже"
        case "archived": return "Архив"
        case "todo": return "Ожидает"
        case "pending": return "Ожидает"
        case "done": return "Завершено"
        case "completed": return "Завершено"
        case "in_progress": return "В работе"
        case "cancelled": return "Отменено"
        case "paid": return "Оплачено"
        case "low": return "Низкий"
        case "medium": return "Средний"
        case "high": return "Высокий"
        case "urgent": return "Срочно"
        case "income": return "Доход"
        case "expense": return "Расход"
        default:
            return normalizedStatus
                .split(separator: "_")
                .map { $0.capitalized }
                .joined(separator: " ")
        }
    }
    
    private var statusColor: Color {
        switch normalizedStatus {
        case "occupied", "completed", "done", "income":
            return AppTheme.Colors.success
        case "vacant", "expense", "urgent", "cancelled":
            return AppTheme.Colors.danger
        case "renovation", "in_progress", "pending", "todo", "high":
            return AppTheme.Colors.warning
        case "medium":
            return AppTheme.Colors.info
        default:
            return AppTheme.Colors.textSecondary
        }
    }
}
