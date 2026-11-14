import SwiftUI

/// Top-level section switch: text tabs on a hairline with a cobalt indicator that slides
/// between them (matched geometry). Used where the segments are whole sub-screens; in-card
/// filters keep the system segmented picker.
struct SlidingSegmentedControl<Item: Hashable & Identifiable>: View {
    let items: [Item]
    let title: (Item) -> String
    @Binding var selection: Item

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            ForEach(items) { item in
                let isSelected = item == selection
                Button {
                    guard !isSelected else { return }
                    AppHaptics.selection()
                    withAnimation(AppTheme.Motion.resolved(.snappy(duration: 0.3), reduceMotion: reduceMotion)) {
                        selection = item
                    }
                } label: {
                    Text(title(item))
                        .font(.system(.subheadline, weight: isSelected ? .semibold : .regular).width(.expanded))
                        .foregroundStyle(isSelected ? AppTheme.Colors.textPrimary : AppTheme.Colors.textSecondary)
                        .frame(minHeight: 44)
                        .overlay(alignment: .bottom) {
                            if isSelected {
                                Rectangle()
                                    .fill(AppTheme.Colors.accent)
                                    .frame(height: 2)
                                    .matchedGeometryEffect(id: "indicator", in: indicator)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.Colors.border).frame(height: 1)
        }
    }
}

#Preview("SlidingSegmentedControl") {
    struct Demo: View {
        enum Tab: String, CaseIterable, Identifiable { case a = "Платежи", b = "Операции", c = "Личные"; var id: String { rawValue } }
        @State private var tab: Tab = .a
        var body: some View {
            SlidingSegmentedControl(items: Tab.allCases, title: { $0.rawValue }, selection: $tab)
                .padding()
        }
    }
    return Demo()
}
