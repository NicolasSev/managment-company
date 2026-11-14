import SwiftUI

/// AppTheme provides semantic access to the design system.
/// Spacing, radius and durations come from `DesignTokens` (packages/design-tokens);
/// colours come from `BlueprintPalette`, which adds the dark variant the tokens lack.
enum AppTheme {
    /// Semantic colours. Values come from `BlueprintPalette` (dynamic light/dark), not from
    /// the generated light-only `DesignTokens.Colors`.
    enum Colors {
        /// Card and sheet surface ("paper").
        static let background = BlueprintPalette.paper
        /// Inset block inside a card.
        static let backgroundSecondary = BlueprintPalette.inset
        /// Screen ground behind cards.
        static let ground = BlueprintPalette.ground
        static let textPrimary = BlueprintPalette.ink
        static let textSecondary = BlueprintPalette.inkMuted
        static let textTertiary = BlueprintPalette.inkFaint
        static let accent = BlueprintPalette.cobalt
        static let accentSecondary = BlueprintPalette.cobaltDeep
        /// Foreground on an accent fill.
        static let onAccent = BlueprintPalette.onCobalt
        /// Positive state and received money are cobalt: there is no second "good" colour.
        static let success = BlueprintPalette.cobalt
        /// Reserved red: overdue, destructive, errors.
        static let danger = BlueprintPalette.overdue
        static let warning = BlueprintPalette.amber
        static let info = BlueprintPalette.cobalt
        static let border = BlueprintPalette.hairline

        static let income = BlueprintPalette.cobalt
        /// A plain expense is neutral ink; red stays reserved for attention states.
        static let expense = BlueprintPalette.ink

        /// Colour of a signed money amount: cobalt for an inflow, ink for a plain minus.
        static func amount(_ value: Double) -> Color {
            value > 0 ? income : expense
        }
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
        /// Card surface (`SurfaceCard`).
        static let surface: CGFloat = 14
        /// Inset block, field, chip inside a card.
        static let inner: CGFloat = 10
        /// Primary controls.
        static let control: CGFloat = 12
        /// Stamps and badges.
        static let stamp: CGFloat = 5
    }

    /// Type helpers. System San Francisco only; every style is built on a text style, so
    /// Dynamic Type keeps working.
    enum Typography {
        /// Masthead: large, light, expanded.
        static let masthead: Font = .system(.largeTitle, weight: .light).width(.expanded)
        /// Second-level display line.
        static let display: Font = .system(.title2, weight: .regular).width(.expanded)
        /// Drafting label above a block: small, expanded, upper-case (see `sectionLabelStyle`).
        static let label: Font = .system(.caption2, weight: .semibold).width(.expanded)
        /// Large money figure.
        static let moneyLarge: Font = .system(.title, weight: .medium).monospacedDigit()
        /// Money figure in a tile or a row total.
        static let money: Font = .system(.title3, weight: .semibold).monospacedDigit()
        /// Money in a list row.
        static let moneyRow: Font = .system(.subheadline, weight: .semibold).monospacedDigit()
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

        /// One building of the isometric street rising on first appearance.
        static let build: Animation = .snappy(duration: 0.7, extraBounce: 0.04)
        /// Delay between buildings of the street, seconds.
        static let buildStep: Double = 0.09
        /// Chart marks drawing in.
        static let draw: Animation = .easeOut(duration: 0.9)

        /// Delay of building `index` in the street build-up (capped, none under Reduce Motion).
        static func buildDelay(index: Int, reduceMotion: Bool = false) -> Double {
            guard !reduceMotion else { return 0 }
            return Double(max(0, min(index, staggerLimit))) * buildStep
        }

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
