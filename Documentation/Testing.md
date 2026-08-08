# Testing terminal output

`TermLoomTestSupport` is a separate library product for tests. It depends on Point-Free's
InlineSnapshotTesting package; the production `TermLoom` target does not.

## Pick the assertion by behavior

- Use `assertWidget(_:size:)` for an ordinary widget. It creates the buffer, renders the widget,
  and records the exact viewport inline.
- Use `assertWidget(_:size:state:)` when rendering must reconcile a `StatefulWidget` value. The
  state remains available for focused assertions after rendering.
- Use `assertTerminal(_:)` when a test already owns a buffer, such as overlapping renders or backend
  operations.
- Use `assertTerminalCodes(_:)` for ANSI output. Escape and carriage-return bytes become readable
  tokens in the snapshot.
- Use `#expect` for scalar behavior such as cursor positions, dimensions, and modifier membership.
- Use CustomDump's `expectNoDifference` for structural values and `expectDifference` for mutations.

All terminal snapshots frame rows with `│`. This makes viewport width and trailing blank cells
visible in source diffs.

## Public API review gate

`Scripts/check-api.sh` builds Swift symbol graphs and compares TermLoom against the normalized baseline in
`Documentation/API/TermLoom.json`. Additive declarations pass; removed or changed declarations, conformances,
inheritance, and availability fail.

```sh
Scripts/check-api.sh
```

For an intentional reviewed change, first follow `Documentation/APIStability.md`, record migration notes in
`Documentation/APIChanges.md`, and then refresh the baseline:

```sh
Scripts/check-api.sh --update
```

Review the baseline diff like source code. Do not update it merely to make a failure disappear.

## Consumer contract matrix

The local workspace matrix validates core, all sibling ecosystem packages, Postcat's explicit and Observation
paths, and—when their sibling checkouts are present—the Codex, Motel, and Herdr stress clients:

```sh
Scripts/test-consumers.sh
```

Use `--skip-codex`, `--skip-motel`, or `--skip-herdr` when another writer is actively changing that checkout.
Override checkout locations with `TERMLOOM_CODEX_PATH`, `TERMLOOM_MOTEL_PATH`, and `TERMLOOM_HERDR_PATH`. A missing
optional checkout is reported and skipped; a present checkout must pass formatting and its complete test suite.

## 0.2 release-candidate matrix

Run the frozen candidate from a clean TermLoom checkout:

```sh
swift format lint --strict --recursive Package.swift Sources Tests
swift test
Scripts/check-api.sh
Scripts/test-ecosystem.sh
Scripts/test-consumers.sh
swift run -c release termloom-benchmark -- --suite all --iterations 10 --json > /tmp/termloom-benchmark-smoke.json
```

The API check must report zero additive symbols. PTY coverage is part of `swift test`; additionally smoke one inline,
one fullscreen, and one fixed-region executable on a real terminal, then verify cursor visibility, raw mode, mouse mode,
and alternate-screen restoration after normal quit and interruption. Record the host and result in the 0.2 release
checklist rather than treating a screenshot as terminal-lifecycle evidence.

## Performance smoke and baselines

CI runs every benchmark scenario with a small iteration count to catch build and JSON-schema regressions. Before
and after performance-sensitive changes, run a release baseline with enough iterations:

```sh
swift run -c release termloom-benchmark -- --suite all --iterations 1000 --json > benchmark.json
```

Compare like hardware and toolchains. See `Documentation/Performance.md` for scenario definitions and metric
limitations.

## Ordinary widgets

Start without a trailing closure:

```swift
import TermLoom
import TermLoomTestSupport
import Testing

@Test func paragraphWraps() {
  assertWidget(
    Paragraph("typed terminal output", wrap: .word),
    size: Size(width: 8, height: 3)
  )
}
```

Run record mode to generate the inline snapshot at the call site:

```sh
SNAPSHOT_TESTING_RECORD=all mise exec -- swift test
```

Do not type or update the generated closure manually. Re-run record mode when an intentional render
change needs a new reference.

## Stateful widgets

The stateful overload returns the rendered buffer while mutating the supplied state:

```swift
var state = ListState(selected: 8)
let buffer = assertWidget(
  List(items) { $0.name },
  size: Size(width: 24, height: 6),
  state: &state
)

#expect(state.offset > 0)
#expect(buffer.count == 144)
```

This keeps the spatial result in an inline snapshot and leaves state behavior explicit.
