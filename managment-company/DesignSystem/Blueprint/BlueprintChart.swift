import Charts
import SwiftUI

/// Shared look of Swift Charts in the app: hairline grid, small muted axis labels, cobalt
/// data ink. Marks animate in through `ChartDrawIn`.
extension View {
    /// Axes in the drafting style: hairline horizontal grid, compact value labels.
    func blueprintChartAxes(xLabelStride: Int = 1, valueLabel: @escaping (Double) -> String) -> some View {
        self
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(AppTheme.Colors.border)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(valueLabel(number))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(AppTheme.Colors.textTertiary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisTick(length: 4, stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(AppTheme.Colors.border)
                    if value.index % max(1, xLabelStride) == 0 {
                        AxisValueLabel()
                            .font(.caption2)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
            }
    }
}

/// Drives a 0 → 1 draw-in factor for chart values on first appearance (instant under
/// Reduce Motion). Multiply mark values by `factor`.
struct ChartDrawIn<Content: View>: View {
    @ViewBuilder var content: (_ factor: Double) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDrawn = false

    var body: some View {
        content((isDrawn || reduceMotion) ? 1 : 0)
            .animation(AppTheme.Motion.resolved(AppTheme.Motion.draw, reduceMotion: reduceMotion), value: isDrawn)
            .onAppear { isDrawn = true }
    }
}

enum BlueprintChartFormat {
    /// Compact axis value: 1 250 000 → "1,3 млн", 243 000 → "243 тыс".
    static func compact(_ value: Double) -> String {
        let magnitude = abs(value)
        let sign = value < 0 ? "−" : ""
        if magnitude >= 1_000_000 {
            return sign + trimmed(magnitude / 1_000_000) + " млн"
        }
        if magnitude >= 1_000 {
            return sign + trimmed(magnitude / 1_000) + " тыс"
        }
        return sign + trimmed(magnitude)
    }

    private static func trimmed(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ",")
    }
}

/// Thin horizontal data bar for table rows: width is `|value| / maximum`. Inflow is cobalt,
/// a plain minus is muted ink. Draws in from the left on first appearance.
struct ProportionBar: View {
    let value: Double
    let maximum: Double
    var height: CGFloat = 4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDrawn = false

    private var fraction: CGFloat {
        guard maximum > 0, value.isFinite else { return 0 }
        return CGFloat(min(1, abs(value) / maximum))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(AppTheme.Colors.border.opacity(0.7))
                Rectangle()
                    .fill(value >= 0 ? AppTheme.Colors.accent : AppTheme.Colors.textTertiary)
                    .frame(width: proxy.size.width * fraction * ((isDrawn || reduceMotion) ? 1 : 0))
            }
        }
        .frame(height: height)
        .animation(AppTheme.Motion.resolved(AppTheme.Motion.draw, reduceMotion: reduceMotion), value: isDrawn)
        .animation(AppTheme.Motion.resolved(AppTheme.Motion.normal, reduceMotion: reduceMotion), value: fraction)
        .onAppear { isDrawn = true }
        .accessibilityHidden(true)
    }
}
