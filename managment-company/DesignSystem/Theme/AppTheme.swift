import SwiftUI

/// AppTheme provides semantic access to design tokens.
/// Uses DesignTokens (from packages/design-tokens) as the source of truth.
/// Mapping: AppTheme → DesignTokens for consistency across iOS and web.
enum AppTheme {
    enum Colors {
        static let background = DesignTokens.Colors.background
        static let backgroundSecondary = DesignTokens.Colors.backgroundSecondary
        static let textPrimary = DesignTokens.Colors.textPrimary
        static let textSecondary = DesignTokens.Colors.textSecondary
        static let textTertiary = DesignTokens.Colors.textTertiary
        static let accent = DesignTokens.Colors.accent
        static let accentSecondary = DesignTokens.Colors.accentSecondary
        static let success = DesignTokens.Colors.success
        static let danger = DesignTokens.Colors.danger
        static let warning = DesignTokens.Colors.warning
        static let info = DesignTokens.Colors.info
        static let border = DesignTokens.Colors.border

        // Semantic aliases (income→success, expense→danger)
        static let income = DesignTokens.Colors.income
        static let expense = DesignTokens.Colors.expense
    }

    enum Spacing {
        static let xs: CGFloat = DesignTokens.Spacing.scale0
        static let sm: CGFloat = DesignTokens.Spacing.scale1
        static let md: CGFloat = DesignTokens.Spacing.scale3
        static let lg: CGFloat = DesignTokens.Spacing.scale5
        static let xl: CGFloat = DesignTokens.Spacing.scale6
        static let xxl: CGFloat = DesignTokens.Spacing.scale7
    }

    enum Radius {
        static let card: CGFloat = DesignTokens.Radius.card
        static let button: CGFloat = DesignTokens.Radius.button
        static let input: CGFloat = DesignTokens.Radius.input
    }
}
