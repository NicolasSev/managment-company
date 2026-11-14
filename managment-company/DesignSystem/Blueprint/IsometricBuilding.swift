import SwiftUI

/// What an isometric building glyph draws. Built from real attributes only: when the floor or
/// the room count is unknown the glyph shows the whole volume instead of inventing a unit.
struct IsometricBuildingSpec: Hashable {
    enum Kind: Hashable {
        /// Multi-storey block (apartment).
        case tower
        /// Low volume with a pitched roof.
        case house
        /// Wide low volume with a storefront band.
        case commercial
        /// Flat plot with corner stakes.
        case land
        /// Plain volume for everything else.
        case block
    }

    var kind: Kind = .tower
    /// Storeys drawn (towers 4...9, others fixed by kind).
    var floors: Int = 5
    /// 1-based storey of the unit; `nil` marks the whole volume.
    var unitFloor: Int?
    /// Window ticks on the unit band, 0...4 (rooms).
    var windows: Int = 0
    /// Occupied units are filled cobalt, vacant ones only outlined.
    var isOccupied: Bool = true
    /// Archived / inactive: drawn in faint ink.
    var isMuted: Bool = false
}

/// Isometric line drawing of one building, generated in code.
///
/// `progress` (0...1) is animatable: the volume rises storey by storey, which is the
/// "build-up" moment of the portfolio street. Decorative — hidden from accessibility.
struct IsometricBuilding: View, Animatable {
    var spec: IsometricBuildingSpec
    var progress: Double = 1

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            IsometricRenderer(spec: spec, progress: max(0, min(1, progress)), size: size)
                .draw(in: &context)
        }
        .accessibilityHidden(true)
    }
}

/// Projects and draws the glyph. Model units: x runs down-right, y down-left, z up.
private struct IsometricRenderer {
    let spec: IsometricBuildingSpec
    let progress: Double
    let size: CGSize

    private static let cos30: CGFloat = 0.866
    private static let sin30: CGFloat = 0.5

    private var line: Color { spec.isMuted ? AppTheme.Colors.textTertiary : AppTheme.Colors.accent }
    private var fillStrong: Color { line.opacity(spec.isMuted ? 0.35 : 0.92) }
    private var fillSoft: Color { line.opacity(spec.isMuted ? 0.22 : 0.62) }
    private var fillFaint: Color { line.opacity(0.16) }
    private var paper: Color { AppTheme.Colors.background }

    /// Footprint (a along x, b along y), storey height and roof allowance in model units.
    private var dimensions: (a: CGFloat, b: CGFloat, storey: CGFloat, roof: CGFloat, floors: Int) {
        switch spec.kind {
        case .tower: return (2, 2, 0.62, 0, max(3, min(spec.floors, 9)))
        case .house: return (2.2, 2, 1.15, 0.95, 1)
        case .commercial: return (3, 2, 0.8, 0.14, 2)
        case .land: return (3, 3, 0, 0.55, 0)
        case .block: return (2, 2, 0.75, 0, 2)
        }
    }

