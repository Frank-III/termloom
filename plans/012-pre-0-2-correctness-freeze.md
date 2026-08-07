# Plan 012: Pre-0.2 correctness freeze

## Status

- **Priority**: P0
- **Effort**: M
- **Risk**: MEDIUM
- **Depends on**: plans 008–011
- **Category**: correctness / consumers / protocol boundaries
- **Planned at**: commit `9964179`, 2026-08-07
- **Status**: DONE

## Why this matters

The Swift-native geometry, fitting, selectable-row, and overflow-tab changes are justified by multiple clients, but review found five concrete regressions. Pre-0.2 stabilization must repair these before adding API.

## Scope

1. Make every public `SelectableRows.rowHeight` value safe, including post-initialization mutation.
2. Preserve `Line.style` and span style precedence when `Tabs` applies base and selected styles.
3. Make Codex transcript pager arithmetic saturating for every public mutation path.
4. Validate Herdr remote-frame dimensions, cell cardinality, deltas, cursor coordinates, and interaction rectangles before multiplication, ranges, allocation, or rendering.
5. Replace Herdr terminal geometry based on `String.count` with terminal-column measurement.
6. Add mutation, rich-style, overflow, malformed-frame, and Unicode regressions.

## Non-goals

- New widgets or demos.
- Herdr protocol redesign beyond validation.
- Typed generic actions.
- TerminalApplication capability splitting.

## Invariants

- Public mutable values cannot bypass initializer normalization and crash rendering.
- Widget base style is the fallback; title and span styles retain their intended precedence; selected style is applied deliberately without erasing richer title styling.
- Pager movement never traps at `Int.min` or `Int.max`.
- Untrusted frame dimensions are positive, bounded, multiplication-safe, cardinality-consistent, and geometrically contained before acceptance.
- Human-visible geometry is measured in terminal columns.

## Verification

Run strict formatting and tests in Ratatui, Codex, and Herdr, then Ratatui's API, ecosystem, and consumer matrices. Recheck KWWK hashes.

## Done criteria

All five findings have focused regressions, all matrices pass, and touched repositories are committed independently and clean.
