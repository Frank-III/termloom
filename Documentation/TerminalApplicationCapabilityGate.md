# TerminalApplication capability design gate

Plan 016 evaluated whether `TerminalApplication` should shrink to body, update, redraw policy, and explicit optional
capabilities before TermLoom Swift 0.2. The source change is rejected for this release.

## Candidate shape

The spike separated three concerns:

```swift
@MainActor
protocol TerminalApplication: AnyObject {
  associatedtype Body: Widget
  var body: Body { get }
  var automaticallyTracksObservableState: Bool { get }
  func update(_ event: TerminalEvent) async -> ApplicationUpdate
}

@MainActor
protocol InlineDocumentTerminalApplication: TerminalApplication {
  associatedtype InlineDocumentID: Hashable & Sendable
  func inlineDocument(size: Size) -> InlineDocument<InlineDocumentID>?
  func terminalHistoryDidReset()
}

@MainActor
protocol SuspendedTerminalApplication: TerminalApplication {
  func performSuspendedAction() async
}
```

`InlineViewportSizing` and `PeriodicallyRedrawingTerminalApplication` already demonstrate that capabilities without an
associated type can be discovered dynamically without affecting widget or action types.

## Client matrix

| Applications | Core only | Periodic redraw | Inline sizing/document | Suspension |
| --- | --- | --- | --- | --- |
| Counter, Gallery, Observation demo | yes | no | no | no |
| DiffScope | yes | no | no | no |
| Postcat | yes | yes | no | no |
| Motel | yes | no | no | no |
| Herdr local and remote | yes | no | no | no |
| Codex | yes | yes | yes | yes |

The fullscreen applications currently get all optional hooks from defaults and therefore write no source-level glue.
Only Codex supplies a source-backed document and suspended operation. TermLoom's PTY fixtures additionally exercise
pending direct history insertion and reset behavior.

## Rejection evidence

`TerminalApplication.run()` must retain one `InlineDocumentRuntime<ID>` across frames. If the associated ID moves to an
optional capability, a runtime generic only over `TerminalApplication` cannot store the opened existential's concrete
ID type across loop iterations. The viable alternatives all violate the plan's gate:

1. Erase every document ID and document into a boxed runtime value, adding identity type erasure and conversion glue to
   the only production inline client.
2. Add separate fullscreen and inline `run` entry points or overloads, making callers choose lifecycle behavior and
   risking duplicated terminal restoration logic.
3. Thread the capability's associated type through a generic runner and every call site, which preserves the generic
   propagation the split was intended to remove.
4. Keep the associated type on `TerminalApplication`, which is the current design (`Never` by default) and does not
   produce the proposed minimal protocol.

Splitting only suspension or pending-history callbacks is mechanically possible, but adds protocol vocabulary and a
Codex conformance without simplifying any fullscreen declaration or resolving the associated-type boundary. It is not
a worthwhile partial migration.

## Decision

Preserve the current protocol for 0.2. Its default `InlineDocumentID == Never` and no-op hooks keep fullscreen clients
source-minimal, while the single generic runner retains typed document identity and one restoration path. Revisit only
if a second source-backed inline client proves a shared type-erased document boundary or Swift gains a way to preserve
an opened associated type across the stored runtime loop without boxing.
