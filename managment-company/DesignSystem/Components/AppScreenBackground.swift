import SwiftUI

struct AppScreenBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AppTheme.Colors.background,
                    AppTheme.Colors.backgroundSecondary
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(AppTheme.Colors.accent.opacity(0.14))
                .frame(width: 280, height: 280)
                .blur(radius: 40)
                .offset(x: -130, y: -260)

            Circle()
                .fill(AppTheme.Colors.info.opacity(0.12))
                .frame(width: 240, height: 240)
                .blur(radius: 50)
                .offset(x: 160, y: -220)
        }
        .ignoresSafeArea()
    }
}
