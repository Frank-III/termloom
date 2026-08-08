# Plan 015: Bound fitting and viewport work

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: plan 012
- **Category**: internal performance
- **Planned at**: commit `d2e18a0`, 2026-08-07
- **Status**: DONE

## Scope

Make `String`, `Span`, and `Line` clipping establish truncation without first measuring complete long inputs. Make `TabViewport` boundary checks linear overall rather than repeatedly reducing remaining slices. Benchmark client-shaped long Unicode strings, large selectable collections, tab projection, and Herdr frame conversion. Optimize Herdr's duplicate Ghostty-to-TermLoom projection only if profiles support it.

## Non-goals

No framework-owned cache, dirty-row API, retained layout index, or Motel database changes.

## Done criteria

Focused benchmarks demonstrate bounded/linear work while preserving exact Unicode/style behavior and all consumer tests.

## Result

Terminal fitting now discovers truncation at the requested column boundary before constructing the clipped result;
`Span` inherits that path and `Line` probes styled spans only until overflow. `TabViewport` computes prefix and suffix
width totals once, eliminating repeated slice reductions while preserving saturating arithmetic. The new `collections`
benchmark compares bounded clipping with full width measurement, million-item visible rows, and 1,000/100,000-tab
projection. Profiles did not identify Herdr's Ghostty projection as the relevant bottleneck, so it remains unchanged.
