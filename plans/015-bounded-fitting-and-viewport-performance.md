# Plan 015: Bound fitting and viewport work

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: plan 012
- **Category**: internal performance

## Scope

Make `String`, `Span`, and `Line` clipping establish truncation without first measuring complete long inputs. Make `TabViewport` boundary checks linear overall rather than repeatedly reducing remaining slices. Benchmark client-shaped long Unicode strings, large selectable collections, tab projection, and Herdr frame conversion. Optimize Herdr's duplicate Ghostty-to-Ratatui projection only if profiles support it.

## Non-goals

No framework-owned cache, dirty-row API, retained layout index, or Motel database changes.

## Done criteria

Focused benchmarks demonstrate bounded/linear work while preserving exact Unicode/style behavior and all consumer tests.
