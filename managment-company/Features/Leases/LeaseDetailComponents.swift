import SwiftUI

/// Short wire-day formatting for dense lease rows.
extension LeaseDay {
    private static let shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd.MM.yy"
        return formatter
    }()

    /// `15.10.26`
    static func short(_ day: String?) -> String {
        guard let day, let date = date(day) else { return "-" }
        return shortFormatter.string(from: date)
    }

    /// `15.10.26 - 14.11.26`
    static func period(_ start: String, _ end: String) -> String {
        start == end ? short(start) : "\(short(start)) - \(short(end))"
    }
}

extension View {
    /// Applies an accessibility identifier only when one is given.
    @ViewBuilder
    func leaseIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}

/// Status pill with lease-specific Russian labels (the shared `StatusBadge` does not know
/// `pending_signature`).
struct LeaseStatusBadge: View {
    let status: LeaseStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(status.title)
                .font(.caption2)
                .fontWeight(.semibold)
                .tracking(0.4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.14))
        .foregroundStyle(color)
        .overlay(Capsule().stroke(color.opacity(0.16), lineWidth: 1))
        .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
        case .active: return AppTheme.Colors.success
        case .draft, .pendingSignature: return AppTheme.Colors.warning
        case .terminated, .cancelled: return AppTheme.Colors.danger
        case .ended, .unknown: return AppTheme.Colors.textSecondary
        }
    }
}

/// Section card with a title; the common frame of every block on the lease screen.
struct LeaseSectionCard<Content: View>: View {
    let title: String
    var identifier: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                content()
            }
        }
        .accessibilityElement(children: .contain)
        .leaseIdentifier(identifier)
    }
}

/// `label ........ value` row.
struct LeaseKeyValueRow: View {
    let label: String
    let value: String
    var valueColor: Color = AppTheme.Colors.textPrimary
    var identifier: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Spacer(minLength: AppTheme.Spacing.sm)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
                .leaseIdentifier(identifier)
        }
    }
}

/// Small metric tile used in the balance block.
struct LeaseMetricTile: View {
    let title: String
    let value: String
    var color: Color = AppTheme.Colors.textPrimary
    var identifier: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .leaseIdentifier(identifier)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.sm)
        .background(Color.white.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

extension ChargeKind {
    var systemImage: String {
        switch self {
        case .rent: return "house"
        case .deposit: return "lock.shield"
        case .extra: return "wrench.and.screwdriver"
        case .unknown: return "questionmark.circle"
        }
    }
}
