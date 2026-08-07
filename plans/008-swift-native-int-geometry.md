# Plan 008: Migrate public terminal geometry to Swift-native `Int`

## Status

- **Priority**: P0
- **Effort**: XL
- **Risk**: HIGH
- **Depends on**: plans 006–007
- **Category**: API / correctness / DX
- **Planned at**: commit `b3706ec`, 2026-08-07

## Why this matters

Production clients repeatedly convert application counts, indices, scroll offsets, measured text widths, and collection sizes between `Int` and `UInt16`. The conversions obscure arithmetic, duplicate clamping policy, and make otherwise-safe Swift collection math awkward. Terminal wire and OS boundaries may remain fixed-width, but framework and application geometry should use Swift's native integer.

## Scope

Convert coordinate and extent values to `Int`, including:

- `Position`, `Size`, `Rect`, `Insets`, and their sequences;
- layout constraints, spacing, padding, scroll offsets, widget dimensions, and viewport heights;
- buffer drawing widths and backend region movement;
- fixed/inline terminal session geometry and history measurement;
- Ratatui packages, Postcat, DiffScope, Codex, and Herdr call sites.

Preserve fixed-width protocol data such as modifier bitsets, terminal mode/device parameters, color channels, Unicode widths, and C ABI `winsize` fields. Convert only at those boundaries.

## Invariants

- Public geometry is nonnegative at construction and terminal boundaries.
- `Rect` prevents negative extents and saturates overflowing right/bottom arithmetic.
- No `UInt16.max`-based application limits remain.
- ANSI coordinates remain one-based only when serialized.
- Existing rendering, clipping, fixed-region ownership, inline history, and PTY behavior remain unchanged.
- KWWK is untouched.

## Verification

1. Strict format lint.
2. Root tests and syntax-highlighting tests.
3. API baseline review/update.
4. Postcat and DiffScope tests.
5. Ecosystem packages.
6. Codex and Herdr full tests.
7. Real PTY lifecycle tests included in the root and consumer suites.
8. KWWK hash verification.

## Done criteria

- Ratatui public geometry and application-facing dimension APIs use `Int`.
- Fixed-width integers remain only where they model protocol, storage, color, Unicode, or ABI data.
- Production clients no longer contain geometry-only `UInt16(clamping:)` glue.
- All verification passes and repositories are clean.
