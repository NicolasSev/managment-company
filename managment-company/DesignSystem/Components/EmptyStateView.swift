import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    let actionName: String
    let action: () -> Void
    var icon: String = "building.2"
    
    var body: some View {
        VStack {
            SurfaceCard {
                VStack(spacing: AppTheme.Spacing.lg) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.Colors.accent.opacity(0.12))
                            .frame(width: 88, height: 88)

                        Image(systemName: icon)
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.accent)
                    }

                    VStack(spacing: AppTheme.Spacing.sm) {
                        Text(title)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppTheme.Colors.textPrimary)

                        Text(message)
                            .font(.body)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }

                    PrimaryButton(title: actionName, action: action)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, AppTheme.Spacing.xl)
    }
}
