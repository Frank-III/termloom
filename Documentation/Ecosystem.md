# Core and ecosystem boundary

Ratatui Swift should be useful as a small rendering library without forcing applications to adopt chat,
HTTP, Git, telemetry, persistence, networking, or a specific state architecture. Codex, Herdr, and Motel plus
Postcat and DiffScope are production-shaped boundary tests, not templates for moving their product semantics into core.

## Current conclusion

The core is still general, with one qualification: the application/runtime surface is accumulating optional
capabilities and should now be treated as a stability boundary. Recent additions fall into three groups:

- **General primitives worth keeping in core:** `ScrollViewport`, `SelectionViewport`, cursor/focus metadata,
  typed terminal events, layout, buffers, widgets, and safe terminal lifecycle mechanics.
- **General but advanced opt-in runtime capabilities:** `InlineDocument`, `InlineViewportSizing`, and
  `PeriodicallyRedrawingTerminalApplication`. None is required by a basic app. The Postcat example exposed an
  important general invariant: when periodic work becomes idle, the runtime must render one trailing frame so
  the completed result cannot remain stuck behind a spinner.
- **Faceted backend mechanics:** the required `Backend` surface now contains only ordinary drawing, sizing,
  clearing, and cursor operations. `LineAppendingBackend` and `InlineHistoryBackend` make advanced operations
  compile-time capabilities instead of required methods with throwing defaults. `HistoryInsertionBatchPosition`
  remains scoped to the inline-history facet. An independent in-memory backend model validates its transaction
  composition, but it should stay provisional until another production native-history backend validates the
  vocabulary against real terminal behavior. The facet also accepts an optional retained viewport for final-chunk
  restoration; ANSI uses it to combine Supaterm history insertion and the synchronized live redraw into one write.

No HTTP, transcript, provider, Markdown-stability, request-library, or chat policy belongs in `Ratatui`.

The `Ratatui` target itself has no dependencies. The root package now uses SwiftPM traits to prevent optional
products from pulling unrelated transitive dependencies:

- `SyntaxHighlighting` gates the Highlight products used by `RatatuiSyntaxHighlighting`.
- `TestSupport` gates InlineSnapshotTesting and CustomDump.
- Both remain default traits for source compatibility; a consumer can request `traits: []` for core only or
  `traits: ["SyntaxHighlighting"]` for the highlighter without test dependencies.

A clean minimal consumer resolves only `ratetui-swift`; the Postcat example resolves only `swift-highlight` in
addition to the local ecosystem packages, while DiffScope uses only core and `RatatuiOverlays`. Snapshot testing,
CustomDump, and SwiftSyntax are not incidental example dependencies. The heavy macro dependency is isolated in
`RatatuiMacros`.

## Postcat boundary test