    func draw(in context: inout GraphicsContext) {
        let dims = dimensions
        let fullHeight = CGFloat(dims.floors) * dims.storey
        let modelWidth = (dims.a + dims.b) * Self.cos30
        let modelHeight = (dims.a + dims.b) * Self.sin30 + fullHeight + dims.roof
        let inset: CGFloat = 1.5
        let unit = min(
            (size.width - inset * 2) / modelWidth,
            (size.height - inset * 2) / modelHeight
        )
        guard unit.isFinite, unit > 0 else { return }

        // Bottom-centred: the nearest ground corner (a, b, 0) sits on the bottom edge.
        let originX = size.width / 2 - (dims.a - dims.b) * Self.cos30 * unit / 2
        let originY = size.height - inset - (dims.a + dims.b) * Self.sin30 * unit

        func point(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGPoint {
            CGPoint(
                x: originX + (x - y) * Self.cos30 * unit,
                y: originY + (x + y) * Self.sin30 * unit - z * unit
            )
        }
        func polygon(_ points: [CGPoint]) -> Path {
            var path = Path()
            path.addLines(points)
            path.closeSubpath()
            return path
        }
        let stroke = StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
        let a = dims.a
        let b = dims.b

        if spec.kind == .land {
            drawLand(in: &context, a: a, b: b, point: point, polygon: polygon, stroke: stroke)
            return
        }

        let height = fullHeight * progress
        guard height > 0.001 else {
            // Footprint only, before the volume starts to rise.
            let footprint = polygon([point(0, 0, 0), point(a, 0, 0), point(a, b, 0), point(0, b, 0)])
            context.stroke(footprint, with: .color(line.opacity(0.5)), style: stroke)
            return
        }

        let left = polygon([point(0, b, 0), point(a, b, 0), point(a, b, height), point(0, b, height)])
        let right = polygon([point(a, b, 0), point(a, 0, 0), point(a, 0, height), point(a, b, height)])
        let top = polygon([point(0, 0, height), point(a, 0, height), point(a, b, height), point(0, b, height)])

        let wholeVolume = spec.unitFloor == nil
        context.fill(left, with: .color(paper))
        context.fill(right, with: .color(paper))
        context.fill(top, with: .color(paper))
        if wholeVolume, spec.isOccupied {
            context.fill(left, with: .color(fillStrong))
            context.fill(right, with: .color(fillSoft))
            context.fill(top, with: .color(fillFaint))
        } else {
            context.fill(right, with: .color(line.opacity(0.06)))
        }

        // The unit band.
        if let unitFloor = spec.unitFloor, dims.floors > 0 {
            let index = CGFloat(max(1, min(unitFloor, dims.floors)) - 1)
            let z0 = min(index * dims.storey, height)
            let z1 = min((index + 1) * dims.storey, height)
            if z1 > z0 {
                let bandLeft = polygon([point(0, b, z0), point(a, b, z0), point(a, b, z1), point(0, b, z1)])
                let bandRight = polygon([point(a, b, z0), point(a, 0, z0), point(a, 0, z1), point(a, b, z1)])
                if spec.isOccupied {
                    context.fill(bandLeft, with: .color(fillStrong))
                    context.fill(bandRight, with: .color(fillSoft))
                } else {
                    context.fill(bandLeft, with: .color(fillFaint))
                    context.fill(bandRight, with: .color(line.opacity(0.08)))
                }
                drawWindows(in: &context, z0: z0, z1: z1, a: a, b: b, point: point)
            }
        } else if wholeVolume {
            drawWindows(in: &context, z0: 0, z1: min(dims.storey, height), a: a, b: b, point: point)
        }

        // Storey lines.
        if dims.floors > 1 {
            var floorLines = Path()
            for level in 1..<dims.floors {
                let z = CGFloat(level) * dims.storey
                guard z < height else { break }
                floorLines.move(to: point(0, b, z))
                floorLines.addLine(to: point(a, b, z))
                floorLines.addLine(to: point(a, 0, z))
            }
            let floorColor = (wholeVolume && spec.isOccupied) ? paper.opacity(0.55) : line.opacity(0.45)
            context.stroke(floorLines, with: .color(floorColor), style: StrokeStyle(lineWidth: 0.75))
        }

        if spec.kind == .commercial {
            // Storefront: an awning line across the ground storey.
            var awning = Path()
            let z = min(dims.storey * 0.62, height)
            awning.move(to: point(0.25, b, z))
            awning.addLine(to: point(a - 0.25, b, z))
            let awningColor = (wholeVolume && spec.isOccupied) ? paper.opacity(0.8) : line
            context.stroke(awning, with: .color(awningColor), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }

        context.stroke(left, with: .color(line), style: stroke)
        context.stroke(right, with: .color(line), style: stroke)
        context.stroke(top, with: .color(line), style: stroke)

        // Roofs appear once the walls are up.
        let roofProgress = max(0, (progress - 0.8) / 0.2)
        if spec.kind == .house, roofProgress > 0 {
            let ridge = height + dims.roof * roofProgress
            let slope = polygon([point(0, b, height), point(a, b, height), point(a, b / 2, ridge), point(0, b / 2, ridge)])
            let gable = polygon([point(a, b, height), point(a, 0, height), point(a, b / 2, ridge)])
            // The far slope shows above the ridge from this angle; it goes in first.
            let farSlope = polygon([point(0, 0, height), point(a, 0, height), point(a, b / 2, ridge), point(0, b / 2, ridge)])
            context.fill(farSlope, with: .color(paper))
            if spec.isOccupied {
                context.fill(farSlope, with: .color(fillFaint))
            }
            context.stroke(farSlope, with: .color(line), style: stroke)
            context.fill(slope, with: .color(paper))
            context.fill(gable, with: .color(paper))
            if spec.isOccupied {
                context.fill(slope, with: .color(fillSoft))
                context.fill(gable, with: .color(fillFaint))
            }
            context.stroke(slope, with: .color(line), style: stroke)
            context.stroke(gable, with: .color(line), style: stroke)
        } else if spec.kind == .commercial, roofProgress > 0 {
            let lip = height + dims.roof * roofProgress
            let parapet = polygon([
                point(0.3, 0.3, lip), point(a - 0.3, 0.3, lip), point(a - 0.3, b - 0.3, lip), point(0.3, b - 0.3, lip)
            ])
            context.stroke(parapet, with: .color(line.opacity(0.7)), style: StrokeStyle(lineWidth: 0.75))
        }
    }

    private func drawWindows(
        in context: inout GraphicsContext,
        z0: CGFloat,
        z1: CGFloat,
        a: CGFloat,
        b: CGFloat,
        point: (CGFloat, CGFloat, CGFloat) -> CGPoint
    ) {
        let count = max(0, min(spec.windows, 4))
        guard count > 0, z1 - z0 > 0.2 else { return }
        var ticks = Path()
        let low = z0 + (z1 - z0) * 0.28
        let high = z0 + (z1 - z0) * 0.72
        for index in 0..<count {
            let x = a * (CGFloat(index) + 0.5) / CGFloat(count)
            ticks.move(to: point(x, b, low))
            ticks.addLine(to: point(x, b, high))
        }
        let color = spec.isOccupied ? paper.opacity(0.9) : line
        context.stroke(ticks, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
    }

    private func drawLand(
        in context: inout GraphicsContext,
        a: CGFloat,
        b: CGFloat,
        point: (CGFloat, CGFloat, CGFloat) -> CGPoint,
        polygon: ([CGPoint]) -> Path,
        stroke: StrokeStyle
    ) {
        let plot = polygon([point(0, 0, 0), point(a, 0, 0), point(a, b, 0), point(0, b, 0)])
        if spec.isOccupied {
            context.fill(plot, with: .color(fillFaint))
        }
        context.stroke(
            plot,
            with: .color(line),
            style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round, dash: spec.isOccupied ? [] : [3, 3])
        )
        // Survey lines across the plot.
        var survey = Path()
        survey.move(to: point(a / 2, 0, 0))
        survey.addLine(to: point(a / 2, b, 0))
        survey.move(to: point(0, b / 2, 0))
        survey.addLine(to: point(a, b / 2, 0))
        context.stroke(survey, with: .color(line.opacity(0.35)), style: StrokeStyle(lineWidth: 0.75))
        // Corner stakes rise with the progress.
        let stake = 0.55 * progress
        guard stake > 0.01 else { return }
        var stakes = Path()
        for corner in [(CGFloat(0), CGFloat(0)), (a, 0), (a, b), (0, b)] {
            stakes.move(to: point(corner.0, corner.1, 0))
            stakes.addLine(to: point(corner.0, corner.1, stake))
        }
        context.stroke(stakes, with: .color(line), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
    }
}

// MARK: - Previews

#Preview("IsometricBuilding") {
    let specs: [IsometricBuildingSpec] = [
        .init(kind: .tower, floors: 7, unitFloor: 4, windows: 2, isOccupied: true),
        .init(kind: .tower, floors: 5, unitFloor: 2, windows: 3, isOccupied: false),
        .init(kind: .tower, floors: 5, unitFloor: nil, isOccupied: true),
        .init(kind: .house, isOccupied: true),
        .init(kind: .house, isOccupied: false),
        .init(kind: .commercial, isOccupied: true),
        .init(kind: .land, isOccupied: false),
        .init(kind: .block, isOccupied: false, isMuted: true),
    ]
    return ScrollView(.horizontal) {
        HStack(alignment: .bottom, spacing: 12) {
            ForEach(specs, id: \.self) { spec in
                IsometricBuilding(spec: spec)
                    .frame(width: 64, height: 96)
            }
        }
        .padding()
    }
    .background(AppTheme.Colors.background)
}
