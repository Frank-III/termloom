# Public API access-control audit

This audit reviews whether Ratatui's public declarations are intentional before the `0.2` stabilization boundary.
It is an access-control audit, not a promise that every declaration is already stable; stability levels remain in
`APIStability.md`.

## Reference model

The reference is upstream Ratatui Rust's current package boundary under `guided/ratatui`:

- `ratatui-core/src/lib.rs` publicly exposes backend, buffer, layout, style, symbols, terminal, text, and base-widget
  modules specifically for widget libraries and backend integrations.
- `ratatui-widgets/src/lib.rs` publicly exposes built-in blocks, paragraphs, tables, lists, charts, canvas, gauges,
  scrollbars, calendars, logos, and related configuration values.
- The main Rust `ratatui` crate re-exports built-in widgets for application convenience.

Swift should preserve that intent rather than treating every widget type as accidental solely because it increases
symbol count. Swift's result builders, protocol witnesses, mutable value configuration, and concrete lazy sequences
also produce more symbol-graph entries than an equivalent count of conceptual APIs.

## Inventory

The reviewed 0.2 candidate baseline contains 1,540 symbols and 2,039 relationships. Source inspection finds 1,273
explicit public declaration lines, concentrated in geometry, terminal lifecycle, fitting and viewport primitives,
Canvas, metric widgets, controls, blocks, tables, and base widget composition.

The high raw count is not evidence by itself that 1,540 independent abstractions were designed. It includes:

- stored-property accessors;
- initializers and protocol witnesses;
- result-builder entry points;
- conformances and inherited requirements;
- operators and convenience modifiers;
- concrete sequence and iterator types.

## Decisions

### Keep public as supported core

Keep geometry, layout, buffer/cell/style/text values, `Widget`, `StatefulWidget`, `Frame`, `CompletedFrame`, basic
widgets, ordinary terminal events, `Backend`, and `TerminalApplication` public. These match upstream core's
extension points and are already used by Postcat, Codex, Herdr, and sibling widget packages.

### Keep public as low-level escape hatches

Keep `ANSIBackend`, `TerminalSession`, `TerminalInput`, `InputParser`, terminal capability reports, and explicit
backend capability protocols public. Although ordinary applications do not need them, external backend, PTY,
embedded-terminal, and testing integrations do. Ratatui Rust likewise keeps backend and terminal contracts public.
Their less-settled portions remain provisional rather than being hidden.

### Keep public builder and sequence plumbing

Types such as `SpanBuilder`, `StackBuilder`, `CanvasLayerBuilder`, table builders, `RectRows`, `RectColumns`, and
`RectPositions` are public because they appear in public result-builder or concrete return signatures. Callers do
not normally spell their names, but reducing their access would either make the containing API invalid or replace
allocation-light concrete sequences with erasure.

### Keep built-in widget configuration public

Canvas, charts, gauges, bars, lists, tables, calendars, borders, and branded widgets follow upstream
`ratatui-widgets`. Version 0.2 keeps them in the umbrella module. They remain provisional as a group because their
configuration vocabulary has less independent-client history than the supported core, not because a package split is
pending during the release candidate.

### Keep inline reconciliation provisional and public

`InlineDocumentRuntime` is not required by ordinary applications, but Codex uses it for direct lifecycle tests and
performance measurements. It remains public as a provisional source-backed-history tool instead of forcing clients
to duplicate reconciliation logic.

## Access-control result

No supported declaration was made internal merely to lower the count. The examined implementation machinery is
already private or internal: observation invalidators and wakeup pipes, ANSI history batch state, parser helpers,
layout caches, canvas rasterization details, table measurement helpers, and output-write test injection.

That is the preferred outcome: a reviewed large surface is safer than an artificially small surface that removes
backend and widget-extension capabilities. Future reductions should happen only with a migration or package split,
not opportunistically while fixing implementation code.

## Rules going forward

1. New helper declarations begin `private` or `internal`; public access requires a documented consumer-facing use.
2. A public declaration must belong to the supported nucleus, a named provisional area, or an experimental sibling
   package.
3. Public protocol requirements must document isolation and ownership.
4. Do not expose a concrete helper merely to test it; use `@testable` internal access or injected internal seams.
5. Review `Scripts/check-api.sh` output and `Documentation/API/Ratatui.json` for every public change.
6. The 0.2 review keeps one umbrella `Ratatui` module. Any future widgets-package split is a separately planned
   migration, not release-candidate cleanup.
