# Plan 007: Remove proven text and block construction workarounds

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report; do not improvise. When done, update the status row for this plan in `plans/README.md` unless a reviewer explicitly says it maintains the index.
>
> **Drift check (run first)**: `git diff --stat 85319e1..HEAD -- Sources/Ratatui/Widget.swift Sources/Ratatui/Paragraph.swift Sources/Ratatui/Block.swift Tests/RatatuiTests/TextTests.swift Tests/RatatuiTests/WidgetTests.swift Examples/Postcat/Sources/PostcatExampleCore/Model.swift Examples/Postcat/Sources/PostcatExampleCore/Screen.swift Examples/DiffScope/Sources/DiffScopeExampleCore/Screen.swift Documentation/APIChanges.md Documentation/API/Ratatui.json`
> If any in-scope file changed since this plan was written, compare the excerpts below with live code. If behavior or signatures differ, stop and report.

## Status

- **Priority**: P1
- **Effort**: S–M
- **Risk**: LOW
- **Depends on**: plan 006
- **Category**: dx
- **Planned at**: commit `85319e1`, 2026-08-07

## Why this matters

Three unrelated construction gaps have already produced application workarounds. `Text` drops intentional leading and internal blank rows, Postcat and DiffScope independently construct dynamic `[Span]` values through local helpers, and Postcat, DiffScope, and Herdr use `Block<Text>` with `Text("")` merely to render decoration and call `inner(_:)`. These are small Swift API improvements with direct client evidence and no need for a larger widget redesign.

## Current state

- `Sources/Ratatui/Widget.swift:56-60` and `:76-82` use `String.split(separator:)`, which removes all empty subsequences. Existing `Tests/RatatuiTests/TextTests.swift:67-68` intentionally establishes that one terminal newline does not add another row; preserve that behavior while retaining leading/consecutive empty lines.
- `Sources/Ratatui/Paragraph.swift:29-56` gives `Line` a String initializer and `@SpanBuilder` initializer but no `[Span]` initializer.
- `Examples/Postcat/Sources/PostcatExampleCore/Model.swift:5-10` defines a local `Line.init(_ spans:[Span], alignment:)` workaround.
- `Examples/DiffScope/Sources/DiffScopeExampleCore/Screen.swift:359-362` creates `Line("")`, assigns `line.spans`, and returns it.
- `Sources/Ratatui/Block.swift:283-353` requires generic content for all initializers.
- `Examples/Postcat/Sources/PostcatExampleCore/Screen.swift:56-67`, `Examples/DiffScope/Sources/DiffScopeExampleCore/Screen.swift:63-75`, and Herdr's screen use `Block<Text>` with `Text("")` as decoration-only shells.

Relevant current excerpts:

```swift
// Widget.swift
let splitLines = content.split(separator: "\n").map { Line(String($0)) }
lines = splitLines.isEmpty ? [Line("")] : splitLines
```

```swift
// Paragraph.swift
public init(_ content: String, style: Style = .plain, alignment: Alignment? = nil)
public init(style: Style = .plain, alignment: Alignment? = nil,
            @SpanBuilder spans: () -> [Span])
```

```swift
// client workaround
private func makeLine(_ spans: [Span]) -> Line {
  var line = Line("")
  line.spans = spans
  return line
}
```

Repository conventions: value-semantic widgets, additive convenience APIs, result builders at coarse composition boundaries, and API baseline updates for every reviewed public symbol.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Format | `swift format lint --strict --recursive Package.swift Sources Tests Examples/Postcat Examples/DiffScope` | exit 0 |
| Text tests | `swift test --filter TextTests` | all pass |
| Widget tests | `swift test --filter WidgetTests` | all pass |
| Full root tests | `swift test` | all pass |
| Postcat | `cd Examples/Postcat && swift test` | all pass |
| DiffScope | `cd Examples/DiffScope && swift test` | all pass |
| Ecosystem | `Scripts/test-ecosystem.sh` | exit 0 |
| Consumers | `Scripts/test-consumers.sh` | Codex and Herdr pass |
| Update API | `Scripts/check-api.sh --update` | baseline updated intentionally |
| Verify API | `Scripts/check-api.sh` | zero additive/removed symbols |

## Scope

**In scope**:
- `Sources/Ratatui/Widget.swift`
- `Sources/Ratatui/Paragraph.swift`
- `Sources/Ratatui/Block.swift`
- `Tests/RatatuiTests/TextTests.swift`
- `Tests/RatatuiTests/WidgetTests.swift`
- `Examples/Postcat/Sources/PostcatExampleCore/Model.swift`
- `Examples/Postcat/Sources/PostcatExampleCore/Screen.swift`
- `Examples/DiffScope/Sources/DiffScopeExampleCore/Screen.swift`
- `Documentation/APIChanges.md`
- `Documentation/API/Ratatui.json`

