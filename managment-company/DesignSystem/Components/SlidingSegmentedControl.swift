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
    /// What the control shows. It moves first; the binding follows once the indicator has
    /// travelled, so a heavy content switch does not swallow the slide.
    @State private var displayed: Item?

    private var current: Item { displayed ?? selection }

    var body: some View {
        // Scrolls sideways when the labels do not fit (large text), instead of widening the screen.
        ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: AppTheme.Spacing.lg) {
            ForEach(items) { item in
                let isSelected = item == current
                Button {
                    guard !isSelected else { return }
                    AppHaptics.selection()
                    select(item)
                } label: {
                    Text(title(item))
                        .font(.system(.subheadline, weight: isSelected ? .semibold : .regular).width(.expanded))
                        .foregroundStyle(isSelected ? AppTheme.Colors.textPrimary : AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
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
        }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.Colors.border).frame(height: 1)
        }
        .onChange(of: selection) { _, new in
            // Selection changed from outside (deep link): follow it.
            if displayed != new {
                withAnimation(AppTheme.Motion.resolved(.snappy(duration: 0.28), reduceMotion: reduceMotion)) {
                    displayed = new
                }
            }
        }
    }

    private func select(_ item: Item) {
        guard !reduceMotion else {
            displayed = item
            selection = item
            return
        }
        withAnimation(.snappy(duration: 0.28)) { displayed = item }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard displayed == item else { return }
            withAnimation(AppTheme.Motion.normal) { selection = item }
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
