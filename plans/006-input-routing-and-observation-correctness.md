# Plan 006: Preserve fragmented input and suppress stale semantic events

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report; do not improvise. When done, update the status row for this plan in `plans/README.md` unless a reviewer explicitly says it maintains the index.
>
> **Drift check (run first)**: `git diff --stat aec5f74..HEAD -- Sources/TermLoom/Application.swift Sources/TermLoom/Interaction.swift Sources/TermLoom/TerminalSession.swift Tests/TermLoomTests/InteractionTests.swift Tests/TermLoomTests/ObservationInvalidationTrackerTests.swift Tests/TermLoomTests/PTYIntegrationTests.swift`
> If any in-scope file changed since this plan was written, compare the excerpts below with live code. If behavior or signatures differ, stop and report.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: plans 001–005 (DONE)
- **Category**: bug
- **Planned at**: commit `aec5f74`, 2026-08-07

## Why this matters

TermLoom supports fragmented terminal sequences, Kitty key release reports, and Observation-driven wakeups, but two paths currently combine incorrectly: a wakeup-only poll flushes a pending Escape byte, and the interaction router treats key releases as semantic activation/navigation. A third issue lets callbacks from obsolete Observation dependency generations request redundant frames. These are framework correctness defects with deterministic regression tests and no desired client behavior to preserve.

## Current state

- `Sources/TermLoom/TerminalSession.swift:789-807` drains the optional wakeup descriptor, then calls `parser.flushEscape()` whenever stdin was not readable. This does not distinguish a real poll timeout from a wakeup-only result.
- `Sources/TermLoom/Interaction.swift:169-190` routes Tab and Enter/Space without checking `KeyEvent.kind`; `.release` may advance focus or emit an action.
- `Sources/TermLoom/Application.swift:84-93` prevents an old Observation generation from disarming the current generation but invokes `onChange()` unconditionally.
- `Tests/TermLoomTests/PTYIntegrationTests.swift:1001-1014` is the existing pattern for a real pipe-backed wakeup interrupting `TerminalInput.readEvent`.
- `Tests/TermLoomTests/InteractionTests.swift:100-130` covers press routing and is the correct place for release/repeat characterization.
- `Tests/TermLoomTests/ObservationInvalidationTrackerTests.swift:21-39` covers dependency tracking and rearming.

Relevant current excerpts:

```swift
// TerminalSession.swift
if descriptors.count > 1, descriptors[1].revents & Int16(POLLIN) != 0 {
  wakeup?.drain()
}
...
guard result > 0, input.revents & Int16(POLLIN) != 0 else {
  return parser.flushEscape().map(localize)
}
```

```swift
// Interaction.swift
case .key(let keyEvent) where keyEvent.key == .tab:
...
case .key(let keyEvent)
where keyEvent.key == .enter || keyEvent.key == .character(" "):
```

```swift
// Application.swift
private func observedChange(generation changedGeneration: Int) {
  lock.withLock {
    if generation == changedGeneration { isArmed = false }
  }
  onChange()
}
```

Repository convention: runtime state transitions stay explicit and preserve queued/parser state. Tests use Swift Testing `@Test`/`#expect`, and terminal transport behavior receives PTY evidence rather than snapshots alone.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Format | `swift format lint --strict --recursive Package.swift Sources Tests` | exit 0 |
| Focused router tests | `swift test --filter InteractionTests` | all pass |
| Focused Observation tests | `swift test --filter ObservationInvalidationTrackerTests` | all pass |
| Focused PTY tests | `swift test --filter PTYIntegrationTests` | all pass |
| Full root tests | `swift test` | all pass |
| Ecosystem | `Scripts/test-ecosystem.sh` | exit 0 |
| Consumers | `Scripts/test-consumers.sh` | Codex and Herdr pass |
| API baseline | `Scripts/check-api.sh` | zero additive/removed symbols |

## Scope

**In scope**:
- `Sources/TermLoom/Application.swift`
- `Sources/TermLoom/Interaction.swift`
- `Sources/TermLoom/TerminalSession.swift`
- `Tests/TermLoomTests/InteractionTests.swift`
- `Tests/TermLoomTests/ObservationInvalidationTrackerTests.swift`
- `Tests/TermLoomTests/PTYIntegrationTests.swift`
- `Documentation/APIChanges.md`