**Out of scope**:
- Geometry scalar migration.
- General `Stylable` conformance expansion.
- Stack/frame/layout redesign.
- Popup/menu presentation abstractions.
- Herdr source migration; it is a validation consumer for this plan, not an edited repository.
- Any KWWK file.

## Git workflow

- Branch: `advisor/007-construction-ergonomics`
- One commit: `Improve text and block construction ergonomics`
- Do not push, merge, or modify KWWK.

## Steps

### Step 1: Preserve semantically meaningful empty text rows

Extract one internal line-splitting helper used by both `Text.init(_:)` and the `content` setter. It must:

- preserve leading empty rows;
- preserve consecutive/internal empty rows;
- preserve existing behavior where a single terminal newline does not create an additional row;
- produce one empty `Line` for the empty string and for `"\n"` under the established terminal-newline semantics;
- make `Text.content` round-trip all represented rows.

Do not change `Paragraph` wrapping or `Line.content`.

Add tests for `"a\n\nb"`, `"\na"`, `"a\n"`, `"\n"`, and setter/getter round trips.

**Verify**: `swift test --filter TextTests` → all tests pass.

### Step 2: Add direct dynamic-span Line construction

Add:

```swift
public init(
  _ spans: [Span],
  style: Style = .plain,
  alignment: Alignment? = nil
)
```

It should assign the provided spans without copying through strings or patching their styles. Add direct construction/render tests including an empty array and mixed styles.

Migrate Postcat's local initializer away and replace DiffScope's mutating `makeLine` workaround with `Line(spans)`. Delete helpers that become unused.

**Verify**:
- `swift test --filter TextTests`
- `(cd Examples/Postcat && swift test)`
- `(cd Examples/DiffScope && swift test)`

All pass.

### Step 3: Add a real empty widget and decoration-only Block initializer

Add a public zero-state `EmptyWidget` conforming to `Widget`, `Hashable`, `Sendable`, with a no-op `render`. Prefer this domain-consistent name over SwiftUI's `EmptyView`.

Add a constrained `Block where Content == EmptyWidget` initializer mirroring the existing decoration parameters but requiring no `content` argument or builder. It must not create overload ambiguity for `Block { ... }` or `Block(content:)`.

Add tests proving:
- `EmptyWidget` leaves cells, interactions, and cursor metadata unchanged;
- a content-free block renders exactly the same decoration and `inner(_:)` geometry as the former `Block<Text>(content: Text(""))` pattern;
- existing builder initializers still resolve.

Migrate Postcat and DiffScope decoration helpers to return/use `Block<EmptyWidget>` or inferred `Block` values. Do not modify Herdr in this plan.

**Verify**: root widget tests plus both example suites pass.

### Step 4: Document and baseline the additive API

Add concise entries to `Documentation/APIChanges.md`. Run `Scripts/check-api.sh --update`, review that only the intended initializer/type/constrained initializer symbols were added, then run `Scripts/check-api.sh`.

Run the full command matrix.

## Test plan

- Text preserves internal and leading blank lines while retaining established trailing-newline semantics.
- Text setter and getter share exactly one splitting policy.
- `[Span]` construction preserves span identity/value ordering and styles.
- Empty span arrays render safely.
- `EmptyWidget` produces no presentation output.
- Decoration-only Block matches the previous dummy-content rendering.
- Postcat and DiffScope local workarounds are removed.
- Codex and Herdr remain source-compatible and pass.

## Done criteria

- [ ] `Text("a\n\nb")` has three rows.
- [ ] Existing `Text("a\n")` behavior remains characterized and passing.
- [ ] Core has a public `[Span]` Line initializer.
- [ ] Postcat and DiffScope no longer mutate an empty Line to install spans.
- [ ] Core has a public `EmptyWidget` and content-free Block initializer.
- [ ] Postcat and DiffScope no longer use `Text("")` solely to instantiate a decoration block.
- [ ] Strict format lint, root tests, examples, ecosystem, consumers, and API baseline all pass.
- [ ] Only in-scope files changed.
- [ ] KWWK remains untouched.

## STOP conditions

Stop and report if:
- Preserving internal blank rows requires changing established trailing-newline behavior.
- The `[Span]` initializer creates an unresolved ambiguity at existing call sites.
- A content-free Block initializer cannot coexist with current builder/content initializers without ambiguous inference.
- Consumer migration requires changing application semantics or snapshot content beyond restored intentional blank rows.
- API baseline changes include symbols unrelated to this plan.
- Any verification fails twice after a focused correction.

## Maintenance notes

Keep `EmptyWidget` behavior strictly empty; layout allocation belongs to parent containers. Do not turn it into a spacer. Dynamic span construction should remain a value initializer rather than exposing syntax-highlighter dependency types. The separate follow-up for broad `Stylable` adoption should evaluate focused-style controls independently.
