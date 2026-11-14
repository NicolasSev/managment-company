import SwiftUI

/// Figure tile: drafting label, one large monospaced-digit value, optional note.
/// `color` tints only the small symbol; the value stays ink so the tile reads as data.
struct KPICard: View {
    let title: String
    let value: String
    let icon: String
    var color: Color = AppTheme.Colors.accent
    var subtitle: String?

    var body: some View {
        SurfaceCard(padding: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                    Text(title)
                        .sectionLabelStyle()
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)

                    Image(systemName: icon)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(color)
                        .accessibilityHidden(true)
                }

                Text(value)
                    .font(AppTheme.Typography.moneyLarge)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())

                if let subtitle {
                    Rectangle()
                        .fill(AppTheme.Colors.border)
                        .frame(height: 1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("KPICard") {
    HStack(alignment: .top) {
        KPICard(title: "Полученный доход", value: "243 000 ₸", icon: "arrow.down.left", subtitle: "Депозиты: 0 ₸")
        KPICard(title: "Расходы", value: "12 400 ₸", icon: "arrow.up.right", color: AppTheme.Colors.textSecondary)
    }
    .padding()
    .background(AppTheme.Colors.ground)
}
