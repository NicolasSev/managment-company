import SwiftUI

/// Empty, error and "nothing found" state: isometric line art on a drafting grid, a short
/// explanation and exactly one action.
struct EmptyStateView: View {
    let title: String
    let message: String
    let actionName: String
    let action: () -> Void
    var icon: String = "building.2"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBuilt = false

    private static let art: [IsometricBuildingSpec] = [
        .init(kind: .house, isOccupied: false),
        .init(kind: .tower, floors: 6, unitFloor: nil, isOccupied: false),
        .init(kind: .block, isOccupied: false),
    ]

    var body: some View {
        VStack {
            SurfaceCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    artwork

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Label {
                            Text(title)
                                .font(AppTheme.Typography.display)
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: icon)
                                .font(.body.weight(.medium))
                                .foregroundStyle(AppTheme.Colors.accent)
                        }
                        .labelStyle(TrailingIconLabelStyle())

                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    PrimaryButton(title: actionName, action: action, systemImage: "arrow.right")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, AppTheme.Spacing.xl)
        .onAppear { isBuilt = true }
    }

    private var artwork: some View {
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(Self.art.enumerated()), id: \.offset) { index, spec in
                    IsometricBuilding(spec: spec, progress: (isBuilt || reduceMotion) ? 1 : 0)
                        .frame(
                            width: IsometricStreet.width(of: spec, height: 84),
                            height: IsometricStreet.height(of: spec, height: 84)
                        )
                        .animation(
                            AppTheme.Motion.build.delay(AppTheme.Motion.buildDelay(index: index, reduceMotion: reduceMotion)),
                            value: isBuilt
                        )
                }
                Spacer(minLength: 0)
            }
            .frame(height: 84, alignment: .bottom)
            DimensionRule(ticks: 4)
        }
        .padding(AppTheme.Spacing.md)
        .background {
            BlueprintGrid(step: 14)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.inner, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.inner, style: .continuous)
                .strokeBorder(AppTheme.Colors.border, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
            configuration.title
            Spacer(minLength: 0)
            configuration.icon
        }
    }
}

#Preview("EmptyStateView") {
    ZStack {
        AppScreenBackground()
        EmptyStateView(
            title: "Объектов пока нет",
            message: "Добавьте первый объект, чтобы начать вести портфель.",
            actionName: "Добавить объект",
            action: {}
        )
    }
}
