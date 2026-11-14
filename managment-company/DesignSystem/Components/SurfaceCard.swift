import SwiftUI

/// The one card surface: a sheet of paper with a hairline edge. No shadow, no glass and no
/// gradient on content (glass belongs to the navigation layer).
struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = AppTheme.Spacing.lg
    @ViewBuilder var content: () -> Content

    private static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppTheme.Radius.surface, style: .continuous)
    }

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.Colors.background, in: Self.shape)
            .overlay(
                Self.shape.strokeBorder(AppTheme.Colors.border, lineWidth: 1)
            )
    }
}

#Preview("SurfaceCard") {
    ZStack {
        AppScreenBackground()
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Портфель").sectionLabelStyle()
                Text("380 000 ₸").font(AppTheme.Typography.moneyLarge)
            }
        }
        .padding()
    }
}
