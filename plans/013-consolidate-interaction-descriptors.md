# Plan 013: Consolidate collection interaction descriptors

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MEDIUM
- **Depends on**: plan 012
- **Category**: public API reduction
- **Planned at**: commit `9b6b48c`, 2026-08-07
- **Status**: DONE

## Scope

Replace `RowInteraction` and `TabInteraction` with one product-neutral, geometry-free interaction descriptor carrying `ControlID`, optional `ActionID`, and focusability. Migrate every client before removing the provisional duplicate names. Generalize `SelectionPlacement` documentation to describe leading/center/trailing placement on either projection axis. Add no other widget API.

## Invariants

The descriptor contains no row/tab semantics or rectangle; geometry remains generated in the render pass. Action IDs remain string-erased for serialization and coarse type erasure.

## Verification

API baseline must show reviewed removals/replacements only; all ecosystem and consumer tests pass.

## Result

`InteractionDescriptor` now supplies the shared geometry-free control, optional string-erased action, and focusability
metadata for both `SelectableRows` and `Tabs`. DiffScope, Postcat, and Motel migrated before the duplicate provisional
names were removed. The API baseline records 1,540 reviewed symbols with no unreviewed additions. Framework and
ecosystem matrices pass; Codex passes, Motel passes, and Herdr's 89-test suite passes serially. Herdr's unrelated
autosaver timing test failed under parallel execution but passed focused and in the complete serial suite.
