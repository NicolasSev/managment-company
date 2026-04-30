import SwiftUI

struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var isLoading: Bool = false
    var isDisabled: Bool = false
    var systemImage: String?
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.headline)
                    }
                    Text(title)
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.md)
            .background(
                LinearGradient(
                    colors: [
                        AppTheme.Colors.accent,
                        AppTheme.Colors.accentSecondary
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: AppTheme.Colors.accent.opacity(0.28), radius: 22, x: 0, y: 12)
        }
        .disabled(isLoading || isDisabled)
        .opacity(isLoading || isDisabled ? 0.72 : 1)
        .buttonStyle(.plain)
    }
}
