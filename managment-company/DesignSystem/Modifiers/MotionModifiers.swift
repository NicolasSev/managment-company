import SwiftUI

// MARK: - appearStagger

/// Fade-and-rise reveal for list items: opacity 0 → 1 and a 6 pt upward offset, delayed by
/// `AppTheme.Motion.staggerStep` per index (capped at `staggerLimit`). With Reduce Motion
/// there is no offset and no delay, only a short opacity change.
///
/// Drive `isVisible` from the first render of a page or segment, not from background
/// refetches (the list would "breathe" on every refresh).
struct AppearStaggerModifier: ViewModifier {
    let index: Int
    let isVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Vertical offset of the hidden state.
    static let hiddenOffset: CGFloat = 6

    static func offset(isVisible: Bool, reduceMotion: Bool) -> CGFloat {
        (isVisible || reduceMotion) ? 0 : hiddenOffset
    }

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: Self.offset(isVisible: isVisible, reduceMotion: reduceMotion))
            .animation(
                AppTheme.Motion.resolved(AppTheme.Motion.normal, reduceMotion: reduceMotion)
                    .delay(AppTheme.Motion.staggerDelay(index: index, reduceMotion: reduceMotion)),
                value: isVisible
            )
    }
}

// MARK: - shimmerPlaceholder

/// `redacted(.placeholder)` plus a moving highlight while `isLoading`. Under Reduce Motion
/// the placeholder stays static (no moving highlight).
struct ShimmerPlaceholderModifier: ViewModifier {
    let isLoading: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -0.6

    private var isShimmering: Bool { isLoading && !reduceMotion }

    func body(content: Content) -> some View {
        content
            .redacted(reason: isLoading ? .placeholder : [])
            .mask {
                if isShimmering {
                    LinearGradient(
                        colors: [.black.opacity(0.35), .black, .black.opacity(0.35)],
                        startPoint: UnitPoint(x: phase, y: 0.5),
                        endPoint: UnitPoint(x: phase + 0.6, y: 0.5)
                    )
                } else {
                    Color.black
                }
            }
            .allowsHitTesting(!isLoading)
            .onChange(of: isShimmering, initial: true) { _, active in
                if active {
                    phase = -0.6
                    withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                        phase = 1.0
                    }
                } else {
                    // `Transaction` is the app's money model, so no SwiftUI transaction here.
                    withAnimation(nil) { phase = -0.6 }
                }
            }
    }
}

// MARK: - moneyText

/// Money typography: monospaced digits so columns and tiles do not jitter, and a rolling
/// digit transition when the value changes inside an animation context
/// (`.animation(AppTheme.Motion.normal, value:)` or `withAnimation`). Reduce Motion
/// replaces the roll with a cross-fade.
struct MoneyTextModifier: ViewModifier {
    /// Numeric value for `numericText(value:)` so the digits roll in the right direction.
    var value: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .monospacedDigit()
            .contentTransition(transition)
    }

    private var transition: ContentTransition {
        if reduceMotion { return .opacity }
        if let value { return .numericText(value: value) }
        return .numericText()
    }
}

extension View {
    /// Fade-and-rise reveal, staggered by `index`. See `AppearStaggerModifier`.
    func appearStagger(index: Int, isVisible: Bool) -> some View {
        modifier(AppearStaggerModifier(index: index, isVisible: isVisible))
    }

    /// Placeholder skeleton with a moving highlight. See `ShimmerPlaceholderModifier`.
    func shimmerPlaceholder(_ isLoading: Bool) -> some View {
        modifier(ShimmerPlaceholderModifier(isLoading: isLoading))
    }

    /// Monospaced digits with a rolling number transition. See `MoneyTextModifier`.
    func moneyText(value: Double? = nil) -> some View {
        modifier(MoneyTextModifier(value: value))
    }
}

// MARK: - Previews

#Preview("appearStagger") {
    struct Demo: View {
        @State private var visible = false
        var body: some View {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                ForEach(0..<10, id: \.self) { index in
                    Text("Строка \(index + 1)")
                        .padding(AppTheme.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.Colors.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .appearStagger(index: index, isVisible: visible)
                }
                Button(visible ? "Скрыть" : "Показать") { visible.toggle() }
            }
            .padding()
            .onAppear { visible = true }
        }
    }
    return Demo()
}

#Preview("shimmerPlaceholder") {
    struct Demo: View {
        @State private var loading = true
        var body: some View {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Аренда").font(.headline)
                Text("380 000 ₸").font(.title2.weight(.semibold))
                Text("Период 15.10.26 - 14.11.26").font(.caption)
                Toggle("Загрузка", isOn: $loading)
            }
            .shimmerPlaceholder(loading)
            .padding()
        }
    }
    return Demo()
}

#Preview("moneyText") {
    struct Demo: View {
        @State private var amount = 205_000.0
        var body: some View {
            VStack(spacing: AppTheme.Spacing.md) {
                Text("\(Int(amount)) ₸")
                    .font(.largeTitle.weight(.semibold))
                    .moneyText(value: amount)
                    .animation(AppTheme.Motion.normal, value: amount)
                Button("Оплатить 180 000") { amount = max(0, amount - 180_000) }
                Button("Сбросить") { amount = 205_000 }
            }
            .padding()
        }
    }
    return Demo()
}
