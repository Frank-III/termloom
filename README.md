# TermLoom — a Swift-native terminal UI framework

TermLoom is an independent Swift framework inspired by Ratatui's rendering lessons; it is not an official Ratatui
binding or a transliteration of Rust APIs. The project asks a different question than “how do we translate Ratatui?”:

> What would a terminal UI framework look like if Ratatui supplied the rendering lessons, but
> Swift and Point-Free supplied the API design lessons?

The first slice already demonstrates the intended split:

```swift
Block(title: "Processes") {
  VStack(spacing: 1) {
    Text("Live").bold().frame(.length(1))
    Table(processes, selectedRow: selection) {
      TableColumn("Name", value: \.name, width: .flex(2))
      TableColumn("CPU", value: \.cpu, alignment: .trailing) { "\($0)%" }
    }
  }
}
```

- Key paths keep table projections rooted in the row type.
- Result builders flatten heterogeneous declarations into arrays at a coarse semantic boundary.
- Widgets are erased once per widget, while cells remain compact values in contiguous storage.
- Rendering is immediate and deterministic; the terminal only emits changed cells.
- The core has no global state, observation, or dependency lookup in its hot path.

Interactive applications own typed state and reduce terminal events into an explicit redraw
decision:

```swift
@MainActor
final class Counter: TerminalApplication {
  var count = 0
  var body: some Widget { Text("Count: \(count)") }

  func update(_ event: TerminalEvent) async -> ApplicationUpdate {
    guard event == .key(KeyEvent(.up)) else { return .ignore }
    count += 1
    return .redraw
  }
}

let counter = Counter()
try await counter.run(viewport: .inline(height: 3))
```

Long-running inline applications can expose canonical history without tracking terminal offsets:

```swift
func inlineDocument(size: Size) -> InlineDocument<String>? {
  InlineDocument(
    id: sessionID,
    blocks: messages.map {
      InlineDocumentBlock(
        id: $0.id,
        text: renderStableRows($0, width: size.width),
        isComplete: $0.isComplete
      )
    }
  )
}
```

The default runtime is inline: it reserves a live region inside ordinary command output, switches
stdin to raw mode for the scoped session, decodes fragmented escape sequences, handles bracketed paste,
mouse, focus and resize events, redraws only when requested, and restores terminal state on exit. It can
resize the retained region through the opt-in `InlineViewportSizing` capability. Starting a
content-fitting application with `.inline(height: 1)` avoids reserving its maximum height up front; the
viewport grows from its stable origin and only scrolls when it reaches the physical bottom. Width changes
reanchor at column zero and purge reflowed owned rows from scrollback and the
visible screen before a complete redraw, preventing stale or duplicated inline frames after rapid
terminal resizing. Applications can expose a canonical `InlineDocument` made of stable, identified blocks. Its runtime
inserts only appended rows above the retained viewport, waits at mutable ordering boundaries, and owns
reset-and-replay after source rewrites, document replacement, or width reflow. Applications still decide
what is semantically stable. Lower-level clients can emit `TerminalHistoryInsertion` values directly or
call `Terminal.insertBefore` themselves.
History insertion is distinct from ordinary visual region scrolling: standard terminals use
bottom-margin CRLF insertion, while Supaterm, Zellij, and tmux use a conservative whole-terminal output
path that clears the live pane, writes real history rows without DECSTBM margins or synchronized-output
wrapping, reserves blank live rows, and forces one complete redraw. Keeping the scrolling write outside
CSI `?2026` is required for Ghostty-family hosts to commit each CRLF to native scrollback. Ordinary
`scrollRegionUp` retains its CSI `S` semantics.
Mouse capture is opt-in (`run(viewport:capturesMouse:)`), so inline applications preserve native
terminal text selection and copy by default. The interaction router only consumes Tab for focus traversal when focusable controls exist, leaving application-level completion and queue bindings intact. Input polling runs away from the main actor so async dependencies and observable models keep
progressing. A fullscreen alternate-screen viewport remains available when an application actually
wants it.

Included widgets and controls:

- `Text`, styled `Span`/`Line`, and wrapping/scrolling `Paragraph`
- Multi-title/selective-border `Block` with exact/fuzzy border merging, `Fill`, `Clear`, `VStack`,
  and `HStack`
