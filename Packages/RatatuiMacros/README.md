# RatatuiMacros

Optional compile-time ergonomics for Ratatui Swift. This package is separate so ordinary Ratatui users never
resolve or compile SwiftSyntax.

```swift
import Ratatui
import RatatuiMacros

@WidgetComponent
struct EmptyState {
  var message: String

  var body: some Widget {
    VStack {
      Text(message, alignment: .center)
      Button("Retry", action: "retry")
    }
  }
}
```

`@WidgetComponent` synthesizes `Widget` conformance and forwards rendering, interactions, cursor position, and
cursor style to `body`. It deliberately does not synthesize state, event handling, layout policy, or an
application runtime. Result builders remain the primary view-construction API; the macro only removes protocol
forwarding boilerplate.
