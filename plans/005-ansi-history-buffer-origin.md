# Plan 005: Honor mapped buffer origins in ANSI history output

> **Executor instructions**: Execute after plan 004. This is a coordinate-correctness fix, not a history-policy redesign. Update `plans/README.md` when complete.
>
> **Drift check**: `Sources/Ratatui/ANSIBackend.swift` SHA-256 was `2d1b05ca7dde20207127b49c0aad4c8bc1e7eef878a47dad9c292ef86de6e5e3`. Confirm `appendHistoryRow` still reads `Position(x: column, y: row)` without `buffer.area` offsets; otherwise STOP.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: plan 004
- **Category**: bug
- **Planned at**: source archive without Git metadata, 2026-08-06

## Why this matters

`Buffer` supports non-zero terminal-coordinate areas, and the new fixed viewport makes such buffers first-class. ANSI history serialization currently treats every buffer as zero-origin, producing blank or incorrect rows when its public history API receives a mapped buffer. The generic restoration implementation already demonstrates the correct offset behavior.

## Current state

`Sources/Ratatui/ANSIBackend.swift:447-451` currently computes:

```swift
Position(x: UInt16(clamping: column), y: UInt16(clamping: row))
```

`Sources/Ratatui/Backend.swift:132-145` correctly adds `viewport.area.x` and `viewport.area.y` while restoring mapped buffers.

## Scope

**In scope**:

- `Sources/Ratatui/ANSIBackend.swift`
- `Tests/RatatuiTests/BackendTests.swift`
- `Tests/RatatuiTests/ANSIBackendTests.swift` if that is the established direct serializer test location
- APIChanges only if observable behavior warrants a note

**Out of scope**:

- fixed viewport lifecycle ownership
- changing terminal destination origin
- native history batching vocabulary
- Widget/Frame changes

## Steps

### 1. Offset source-cell lookup

Treat `row` and `column` as local indices into the provided buffer and read from:

```swift
x = buffer.area.x + column
y = buffer.area.y + row
```

Use clamped integer conversion consistently with existing buffer code. Do not change emitted terminal destination coordinates or row counts.

**Verify**:

```sh
swift test --filter BackendTests
swift test --filter ANSIBackendTests
```

Expected: all existing tests pass.

### 2. Add mapped-buffer regressions

Create a non-zero-origin history buffer containing:

- styled ASCII cells;
- at least one wide character/continuation pair;
- leading/trailing blank cells;
- multiple rows.

Call ANSI native history insertion and assert output contains the intended symbols/styles exactly once and does not serialize continuation cells. Add a mapped retained-viewport restoration case as well.

**Verify**: focused tests pass and fail if the area offsets are removed.

### 3. Run fixed-viewport and history matrices

Although fixed viewports do not own inline history, their non-zero coordinate model is the reason this contract must remain explicit.

**Verify**:

```sh
swift test --filter TerminalViewportTests
swift test --filter PTYIntegrationTests
swift test --filter InlineInsertionTests
```

Expected: all pass.

## Done criteria

- [x] ANSI history reads every source cell relative to `buffer.area`.
- [x] Zero-origin behavior is byte-for-byte unchanged.
- [x] Non-zero history and restoration buffers have regressions.
- [x] Wide-cell continuation behavior remains correct.
- [x] Full framework and consumer matrix passes.

## STOP conditions

- Fixing source lookup appears to require changing destination terminal origin.
- Existing callers rely on non-zero buffers being interpreted as zero-origin.
- A test requires enabling history for `Viewport.fixed`; that is out of scope.

## Maintenance notes

Any serializer consuming `Buffer` must decide explicitly whether coordinates are local indices or absolute positions. Review future code for zero-origin assumptions now that fixed terminal-coordinate buffers are supported.
