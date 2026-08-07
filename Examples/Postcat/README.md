# Postcat example

A compact, keyboard-first HTTP client built as a separate Swift package against the local Ratatui products.
It is inspired by [egoist/postcat](https://github.com/egoist/postcat) (MIT), but intentionally implements a
small teaching surface rather than copying the complete application.

The example exercises fullscreen lifecycle, custom widget composition, text editing, focus policy, tabs,
scrolling, syntax highlighting, async work, cancellation, periodic redraws, overlays, cursor placement, and an
injected/testable network boundary. It composes `RatatuiTextArea` and `RatatuiOverlays` while requesting only
the root package's `SyntaxHighlighting` trait. It required no Postcat-specific additions to `Ratatui` core.

```sh
cd Examples/Postcat
# Existing explicit redraw scheduler
swift run ratatui-postcat

# Swift Observation scheduler: model mutations return .ignore and wake rendering automatically
swift run ratatui-postcat -- --observable

# Optional independently packaged diagnostics overlay (toggle with F12)
swift run --traits DevTools ratatui-postcat
swift run --traits DevTools ratatui-postcat -- --observable
```

Keys:

- `tab` / `shift-tab`, `1`-`3`: move between URL, request, and response panes
- `i`: edit the focused URL or request body; `esc` finishes editing
- `m` / `M`: cycle the HTTP method
- `s` or `enter`: send; `esc` cancels an in-flight request
- `[` / `]`: response body or headers
- `j` / `k`, `g` / `G`, `page up` / `page down`: scroll the response
- `w`: toggle response wrapping
- `?`: help; `q`: quit

The default endpoint is `https://httpbin.org/anything`. Tests inject a transport and never use the network.

## Deliberate omissions

The upstream Postcat is a complete product with saved requests, environments, key/value grids, authentication,
SSE/chunk streaming, mouse text selection, and clipboard integration. Those remain outside this teaching app.
The multiline editor and generic popup were promoted into optional sibling packages rather than HTTP-specific
core APIs.
