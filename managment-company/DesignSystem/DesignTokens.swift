// Auto-generated from packages/design-tokens/tokens.json.
// Regenerate with: cd packages/design-tokens && npm run generate
// Do not edit manually.

import SwiftUI

enum DesignTokens {
  enum Colors {
    static let background = Color(hex: "#FFFFFF")
    static let backgroundSecondary = Color(hex: "#F8F9FA")
    static let textPrimary = Color(hex: "#111827")
    static let textSecondary = Color(hex: "#6B7280")
    static let textTertiary = Color(hex: "#9CA3AF")
    static let border = Color(hex: "#E5E7EB")
    static let accent = Color(hex: "#2563EB")
    static let accentSecondary = Color(hex: "#7C3AED")
    static let success = Color(hex: "#059669")
    static let danger = Color(hex: "#DC2626")
    static let warning = Color(hex: "#D97706")
    static let info = Color(hex: "#0891B2")
    static let income = Color(hex: "#059669")
    static let expense = Color(hex: "#DC2626")
    static let neutral = Color(hex: "#6B7280")
  }

  enum Spacing {
    static let cardPaddingMobile: CGFloat = 20
    static let cardPaddingDesktop: CGFloat = 24
    static let gapMobile: CGFloat = 16
    static let gapDesktop: CGFloat = 20
    static let scale0: CGFloat = 4
    static let scale1: CGFloat = 8
    static let scale2: CGFloat = 12
    static let scale3: CGFloat = 16
    static let scale4: CGFloat = 20
    static let scale5: CGFloat = 24
    static let scale6: CGFloat = 32
    static let scale7: CGFloat = 40
    static let scale8: CGFloat = 48
    static let scale9: CGFloat = 64
  }

  enum Radius {
    static let card: CGFloat = 12
    static let button: CGFloat = 8
    static let input: CGFloat = 6
    static let badge: CGFloat = 6
    static let modal: CGFloat = 16
  }

  enum Typography {
    static let largeNameSize: CGFloat = 34
    static let title2Size: CGFloat = 22
    static let headlineSize: CGFloat = 17
    static let bodySize: CGFloat = 17
    static let subheadlineSize: CGFloat = 15
    static let captionSize: CGFloat = 13
  }

  enum Animation {
    static let durationFast: Double = 0.15
    static let durationNormal: Double = 0.25
    static let durationSlow: Double = 0.4
    static let easingDefault = "ease-out"
    static let easingBounce = "cubic-bezier(0.34, 1.56, 0.64, 1)"
  }
}
