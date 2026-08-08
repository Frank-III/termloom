# Plan 010: Add lazy, action-aware fixed-height selectable rows

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MEDIUM
- **Depends on**: plans 008–009
- **Category**: collections / interaction / DX
- **Planned at**: commit `2a4087a`, 2026-08-07

## Why this matters

DiffScope, Motel, Herdr, and Codex repeatedly compute a selected-item viewport, derive row rectangles, fill the selected row, register row interactions, and render only the visible items. Core `List` handles selection styling and visibility but eagerly materializes every row and cannot expose or attach interaction metadata to visible rows. Large or domain-shaped collections therefore reimplement the same immediate-mode mechanics.

A fixed-height lazy row primitive should own only projection and presentation mechanics. Applications must continue to own stable identity, filtering, navigation, action meaning, and domain rendering.

## Scope

1. Add a pure fixed-height selection projection with explicit selected-row placement (`leading`, `center`, or `trailing`).
2. Add an immediate-mode `SelectableRows` widget that:
   - invokes row rendering only for visible indices;
   - supplies each visible index, rectangle, and selection flag;
   - optionally fills the selected row;
   - optionally registers application-provided control/action metadata for visible rows;
   - stores no retained selection or viewport state.
3. Preserve stable application-owned IDs and string action routing; do not redesign `ActionID` in this milestone.
4. Migrate DiffScope file rows and Motel trace/waterfall rows without moving Git or telemetry presentation into TermLoom.
5. Characterize projection boundaries, laziness, selection styling, interaction rectangles, and modal interaction suppression.
6. Update API documentation and baseline.

## Non-goals

- A generic menu framework.
- Variable-height lazy measurement.
- Retained collection state, filtering, sorting, or navigation.
- Domain row models or domain action payloads.
- Refactoring `List` variable-height behavior.
- Overflow-aware tabs or wrapped editable text.

## Invariants

- Empty areas and empty collections render no rows or interactions.
- Negative counts, heights, and indices normalize safely.
- Selected indices clamp only for projection; application selection identity is not mutated.
- Only visible rows invoke row and interaction closures.
- Every emitted interaction uses the exact row rectangle from the render pass.
- Selection fill precedes application row rendering so domain styles can patch or override it deliberately.
- Row geometry remains nonnegative and clipped to the supplied area.
- Existing `List`, `SelectionViewport`, and interaction routing behavior remain source-compatible.

## Verification

1. Strict format lint.
2. TermLoom tests, including focused row-projection tests.
3. API baseline review/update.
4. DiffScope tests, including visible interaction ranges.
5. Motel tests, including trace and waterfall row actions.
6. Full ecosystem and consumer matrices.
7. KWWK hash verification.

## Done criteria

- DiffScope and Motel no longer own fixed-height selected viewport, row rectangle, selection-fill, and interaction-registration loops.
- Domain-specific row cell rendering remains visibly local to each client.
- New tests prove visible-only evaluation and exact interaction geometry.
- All verification passes and touched repositories are clean.
