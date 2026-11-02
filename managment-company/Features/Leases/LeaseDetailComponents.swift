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
/// `pending_signature`): a thin wrapper that only maps the lease status to a label and tone.
struct LeaseStatusBadge: View {
    let status: LeaseStatus

    var body: some View {
        StatusBadge(label: status.title, tone: tone)
    }

    private var tone: StatusTone {
        switch status {
        case .active: return .success
        case .draft, .pendingSignature: return .warning
        case .terminated, .cancelled: return .danger
        case .ended, .unknown: return .neutral
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

/// Small metric tile used in the balance block and on lease cards.
struct LeaseMetricTile: View {
    enum Size {
        case regular
        /// Headline figures of the balance («К оплате», «Просрочено»).
        case large
    }

    let title: String
    let value: String
    var color: Color = AppTheme.Colors.textPrimary
    var identifier: String?
    var size: Size = .regular
    /// Quiet background tint (e.g. danger for overdue). Plain secondary surface when `nil`.
    var tint: Color?
    var systemImage: String?
    /// Numeric value behind `value`, so changing digits roll in the right direction.
    var numericValue: Double?
    /// Bounces the icon whenever this changes (payment accepted). Ignored under Reduce Motion.
    var successTrigger: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                        .symbolEffect(.bounce, value: reduceMotion ? 0 : successTrigger)
                }
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            Text(value)
                .font(size == .large ? .title2.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .moneyText(value: numericValue)
                .animation(AppTheme.Motion.resolved(AppTheme.Motion.normal, reduceMotion: reduceMotion), value: value)
                .leaseIdentifier(identifier)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, size == .large ? AppTheme.Spacing.md : AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.md)
        .background(tint.map { $0.opacity(0.08) } ?? AppTheme.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Symbol and title in one tight row (small captions beside amounts).
struct InlineIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}

extension LabelStyle where Self == InlineIconLabelStyle {
    static var inlineIcon: InlineIconLabelStyle { InlineIconLabelStyle() }
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
