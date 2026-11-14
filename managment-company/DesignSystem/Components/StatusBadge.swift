import SwiftUI

/// Meaning of a status, shared by every badge. Colour alone is not enough (grayscale,
/// Increase Contrast), so each tone also has its own symbol. Positive and informational
/// tones share cobalt: the palette has one chromatic accent.
enum StatusTone: Equatable {
    case success
    case warning
    case danger
    case info
    case neutral

    var color: Color {
        switch self {
        case .success: return AppTheme.Colors.success
        case .warning: return AppTheme.Colors.warning
        case .danger: return AppTheme.Colors.danger
        case .info: return AppTheme.Colors.info
        case .neutral: return AppTheme.Colors.textSecondary
        }
    }

    /// Fill behind the label: neutral stamps are outlined only.
    var fill: Color {
        self == .neutral ? Color.clear : color.opacity(0.1)
    }

    var systemImage: String {
        switch self {
        case .success: return "checkmark"
        case .warning: return "clock"
        case .danger: return "exclamationmark"
        case .info: return "info"
        case .neutral: return "minus"
        }
    }
}

struct StatusBadge: View {
    private let label: String
    private let tone: StatusTone

    /// Badge for a raw status string (`occupied`, `overdue`, ...).
    init(status: String) {
        let normalized = Self.normalize(status)
        self.label = Self.display(normalized)
        self.tone = Self.tone(normalized)
    }

    /// Badge with an explicit label and tone (domain enums with their own titles).
    init(label: String, tone: StatusTone) {
        self.label = label
        self.tone = tone
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: tone.systemImage)
                .font(.system(size: 9, weight: .heavy))
                .accessibilityHidden(true)

            Text(label)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .foregroundStyle(tone.color)
        .background(tone.fill, in: Self.shape)
        .overlay(Self.shape.strokeBorder(tone.color.opacity(tone == .neutral ? 0.35 : 0.3), lineWidth: 1))
        .animation(AppTheme.Motion.fast, value: tone)
    }

    /// A stamp, not a pill: small radius, hairline edge.
    private static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppTheme.Radius.stamp, style: .continuous)
    }

    private static func normalize(_ status: String) -> String {
        status.lowercased().replacingOccurrences(of: " ", with: "_")
    }

    private static func display(_ normalizedStatus: String) -> String {
        switch normalizedStatus {
        case "occupied": return "Занято"
        case "vacant": return "Свободно"
        case "renovation": return "Ремонт"
        case "for_sale": return "В продаже"
        case "archived": return "Архив"
        case "active": return "Активно"
        case "terminated": return "Завершено"
        case "expired": return "Истекло"
        case "todo": return "Ожидает"
        case "pending": return "Ожидает"
        case "done": return "Завершено"
        case "completed": return "Завершено"
        case "in_progress": return "В работе"
        case "cancelled": return "Отменено"
        case "low": return "Низкий"
        case "medium": return "Средний"
        case "high": return "Высокий"
        case "urgent": return "Срочно"
        case "income": return "Доход"
        case "expense": return "Расход"
        case "paid": return "Оплачено"
        case "skipped": return "Пропущено"
        case "overdue": return "Просрочено"
        default:
            return normalizedStatus
                .split(separator: "_")
                .map { $0.capitalized }
                .joined(separator: " ")
        }
    }
    
    static func tone(_ normalizedStatus: String) -> StatusTone {
        switch normalizedStatus {
        case "occupied", "completed", "done", "income", "active", "paid":
            return .success
        // Red is reserved for attention: an empty unit, an expense or an ended lease is neutral.
        case "urgent", "overdue":
            return .danger
        case "renovation", "in_progress", "pending", "todo", "high":
            return .warning
        case "medium":
            return .info
        default:
            return .neutral
        }
    }
}
