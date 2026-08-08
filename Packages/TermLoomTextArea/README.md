# TermLoomTextArea

A value-semantic multiline editor for TermLoom Swift.

```swift
import TermLoom
import TermLoomTextArea

var source = TextAreaState(text: "hello\nworld")

var body: some Widget {
  TextArea(source, id: "source", showsLineNumbers: true)
}

// In the application's update function:
if source.handle(event, when: focusedControl, is: "source") {
  return .redraw
}
```

The initial package supports grapheme-safe multiline insertion/deletion, paste, cross-line selection,
Shift-selection, undo/redo, line joining/splitting, horizontal and vertical viewport reconciliation, optional
line numbers, interaction registration, and hardware cursor forwarding. Syntax semantics and filesystem
operations remain separate concerns.
