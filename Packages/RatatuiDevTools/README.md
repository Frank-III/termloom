# RatatuiDevTools

An opt-in diagnostics state and panel for frame timing, changed-cell/output counts, terminal size, and bounded
runtime logs.

```swift
import RatatuiDevTools

var devTools = DevToolsState()
devTools.terminalSize = Size(width: 120, height: 40)
devTools.record(frameMilliseconds: 4.2, changedCells: 18, outputBytes: 240)
devTools.log("request completed")

let panel = DevToolsPanel(devTools)
```

The default `Overlays` trait adds `DevToolsOverlay`, a ready-made popup backed by `RatatuiOverlays`:

```swift
.package(
  path: "../RatatuiDevTools",
  traits: ["Overlays"]
)
```

Disable defaults to use only the diagnostics model and panel without resolving `RatatuiOverlays`. Instrumenting
an application is explicit today; an automatic runtime instrumentation hook should be designed only after more
than one client establishes the required measurements.
