# Plan 014: Adopt stabilized collections in Herdr

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MEDIUM
- **Depends on**: plans 012–013
- **Category**: consumer proof
- **Planned at**: commit `f32a379`, 2026-08-07
- **Status**: DONE

## Scope

Migrate Herdr workspace tabs to `Tabs` and fixed-height overlay rows to `SelectableRows`. Produce cells, interaction rectangles, and cursor metadata from shared computed geometry in the same pass. Keep BSP layout, PTYs, Ghostty projection, daemon protocol, plugins, workspaces, and action decoding in Herdr.

## Non-goals

No generic menu framework, variable-height lazy collection, or core terminal-emulator API.

## Done criteria

Herdr removes duplicated tab/row geometry without semantic movement into TermLoom; its complete baseline plus new Unicode and interaction tests pass.

## Result

Herdr workspace tabs now use `Tabs`, including overflow projection and exact same-pass `InteractionDescriptor` regions.
Workspace-switcher, command-palette, and context-menu rows now use `SelectableRows`; the row closure and interaction
metadata consume the same visible geometry, while Herdr retains labels, selection state, action decoding, cursor policy,
and overlay meaning. Unicode overflow, context targeting, and overlay geometry regressions pass with the complete
91-test Herdr suite.
