import SwiftUI

/// Flat screen ground with a faint drafting grid behind the masthead that fades out before
/// the content starts. No blurred shapes (they show through the translucent navigation bar).
struct AppScreenBackground: View {
    var body: some View {
        AppTheme.Colors.ground
            .overlay(alignment: .top) {
                BlueprintHeroBackground()
                    .frame(height: 300)
            }
            .ignoresSafeArea()
    }
}

#Preview("AppScreenBackground") {
    AppScreenBackground()
}
