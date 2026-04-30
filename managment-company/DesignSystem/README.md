# Design System

## DesignTokens

`DesignTokens.swift` is generated from `packages/design-tokens/tokens.json`. To refresh after token changes:

```bash
cd packages/design-tokens && npm run generate
```

Then copy `packages/design-tokens/dist/tokens.swift` to `DesignTokens.swift` (or run a copy script).

## AppTheme Mapping

| AppTheme | DesignTokens |
|----------|--------------|
| Colors.* | DesignTokens.Colors.* |
| Spacing.xs/sm/md/lg/xl | Spacing.scale0/1/3/5/6 |
| Radius.* | DesignTokens.Radius.* |

Use `AppTheme` for semantic access; use `DesignTokens` directly when you need the full scale (e.g. `DesignTokens.Spacing.scale4`).