- Key-path-driven `Table` and `List`, stateful scrolling variants, plus `Tabs`
- `Gauge`, `Sparkline`, grouped/directional `BarChart`, stateful edge-aware `Scrollbar`, and
  event-styled `Monthly` calendar
- Multi-resolution `Canvas` shapes and world maps, rich coordinate labels, sextant/octant markers, ordered result-builder layers, and axis/legend-aware `Chart` datasets
- Focusable `Button`, `Checkbox`, `RadioButton`, and editable `TextField` controls
- Grapheme-safe `TextFieldState` with selection, word movement, paste, horizontal scrolling, and
  state-derived hardware cursor placement
- Unicode-aware terminal-column clipping, ellipsis, alignment padding, and style-preserving `Span`/`Line`
  fitting, plus pure top-origin and end-origin row viewport geometry
- Point-Free inline snapshot helpers for exact-width terminal buffers and readable ANSI streams
- `TermLoomSyntaxHighlighting`, an optional pure-Swift 192-language highlighter that emits styled
  terminal spans, maps paths to languages, includes the Codex theme catalog, and parses custom
  TextMate `.tmTheme` files without coupling the core renderer to a syntax engine

SwiftPM traits keep transitive dependencies conditional. `SyntaxHighlighting` and `TestSupport` are enabled by
default for compatibility, but a core-only consumer can opt out completely. Until the first release candidate is
tagged, depend on the public development branch:

```swift
.package(
  url: "https://github.com/Frank-III/termloom.git",
  branch: "main",
  traits: []
)
```

Request only `traits: ["SyntaxHighlighting"]` when using that product. This does not resolve snapshot,
CustomDump, or SwiftSyntax dependencies.

Independent packages live under [`Packages/`](Packages):

- `TermLoomTextArea` — multiline editing, selection, undo/redo, and viewport state
- `TermLoomOverlays` — popup geometry and metadata-preserving presentation
- `TermLoomDevTools` — frame metrics, logs, and a trait-gated popup
- `TermLoomMacros` — optional `@WidgetComponent` ergonomics, isolated with SwiftSyntax

This mirrors an important Point-Free technique: preserve type information where it prevents invalid
programs, then deliberately erase or flatten where deeply nested generic types would hurt compiler
performance. State, event routing, observation, and dependency integration remain layers over this
renderer rather than responsibilities of `Cell` or `Buffer`. Colors and modifiers are packed into a
16-byte `Style`; display-width metadata stays inside the resulting 32-byte `Cell`, keeping ordinary
double buffers contiguous and modest without weakening the public types.

Editable controls are ordinary value state, so they compose with Observation or any other model
layer without putting reference lookups in the renderer:

```swift
var query = TextFieldState()
var focusedControl: ControlID?

var body: some Widget {
  TextField(query, id: "query", placeholder: "Filter processes")
}

func update(_ event: TerminalEvent) async -> ApplicationUpdate {
  if case .focusChanged(let control) = event { focusedControl = control }
  return query.handle(event, when: focusedControl, is: "query") ? .redraw : .ignore
}
```

Swift Observation is supported without adopting SwiftUI's retained view lifecycle. Reads from an `@Observable`
model invalidate one complete TermLoom frame; an internal wakeup pipe interrupts the input poll immediately,
and repeated mutations coalesce before the ordinary buffer diff:

```swift
@Observable
final class Model {
  var status = "ready"
}

final class App: TerminalApplication {
  let model = Model()
  var body: some Widget { Text(model.status) }
  // Mutating model.status from async work schedules a frame automatically.
}
```

There is intentionally no TermLoom-specific `@State`: application state remains normal Swift value/reference
state, and widgets do not acquire a hidden reconciliation identity. Applications that already own a complete
explicit event/stream scheduler can return `false` from `automaticallyTracksObservableState` to prevent duplicate
frames while retaining the ordinary immediate-mode runtime. Run `swift run termloom-observation` for a live demo:
its timer and key handlers mutate an `@Observable` model while deliberately returning `.ignore`, with no periodic
redraw protocol.

Offscreen and remote renderers can use the same dependency tracking through
`ObservationInvalidationTracker`. Wrap each complete presentation/render transaction with `track`, then wake the
renderer from its `onChange` callback; the callback is one-shot and the next render rearms the current dependency
set. This keeps terminal-attached and daemon-owned render loops on the same Observation semantics without imposing
a TermLoom transport protocol.

