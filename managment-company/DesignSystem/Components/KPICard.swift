import SwiftUI

struct KPICard: View {
    let title: String
    let value: String
    let icon: String
    var color: Color = AppTheme.Colors.accent
    var subtitle: String?
    
    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack {
                    Text(title.uppercased())
                        .font(.caption)
                        .fontWeight(.semibold)
                        .tracking(1.2)
                        .foregroundStyle(AppTheme.Colors.textSecondary)

                    Spacer()

                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(color.opacity(0.12))
                            .frame(width: 44, height: 44)

                        Image(systemName: icon)
                            .font(.headline)
                            .foregroundStyle(color)
                    }
                }

                Text(value)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineSpacing(2)
                }
            }
        }
    }
}
