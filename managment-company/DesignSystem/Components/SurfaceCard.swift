import SwiftUI

/// The one card surface: solid fill, hairline border, a single faint shadow.
/// No glass and no gradient on content (glass belongs to the navigation layer).
struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = AppTheme.Spacing.lg
    @ViewBuilder var content: () -> Content

    private static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
    }

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.Colors.background, in: Self.shape)
            .overlay(
                Self.shape.stroke(AppTheme.Colors.border.opacity(0.6), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}