The [API stability policy](Documentation/APIStability.md) defines the supported nucleus, provisional surfaces,
deprecation process, and public-symbol review gate. The [public API audit](Documentation/PublicAPIAudit.md)
compares access-control decisions with Ratatui Rust. [API changes](Documentation/APIChanges.md) records migration
notes until tagged releases provide a generated changelog. The [performance guide](Documentation/Performance.md)
documents frame, primitive, memory-retention, and ANSI-output benchmarks. The [ecosystem guide](Documentation/Ecosystem.md)
documents package boundaries and the admission rule for core. The source-backed
[capability map](Documentation/Parity.md) records what is complete and keeps validation work separate from feature
parity. The [complementary TermLoom/Codex audit](Documentation/ComplementaryAudit.md) classifies stress-client
findings by framework mechanics versus application policy. The 0.2 candidate freezes the single-pass `Frame` contract, Swift-native terminal geometry, fixed/fullscreen/inline
viewport semantics, and the current backend capability facets. Remaining post-0.2 work is deliberately narrower: a
broader physical-terminal matrix, validation of provisional native-history batching with another production backend,
and continued allocation/output benchmarking.

Run it with the mise-managed Swift toolchain:

```sh
mise exec -- swift test
mise exec -- swift run termloom-demo
mise exec -- swift run termloom-counter
mise exec -- swift run termloom-gallery
mise exec -- swift run termloom-observation
mise exec -- swift run -c release termloom-benchmark

# Validate all sibling packages and conditional dependency boundaries
Scripts/test-ecosystem.sh

# Separate example package: a compact, real HTTP client
cd Examples/Postcat
swift run termloom-postcat

# Fullscreen large-diff browser; defaults to a Bun #30412 demonstration
cd ../DiffScope
swift run termloom-diffscope
swift run termloom-diffscope --repo /path/to/repository
swift run termloom-diffscope --repo /path/to/pr-head --base BASE_SHA
```

[`Examples/DiffScope`](Examples/DiffScope) is a read-only, GitUI-inspired stress client for responsive
panes, filtering, async detail loading, large selectable collections, styled diffs, scrollbars, mouse
actions, overlays, and alternate-screen lifecycle. Its deterministic default dataset reproduces the
2,188-file shape of Bun PR #30412 without downloading or bundling that pull request.

The [core and ecosystem boundary](Documentation/Ecosystem.md) explains which capabilities stay in the basic
framework, which should be optional sibling packages, and what the examples reveal during review.

Rendering tests can snapshot a complete buffer without losing trailing cells:

```swift
import TermLoomTestSupport

assertWidget(
  Paragraph("ready\nrunning", wrap: .none),
  size: Size(width: 8, height: 2)
)
```

Record mode generates the trailing closure in place. Each row is framed with `│`, so viewport width
and trailing whitespace remain visible in ordinary source diffs. Focused invariants still use Swift
Testing and `CustomDump`; snapshots cover spatial compositions and protocol streams where an
isolated assertion would hide the whole rendered result.

Record or refresh inline snapshots with:

```sh
SNAPSHOT_TESTING_RECORD=all mise exec -- swift test
```

See [Testing terminal output](Documentation/Testing.md) for the project-wide assertion policy and
stateful-widget examples.

## Acknowledgements

TermLoom is an independent Swift implementation built to learn from and test ideas established by other open-source
projects:

- [Ratatui](https://github.com/ratatui/ratatui) and its predecessor
  [tui-rs](https://github.com/fdehau/tui-rs) are the primary references for terminal rendering behavior, widgets, and
  backend invariants.
- [Point-Free](https://github.com/pointfreeco)'s Swift libraries influenced the value-oriented API design, dependency
  boundaries, and snapshot-testing approach.
- [swift-highlight](https://github.com/danelyan/swift-highlight) provides the optional syntax engine;
  [Highlightr](https://github.com/raspu/Highlightr) and
  [two-face](https://github.com/CosmicHorrorDev/two-face) informed syntax and theme research.
- [Ghostty](https://github.com/ghostty-org/ghostty) provides important terminal-behavior references used during PTY and
  real-terminal validation.

TermLoom is not affiliated with or endorsed by those projects. Their names and links identify inspiration and
behavioral references, not copied ownership.
