# API changes

Record public source or observable behavioral changes here until release tags provide a generated changelog.
Entries must identify the stability level, migration path, and validation evidence.

## Unreleased

### Overflow-aware interactive tabs

- **Additive:** `TabViewport` projects contiguous variable-width tabs while keeping the selected index represented and
  reporting leading/trailing overflow. `Tabs.layout(in:)` returns value-semantic `TabLayout` and `TabPlacement` geometry.
- **Additive:** `Tabs` supports configurable overflow indicators, selected-tab placement, and optional value-semantic
  `TabInteraction` metadata. Emitted interactions use the exact visible tab rectangles from the render pass.
- **Ownership:** Ratatui owns terminal-column projection and geometry. Applications retain tab identity, navigation,
  labels, colors, switching behavior, and action meaning.
- **Evidence:** synthetic tests cover Unicode widths, overflow boundaries, oversized selected tabs, narrow areas, and
  same-pass interaction geometry. Motel service tabs and Postcat response tabs validate unrelated product use cases.

### Lazy interactive selectable rows

- **Additive:** `SelectionViewport.fixed` projects fixed-height selections with leading, centered, or trailing
  placement without materializing row content. `SelectableRows` invokes application row and interaction closures only for
  visible indices and supplies exact same-pass `SelectableRow` geometry.
- **Ownership:** applications retain stable row identity, selection, navigation, filtering, and action meaning.
  `RowInteraction` supplies only control/action metadata; the widget retains no collection state.
- **Migration:** replace fixed-height selected-range calculations, row rectangles, selection fills, and per-row
  `InteractionRegion` construction with `SelectableRows`. Keep domain cell rendering in the row closure.
- **Evidence:** projection and rendering regressions cover boundary clamping, visible-only evaluation, multi-line row
  geometry, selection painting, and exact interaction rectangles. DiffScope file rows and Motel trace/waterfall rows
  validate large-list, domain-rendering, and modal-suppression behavior.

### Terminal-column fitting and top-origin row viewports

- **Additive:** `TerminalWidth` now clips prefixes and suffixes, truncates with an optional ellipsis, pads by alignment,
  and combines truncation and padding into exact-column fitting. `Span` and `Line` provide style-preserving
  `truncated` and `fitted` operations.
- **Additive:** `RowViewport` provides normalized top-origin row projection, a clamped visible range, boundary flags,
  and progress. `ScrollViewport.rowViewport` exposes the equivalent projection without changing its established
  end-origin behavior.
- **Migration:** replace `String.count`, `String.padding`, and local grapheme loops used for terminal alignment with
  `TerminalWidth` fitting. Replace manually clamped top-origin slices with `RowViewport.visibleRange`.
- **Evidence:** Unicode regressions cover CJK, emoji ZWJ families, combining sequences, narrow ellipses, alignment,
  CJK width policy, and styled spans. Exhaustive small-domain viewport tests cover invalid and extreme inputs.
  Postcat, DiffScope, and Motel exercise the APIs in production-shaped rendering.

### Swift-native terminal geometry

- **Supported breaking migration:** application-facing coordinates and extents now use Swift `Int`. This includes
  `Position`, `Size`, `Rect`, `Insets`, layout constraints and spacing, buffer widths, paragraph scroll offsets,
  widget dimensions, viewport heights, backend region movement, and fixed/inline session geometry.
- **Migration:** remove `UInt16(clamping:)` and `Int(...)` conversion glue from layout and rendering code. Convert only
  where a real fixed-width boundary requires it, such as `winsize`, terminal-emulator APIs, or a serialized wire
  protocol. Geometry constructors and mutable geometry fields normalize negative values to zero; rectangle edge and
  offset arithmetic saturates on integer overflow.
- **Performance:** `Position` now occupies 16 bytes and `CellUpdate` 48 bytes on 64-bit platforms. The larger hot values
  are an intentional tradeoff for native collection arithmetic and removal of pervasive client conversions.
- **Evidence:** native-range and mutation regressions cover negative normalization, mutable rectangle invariants, ANSI
  serialization, and overflow saturation; extreme constraints, fill weights, and spacing no longer overflow layout arithmetic.
  Root PTY tests, Postcat, DiffScope, ecosystem packages, Codex, and Herdr
  validate rendering, lifecycle, inline-history, fixed-viewport, and production-client behavior.

### Text, line, and empty-block construction ergonomics

- **Supported:** `Text` preserves leading and consecutive empty rows while retaining its established single
  terminal-newline behavior. `Line` accepts dynamic `[Span]` values directly. `EmptyWidget` and the constrained
  `Block<EmptyWidget>` initializer support decoration-only blocks without dummy text content.
- **Migration:** replace local span-installation helpers with `Line(spans)` and `Block<Text>(content: Text(""))`
  decoration shells with an inferred `Block(...)` or `Block<EmptyWidget>`.
