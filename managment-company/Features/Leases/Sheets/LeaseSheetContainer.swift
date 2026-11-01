import SwiftUI

/// Shared chrome of the lease sheets: navigation bar with cancel and confirm, the form, and
/// the error footer. Identifiers: `lease.detail.sheet.<name>`, `.cancel`, `.submit`, `.error`.
struct LeaseSheetContainer<Content: View>: View {
    let title: String
    /// Sheet name inside `lease.detail.sheet.`.
    let name: String
    let submitTitle: String
    var canSubmit: Bool = true
    var isSubmitting: Bool = false
    var errorMessage: String?
    var submitRole: ButtonRole?
    let onCancel: () -> Void
    let onSubmit: () -> Void
    @ViewBuilder var content: () -> Content

    private var prefix: String { "lease.detail.sheet.\(name)" }

    var body: some View {
        NavigationStack {
            Form {
                content()

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(AppTheme.Colors.danger)
                            .accessibilityIdentifier("\(prefix).error")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", action: onCancel)
                        .accessibilityIdentifier("\(prefix).cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button(submitTitle, role: submitRole, action: onSubmit)
                            .disabled(!canSubmit)
                            .accessibilityIdentifier("\(prefix).submit")
                    }
                }
            }
        }
        .accessibilityIdentifier(prefix)
        .interactiveDismissDisabled(isSubmitting)
    }
}

/// `Date` <-> wire day binding helper for the pickers.
func leaseDayBinding(_ day: Binding<String>) -> Binding<Date> {
    Binding<Date>(
        get: { LeaseDay.pickerDate(day.wrappedValue) ?? Date() },
        set: { day.wrappedValue = LeaseDay.string(fromPicker: $0) }
    )
}

/// Text field row for a sheet form with a stable identifier.
struct LeaseSheetField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboard: UIKeyboardType = .default
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            TextField(placeholder.isEmpty ? title : placeholder, text: $text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .default ? .sentences : .never)
                .accessibilityIdentifier(identifier)
        }
    }
}
