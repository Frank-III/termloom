# API changes

Record public source or observable behavioral changes here until release tags provide a generated changelog.
Entries must identify the stability level, migration path, and validation evidence.

## Unreleased

### Main-actor terminal-session lifecycle

- **Supported concurrency correction:** `TerminalSession` is now `@MainActor` instead of
  `@unchecked Sendable`. Its raw-mode, viewport, cursor-origin, prefetched-input, and restoration state has one
  compiler-enforced owner matching `TerminalApplication` lifecycle isolation.
- **Migration:** create and operate on `TerminalSession` from main-actor code. Synchronous and asynchronous
  `withTerminalSession` scopes are both main-actor isolated. Blocking terminal input remains in the detached,
  lock-isolated input pump, and transactional output remains a separately synchronized transport primitive.
- **Evidence:** the minimal Swift 6 build and real-PTY inline, fullscreen, fixed, resize, suspend/resume, input-transfer,
  and application-loop tests compile and pass without an unchecked session conformance.

### One-pass widget presentation and fixed viewports

- **Supported breaking redesign:** `Widget` now has one presentation requirement,
  `render(in:into: inout Frame)`. `Frame` owns the mutable buffer, render environment, interaction regions, and
  hardware-cursor metadata, so type erasure and composed widgets execute layout and presentation exactly once.
  `StatefulWidget` is independent from `Widget`; a stateful widget conforms to both only when it also has meaningful
  stateless presentation.
- **Migration:** replace `render(in:into:environment:)`, `collectInteractions`, `cursorPosition`, and `cursorStyle`
  implementations with one `render(in:into:)` implementation. Read `frame.environment`, mutate `frame.buffer`, call
  `frame.addInteraction(s)`, and call `frame.placeCursor(at:style:)` during that pass. Use
  `frame.render(_:in:environment:)` for scoped environment overrides. Existing buffer-only render helpers remain for
  snapshots and low-level cell rendering, but intentionally discard interaction and cursor metadata.
- This is an intentional pre-0.2 source break rather than a deprecated forwarding layer: retaining the old protocol
  requirements would preserve the repeated layout traversals that the redesign removes. Ratatui core, all sibling
  packages and examples, Codex, and Herdr have migrated to the new contract.
- **Provisional:** `Viewport.fixed(Rect)` embeds an exact terminal-coordinate region without alternate-screen or inline
  history ownership. The region does not autoresize with its host; callers explicitly use `Terminal.resize(to:)`.
  Fixed clear/reset operations affect only that region, input mouse coordinates remain physical, and session teardown
  restores the surrounding cursor.
- **Evidence:** a one-pass type-erasure regression verifies cells, interactions, and cursor metadata from one render;
  fixed-region buffer tests and a real PTY verify absolute addressing, scoped clearing, resize behavior, mode balance,
  and cursor restoration. The full 229-test Ratatui suite, ecosystem script, Codex's 155 tests, and Herdr's 87 tests
  pass under strict formatting.

### Application redraw scheduling

- **Supported:** `TerminalApplication.automaticallyTracksObservableState` defaults to `true`. Applications that
  already own a complete event/stream redraw scheduler can return `false` to prevent duplicate frames.
- Swift Observation mutations read during presentation or widget rendering coalesce into an ordinary whole-frame
  render and changed-cell diff. Ratatui does not retain widget state or repaint subtrees.
- **Provisional:** `ObservationInvalidationTracker` exposes that one-shot dependency tracking to offscreen and remote
  renderers. Each render rearms its current dependencies and supplies its own transport-neutral wakeup callback.
- Postcat provides explicit and `--observable` modes; Codex uses its explicit scheduler. PTY coverage verifies
  synchronous mutation coalescing and that invalidation during an asynchronous `update` is not lost.

### Backend capabilities

- **Supported:** ordinary drawing, sizing, clearing, and cursor operations remain requirements of `Backend`.
- **Supported:** append-only line emission is expressed by `LineAppendingBackend`.
- **Provisional:** native inline history is expressed by `InlineHistoryBackend`; batching and
  `HistoryInsertionBatchPosition` are not stable yet. Failure injection now covers clear, single, first, middle, last,
  and partially written chunks. Every failure restores margins, styles, and wrapping, discards stale transaction
  state, and permits a subsequent insertion. Reset coalescing discards queued rows before the final reset marker.
  PTY coverage verifies origin clamping when the terminal shrinks between chunks, and full-width rows remain inside
  disabled-autowrap boundaries.
- A second in-memory native-history backend model and the generic fallback validate batch composition independently
  from ANSI output. A second production backend is still required before stabilizing the vocabulary.
- `InlineHistoryBackend` can restore a retained live viewport as the final batch chunk commits. `ANSIBackend` emits
  Supaterm history bytes first, then restores the live viewport inside synchronized output, all in one write. This
  prevents the terminal from painting the intentionally blank reservation between history insertion and the next
  application frame while preserving native scrollback metadata.

### Paragraph viewport work

- **Supported:** paragraph rendering preserves wrapping, styling, Unicode width, alignment, and scrolling semantics
  while composing only enough source and visual lines to fill the viewport.
- Unscrolled rendering of the 2,048-line benchmark improved from approximately 14.0 ms to 0.52 ms. Locating a
  scrolled wrapped row remains streaming and proportional to the scroll offset, as in Ratatui Rust.
- **Migration:** none. `Paragraph.lineCount(width:)` still computes the complete document height.

### Optional package graph

- Syntax highlighting and test support are independently trait-gated. `traits: []` builds the minimal production
  core.
- Overlays, multiline editing, DevTools, and macro ergonomics live in independently consumable sibling packages.
  Only the macro package resolves SwiftSyntax.

## Entry template

```markdown
### Change title

- **Supported | Provisional | Experimental:** affected declarations and behavior.
- **Migration:** exact replacement or application action.
- **Evidence:** tests, consumer builds, PTY captures, and benchmarks.
```
