# Plan 014: Adopt stabilized collections in Herdr

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MEDIUM
- **Depends on**: plans 012–013
- **Category**: consumer proof

## Scope

Migrate Herdr workspace tabs to `Tabs` and fixed-height overlay rows to `SelectableRows`. Produce cells, interaction rectangles, and cursor metadata from shared computed geometry in the same pass. Keep BSP layout, PTYs, Ghostty projection, daemon protocol, plugins, workspaces, and action decoding in Herdr.

## Non-goals

No generic menu framework, variable-height lazy collection, or core terminal-emulator API.

## Done criteria

Herdr removes duplicated tab/row geometry without semantic movement into Ratatui; its complete 87-test baseline plus new Unicode and interaction tests pass.
