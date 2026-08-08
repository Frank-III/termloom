# Plan 011: Add overflow-aware interactive tabs

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MEDIUM
- **Depends on**: plans 009–010
- **Category**: collections / interaction / geometry
- **Planned at**: commit `3e401de`, 2026-08-07

## Why this matters

Motel, Herdr, and Postcat need the same terminal-sensitive tab mechanics: keep the selected tab visible, reserve overflow indicators, derive exact visible tab rectangles, and optionally attach application actions. Existing `Tabs` renders rich titles and selection styles but clips from the leading edge, exposes no geometry, and cannot emit interactions. Clients therefore duplicate Unicode width projection and hit-region calculations.

Applications provide evidence for the invariant, not the API shape. TermLoom should own only generic horizontal projection and same-pass presentation geometry. Product labels, colors, identity, switching behavior, trailing mode chrome, and navigation remain application-owned.

## Scope

1. Add a pure `TabViewport` for contiguous variable-width tab projection with explicit selected-tab placement and overflow flags.
2. Add value-semantic `TabPlacement` and `TabLayout` geometry, including optional leading/trailing overflow areas.
3. Evolve `Tabs` additively with:
   - selected-tab visibility;
   - configurable overflow indicators;
   - same-pass geometry via `layout(in:)`;
   - optional per-index `TabInteraction` metadata;
   - preserved rich `Line` styling and alignment.
4. Preserve `Tabs` value semantics, `Hashable`, and `Sendable`; do not store rendering or interaction closures.
5. Migrate Motel service tabs and Postcat response tabs while retaining their product styling and action meaning.
6. Characterize Unicode widths, narrow/empty areas, oversized selected tabs, overflow flags, exact interaction rectangles, and selected-tab visibility.
7. Update API documentation and baseline.

## Non-goals

- Service, workspace, HTTP, or telemetry semantics in core.
- Tab navigation or retained selection state.
- Herdr's trailing mode label or workspace behavior.
- A generic menu framework.
- Structured action payload redesign.
- Wrapped editable text.

## Invariants

- Projection uses terminal columns, not grapheme or scalar counts.
- A valid selected index is represented whenever capacity is nonzero, clipping only when that tab itself cannot fit.
- Visible tabs are contiguous and remain in source order.
- Overflow indicators appear when hidden tabs exist on that side and space remains after preserving a visible selected-tab cell.
- Every tab interaction uses the exact visible rectangle rendered in the same pass.
- Application-provided identity and action meaning are not interpreted by TermLoom.
- Existing `Tabs` initializers and non-overflow rendering remain source-compatible.
- Empty titles and empty areas emit no tab interactions.

## Verification

1. Strict format lint.
2. TermLoom tests, including synthetic projection and interaction geometry.
3. API baseline review/update.
4. Postcat and Motel tests.
5. Full ecosystem and consumer matrices.
6. KWWK hash verification.

## Done criteria

- Motel no longer owns overflow projection, tab rectangles, or per-tab interaction construction.
- Postcat uses core tab interactions without moving response semantics into TermLoom.
- Synthetic tests prove Unicode-aware projection and same-pass geometry.
- All verification passes and touched repositories are clean.