`Examples/Postcat` is a separate Swift package depending on the local framework products. It is inspired by
[egoist/postcat](https://github.com/egoist/postcat), an MIT-licensed Ratatui application. The upstream project
is a polished product of roughly 5,800 Rust lines plus 1,300 lines of end-to-end tests, not literally a tiny
example. The Swift package intentionally implements a smaller teaching surface:

- fullscreen request, response, and status layout;
- editable URL and multiline JSON body powered by `RatatuiTextArea`;
- HTTP method cycling and real `URLSession` requests;
- async loading, cancellation, error and completion states;
- JSON syntax highlighting, response headers, scrolling, wrapping, and help overlay;
- injected transport tests with no external network.

It required no HTTP-specific core APIs. It did reveal and fix the trailing-periodic-redraw invariant. That is
the desired pressure-test outcome: improve a reusable mechanic, leave request semantics in the example. It now
also consumes `RatatuiTextArea` and `RatatuiOverlays`, plus an opt-in `DevTools` trait backed by
`RatatuiDevTools`, proving the sibling packages compose in a real app without making diagnostics mandatory.
Its `--observable` mode provides a direct A/B comparison: HTTP completion, editing, navigation, and spinner ticks
mutate an `@Observable` application and return `.ignore`, while the default mode keeps the explicit redraw and
periodic-spinner scheduler.

## DiffScope boundary test

`Examples/DiffScope` is a separate, read-only Git diff viewer inspired by
[gitui-org/gitui](https://github.com/gitui-org/gitui). It intentionally stops before staging, committing,
branches, remotes, credentials, and other Git-client product semantics. Its default demonstration reproduces
the 2,188-file metadata shape of Bun PR #30412 with deterministic synthetic patches, while `--repo` uses the
installed Git executable to inspect local working-tree changes or a `--base BASE_SHA` revision range.

DiffScope exercises fullscreen alternate-screen lifecycle, responsive split/compact layouts, stable file
selection, path filtering through `TextFieldState`, async and cancellable patch loading, bounded caching,
vertical and horizontal scrolling, styled diff rows, scrollbars, popup help, and mouse selection. It required
no Git-specific framework APIs. The example requests no root SwiftPM traits and resolves only core plus
`RatatuiOverlays`, making it an additional dependency-boundary check.

## Lessons from OpenTUI

OpenTUI uses a monorepo but publishes independent packages: core, React and Solid reconcilers, keymap, QR code,
SSH hosting, Three.js rendering, examples, and web documentation. React DevTools is an optional peer dependency
loaded only in development. Its useful lesson is packaging, not copying its exact core boundary—OpenTUI core is
much broader and includes editing, Markdown, images, audio, clipboard, animations, and a console.

The Swift direction is:

- keep `Ratatui` small and behaviorally aligned with Ratatui's rendering/terminal invariants;
- publish focused packages from `Packages/` with their own manifests and tests;
- keep examples in a separate package that composes those libraries;
- isolate heavy compiler/tooling dependencies, especially SwiftSyntax;
- eventually add discoverability assets: a package catalogue, executable examples, and an agent skill;
- consider `RatatuiKeymap`, `RatatuiQRCode`, and an SSH terminal host only after real clients establish APIs.

## Ecosystem shape

Popular Rust Ratatui applications commonly compose focused crates instead of growing the core framework. Swift
should follow the same model. Optional libraries can live alongside this repository or in a workspace, but
must remain separate products/packages with independent dependencies and release cadence.

| Rust ecosystem role | Swift status | Recommended package |
| --- | --- | --- |
| `tui-input` | Single-line `TextFieldState` exists in core | Keep the basic field in core |
| `tui-textarea` / `ratatui-textarea` | Initial multiline editor, selection, undo, viewport package built | `RatatuiTextArea` |
| `tui-popup` / command palettes | Popup geometry/presentation package built | `RatatuiOverlays` |
| `tui-tree-widget` | Missing hierarchical expansion and navigation | `RatatuiTree` |
| `ratatui-image` | No Kitty/Sixel/iTerm2 protocol abstraction | `RatatuiImage` |
| `tui-logger` | No log store, filtering, levels, tail-follow widget | `RatatuiLogger` |
| `ratatui-explorer` | Filesystem semantics correctly absent from core | `RatatuiFileExplorer` |
| `ratatui-themes` | Styles exist; semantic theme catalogs do not | `RatatuiThemes` |
| `tui-big-text`, throbbers, extra charts | Some metrics exist; decorative widgets vary | `RatatuiWidgets` |
| Markdown/rendering crates | Codex currently owns Markdown semantics | `RatatuiMarkdown` only after a second client |
| Form/grid crates | Tables exist, editable forms do not | `RatatuiForms` |
| OpenTUI console / React DevTools | Initial metrics/log panel and optional overlay built | `RatatuiDevTools` |
| Declarative framework adapters | Result builders exist; forwarding boilerplate remained | `RatatuiMacros` |

`RatatuiSyntaxHighlighting` and `RatatuiTestSupport` demonstrate conditional products within the root package.
`RatatuiTextArea`, `RatatuiOverlays`, `RatatuiDevTools`, and `RatatuiMacros` are independent sibling packages.
The macro package provides `@WidgetComponent`, which forwards all four `Widget` passes to `body`; result builders
remain the primary construction API, and core consumers never resolve SwiftSyntax.

## Priority

1. **Harden the new sibling packages.** Add composition examples and terminal coverage for `RatatuiTextArea`,
   `RatatuiOverlays`, `RatatuiDevTools`, and `RatatuiMacros` before expanding their APIs.
2. **External-event wakeup.** Observation invalidations now wake the input poll immediately and coalesce into a
   whole-frame diff. A public event source may still be useful for non-observable network streams and file
   watchers; do not turn it into per-widget signal repainting.
3. **Backend capability facets.** Replace required optional operations and the exposed history batch state before
   declaring the backend protocol stable.
4. **Selectable text and clipboard adapters.** Keep OSC 52 and platform clipboard effects optional and explicit.
5. **Keymap next.** OpenTUI and Codex both show demand for commands, key sequences, conflict detection, and
   discoverable help, but the package should be extracted from at least two clients rather than invented in core.
6. **Forms/grids, tree, file explorer, images, logger, themes, QR, and SSH hosting** as independent examples
   establish demand.

## Admission rules

A feature belongs in core only when all of these hold:

1. At least two unrelated application categories need the same terminal invariant or rendering primitive.
2. The API can be described without product nouns such as transcript, request, agent, session, or provider.
3. A basic counter or dashboard does not pay dependency, state, or lifecycle costs for the feature.
4. Unsupported backends have an explicit capability story rather than required methods that merely throw.
5. The behavior can be validated with deterministic buffer tests and, where terminal state is involved, PTYs.

Otherwise it belongs in an optional package or the application.
