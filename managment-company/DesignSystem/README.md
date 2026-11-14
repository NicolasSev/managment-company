# Design System

## DesignTokens

`DesignTokens.swift` is generated from `packages/design-tokens/tokens.json`. To refresh after token changes:

```bash
cd packages/design-tokens && npm run generate
```

Then copy `packages/design-tokens/dist/tokens.swift` to `DesignTokens.swift` (or run a copy script).

## Visual language: Blueprint

Paper, ink and one chromatic accent (cobalt). Colours live in `Theme/BlueprintPalette.swift` as
dynamic light/dark pairs and are read through `AppTheme.Colors`; the generated
`DesignTokens.Colors` is light-only and is no longer the colour source (reconcile
`packages/design-tokens/tokens.json` with the palette when the web redesign lands).

| Role | Light | Dark |
|------|-------|------|
| ground | `#F4F6F8` | `#070B14` |
| paper (cards) | `#FFFFFF` | `#0E1524` |
| inset | `#F4F6F8` | `#162038` |
| ink / muted / faint | `#0B0F14` / `#5B6672` / `#6F7A86` | `#EAF0FF` / `#9BA8C9` / `#7C8AB0` |
| cobalt (accent, income, success) | `#1F4FFF` | `#5B7CFF` |
| on-cobalt | `#FFFFFF` | `#070B14` |
| hairline | `#DDE2E8` | `#1E2A44` |
| overdue (reserved red) | `#D4372C` | `#FF6B5E` |
| amber (warning) | `#B7791F` | `#E0A84A` |

Rules: red only for overdue, destructive and errors; a plain expense or an empty unit is neutral
ink. No shadows, gradients or glass on content — glass stays in the system bars.

- `Blueprint/IsometricBuilding.swift`, `IsometricStreet.swift` — line-drawn buildings (`Canvas`),
  `progress` animates the build-up; `Features/Properties/PropertyGlyph.swift` maps a property to a glyph.
- `Blueprint/BlueprintGrid.swift` — hero grid, `sectionLabelStyle()`, `SectionHeader`, `MetricTile`.
- `Blueprint/BlueprintChart.swift` — Swift Charts axes, `ChartDrawIn`, `ProportionBar`.
- `Blueprint/PaidCheckMark.swift` — ring → check morph with a success haptic.
- `AppTheme.Typography` — expanded light masthead, drafting label, monospaced money.
- `Theme/AppAppearance.swift` — masthead type of large navigation titles.

## AppTheme Mapping

| AppTheme | Source |
|----------|--------------|
| Colors.* | BlueprintPalette.* |
| Spacing.xs/sm/md/lg/xl | Spacing.scale0/1/3/5/6 |
| Radius.* | DesignTokens.Radius.* |

Use `AppTheme` for semantic access; use `DesignTokens` directly when you need the full scale (e.g. `DesignTokens.Spacing.scale4`).
