# Architecture: Swift first, TermLoom informed

TermLoom is the behavioral reference for terminal correctness: cells, clipping, Unicode width,
double buffering, minimal diffs, layout, and backend separation. It is not the API template.

The API template comes from studying Point-Free's current libraries locally:

- StructuredQueries keeps columns rooted with key paths and primary associated types, but its
  result builder intentionally flattens fragments to arrays. It also documents an explicit `#sql`
  escape hatch for cases where generic query expressions become expensive for the compiler.
- Dependencies captures a dependency context and resolves task-local overrides at access time.
  That is excellent at feature boundaries and inappropriate inside a cell-rendering loop.
- CasePaths turns enum cases into composable key-path-like values. That is a natural future model
  for typed routes, focus destinations, commands, and modal state.
- SwiftNavigation combines Observation with type-erased bindings at a deliberate reference
  boundary. It can power invalidation without making every widget an observable reference type.
- IdentifiedCollections maintains stable identity and collection invariants while retaining fast
  indexed access. The same principle should govern focusable and stateful children.
- Sharing and SQLiteData compose dynamic-member projection, shared observation, and type-safe
  query results. A TUI feature should be able to render those values directly; the renderer should
  not know where they came from.

## Runtime layers

```text
Feature state (Observation, @Dependency, @FetchAll, @Shared)
        │ invalidation + typed actions
        ▼
Application runtime (events, focus, commands, scheduling)
        │ renders when dirty
        ▼
Widget declarations (key paths + builders, flattened once)
        │ immediate render
        ▼
Contiguous Buffer<Cell> ── diff ──> Backend
```

The layering is the performance feature. Observation avoids unnecessary frames. The retained pair
of buffers avoids unnecessary output. Coarse type erasure prevents compiler blow-ups. The cell
loop is plain value manipulation with no dependency lookup, reflection, environment traversal, or
per-cell existential dispatch.

## Intended application DX

The framework should allow Point-Free libraries to compose naturally without owning application
architecture:

```swift
@Observable
final class ProcessesModel {
  @ObservationIgnored @Dependency(\.processClient) var processClient
  @ObservationIgnored @FetchAll(Process.order(by: \.cpu.desc)) var processes

  var selection: Process.ID?
}

struct ProcessesView: Widget {
  let model: ProcessesModel

  func render(in area: Rect, into frame: inout Frame) {
    frame.render(
      Table(model.processes, selectedRow: model.selectedIndex) {
        TableColumn("Name", value: \.name, width: .flex(2))
        TableColumn("CPU", value: \.cpu, alignment: .trailing) { "\($0)%" }
      },
      in: area)
  }
}
```

The runtime tracks observable reads from both presentation construction and the complete widget render
transaction, then coalesces invalidations and redraws. A widget may therefore read `model.processes`
inside `render`; it does not need an eager snapshot getter solely to register Observation. Tests can
override `processClient` and the database independently. None of that enlarges `Cell` or changes the
backend.

## Near-term design rules

1. Make impossible states hard to express at feature boundaries using key paths, enums, IDs, and
   primary associated types.
2. Flatten builders into arrays of render records rather than preserving arbitrarily deep generic
   trees.
3. Add macros only to eliminate boilerplate after the underlying protocol is proven.
4. Keep focus, editing, and terminal-input mechanics framework-owned, with stable IDs and semantic actions; keep
   product state and action meaning application-owned.
5. Preserve inline rendering as a first-class mode; alternate-screen applications are not the only
   kind of real TUI.
6. Measure allocation count, changed-cell count, compile time, and bytes written independently.

## Implemented runtime boundary

`TerminalApplication` is main-actor isolated and converts `TerminalEvent` values into `.redraw`,
`.ignore`, or `.quit`. Its update function is async, so Dependencies clients and other structured
concurrency work compose naturally. A detached, lock-isolated input pump is the only blocking
piece. The runtime owns raw-mode scope, event polling, resize-triggered redraws, cursor state, and
terminal restoration. Scoped session and suspension helpers run cleanup exactly once: cleanup failure replaces a
successful body, while `TerminalScopeError` preserves both errors when the body and cleanup fail. Deinitialization
remains best-effort because it cannot report errors. Frame output is buffered into one physical write; failed commits
perform an unbuffered terminal-mode recovery epilogue and roll session, terminal/backend, and inline-document state
back to their pre-transaction snapshots before propagating the error. Idle applications remain event-driven.

