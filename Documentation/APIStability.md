# API stability

Ratatui is moving from exploratory development toward a supported `0.x` API. This document defines what
compatibility means before a `1.0` release and prevents every currently public declaration from becoming an
accidental permanent commitment.

## Stability levels

### Supported

Supported APIs are the intended foundation for ordinary applications. Changes should remain source-compatible.
If a replacement is necessary, retain the old API with an `@available(..., deprecated, message:)` migration path
for at least one minor release and record the change in `APIChanges.md`.

The supported nucleus is:

- geometry and layout: `Position`, `Size`, `Rect`, `Insets`, `Constraint`, `Flex`, and `Layout`;
- rendering values: `Color`, `Modifier`, `Style`, `Cell`, `Buffer`, `Span`, `Line`, and `Text`;
- composition: `Widget`, `StatefulWidget`, `RenderEnvironment`, `WidgetBuilder`, `Block`, `Paragraph`, and stack
  primitives;
- ordinary input: `TerminalEvent`, `KeyEvent`, `MouseEvent`, paste, resize, and focus events;
- application control: `TerminalApplication`, `ApplicationUpdate`, fullscreen and inline viewport selection, and
  the automatic-Observation opt-out;
- ordinary terminal/backend operations: drawing, sizing, clearing, cursor position/style, `Backend`, and
  `LineAppendingBackend`.

A bug fix may change behavior when the old behavior violated documented terminal restoration, clipping, Unicode,
input-continuity, or rendering invariants. Such fixes require regression evidence and an entry in `APIChanges.md`
when applications could observe the difference.

### Provisional

Provisional APIs are usable and tested, but their names or transaction boundaries may change as additional
backends and applications provide evidence. A reviewed change does not require a full deprecation release, but it
must include migration notes.

Current provisional areas are:

- `InlineHistoryBackend`, `HistoryInsertionBatchPosition`, native-history batching, and source-backed inline
  document reconciliation;
- terminal capability probing and low-level session/reconstruction controls;
- interaction routing, focus metadata, scroll/selection viewport policies, and public wakeup mechanics;
- specialized collection, metric, calendar, canvas, and branded widgets;
- syntax-highlighting and test-support products;
- sibling ecosystem packages, including overlays, multiline editing, DevTools, and macros.

`HistoryInsertionBatchPosition` must remain provisional until a second native-history backend validates its
transaction vocabulary.

### Experimental

Experimental work belongs in a sibling package, an example, or an explicitly documented prototype. It carries no
source-compatibility promise. Macros, images/graphics, terminal-surface adapters, command registries, and new
hosting integrations should begin here and graduate only after real clients establish their shape.

## Compatibility dimensions

Ratatui reviews more than declaration spelling:

- **Source:** existing supported clients continue compiling.
- **Behavior:** buffer output, cursor metadata, interaction geometry, terminal modes, and restoration remain
  deterministic unless a documented bug is fixed.
- **Concurrency:** `TerminalApplication` and `TerminalSession` lifecycle operations are compiler-enforced main-actor
  state. Blocking input polling and transactional output use separate synchronized transport primitives. Values
  declared `Sendable` may cross isolation boundaries; public reference types without `Sendable` carry no such promise.
- **Dependencies:** the `Ratatui` product remains usable with `traits: []` and does not acquire SwiftSyntax,
  snapshot-testing, syntax-highlighting, HTTP, provider, PTY, or application dependencies.
- **Backend capability:** simple backends implement only `Backend`; advanced operations require explicit capability
  protocols rather than runtime flags or throwing defaults.

Public enums can gain cases during `0.x` development where terminal protocols evolve. Application code should use
an appropriate `default` or `@unknown default` when forwarding events it does not own. Removing or changing an
existing supported case remains a breaking change.

## Public API baseline

`Documentation/API/Ratatui.json` is a normalized Swift symbol-graph snapshot. It covers every public Ratatui
symbol—not only the supported nucleus—so that provisional changes are deliberate rather than accidental.

Run:

```sh
Scripts/check-api.sh
```

The check permits additive symbols and rejects removed or changed declarations, conformances, inheritance, and
availability. For an intentional reviewed change:

1. classify the affected API using this document;
2. preserve a deprecated forwarding API when the affected surface is supported;
3. add migration notes to `Documentation/APIChanges.md`;
4. update affected consumer and behavior tests;
5. run `Scripts/check-api.sh --update` and review the baseline diff.

Once the project has release tags and Git history, CI should additionally run SwiftPM's
`diagnose-api-breaking-changes` against the latest supported tag. The checked-in baseline remains useful for
source archives and workspaces without Git metadata.

## Admission into supported core

A new API graduates into the supported nucleus only when it has:

1. at least two unrelated clients or one client plus a backend implementation proving the abstraction;
2. product-neutral vocabulary;
3. no dependency or lifecycle cost for applications that do not use it;
4. explicit actor isolation, ownership, and backend capability semantics;
5. deterministic buffer tests and, for terminal mechanics, PTY or physical-terminal evidence;
6. documentation that states behavior rather than copying a Rust API shape.

Until all six are true, keep the capability provisional or in a sibling package.

## Release posture

The next milestone should be a `0.2` stabilization release, not `1.0`. A `1.0` release should wait until the
supported nucleus has survived multiple releases and the Codex, Postcat, and Herdr consumer matrix without
special-case compatibility patches.
