import SwiftUI

/// The portfolio as a small isometric street: one building per property on a shared ground
/// line with drafting ticks. Buildings rise one after another on first appearance (the one
/// orchestrated moment of a hero area); under Reduce Motion they are simply there.
struct IsometricStreet: View {
    let buildings: [IsometricBuildingSpec]
    /// Height of the tallest possible building.
    var height: CGFloat = 96
    /// Buildings past this count are summarised as "+N".
    var limit: Int = 7

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBuilt = false

    /// As tall as the tallest building, so a low street leaves no empty band above it.
    private var rowHeight: CGFloat {
        buildings.prefix(limit).map { Self.height(of: $0, height: height) }.max() ?? height * 0.5
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The widest row that fits: buildings that do not fit are summarised as "+N".
            ViewThatFits(in: .horizontal) {
                ForEach(candidateCounts, id: \.self) { count in
                    row(count: count)
                }
            }
            .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .bottomLeading)

            DimensionRule(ticks: max(2, min(buildings.count, limit) + 1))
                .padding(.top, 4)
        }
        .onAppear { isBuilt = true }
        .accessibilityHidden(true)
    }

    private var candidateCounts: [Int] {
        let top = min(buildings.count, limit)
        return Array(stride(from: top, through: min(top, 2), by: -1))
    }

    private func row(count: Int) -> some View {
        let overflow = buildings.count - count
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(buildings.prefix(count).enumerated()), id: \.offset) { index, spec in
                IsometricBuilding(spec: spec, progress: (isBuilt || reduceMotion) ? 1 : 0)
                    .frame(width: Self.width(of: spec, height: height), height: Self.height(of: spec, height: height))
                    .animation(
                        AppTheme.Motion.build.delay(AppTheme.Motion.buildDelay(index: index, reduceMotion: reduceMotion)),
                        value: isBuilt
                    )
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(AppTheme.Typography.label)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize()
                    .padding(.bottom, 6)
            }
        }
        .frame(height: rowHeight, alignment: .bottom)
    }

    /// Lower kinds get a shorter frame so that every glyph is drawn at a comparable scale.
    static func height(of spec: IsometricBuildingSpec, height: CGFloat) -> CGFloat {
        switch spec.kind {
        case .tower: return height * (0.5 + 0.5 * CGFloat(max(3, min(spec.floors, 9))) / 9)
        case .house: return height * 0.62
        case .commercial: return height * 0.52
        case .land: return height * 0.36
        case .block: return height * 0.5
        }
    }

    static func width(of spec: IsometricBuildingSpec, height: CGFloat) -> CGFloat {
        switch spec.kind {
        case .tower, .block: return height * 0.46
        case .house: return height * 0.56
        case .commercial: return height * 0.72
        case .land: return height * 0.72
        }
    }
}

/// Drafting dimension line: a hairline with end and intermediate ticks.
struct DimensionRule: View {
    var ticks: Int = 2
    var color: Color = AppTheme.Colors.border

    var body: some View {
        Canvas { context, size in
            var path = Path()
            let y = size.height / 2
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            let count = max(2, ticks)
            for index in 0..<count {
                let x = size.width * CGFloat(index) / CGFloat(count - 1)
                let clamped = min(max(x, 0.5), size.width - 0.5)
                path.move(to: CGPoint(x: clamped, y: 0))
                path.addLine(to: CGPoint(x: clamped, y: size.height))
            }
            context.stroke(path, with: .color(color), lineWidth: 1)
        }
        .frame(height: 7)
        .accessibilityHidden(true)
    }
}

#Preview("IsometricStreet") {
    IsometricStreet(buildings: [
        .init(kind: .tower, floors: 7, unitFloor: 4, windows: 2, isOccupied: true),
        .init(kind: .house, isOccupied: false),
        .init(kind: .tower, floors: 5, unitFloor: nil, isOccupied: true),
        .init(kind: .commercial, isOccupied: true),
        .init(kind: .land, isOccupied: false),
    ])
    .padding()
    .background(AppTheme.Colors.background)
}
