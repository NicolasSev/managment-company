import SwiftUI

/// The "paid" moment: an empty ring morphs into a filled check, with a success haptic.
/// Use it where a payment (or a task) flips to done; `isOn` drives the morph.
struct PaidCheckMark: View {
    let isOn: Bool
    var size: CGFloat = 24
    /// Off when the caller plays its own haptic on the confirmed result.
    var haptic: Bool = true
    var onTint: Color = AppTheme.Colors.accent
    var offTint: Color = AppTheme.Colors.textTertiary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(isOn ? onTint : offTint)
            .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace.downUp))
            .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : isOn)
            .animation(AppTheme.Motion.resolved(AppTheme.Motion.success, reduceMotion: reduceMotion), value: isOn)
            .sensoryFeedback(.success, trigger: isOn) { _, new in new && haptic }
            .accessibilityHidden(true)
    }
}

#Preview("PaidCheckMark") {
    struct Demo: View {
        @State private var paid = false
        var body: some View {
            Button { paid.toggle() } label: {
                HStack { PaidCheckMark(isOn: paid); Text(paid ? "Оплачено" : "Отметить оплату") }
            }
            .padding()
        }
    }
    return Demo()
}