Presentation and widget-render reads are wrapped in Swift Observation access tracking. A mutation of an
`@Observable` model marks the next complete frame dirty and signals an internal nonblocking pipe included in
the input poll, so the loop wakes immediately rather than waiting for its polling timeout. Repeated mutations
coalesce behind one invalidation bit. Periodic-only frames reuse their armed access registrations rather than
accumulating new one-shot Observation callbacks; event-driven and observed changes refresh the dependency set.
TermLoom still performs an ordinary whole-frame buffer render and changed-cell diff; it does not build a signal
graph or repaint individual widget subtrees.

This deliberately adopts `@Observable`, which is a zero-dependency Swift language/runtime facility, without
imitating SwiftUI's `@State` storage and retained view-identity lifecycle. Automatic tracking is enabled by
default; mature applications with an explicit redraw scheduler can opt out through
`automaticallyTracksObservableState` to avoid duplicate or transient intermediate frames. In the release dashboard benchmark,
5,000 120×40 frames measured about 12.6k frames/s both with and without the two access-tracking scopes; buffer
construction and diffing still dominate. Timers or external sources that are not observable can opt into
`PeriodicallyRedrawingTerminalApplication`; redraws occur only while its flag is active, plus one trailing frame
when work becomes idle.

`InputParser` accepts arbitrary byte chunks rather than assuming one `read` equals one key. It
retains incomplete CSI sequences, distinguishes a standalone Escape using a timeout, parses xterm
modifiers and SGR mouse reports, and accumulates bracketed paste until its terminator arrives. The
parser remains a value with deterministic tests; only `TerminalInput` performs POSIX polling and
reads. Runtime viewport rebuilds keep one input pump and rebase its physical-to-local mouse transform
in place, preserving partial escape sequences, queued burst events, and the last observed window size.
Cursor-probe leftovers are transferred exactly once rather than replayed whenever a backend is rebuilt.

Widgets perform one immediate presentation pass into `Frame`, which owns the mutable cell buffer, render
environment, interaction regions, and hardware-cursor metadata. Controls register stable `ControlID` values and
local hit regions through arbitrary builder/stack/block nesting during that pass. `InteractionRouter` owns
reconciliation, Tab/Shift-Tab traversal, mouse focus, and Enter/Space activation, and sends `ActionID` values back
to the application. Type erasure and compositional containers forward one render call rather than repeating layout
for metadata queries. Stateful widgets can derive cursor position and style while reconciling application-owned
state. Terminal resets and dynamic inline-height changes preserve stable focus identity instead of treating backend
reconstruction as a new application.

Fixed rendering uses exact terminal coordinates without owning the alternate screen or inline history. A standalone
fixed `Terminal` resizes through `Terminal.resize(to:)`; a terminal associated with `TerminalSession` resizes through
`TerminalSession.resizeFixedViewport(to:terminal:)` so terminal buffers, ANSI backend origin metadata, and the session
lifecycle rectangle remain synchronized.

Inline rendering keeps widget coordinates local `(0, 0)` while the backend stores an explicit
physical viewport origin. `Terminal.insertBefore(height:_:)` uses scrolling regions to insert log
or history rows above the live viewport without clearing it. Its generic fallback still requires a genuine
native-scrollback operation; a conformer that supplies only visual region scrolling fails explicitly as unsupported.
Mouse localization is rebased whenever insertion or dynamic sizing moves that physical origin. Large
canonical replays are grouped into bounded buffers and carry batch positions; whole-terminal history
backends clear the live pane once, stream continuation chunks, and reserve composer rows only after the
last chunk. This avoids thousands of blank-row reservations during a resumed session while bounding render
memory. During an ordinary application frame, dynamic viewport mutation, history insertion, and the final
draw are buffered into one terminal write. This follows Codex Rust's host-level synchronized draw boundary
without putting native-scrollback line feeds inside synchronized-output mode, which Ghostty-family hosts may
otherwise omit from scrollback. If the coalesced physical write fails, an unbuffered defensive epilogue closes
synchronized output and resets margins, styles, wrapping, and cursor visibility. Session viewport state,
terminal diff/backend state, and inline-document reconciliation roll back to their pre-frame snapshots so a
caller-driven retry emits a complete update. A scrollback reset already leaves the cursor at the known home position, so
TermLoom rebuilds the inline reservation from row zero instead of issuing a competing cursor-position query
while the asynchronous input pump is active. Terminal protocol setup is session-scoped: resets do not stack
extra Kitty keyboard pushes, so final restoration balances the original push exactly once.

`TextFieldState` also supports identified atomic elements. Cursor motion skips element interiors,
intersecting deletion expands to the complete element, edits before/after it preserve ranges, and callers
expand semantic payloads by identity. This is reusable composer mechanics; Codex owns the policy that a
large paste becomes such an element and the payload associated with its ID.

