import SwiftUI

// Form controls of the move-in wizard. Flat (D2): sentence-case labels, a hairline border, no
// shadow, no uppercase and no tracking. The shared `AppTextField` keeps its older look and is
// not used here.

/// Label above a control, with an optional note under it (badge text, error).
struct SettleFieldFrame<Content: View>: View {
    let title: String
    var note: String?
    var noteTone: StatusTone = .warning
    var identifier: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppTheme.Colors.textSecondary)
            content()
            if let note {
                Label(note, systemImage: noteTone.systemImage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(noteTone.color)
                    .labelStyle(.titleAndIcon)
                    .accessibilityIdentifier(identifier.map { "\($0).note" } ?? "")
            }
        }
    }
}

extension View {
    /// The input surface every text control of the wizard shares.
    func settleInputSurface(highlighted: Bool = false) -> some View {
        self
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, 12)
            .background(AppTheme.Colors.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(highlighted ? AppTheme.Colors.danger : AppTheme.Colors.border, lineWidth: highlighted ? 1.5 : 1)
            )
    }
}

struct SettleTextField: View {
    let title: String
    @Binding var text: String
    var placeholder = ""
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences
    var identifier: String
    var badge: SettleFieldBadge = .none
    var highlighted = false
    var footnote: String?
    var axis: Axis = .horizontal

    var body: some View {
        SettleFieldFrame(
            title: title,
            note: footnote ?? badge.text,
            noteTone: footnote != nil ? .danger : (badge == .missing ? .danger : .warning),
            identifier: identifier
        ) {
            TextField(placeholder.isEmpty ? title : placeholder, text: $text, axis: axis)
                .lineLimit(axis == .vertical ? 1...4 : 1...1)
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled(keyboard != .default)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .tint(AppTheme.Colors.accent)
                .settleInputSurface(highlighted: highlighted || badge == .missing)
                .accessibilityIdentifier(identifier)
        }
    }
}

/// A date that may be empty: «Указать» sets it, the picker edits it, «Очистить» removes it.
/// `value` is `YYYY-MM-DD` or empty.
struct SettleOptionalDateField: View {
    let title: String
    @Binding var value: String
    var identifier: String
    var badge: SettleFieldBadge = .none
    var highlighted = false

    private var dateBinding: Binding<Date> {
        Binding(
            get: { LeaseDay.pickerDate(value) ?? Date() },
            set: { value = LeaseDay.string(fromPicker: $0) }
        )
    }

    var body: some View {
        SettleFieldFrame(
            title: title,
            note: badge.text,
            noteTone: badge == .missing ? .danger : .warning,
            identifier: identifier
        ) {
            HStack {
                if value.isEmpty {
                    Text("Не указана")
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                    Spacer()
                    Button("Указать") {
                        value = LeaseDay.string(fromPicker: Date())
                    }
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("\(identifier).set")
                } else {
                    DatePicker(title, selection: dateBinding, in: ...Date(), displayedComponents: .date)
                        .labelsHidden()
                        .environment(\.locale, AppFormatting.displayLocale)
                        .accessibilityIdentifier(identifier)
                    Spacer()
                    Button("Очистить") { value = "" }
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .accessibilityIdentifier("\(identifier).clear")
                }
            }
            .settleInputSurface(highlighted: highlighted || badge == .missing)
        }
    }
}

/// One line of a summary: label left, value right.
struct SettleSummaryRow: View {
    let title: String
    let value: String
    var identifier: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Spacer(minLength: AppTheme.Spacing.md)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(identifier ?? "")
        }
    }
}

/// A quiet message block: icon, text, tone. Replaces the filled colour boxes.
struct SettleNotice: View {
    let text: String
    var tone: StatusTone = .warning
    var systemImage: String?
    var identifier: String

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            Image(systemName: systemImage ?? tone.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tone.color)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AppTheme.Spacing.md)
        .background(tone.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// Outlined action: icon over a short title (the scan / photo / file choice).
struct SettleSourceButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3)
            Text(title)
                .font(.footnote.weight(.medium))
        }
        .foregroundStyle(AppTheme.Colors.accent)
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.md)
        .background(AppTheme.Colors.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.Colors.accent.opacity(0.25), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// A selectable row (property, existing tenant): checkmark on the chosen one.
struct SettleChoiceRow<Content: View>: View {
    let isSelected: Bool
    let identifier: String
    let action: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AppTheme.Colors.accent : AppTheme.Colors.border)
                    .accessibilityHidden(true)
            }
            .padding(AppTheme.Spacing.md)
            .background(AppTheme.Colors.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? AppTheme.Colors.accent : AppTheme.Colors.border, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}
