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

    /// Motion tokens. Durations mirror `animation.duration*` in `packages/design-tokens`
    /// (150 / 250 / 400 ms); SwiftUI uses its own curves, so the CSS easing strings of
    /// `DesignTokens.Animation` are intentionally not mapped.
    ///
    /// Every use site must honour `accessibilityReduceMotion`: pass the animation through
    /// `Motion.resolved(_:reduceMotion:)` or use the modifiers in `MotionModifiers.swift`.
    enum Motion {
        /// Press, badge colour, small toggles.
        static let fast: Animation = .easeOut(duration: 0.15)
        /// Appearing rows and cards, number changes, row removal.
        static let normal: Animation = .smooth(duration: 0.25)
        /// Sheets, zoom transitions, whole-list reveals.
        static let slow: Animation = .snappy(duration: 0.4)
        /// Success moments only (paid badge, check mark). Never for layout.
        static let success: Animation = .bouncy(duration: 0.35)

        /// Delay between consecutive items of a staggered reveal, seconds.
        static let staggerStep: Double = 0.03
        /// Items past this index appear without extra delay.
        static let staggerLimit = 8

        /// Replacement for spring and moving animations when Reduce Motion is on.
        static let reduced: Animation = .easeInOut(duration: 0.2)

        /// `animation` normally, a short cross-fade timing under Reduce Motion.
        static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation {
            reduceMotion ? reduced : animation
        }

        /// Delay of the item at `index` in a staggered reveal (capped, none under Reduce Motion).
        static func staggerDelay(index: Int, reduceMotion: Bool = false) -> Double {
            guard !reduceMotion else { return 0 }
            return Double(max(0, min(index, staggerLimit))) * staggerStep
        }
    }
}
