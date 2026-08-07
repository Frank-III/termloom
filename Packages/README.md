# Ratatui Swift ecosystem packages

These are independent Swift packages that depend on the zero-dependency `Ratatui` product. Keeping them
separate lets applications opt into focused capabilities without expanding the core API or dependency graph.

| Package | Purpose | Extra dependency cost |
| --- | --- | --- |
| [`RatatuiOverlays`](RatatuiOverlays) | Popup geometry and presentation | None |
| [`RatatuiTextArea`](RatatuiTextArea) | Multiline editor state and widget | None |
| [`RatatuiDevTools`](RatatuiDevTools) | Frame metrics, logs, diagnostics panel | Optional `Overlays` trait |
| [`RatatuiMacros`](RatatuiMacros) | `@WidgetComponent` forwarding macro | SwiftSyntax, isolated here |

Each package has its own manifest and tests. Run the complete matrix from the repository root:

```sh
Scripts/test-ecosystem.sh
```

The layout follows the useful part of OpenTUI's model: a stable core, independent adapters/tools, explicit
examples, and optional developer integrations. It intentionally avoids moving every useful component into the
core package.
