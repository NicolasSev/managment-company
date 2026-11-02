import SwiftUI

/// Quiet, flat screen background: a faint vertical shift between the two surface tokens.
/// No blurred shapes (they show through the translucent navigation bar and muddy it).
struct AppScreenBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                AppTheme.Colors.background,
                AppTheme.Colors.backgroundSecondary
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