- **Evidence:** focused text and widget regressions cover blank-row round trips, styled and empty span arrays,
  presentation metadata, decoration equivalence, inner geometry, and existing block initializer resolution. Postcat,
  DiffScope, ecosystem, and consumer suites validate source compatibility.

### Input routing and invalidation correctness

- **Supported behavioral corrections:** wakeup-only input polls preserve pending fragmented Escape sequences; key-release
  events remain observable without driving focus traversal or control activation; and obsolete Observation dependency
  callbacks no longer request frames.
- **Migration:** none. Repeated Tab, Enter, and Space events retain their existing interaction behavior.
- **Evidence:** focused PTY, interaction-router, and Observation-generation regressions cover each correction.

### Main-actor terminal-session lifecycle

- **Supported concurrency correction:** `TerminalSession` is now `@MainActor` instead of
  `@unchecked Sendable`. Its raw-mode, viewport, cursor-origin, prefetched-input, and restoration state has one
  compiler-enforced owner matching `TerminalApplication` lifecycle isolation.
- **Migration:** create and operate on `TerminalSession` from main-actor code. Synchronous and asynchronous
  `withTerminalSession` scopes are both main-actor isolated. Blocking terminal input remains in the detached,
  lock-isolated input pump, and transactional output remains a separately synchronized transport primitive.
- **Evidence:** the minimal Swift 6 build and real-PTY inline, fullscreen, fixed, resize, suspend/resume, input-transfer,
  and application-loop tests compile and pass without an unchecked session conformance.

### Observable terminal-scope cleanup failures

- **Supported:** synchronous and asynchronous `withTerminalSession` and suspended-action scopes now propagate failed
  restoration or resume operations. A successful body followed by failed cleanup throws the cleanup error; a failed
  body followed by successful cleanup preserves the body error.
- When both phases fail, `TerminalScopeError` retains `operationError` and `cleanupError` without exposing terminal
  control bytes in its localized description. Session deinitialization remains explicitly best-effort.
- **Evidence:** deterministic tests cover all four body/cleanup outcomes and the asynchronous path; real-PTY lifecycle
  tests cover ordinary session restoration and suspend/resume behavior.

### Frame-transaction failure recovery

- **Supported:** a failed physical frame commit now performs one unbuffered emergency epilogue that ends synchronized
  output, resets scrolling margins and SGR, reenables autowrap, and shows the cursor. If that epilogue also fails,
  `TerminalScopeError` preserves both failures.
- Session viewport state and the application runtime's terminal/backend and inline-document state are restored to their
  pre-transaction snapshots before the commit error escapes. A later retry therefore emits a complete frame instead of
  trusting logical state that may not have reached the terminal.
- Final session restoration emits the same defensive mode reset. Native-scrollback-producing line feeds remain outside
  synchronized output, and successful frame transactions still use one physical write.
- **Evidence:** deterministic partial-write tests verify the unbuffered epilogue, dual-failure reporting, and retry;
  backend and real-PTY tests preserve successful byte ordering, history restoration, and lifecycle balance.

### Native-scrollback capability semantics

- **Provisional correctness fix:** the default `InlineHistoryBackend.scrollRegionUpIntoScrollback` implementation now
  throws `BackendOperationError.unsupported("native scrollback insertion")`. It no longer substitutes visual region
  scrolling, which can discard displaced rows instead of retaining native terminal history. Backends returning `false`
  from `insertHistory` must implement the semantic native-scrollback operation for the generic fallback to succeed.
- **Migration:** custom inline-history backends that relied on the old forwarding default must implement genuine native
  scrollback insertion or allow the explicit unsupported error to propagate.
- **Evidence:** a visual-only backend fails explicitly without invoking its visual-scroll operation; explicit ANSI and
  test backends preserve their native-history behavior.

### Mapped ANSI history buffers

- **Provisional correctness fix:** ANSI history and retained-viewport serialization now read source cells relative to
  `Buffer.area`. This fixes non-zero-origin buffers without changing destination terminal coordinates or zero-origin
  output.
- **Evidence:** mapped multi-row, styled, and wide-cell history and restoration regressions verify source offsets and
  continuation-cell handling.

### Synchronized fixed-viewport ownership

- **Supported:** `TerminalSession.resizeFixedViewport(to:terminal:)` explicitly resizes a caller-owned fixed
  `Terminal<ANSIBackend>` and publishes the same rectangle to session reset, backend reconstruction, and lifecycle state
  only after the terminal resize succeeds.
- `ANSIBackend.setViewportOrigin(_:)` now updates fixed absolute-addressing metadata as well as inline absolute-origin
  addressing. Cursor destination coordinates remain absolute.
- **Evidence:** a real PTY verifies the terminal, session, backend origin, host-resize policy, and scoped reset all retain
  the replacement non-zero rectangle.

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
