# Plan 009: Add terminal-column fitting and top-origin row viewport geometry

## Status

- **Priority**: P0
- **Effort**: M
- **Risk**: MEDIUM
- **Depends on**: plan 008
- **Category**: correctness / API / DX
- **Planned at**: commit `f759630`, 2026-08-07

## Why this matters

Production clients repeatedly clip and pad strings using `String.count`, `String.padding`, or local loops even though terminal columns do not correspond to Swift character counts. CJK, emoji, variation selectors, and combining sequences therefore drift across columns. DiffScope and Postcat also manually clamp top-origin row offsets and slice visible rows despite sharing the same pure geometry.

## Scope

1. Add grapheme-safe terminal-column operations for plain strings:
   - leading prefix and trailing suffix clipping;
   - optional-ellipsis truncation;
   - leading, centered, and trailing padding;
   - combined fixed-column fitting.
2. Add equivalent style-preserving fitting for `Span` and `Line`.
3. Add a pure `RowViewport` with a top-origin offset, clamped visible range, boundary flags, and progress.
4. Preserve `ScrollViewport` end-origin behavior while sharing the top-origin projection.
5. Replace proven fitting and viewport workarounds in Postcat, DiffScope, and Motel.
6. Add Motel to the optional production-consumer validation matrix.

## Invariants

- Never split a Swift grapheme cluster or emit a partial wide terminal glyph.
- Results never exceed the requested terminal-column width.
- Ellipsis text is itself clipped safely when the target is narrow.
- Rich fitting preserves source span styles, line style, and alignment.
- Padding is measured in terminal columns and uses ordinary spaces.
- Negative widths, row counts, viewport sizes, and offsets normalize to zero.
- A viewport range is always within `0..<totalRows` and never exceeds `viewportRows`.
- Existing end-origin `ScrollViewport` behavior remains source- and behavior-compatible.
- Domain selection, filtering, actions, Git, HTTP, and telemetry remain application-owned.

## Verification

1. Strict format lint.
2. Focused Unicode fitting and exhaustive small-domain viewport tests.
3. Root and syntax-highlighting suites.
4. API baseline review/update.
5. Postcat and DiffScope suites.
6. Motel full suite.
7. Codex and Herdr full consumer suites.
8. KWWK hash verification.

## Done criteria

- TermLoom exposes tested plain and rich terminal-column fitting.
- TermLoom exposes tested top-origin row viewport geometry.
- Postcat, DiffScope, and Motel remove representative local fitting/slicing workarounds.
- The full ecosystem and production-consumer matrix passes.
- Plan 009 is marked `DONE` and all touched repositories are clean.