**Out of scope**:
- Parser grammar changes unrelated to pending Escape flushing.
- New key-binding abstractions or changes to application-owned keymaps.
- Redraw-policy redesign.
- Terminal session ownership or backend capability changes.
- Any KWWK file.

## Git workflow

- Branch: `advisor/006-input-correctness`
- One commit: `Fix input routing and observation wakeups`
- Do not push, merge, or modify sibling repositories.

## Steps

### Step 1: Distinguish timeout from wakeup-only polling

In `TerminalInput.readEvent(timeoutMilliseconds:wakeup:)`, record whether the wakeup descriptor fired. Drain it as today. Flush a pending Escape only when the poll genuinely times out (`result == 0`) or when stdin reaches EOF as already specified. When the poll returns because only the wakeup descriptor is readable, return `nil` without changing parser state.

Preserve precedence when stdin and wakeup are both readable: consume stdin normally. Preserve HUP handling.

Add a PTY regression that:
1. Feeds one Escape byte so the parser retains it.
2. Signals the wakeup before the timeout.
3. Confirms the read returns `nil` rather than `.key(.escape)`.
4. Writes the rest of a valid fragmented sequence and confirms the combined semantic event is decoded.

**Verify**: `swift test --filter PTYIntegrationTests` → all PTY tests pass.

### Step 2: Prevent release events from driving interactions

Update `InteractionRouter.route` so `.release` events never advance focus or activate Enter/Space actions. Preserve the original release event in the routed output so an application that explicitly cares about releases can still observe it. Characterize `.repeat` deliberately in tests: retain the existing useful behavior for repeated Tab/activation unless a current test or documented contract proves otherwise.

Add tests for Tab release, Enter release, Space release, and at least one repeat case.

**Verify**: `swift test --filter InteractionTests` → all tests pass.

### Step 3: Ignore obsolete Observation callbacks

Change `ObservationInvalidationTracker.observedChange` so only the current generation disarms the tracker and calls `onChange`. The lock-protected section should return whether the callback was current; invoke the external callback after releasing the lock.

Add a test that tracks dependency A, refreshes tracking to dependency B before A mutates, then proves mutation of A does not invoke the callback while mutation of B does.

**Verify**: `swift test --filter ObservationInvalidationTrackerTests` → all tests pass.

### Step 4: Document and run the matrix

Add a concise `Documentation/APIChanges.md` entry describing the observable bug fixes without claiming a source change. Run formatting, the root suite, ecosystem, consumers, and API check.

**Verify**: all commands in the command table exit 0.

## Test plan

- PTY wakeup with pending Escape retains parser state.
- Wakeup followed by the remaining bytes decodes the intended combined key/sequence.
- Tab/Enter/Space release events are forwarded but do not alter focus or emit actions.
- Repeat behavior is explicitly characterized.
- Stale Observation generation produces no callback; current generation still produces exactly one.

## Done criteria

- [ ] Wakeup-only polling never flushes pending Escape.
- [ ] Simultaneous stdin+wakeup still processes stdin.
- [ ] Release events cannot traverse focus or activate controls.
- [ ] Stale Observation generations cannot schedule redraws.
- [ ] Focused and full tests pass.
- [ ] Ecosystem and consumer scripts pass.
- [ ] Strict format lint and API baseline pass.
- [ ] Only in-scope files changed.
- [ ] KWWK remains untouched.

## STOP conditions

Stop and report if:
- The live polling code no longer matches the excerpt or wakeup ownership moved elsewhere.
- Preserving repeat behavior conflicts with an existing documented test.
- The PTY regression cannot deterministically create a pending Escape without changing parser visibility/API.
- A fix requires changing parser grammar or public event cases.
- Any verification fails twice after a focused correction.

## Maintenance notes

A wakeup is an out-of-band scheduling signal, not elapsed input ambiguity time. Future wakeup sources must preserve that distinction. Interaction routing should continue forwarding unsupported event kinds rather than swallowing them. Observation callbacks must never execute while the tracker's lock is held.
