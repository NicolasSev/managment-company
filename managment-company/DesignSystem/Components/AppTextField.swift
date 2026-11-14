import SwiftUI

struct AppTextField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences
    /// Accessibility identifier of the text field itself (not of the title and container).
    var identifier: String?
    /// Masks the input (passwords).
    var isSecure: Bool = false
    var contentType: UITextContentType?

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs + 2) {
            Text(title)
                .sectionLabelStyle()
            field
                .textFieldStyle(.plain)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .tint(AppTheme.Colors.accent)
                .textContentType(contentType)
                .focused($isFocused)
                .optionalIdentifier(identifier)
                .appFieldChrome(isFocused: isFocused)
        }
    }

    @ViewBuilder
    private var field: some View {
        if isSecure {
            SecureField(placeholder.isEmpty ? title : placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } else {
            TextField(placeholder.isEmpty ? title : placeholder, text: $text)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled(keyboardType == .emailAddress)
        }
    }
}

/// Chrome of every input: inset fill, hairline edge that turns cobalt on focus, 48 pt tall.
struct AppFieldChrome: ViewModifier {
    var isFocused: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppTheme.Radius.inner, style: .continuous)
        content
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(minHeight: 48)
            .background(AppTheme.Colors.backgroundSecondary, in: shape)
            .overlay(
                shape.strokeBorder(
                    isFocused ? AppTheme.Colors.accent : AppTheme.Colors.border,
                    lineWidth: isFocused ? 1.5 : 1
                )
            )
            .animation(AppTheme.Motion.resolved(AppTheme.Motion.fast, reduceMotion: reduceMotion), value: isFocused)
    }
}

extension View {
    /// Field chrome shared by `AppTextField` and hand-built inputs.
    func appFieldChrome(isFocused: Bool = false) -> some View {
        modifier(AppFieldChrome(isFocused: isFocused))
    }
}

private extension View {
    @ViewBuilder
    func optionalIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}

#Preview("AppTextField") {
    struct Demo: View {
        @State private var email = ""
        @State private var password = "secret"
        var body: some View {
            VStack(spacing: 16) {
                AppTextField(title: "Email", text: $email, placeholder: "name@example.com")
                AppTextField(title: "Пароль", text: $password, isSecure: true)
            }
            .padding()
        }
    }
    return Demo()
}
