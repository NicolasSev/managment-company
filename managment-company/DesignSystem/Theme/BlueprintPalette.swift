import SwiftUI
import UIKit

/// "Blueprint" palette: paper, ink and one chromatic accent (cobalt), with a night variant.
/// Every colour is dynamic, so a view that uses `AppTheme.Colors` is correct in light and dark.
///
/// The generated `DesignTokens.Colors` are still light-only; `packages/design-tokens/tokens.json`
/// has to be reconciled with these values (the web redesign uses the same hexes).
enum BlueprintPalette {
    /// Screen ground behind cards.
    static let ground = Color(light: "#F4F6F8", dark: "#070B14")
    /// Paper: cards, sheets, raised surfaces.
    static let paper = Color(light: "#FFFFFF", dark: "#0E1524")
    /// Inset blocks inside a card (facts, chips, fields).
    static let inset = Color(light: "#F4F6F8", dark: "#162038")

    static let ink = Color(light: "#0B0F14", dark: "#EAF0FF")
    static let inkMuted = Color(light: "#5B6672", dark: "#9BA8C9")
    static let inkFaint = Color(light: "#6F7A86", dark: "#7C8AB0")

    /// The only chromatic accent: line art, selection, data ink, received money.
    static let cobalt = Color(light: "#1F4FFF", dark: "#5B7CFF")
    /// Text and symbols on a cobalt fill (white on day cobalt, night ink on night cobalt).
    static let onCobalt = Color(light: "#FFFFFF", dark: "#070B14")
    /// Darker cobalt for a second data series.
    static let cobaltDeep = Color(light: "#0B2A99", dark: "#A9BBFF")

    static let hairline = Color(light: "#DDE2E8", dark: "#1E2A44")

    /// Reserved red: overdue and destructive only.
    static let overdue = Color(light: "#D4372C", dark: "#FF6B5E")
    static let amber = Color(light: "#B7791F", dark: "#E0A84A")
}

extension Color {
    /// Dynamic colour from two hex strings, resolved by the interface style.
    init(light: String, dark: String) {
        let lightColor = UIColor(Color(hex: light))
        let darkColor = UIColor(Color(hex: dark))
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? darkColor : lightColor
        })
    }
}