## API pressure found by the Codex client

Codex is intentionally a stress client, not an API template. Its current size highlights where the
framework boundary is making an application repeat mechanics:

- `CodexApplication` previously carried roughly 230 lines of emitted-history IDs, source offsets,
  replay keys, reset detection, and overlay deferral. `InlineDocument` and `InlineDocumentRuntime` now
  own rendered-prefix tracking, mutable ordering boundaries, width-dependent replay, canonical rewrite
  detection, and document identity. Codex only declares stable identified blocks and its mutable live
  tail; the semantic decision that a Markdown line is stable remains application policy. Very large
  documents may provide an optional monotonic `revision`: an unchanged revision at the same identity and
  width bypasses stable-block comparison, while width changes still force canonical replay. The revision
  is an application-owned correctness promise and remains `nil` by default.
- `CodexScreen` is large partly because every picker repeats popup allocation, selection rendering,
  footer replacement, cursor placement, and event routing. The pure `SelectionViewport` computes contiguous
  windows from variable rendered row heights, so wrapped descriptions keep the highlighted item visible and
  preserve absolute numbering without mutating observed state during rendering. `ScrollViewport` provides the
  complementary end-anchored row window for pre-rendered logs and transcript pagers, avoiding measurement or
  rendering of off-screen rows. A future framework `Menu`/`Popup` presenter should compose these mechanisms
  without owning Codex's commands or data.
- `TerminalApplication` retains defaulted inline-history and suspension hooks for 0.2. The capability-splitting
  spike in `TerminalApplicationCapabilityGate.md` found that moving the document ID to an optional protocol requires
  identity erasure, separate run entry points, or generic propagation through the runner. Fullscreen clients already
  inherit no-op defaults without source glue, so the current single typed lifecycle remains the smaller practical
  boundary until a second source-backed inline client changes that evidence.
- A generic `clear` effect must not hide `CSI 3 J`. The runtime now distinguishes safe
  `clearViewport` from explicit `resetTerminalHistory`; application-owned history replay and full
  terminal scrollback purge should remain visibly destructive operations.
- Resize results must distinguish a viewport-only clamp from a destructive history reset. Treating
  both as one Boolean made height-only resizes replay already-retained rows and duplicate scrollback;
  `TerminalResizeDisposition` now carries that distinction. Content-sized inline applications opt into
  the separate `InlineViewportSizing` capability instead of adding another requirement to every
  `TerminalApplication`.
- Optional backend mechanics are capability facets: `LineAppendingBackend` owns physical line emission and
  `InlineHistoryBackend` owns native-history insertion and region movement. The base `Backend` remains limited to
  ordinary drawing, size, clearing, and cursor operations. Unsupported native scrollback fails explicitly rather than
  degrading to visual scrolling.

### Recommended Swift-first direction

1. Continue hardening the implemented `InlineDocument` runtime with a second independent client and
   consider a higher-level document-plus-live-widget presentation type. The current runtime already owns
   emitted IDs, width replay, overlay deferral through `nil` snapshots, and viewport synchronization;
   applications retain source stability and semantic replacement.
2. Continue replacing coarse lifecycle callbacks with explicit effects. `clearViewport` and
   `resetTerminalHistory` are now distinct; suspended operations and custom document rebuild effects can
   become typed payloads in a future source-breaking revision.
3. Add a reusable popup/menu presenter that composes an anchor widget, filtered/scrolling selection,
   and footer policy. Do not add Codex-specific overlays to TermLoom.
4. Keep Markdown streaming, provider lifecycle, transcript semantics, slash commands, and skill/file
   resolution outside core TermLoom. They may become separate packages after a second independent client
   proves the abstraction.

### Remaining architectural risks

- `InlineHistoryBackend` remains provisional until a second production backend validates its batching and native
  scrollback transaction vocabulary.
- `resetTerminalHistory` deliberately emits `CSI 3 J`; ordinary clearing cannot invoke it, but an explicit
  reset can erase shell scrollback outside the application's semantic history.
- A policy-free `Menu`/`Popup` presenter is not yet proven by a second independent client. TermLoom should
  own placement, clipping, variable-height visibility and actions, never Codex filtering or commands.
- PTY tests now cover the real application loop, render-only Observation, burst input across reset,
  mouse rebasing, dynamic-height overflow, focus preservation, and protocol balance. Emulator-native
  scrollback/reflow still needs attested coverage across standard terminals, Ghostty-family hosts, and
  tmux/Zellij.
