# Plan 013: Consolidate collection interaction descriptors

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MEDIUM
- **Depends on**: plan 012
- **Category**: public API reduction

## Scope

Replace `RowInteraction` and `TabInteraction` with one product-neutral, geometry-free interaction descriptor carrying `ControlID`, optional `ActionID`, and focusability. Migrate every client before removing the provisional duplicate names. Generalize `SelectionPlacement` documentation to describe leading/center/trailing placement on either projection axis. Add no other widget API.

## Invariants

The descriptor contains no row/tab semantics or rectangle; geometry remains generated in the render pass. Action IDs remain string-erased for serialization and coarse type erasure.

## Verification

API baseline must show reviewed removals/replacements only; all ecosystem and consumer tests pass.
