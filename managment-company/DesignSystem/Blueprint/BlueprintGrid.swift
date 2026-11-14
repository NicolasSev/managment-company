import SwiftUI

/// Faint drafting grid for hero areas only (masthead, empty state art). Never behind lists.
struct BlueprintGrid: View {
    var step: CGFloat = 24
    var opacity: Double = 1

    var body: some View {
        Canvas { context, size in
            var minor = Path()
            var major = Path()
            var column = 0
            var x: CGFloat = 0
            while x <= size.width {
                if column % 4 == 0 {
                    major.move(to: CGPoint(x: x, y: 0)); major.addLine(to: CGPoint(x: x, y: size.height))
                } else {
                    minor.move(to: CGPoint(x: x, y: 0)); minor.addLine(to: CGPoint(x: x, y: size.height))
                }
                x += step
                column += 1
            }
            var row = 0
            var y: CGFloat = 0
            while y <= size.height {
                if row % 4 == 0 {
                    major.move(to: CGPoint(x: 0, y: y)); major.addLine(to: CGPoint(x: size.width, y: y))
                } else {
                    minor.move(to: CGPoint(x: 0, y: y)); minor.addLine(to: CGPoint(x: size.width, y: y))
                }
                y += step
                row += 1
            }
            context.stroke(minor, with: .color(AppTheme.Colors.border.opacity(0.45 * opacity)), lineWidth: 0.5)
            context.stroke(major, with: .color(AppTheme.Colors.border.opacity(0.9 * opacity)), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// Grid that fades out towards the bottom: the background of a hero block.
struct BlueprintHeroBackground: View {
    var body: some View {
        BlueprintGrid()
            .mask(
                LinearGradient(
                    colors: [.black, .black.opacity(0.55), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
}

// MARK: - Drafting text styles

extension View {
    /// Drafting label above a block: small expanded upper-case with wide tracking.
    func sectionLabelStyle(_ color: Color = AppTheme.Colors.textSecondary) -> some View {
        self
            .font(AppTheme.Typography.label)
            .textCase(.uppercase)
            .tracking(1.4)
            .foregroundStyle(color)
    }
}

/// Consistent section header: drafting label, optional trailing accessory, hairline below.
struct SectionHeader<Accessory: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
                Text(title)
                    .sectionLabelStyle()
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: AppTheme.Spacing.sm)
                accessory()
            }
            Rectangle()
                .fill(AppTheme.Colors.border)
                .frame(height: 1)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension SectionHeader where Accessory == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = { EmptyView() }
    }
}

/// Small figure with a drafting label: the building block of fact rows inside cards.
struct MetricTile: View {
    let title: String
    let value: String
    var tint: Color = AppTheme.Colors.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .sectionLabelStyle()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(AppTheme.Typography.money)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.leading, AppTheme.Spacing.md)
        .padding(.trailing, AppTheme.Spacing.sm)
        .overlay(alignment: .leading) {
            Rectangle().fill(AppTheme.Colors.border).frame(width: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Blueprint blocks") {
    VStack(alignment: .leading, spacing: 16) {
        SectionHeader("Заселённость", subtitle: "Занятые объекты портфеля.")
        HStack {
            MetricTile(title: "Занято", value: "3")
            MetricTile(title: "Всего", value: "4")
            MetricTile(title: "Доля", value: "75%", tint: AppTheme.Colors.accent)
        }
    }
    .padding()
    .background { BlueprintHeroBackground() }
}
