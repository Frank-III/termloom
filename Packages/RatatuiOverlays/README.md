# RatatuiOverlays

Popup geometry and presentation without application-specific commands or data.

```swift
import Ratatui
import RatatuiOverlays

let popup = Popup(
  layout: PopupLayout(
    size: .cells(width: 50, height: 12),
    placement: .center
  ),
  title: "Search",
  borderStyle: Style(foreground: .cyan),
  padding: .all(1)
) {
  Text("No results")
}
```

`Popup` forwards interactions and cursor metadata to its content. `PopupLayout` is a pure value and supports
cell, percentage, fill, centered, edge, and corner placement. `Overlay` composes any base and layer widgets,
renders them in order, and makes base-cursor suppression explicit. The package does not own dismissal, focus,
or application overlay state.
