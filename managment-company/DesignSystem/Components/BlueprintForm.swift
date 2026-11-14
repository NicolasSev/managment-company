import SwiftUI

/// `Form` on the app's ground: the system grouped background is hidden, rows sit on paper
/// with the hairline separator, so sheets match the screens in light and at night.
struct BlueprintForm<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        Form {
            Group(content: content)
                .listRowBackground(AppTheme.Colors.background)
                .listRowSeparatorTint(AppTheme.Colors.border)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.Colors.ground.ignoresSafeArea())
        .tint(AppTheme.Colors.accent)
    }
}

/// `List` on the app's ground. Same treatment as `BlueprintForm`.
struct BlueprintList<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        List {
            Group(content: content)
                .listRowBackground(AppTheme.Colors.background)
                .listRowSeparatorTint(AppTheme.Colors.border)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.Colors.ground.ignoresSafeArea())
        .tint(AppTheme.Colors.accent)
    }
}

#Preview("BlueprintForm") {
    BlueprintForm {
        Section("Платёж") {
            Text("250 000 ₸")
            Toggle("Напоминание", isOn: .constant(true))
        }
    }
}
