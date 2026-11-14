import SwiftUI

/// The one primary action of a screen or a card: a solid cobalt bar, 50 pt tall.
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
                        .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.Colors.onAccent))
                } else {
                    Text(title)
                        .font(.body.weight(.semibold))
                    if let systemImage {
                        Spacer(minLength: AppTheme.Spacing.sm)
                        Image(systemName: systemImage)
                            .font(.body.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: systemImage == nil || isLoading ? .center : .leading)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .frame(minHeight: 50)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(isLoading || isDisabled)
    }
}

/// Solid accent fill with a quick press response; dims when disabled.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(AppTheme.Colors.onAccent)
            .background(
                AppTheme.Colors.accent,
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.86 : 1) : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(AppTheme.Motion.fast, value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
    }
}

/// Compact secondary action inside a row or a card: hairline outline, accent label, 44 pt
/// touch height.
struct QuietActionButtonStyle: ButtonStyle {
    var tint: Color = AppTheme.Colors.accent
    /// Stretch to the available width (default) or hug the label.
    var fills: Bool = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(tint)
            .padding(.horizontal, fills ? AppTheme.Spacing.sm : 12)
            .frame(maxWidth: fills ? .infinity : nil, minHeight: 38)
            .background(
                tint.opacity(configuration.isPressed ? 0.16 : 0.07),
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.inner, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.inner, style: .continuous)
                    .strokeBorder(tint.opacity(0.28), lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
            .padding(.vertical, 3)
    }
}

#Preview("Buttons") {
    VStack(spacing: 16) {
        PrimaryButton(title: "Войти", action: {}, systemImage: "arrow.right")
        PrimaryButton(title: "Сохранить", action: {})
        PrimaryButton(title: "Сохранить", action: {}, isDisabled: true)
        PrimaryButton(title: "Сохраняем", action: {}, isLoading: true)
        HStack {
            Button("Изменить") {}.buttonStyle(QuietActionButtonStyle())
            Button("Отменить") {}.buttonStyle(QuietActionButtonStyle(tint: AppTheme.Colors.danger))
        }
    }
    .padding()
}
